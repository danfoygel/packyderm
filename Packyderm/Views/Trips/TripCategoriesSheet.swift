import SwiftData
import SwiftUI

/// Choose which categories apply to this trip. Weather-triggered ones are pre-set but can be overridden.
struct TripCategoriesSheet: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @Environment(\.units) private var units
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PackCategory.sortOrder) private var categories: [PackCategory]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories.filter { !$0.alwaysIncluded }) { category in
                        row(category)
                    }
                } header: {
                    Text("Optional categories")
                } footer: {
                    Text("Categories with a cloud were switched on by the forecast. Flip any switch to decide yourself; “Reset to weather” hands control back.")
                }
                Section("Always included") {
                    ForEach(categories.filter(\.alwaysIncluded)) { category in
                        Label(category.name, systemImage: category.symbol)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Packing for")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ category: PackCategory) -> some View {
        let state = trip.state(for: category)
        let isOn = Binding(
            get: { trip.isActive(category) },
            set: { CategoryEvaluator.setManual($0, category: category, trip: trip, context: context) }
        )
        return Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Label(category.name, systemImage: category.symbol)
                if state?.source == .weather, let reason = state?.reason, !reason.isEmpty {
                    Label(reason, systemImage: "cloud.sun.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else if state?.source == .manual, !category.triggers.isEmpty {
                    Button("Reset to weather") {
                        state?.source = .none
                        TripService.reevaluateCategories(for: trip, units: units, context: context)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                } else if !category.triggers.isEmpty {
                    Text(category.triggers.map(units.describe).joined(separator: " or "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
