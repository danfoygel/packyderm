#if DEBUG
import EventKit
import Foundation

/// Debug helper: launch with `-demoCalendar YES` to add sample travel events to the calendar.
enum DemoCalendar {
    @MainActor
    static func seedIfRequested() async {
        guard UserDefaults.standard.bool(forKey: "demoCalendar") else { return }
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true,
              let calendar = store.defaultCalendarForNewEvents else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func day(_ offset: Int, _ hour: Int = 0) -> Date {
            cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: today)!)!
        }

        // Skip if already seeded.
        let existing = store.events(matching: store.predicateForEvents(withStart: today, end: day(60), calendars: [calendar]))
        guard !existing.contains(where: { $0.title == "Flight to Denver (UA 455)" }) else { return }

        func add(_ title: String, _ start: Date, _ end: Date, location: String? = nil, allDay: Bool = false) {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = title
            event.startDate = start
            event.endDate = end
            event.isAllDay = allDay
            event.location = location
            try? store.save(event, span: .thisEvent)
        }

        add("Team standup", day(1, 9), day(1, 10), location: "Zoom")
        add("Flight to Denver (UA 455)", day(5, 8), day(5, 11))
        add("Hotel Teatro", day(5, 15), day(8, 11), location: "1100 14th St, Denver, CO")
        add("Customer workshop", day(6, 9), day(6, 17), location: "University of Colorado Boulder")
        add("Dinner with Sam", day(7, 19), day(7, 21), location: "Larimer Square, Denver")
        add("Flight to Boston (UA 1022)", day(8, 13), day(8, 19))
        add("Dentist", day(12, 10), day(12, 11), location: "Newbury St, Boston, MA")
        add("Trip to Paris", day(30), day(35), allDay: true)
        add("Rome", day(35), day(38), location: "Rome, Italy", allDay: true)
        try? store.commit()
    }
}
#endif
