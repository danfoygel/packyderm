import EventKit
import SwiftUI

/// Settings → Calendars: which calendars trip detection reads.
struct CalendarSettingsView: View {
    @AppStorage(SettingsKey.calendarIDs) private var calendarIDs = ""
    @State private var detector = CalendarTripDetector()
    @State private var calendars: [EKCalendar] = []
    @State private var hasAccess: Bool?

    var body: some View {
        Group {
            switch hasAccess {
            case nil:
                ProgressView()
            case false:
                ContentUnavailableView {
                    Label("No calendar access", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Allow Packyderm full access to your calendars in the Settings app.")
                } actions: {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case true:
                List {
                    Section {
                        Text("Only events on these calendars are used to find trips. Leave out shared calendars so other people's plans aren't mistaken for yours.")
                            .foregroundStyle(.secondary)
                    }
                    CalendarChecklist(calendars: calendars, selection: selection)
                }
            }
        }
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let granted = await detector.requestAccess()
            if granted { calendars = detector.selectableCalendars() }
            hasAccess = granted
        }
    }

    private var selection: Binding<Set<String>> {
        Binding {
            CalendarSelection.decode(calendarIDs)
        } set: { ids in
            // Drop identifiers of calendars that no longer exist.
            calendarIDs = CalendarSelection.encode(ids.intersection(calendars.map(\.calendarIdentifier)))
        }
    }
}
