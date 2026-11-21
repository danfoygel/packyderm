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
            let short = leg.place.name.components(separatedBy: ",").first ?? leg.place.name
            if !names.contains(short) { names.append(short) }
        }
        return names.prefix(3).joined(separator: " & ")
    }
}

/// Reads upcoming calendar events and guesses where the user will be on each day.
///
/// Signals, strongest first:
///  - stays: hotel/Airbnb events, or multi-day events with a location
///  - flights: "Flight to Denver", "BOS → DEN" (you're at the destination from that day on)
///  - ordinary events with a location far from home
/// Away days separated by short gaps are joined into a trip; a flight back home ends one.
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

    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        if Self.hasAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    private enum Kind: Int { case event = 1, flight = 2, stay = 3 }

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
        guard !days.isEmpty else { return nil }

        var kind: Kind = .event
        var place: Place?

        if let destination = Self.flightDestination(in: title) {
            kind = .flight
            place = await geocoder.place(for: destination)
        } else if Self.looksLikeFlight(title) {
            // A flight we can't parse; its location is usually the departure airport.
            return nil
        } else {
            if Self.looksLikeStay(title) || days.count > 1 { kind = .stay }
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
            let name = await geocoder.cityName(for: geo) ?? event.structuredLocation?.title ?? event.location ?? "Unknown"
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

    private func buildTrips(from signals: [Signal], today: Date) -> [DetectedTrip] {
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

    static func isVirtualLocation(_ location: String) -> Bool {
        let lower = location.lowercased()
        return lower.hasPrefix("http") || ["zoom", "teams", "meet.google", "webex", "facetime", "phone", "virtual", "online"]
            .contains { lower.contains($0) }
    }
}
