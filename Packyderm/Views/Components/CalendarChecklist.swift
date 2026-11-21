import EventKit
import SwiftUI

/// The device's calendars grouped by account, each with a checkmark. Meant to sit inside a `List` or `Form`.
struct CalendarChecklist: View {
    let calendars: [EKCalendar]
    @Binding var selection: Set<String>

    private var groups: [(id: String, title: String, calendars: [EKCalendar])] {
        Dictionary(grouping: calendars) { $0.source.sourceIdentifier }
            .map { (id: $0.key, title: $0.value[0].source.title, calendars: $0.value) }
            .sorted { $0.title < $1.title }
    }

    var body: some View {
        ForEach(groups, id: \.id) { group in
            Section(group.title) {
                ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                    row(calendar)
                }
            }
        }
    }

    private func row(_ calendar: EKCalendar) -> some View {
        let id = calendar.calendarIdentifier
        let isOn = selection.contains(id)
        return Button {
            if isOn { selection.remove(id) } else { selection.insert(id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(Color(cgColor: calendar.cgColor))
                Text(calendar.title)
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
