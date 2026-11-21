import EventKit
import SwiftData
import SwiftUI

/// New Trip: choose calendars (first time only) → scan calendar → pick a detected trip → confirm/edit legs → create and fetch weather.
struct NewTripFlow: View {
    var onCreated: (Trip) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.units) private var units
    @AppStorage(SettingsKey.homeName) private var homeName = ""
    @AppStorage(SettingsKey.homeLatitude) private var homeLatitude = 0.0
    @AppStorage(SettingsKey.homeLongitude) private var homeLongitude = 0.0
    @AppStorage(SettingsKey.lookaheadDays) private var lookaheadDays = 60
    @AppStorage(SettingsKey.calendarIDs) private var calendarIDs = ""

    private enum Phase {
        case needsHome, scanning, noAccess, chooseCalendars([EKCalendar]), results([DetectedTrip]), confirm, creating
    }

    @State private var phase: Phase = .scanning
    @State private var draftName = ""
    @State private var draftLegs: [DetectedLeg] = []
    @State private var evidence: [String] = []
    @State private var error: String?
    @State private var calendarDraft: Set<String> = []
    @State private var detector = CalendarTripDetector()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("New Trip")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task { await start() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .needsHome:
            HomePromptView { place in
                homeName = place.name
                homeLatitude = place.latitude
                homeLongitude = place.longitude
                Task { await scan() }
            }
        case .scanning:
            ProgressView("Looking at your calendar…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noAccess:
            ContentUnavailableView {
                Label("No calendar access", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("Allow calendar access in Settings to detect trips automatically, or enter the trip yourself.")
            } actions: {
                Button("Enter trip manually") { startManual() }
                    .buttonStyle(.borderedProminent)
            }
        case .chooseCalendars(let calendars):
            CalendarChooser(calendars: calendars, selection: $calendarDraft) {
                calendarIDs = CalendarSelection.encode(calendarDraft)
                Task { await scan() }
            }
        case .results(let trips):
            DetectedTripsList(trips: trips, onPick: pick, onManual: startManual, onChangeCalendars: {
                chooseCalendars(preselecting: CalendarSelection.decode(calendarIDs))
            })
        case .confirm:
            ItineraryEditor(name: $draftName, legs: $draftLegs, evidence: evidence) {
                Task { await create() }
            }
        case .creating:
            ProgressView("Checking the weather…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var home: Place? {
        homeName.isEmpty ? nil : Place(name: homeName, latitude: homeLatitude, longitude: homeLongitude)
    }

    private func start() async {
        guard home != nil else {
            phase = .needsHome
            return
        }
        await scan()
    }

    private func scan() async {
        guard let home else { phase = .needsHome; return }
        phase = .scanning
        guard await detector.requestAccess() else {
            phase = .noAccess
            return
        }
        let calendars = detector.calendars(withIDs: CalendarSelection.decode(calendarIDs))
        guard !calendars.isEmpty else {
            chooseCalendars(preselecting: detector.suggestedCalendarIDs(lookaheadDays: lookaheadDays))
            return
        }
        let trips = await detector.detectTrips(home: home, lookaheadDays: lookaheadDays, calendars: calendars)
        phase = .results(trips)
    }

    private func chooseCalendars(preselecting ids: Set<String>) {
        calendarDraft = ids
        phase = .chooseCalendars(detector.selectableCalendars())
    }

    private func pick(_ trip: DetectedTrip) {
        draftLegs = trip.legs
        draftName = trip.suggestedName
        evidence = trip.evidence
        phase = .confirm
    }

    private func startManual() {
        draftLegs = []
        draftName = ""
        evidence = []
        phase = .confirm
    }

    private func create() async {
        phase = .creating
        let name = draftName.trimmingCharacters(in: .whitespaces).isEmpty ? "Trip" : draftName
        let trip = TripService.createTrip(name: name, legs: draftLegs, context: context)
        try? context.save()
        do {
            try await TripService.refreshWeather(for: trip, units: units, context: context)
        } catch {
            // Trip still works without weather; detail view offers retry.
            TripService.reevaluateCategories(for: trip, units: units, context: context)
        }
        onCreated(trip)
    }
}

// MARK: - Detected trips

private struct DetectedTripsList: View {
    let trips: [DetectedTrip]
    var onPick: (DetectedTrip) -> Void
    var onManual: () -> Void
    var onChangeCalendars: () -> Void

    var body: some View {
        List {
            if trips.isEmpty {
                Section {
                    Text("Didn't find any trips on your calendar. Events need a location away from home, or titles like “Flight to Denver”, “Hotel …”, or “Trip to Paris”.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Found on your calendar") {
                    ForEach(trips) { trip in
                        Button { onPick(trip) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trip.suggestedName).font(.headline)
                                Text(DateRange.format(trip.start, trip.end))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if trip.legs.count > 1 {
                                    Text(trip.legs.map { $0.place.name.components(separatedBy: ",").first ?? "" }.joined(separator: " → "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            Section {
                Button("Enter trip manually", systemImage: "square.and.pencil", action: onManual)
                Button("Choose calendars", systemImage: "calendar", action: onChangeCalendars)
            }
        }
    }
}

// MARK: - Calendar chooser

/// Shown the first time (or when the saved calendars are gone): which calendars are yours to scan.
private struct CalendarChooser: View {
    let calendars: [EKCalendar]
    @Binding var selection: Set<String>
    var onContinue: () -> Void

    var body: some View {
        List {
            Section {
                Text("Which calendars have your plans? Leave out shared calendars like family members', coworkers', and holidays, so their trips aren't mistaken for yours.")
                    .foregroundStyle(.secondary)
            }
            CalendarChecklist(calendars: calendars, selection: $selection)
            Section {
                Text("You can change this later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text(selection.isEmpty ? "Choose at least one calendar" : "Find trips")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selection.isEmpty)
            .padding()
        }
    }
}

// MARK: - Home prompt

private struct HomePromptView: View {
    var onSet: (Place) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "house")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Where's home?")
                .font(.title2.bold())
            Text("Packyderm compares calendar event locations to your home city to tell trips apart from everyday plans.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            PlacePicker(title: "Home city", onPick: onSet)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
