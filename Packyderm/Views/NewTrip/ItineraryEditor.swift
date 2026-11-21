import SwiftUI

/// Confirmation screen: where you'll be on which days, all editable.
struct ItineraryEditor: View {
    @Binding var name: String
    @Binding var legs: [DetectedLeg]
    var evidence: [String]
    var onCreate: () -> Void

    @State private var editingLeg: DetectedLeg?
    @State private var addingLeg = false

    private var sortedIndices: [Int] {
        legs.indices.sorted { legs[$0].start < legs[$1].start }
    }

    var body: some View {
        Form {
            Section("Trip name") {
                TextField("e.g. Denver work trip", text: $name)
            }

            Section {
                if legs.isEmpty {
                    Text("Add at least one destination.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedIndices, id: \.self) { index in
                    Button { editingLeg = legs[index] } label: {
                        LegRow(leg: legs[index])
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    let ids = offsets.map { legs[sortedIndices[$0]].id }
                    legs.removeAll { ids.contains($0.id) }
                }
                Button("Add destination", systemImage: "plus") { addingLeg = true }
            } header: {
                Text("Where you'll be")
            } footer: {
                if !legs.isEmpty {
                    Text("Tap a stop to change the place or dates.")
                }
            }

            if !evidence.isEmpty {
                Section("Based on these events") {
                    ForEach(evidence, id: \.self) { title in
                        Label(title, systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom) {
            Button(action: onCreate) {
                Text("Create trip & check weather")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .disabled(legs.isEmpty)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .sheet(item: $editingLeg) { leg in
            LegEditor(leg: leg) { updated in
                if let i = legs.firstIndex(where: { $0.id == updated.id }) { legs[i] = updated }
                editingLeg = nil
            }
        }
        .sheet(isPresented: $addingLeg) {
            let start = legs.map(\.end).max() ?? Calendar.current.startOfDay(for: .now)
            LegEditor(leg: DetectedLeg(place: Place(name: "", latitude: 0, longitude: 0), start: start, end: start)) { new in
                legs.append(new)
                if name.isEmpty { name = new.place.name.components(separatedBy: ",").first ?? "" }
                addingLeg = false
            }
        }
    }
}

private struct LegRow: View {
    let leg: DetectedLeg

    var body: some View {
        HStack {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            VStack(alignment: .leading) {
                Text(leg.place.name).font(.body)
                let days = DateRange.dayCount(leg.start, leg.end)
                Text("\(DateRange.format(leg.start, leg.end)) · \(days) day\(days == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

struct LegEditor: View {
    @State var leg: DetectedLeg
    var onSave: (DetectedLeg) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Place") {
                    if !leg.place.name.isEmpty {
                        Label(leg.place.name, systemImage: "mappin.and.ellipse")
                    }
                    PlacePicker(title: leg.place.name.isEmpty ? "Search for a city" : "Change place") { leg.place = $0 }
                }
                Section("Dates") {
                    DatePicker("Arrive", selection: $leg.start, displayedComponents: .date)
                    DatePicker("Leave", selection: $leg.end, in: leg.start..., displayedComponents: .date)
                }
            }
            .navigationTitle(leg.place.name.isEmpty ? "New destination" : "Edit stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let cal = Calendar.current
                        leg.start = cal.startOfDay(for: leg.start)
                        leg.end = cal.startOfDay(for: max(leg.end, leg.start))
                        onSave(leg)
                    }
                    .disabled(leg.place.name.isEmpty)
                }
            }
        }
    }
}
