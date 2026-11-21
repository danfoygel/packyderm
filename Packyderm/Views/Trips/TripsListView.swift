import SwiftData
import SwiftUI

struct TripsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @State private var showingNewTrip = false
    @State private var showingLibrary = false
    @State private var showingSettings = false
    @State private var path: [Trip] = []

    private var upcoming: [Trip] { trips.filter { !$0.isPast }.sorted { $0.startDate < $1.startDate } }
    private var past: [Trip] { trips.filter(\.isPast) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("No trips yet", systemImage: "suitcase.rolling")
                    } description: {
                        Text("Tap New Trip and Packyderm will look at your calendar to figure out where you're headed.")
                    } actions: {
                        Button("New Trip") { showingNewTrip = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { trip in
                            NavigationLink(value: trip) { TripRow(trip: trip) }
                        }
                        .onDelete { delete(upcoming, at: $0) }
                    }
                }
                if !past.isEmpty {
                    Section("Past") {
                        ForEach(past) { trip in
                            NavigationLink(value: trip) { TripRow(trip: trip) }
                        }
                        .onDelete { delete(past, at: $0) }
                    }
                }
            }
            .navigationTitle("Packyderm")
            .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingLibrary = true } label: { Image(systemName: "list.bullet.rectangle") }
                        .accessibilityLabel("Packing library")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { showingNewTrip = true } label: {
                        Label("New Trip", systemImage: "plus")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showingNewTrip) {
                NewTripFlow { trip in
                    showingNewTrip = false
                    path = [trip]
                }
            }
            .sheet(isPresented: $showingLibrary) { LibraryView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    private func delete(_ list: [Trip], at offsets: IndexSet) {
        for index in offsets { context.delete(list[index]) }
        try? context.save()
    }
}

struct TripRow: View {
    let trip: Trip
    @Environment(\.units) private var units

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.name).font(.headline)
            Text(DateRange.format(trip.startDate, trip.endDate))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let weather = trip.weather, let high = weather.high, let low = weather.low {
                HStack(spacing: 10) {
                    Label("\(units.temp(low))–\(units.temp(high))", systemImage: "thermometer.medium")
                    if let rain = weather.rainChanceAnyDay {
                        Label("\(Int(rain.rounded()))%", systemImage: "umbrella")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

enum DateRange {
    static func format(_ start: Date, _ end: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(start, inSameDayAs: end) {
            return start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        let sameYear = cal.component(.year, from: start) == cal.component(.year, from: end)
        let startText = start.formatted(.dateTime.month(.abbreviated).day())
        let endText = end.formatted(sameYear ? .dateTime.month(.abbreviated).day().year() : .dateTime.month(.abbreviated).day().year())
        return "\(startText) – \(endText)"
    }

    static func dayCount(_ start: Date, _ end: Date) -> Int {
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0) + 1
    }
}
