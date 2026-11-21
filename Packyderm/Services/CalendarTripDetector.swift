import EventKit
import Foundation

struct DetectedLeg: Identifiable, Hashable {
    var id = UUID()
    var place: Place
    var start: Date
    var end: Date
}

struct DetectedTrip: Identifiable, Hashable {
    var id = UUID()
    var legs: [DetectedLeg]
    /// Calendar events that led to this guess, for display.
    var evidence: [String]

    var start: Date { legs.map(\.start).min() ?? .now }
    var end: Date { legs.map(\.end).max() ?? .now }

    var suggestedName: String {
        var names: [String] = []
        for leg in legs {
            let short = (leg.place.name.components(separatedBy: ",").first ?? leg.place.name)
                .trimmingCharacters(in: .whitespaces)
            if !short.isEmpty, !names.contains(short) { names.append(short) }
        }
        return names.prefix(3).joined(separator: " & ")
    }
}

/// Reads upcoming calendar events and guesses where the user will be on each day.
///
/// Signals, strongest first:
///  - flights: "Flight to Denver", "BOS → DEN" (you're at the destination from that day until the next flight)
///  - lodging: hotel/Airbnb events
///  - stays: multi-day events with a location, "Trip to Paris"
///  - ordinary events with a location far from home
/// Away days separated by short gaps are joined into a trip; a flight back home ends one.
/// Other people's events (coworkers' PTO on a shared calendar, invites you're not on) are ignored.
@MainActor
final class CalendarTripDetector {
    private let store = EKEventStore()
    private let geocoder = Geocoder.shared
    private var calendar: Calendar { .current }

    /// Distance from home (km) beyond which an event counts as "away".
    var awayThresholdKm: Double = 80
    /// Places closer than this are treated as the same leg.
    var sameLegKm: Double = 40
    /// Days without an event between away days that still count as one trip.
    var maxGapDays = 2
    /// A flight followed by another flight within this many days means you stay at its destination in between.
    var maxFlightTripDays = 30
    /// While at a flight's destination, weaker signals farther than this (km) are ignored as someone else's.
    var sideTripKm: Double = 300

    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        if Self.hasAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// `carried`: a day between a flight out and the next flight, spent at the flight's destination.
    private enum Kind: Int { case carried = 0, event, stay, lodging, flight }

    private struct Signal {
        var kind: Kind
        var place: Place
        var start: Date
        var days: [Date]
        var title: String
        var isHome: Bool
    }

    func detectTrips(home: Place, lookaheadDays: Int) async -> [DetectedTrip] {
        let today = calendar.startOfDay(for: .now)
        guard let horizon = calendar.date(byAdding: .day, value: lookaheadDays, to: today) else { return [] }
        let predicate = store.predicateForEvents(withStart: today, end: horizon, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.calendar.type != .birthday }
            .sorted { $0.startDate < $1.startDate }

        var signals: [Signal] = []
        for event in events {
            if let signal = await signal(for: event, home: home) {
                signals.append(signal)
            }
        }
        return buildTrips(from: signals, today: today)
    }

    // MARK: Event → signal

    private func signal(for event: EKEvent, home: Place) async -> Signal? {
        let title = event.title ?? ""
        let days = coveredDays(event)
        guard !days.isEmpty, !Self.isSomeoneElses(event) else { return nil }

        var kind: Kind = .event
        var place: Place?

        if let destination = Self.flightDestination(in: title) {
            kind = .flight
            place = await geocoder.place(for: destination)
        } else if Self.looksLikeFlight(title) {
            // A flight we can't parse; its location is usually the departure airport.
            return nil
        } else if Self.looksLikeAbsence(title) && Self.tripDestination(in: title) == nil {
            // "Kate - PTO", "Nalini OOO": availability notices, usually a coworker's on a shared calendar.
            // Any location on them is an office or someone's home, not where you'll be.
            return nil
        } else {
            if Self.looksLikeStay(title) {
                kind = .lodging
            } else if days.count > 1 {
                kind = .stay
            }
            place = await resolveLocation(of: event)
            if place == nil, let named = Self.tripDestination(in: title) {
                kind = .stay
                place = await geocoder.place(for: named)
            }
        }
        guard let place else { return nil }

        let isHome = place.distanceKm(to: home) < awayThresholdKm
        // Only flights home matter as "home" signals; local events are too noisy.
        if isHome && kind != .flight { return nil }
        let signalDays = kind == .flight ? [days[0]] : days
        return Signal(kind: kind, place: place, start: event.startDate, days: signalDays, title: title, isHome: isHome)
    }

    private func resolveLocation(of event: EKEvent) async -> Place? {
        if let geo = event.structuredLocation?.geoLocation {
            let city = await geocoder.cityName(for: geo)
            let name = Geocoder.firstNonBlank(city, event.structuredLocation?.title, event.location) ?? "Unknown"
            return Place(name: name, latitude: geo.coordinate.latitude, longitude: geo.coordinate.longitude)
        }
        guard let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty, !Self.isVirtualLocation(location) else { return nil }
        return await geocoder.place(for: location)
    }

    private func coveredDays(_ event: EKEvent) -> [Date] {
        let first = calendar.startOfDay(for: event.startDate)
        // All-day events end at midnight of the following day.
        let endInstant = event.isAllDay ? event.endDate.addingTimeInterval(-1) : event.endDate
        let last = calendar.startOfDay(for: max(endInstant ?? event.startDate, event.startDate))
        var days: [Date] = []
        var day = first
        while day <= last, days.count < 60 {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }

    // MARK: Signals → trips

    private func buildTrips(from allSignals: [Signal], today: Date) -> [DetectedTrip] {
        let stays = flightStays(in: allSignals)
        let signals = withoutFarSignals(allSignals, during: stays) + stays

        // Best away signal per day.
        var byDay: [Date: Signal] = [:]
        var homeDays: Set<Date> = []
        for signal in signals {
            if signal.isHome {
                homeDays.formUnion(signal.days)
                continue
            }
            for day in signal.days {
                if let existing = byDay[day] {
                    if signal.kind.rawValue > existing.kind.rawValue
                        || (signal.kind == existing.kind && signal.start > existing.start) {
                        byDay[day] = signal
                    }
                } else {
                    byDay[day] = signal
                }
            }
        }

        // Group away days into trips.
        let awayDays = byDay.keys.sorted()
        var groups: [[Date]] = []
        for day in awayDays {
            if let lastDay = groups.last?.last {
                let gap = calendar.dateComponents([.day], from: lastDay, to: day).day ?? 99
                let returnedHome = homeDays.contains { $0 > lastDay && $0 < day }
                if gap <= maxGapDays + 1 && !returnedHome && !homeDays.contains(lastDay) {
                    groups[groups.count - 1].append(day)
                    continue
                }
            }
            groups.append([day])
        }

        return groups.compactMap { days -> DetectedTrip? in
            guard let first = days.first, let last = days.last else { return nil }
            // A flight home right after the last away day is the travel day back.
            var end = last
            if let next = calendar.date(byAdding: .day, value: 1, to: last), homeDays.contains(next) {
                end = next
            }

            var legs: [DetectedLeg] = []
            var evidence: [String] = []
            for signal in signals where signal.days.contains(where: { $0 >= first && $0 <= end }) {
                if !evidence.contains(signal.title) { evidence.append(signal.title) }
            }
            var currentPlace = byDay[first]!.place
            var day = first
            while day <= end {
                if let signal = byDay[day] {
                    currentPlace = signal.place
                }
                if let leg = legs.last, leg.place.distanceKm(to: currentPlace) < sameLegKm {
                    legs[legs.count - 1].end = day
                } else {
                    legs.append(DetectedLeg(place: currentPlace, start: day, end: day))
                }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            return DetectedTrip(legs: legs, evidence: evidence)
        }
    }

    /// Between a flight out and the next flight, you're at the flight's destination.
    private func flightStays(in signals: [Signal]) -> [Signal] {
        let flights = signals.filter { $0.kind == .flight }.sorted { $0.start < $1.start }
        var stays: [Signal] = []
        for (flight, next) in zip(flights, flights.dropFirst()) where !flight.isHome {
            let first = flight.days[0]
            let gap = calendar.dateComponents([.day], from: first, to: next.days[0]).day ?? 0
            guard gap > 0, gap <= maxFlightTripDays else { continue }
            let days = (0..<gap).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
            stays.append(Signal(kind: .carried, place: flight.place, start: flight.start, days: days, title: flight.title, isHome: false))
        }
        return stays
    }

    /// Drops days of ordinary events and multi-day events that are far from where your flights put you;
    /// those are usually other people's plans on shared calendars. Hotel bookings still count, since you may
    /// have moved on by train or car.
    private func withoutFarSignals(_ signals: [Signal], during stays: [Signal]) -> [Signal] {
        var destinationByDay: [Date: Place] = [:]
        for stay in stays {
            for day in stay.days { destinationByDay[day] = stay.place }
        }
        return signals.compactMap { signal -> Signal? in
            guard signal.kind == .event || signal.kind == .stay else { return signal }
            var kept = signal
            kept.days = signal.days.filter { day in
                guard let destination = destinationByDay[day] else { return true }
                return signal.place.distanceKm(to: destination) <= sideTripKm
            }
            return kept.days.isEmpty ? nil : kept
        }
    }

    // MARK: Title parsing

    static func looksLikeFlight(_ title: String) -> Bool {
        let lower = title.lowercased()
        if lower.contains("flight") || title.contains("✈") { return true }
        return title.range(of: #"\b[A-Z]{3}\s*(→|->|–|—|-|to)\s*[A-Z]{3}\b"#, options: .regularExpression) != nil
    }

    static func flightDestination(in title: String) -> String? {
        // "BOS → DEN", "SFO-JFK"
        if let match = title.firstMatch(of: /\b[A-Z]{3}\s*(?:→|->|–|—|-|to)\s*([A-Z]{3})\b/) {
            return "\(match.1) airport"
        }
        guard looksLikeFlight(title) else { return nil }
        // "Flight to Denver (UA 123)", "✈ Flight to Paris on Air France"
        if let match = title.firstMatch(of: /(?i)(?:flight|✈️?)\s*(?:\w+\s+)?to\s+([^(\[,]+?)(?:\s+(?:on|via|from)\b|\s*[(\[,]|$)/) {
            let destination = String(match.1).trimmingCharacters(in: .whitespaces)
            return destination.isEmpty ? nil : destination
        }
        return nil
    }

    static func looksLikeStay(_ title: String) -> Bool {
        let lower = title.lowercased()
        return ["hotel", "airbnb", "stay at", "check-in", "check in", "resort", "lodging", "vrbo", "hostel", "inn "]
            .contains { lower.contains($0) }
    }

    /// "Trip to Paris", "Vacation in Maui"
    static func tripDestination(in title: String) -> String? {
        guard let match = title.firstMatch(of: /(?i)\b(?:trip|vacation|holiday|travel(?:ing)?|getaway)\s+(?:to|in)\s+(.+)/) else { return nil }
        let destination = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return destination.isEmpty ? nil : destination
    }

    /// "Courtney PTO", "Nalini OOO", "JT - Sabbatical", "Out of office"
    static func looksLikeAbsence(_ title: String) -> Bool {
        title.range(
            of: #"(?i)\b(pto|ooo|ooto|out of (the )?office|sabbatical|(on|parental|maternity|paternity|medical) leave)\b"#,
            options: .regularExpression
        ) != nil
    }

    /// An event someone else organized that you aren't invited to, e.g. on a coworker's or family member's calendar.
    static func isSomeoneElses(_ event: EKEvent) -> Bool {
        guard let organizer = event.organizer, !organizer.isCurrentUser else { return false }
        return !(event.attendees ?? []).contains { $0.isCurrentUser }
    }

    static func isVirtualLocation(_ location: String) -> Bool {
        let lower = location.lowercased()
        return lower.hasPrefix("http") || ["zoom", "teams", "meet.google", "webex", "facetime", "phone", "virtual", "online"]
            .contains { lower.contains($0) }
    }
}
