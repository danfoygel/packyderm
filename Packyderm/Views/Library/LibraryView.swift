import SwiftData
import SwiftUI

/// Manage categories, items, persistent flags and weather triggers.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.units) private var units
    @Query(sort: \PackCategory.sortOrder) private var categories: [PackCategory]
    @State private var addingCategory = false
    @State private var newCategoryName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories) { category in
                    NavigationLink {
                        CategoryEditor(category: category)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(category.name, systemImage: category.symbol)
                            Group {
                                if category.alwaysIncluded {
                                    Text("Always included · \(category.items.count) items")
                                } else if !category.triggers.isEmpty {
                                    Text("\(category.triggers.map(units.describe).joined(separator: " or ")) · \(category.items.count) items")
                                } else {
                                    Text("Choose per trip · \(category.items.count) items")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { categories[$0] }.forEach(context.delete)
                }
                .onMove(perform: move)
            }
            .navigationTitle("Packing Library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .bottomBar) {
                    Button("New Category", systemImage: "plus") {
                        newCategoryName = ""
                        addingCategory = true
                    }
                }
            }
            .alert("New category", isPresented: $addingCategory) {
                TextField("Name", text: $newCategoryName)
                Button("Add") {
                    let name = newCategoryName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    context.insert(PackCategory(name: name, symbol: "tag", sortOrder: (categories.last?.sortOrder ?? 0) + 1))
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in reordered.enumerated() { category.sortOrder = index }
    }
}

struct CategoryEditor: View {
    @Bindable var category: PackCategory
    @Environment(\.modelContext) private var context
    @Environment(\.units) private var units
    @State private var newItemName = ""
    @State private var addingTrigger = false

    private static let symbols = ["suitcase", "star", "tshirt", "shower", "bolt", "cloud.rain", "thermometer.snowflake",
                                  "snowflake", "sun.max", "sunglasses", "airplane", "globe", "briefcase", "beach.umbrella",
                                  "figure.hiking", "figure.run", "bicycle", "car", "tent", "camera", "gamecontroller",
                                  "book", "pills", "cross.case", "dog", "figure.and.child.holdinghands", "fork.knife", "tag"]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $category.name)
                Picker("Icon", selection: $category.symbol) {
                    ForEach(Self.symbols, id: \.self) { Image(systemName: $0).tag($0) }
                }
                .pickerStyle(.navigationLink)
                Toggle("Always included", isOn: $category.alwaysIncluded)
            } footer: {
                Text(category.alwaysIncluded ? "Part of every trip." : "Turned on per trip — by you, or automatically by a weather trigger below.")
            }

            if !category.alwaysIncluded {
                Section {
                    ForEach(category.triggers) { trigger in
                        Label(units.describe(trigger), systemImage: trigger.metric.symbol)
                    }
                    .onDelete { offsets in
                        offsets.map { category.triggers[$0] }.forEach(context.delete)
                    }
                    Button("Add weather trigger", systemImage: "cloud.sun") { addingTrigger = true }
                } header: {
                    Text("Weather triggers")
                } footer: {
                    Text("If any trigger matches the trip's forecast, this category is switched on automatically.")
                }
            }

            Section("Items") {
                ForEach(category.sortedItems) { item in
                    ItemEditorRow(item: item)
                }
                .onDelete { offsets in
                    let items = category.sortedItems
                    offsets.map { items[$0] }.forEach(context.delete)
                }
                .onMove { source, destination in
                    var items = category.sortedItems
                    items.move(fromOffsets: source, toOffset: destination)
                    for (index, item) in items.enumerated() { item.sortOrder = index }
                }
                HStack {
                    TextField("New item", text: $newItemName)
                        .onSubmit(addItem)
                    Button("Add", action: addItem)
                        .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle(category.name)
        .toolbar { EditButton() }
        .sheet(isPresented: $addingTrigger) {
            TriggerEditor { metric, comparison, threshold in
                let trigger = WeatherTrigger(metric: metric, comparison: comparison, threshold: threshold)
                context.insert(trigger)
                trigger.category = category
            }
        }
    }

    private func addItem() {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let item = PackItem(name: name, sortOrder: (category.items.map(\.sortOrder).max() ?? 0) + 1)
        context.insert(item)
        item.category = category
        newItemName = ""
    }
}

private struct ItemEditorRow: View {
    @Bindable var item: PackItem

    var body: some View {
        HStack {
            TextField("Item", text: $item.name)
            Spacer()
            Button { item.isCritical.toggle(); if item.isCritical { item.isOptional = false } } label: {
                FlagBadge(text: "Critical", color: .red, filled: item.isCritical)
            }
            .buttonStyle(.borderless)
            Button { item.isOptional.toggle(); if item.isOptional { item.isCritical = false } } label: {
                FlagBadge(text: "Optional", color: .gray, filled: item.isOptional)
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct TriggerEditor: View {
    var onSave: (WeatherMetric, TriggerComparison, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.units) private var units
    @State private var metric: WeatherMetric = .rainChance
    @State private var comparison: TriggerComparison = .atLeast
    @State private var displayValue: Double = 40

    var body: some View {
        NavigationStack {
            Form {
                Picker("When", selection: $metric) {
                    ForEach(WeatherMetric.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                Picker("Is", selection: $comparison) {
                    Text("at least").tag(TriggerComparison.atLeast)
                    Text("at most").tag(TriggerComparison.atMost)
                }
                .pickerStyle(.segmented)
                Stepper(value: $displayValue, step: units.step(for: metric)) {
                    Text("\(displayValue, specifier: displayValue == displayValue.rounded() ? "%.0f" : "%.1f") \(units.unitLabel(for: metric))")
                        .monospacedDigit()
                }
            }
            .navigationTitle("Weather trigger")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: metric) { _, new in
                displayValue = units.displayValue(defaultThreshold(new), for: new).rounded()
                comparison = new == .lowTemp ? .atMost : .atLeast
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(metric, comparison, units.canonicalValue(displayValue, for: metric))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func defaultThreshold(_ metric: WeatherMetric) -> Double {
        switch metric {
        case .highTemp: 27
        case .lowTemp: 7
        case .rainChance: 40
        case .snowfall: 1
        case .maxWind: 40
        case .maxUV: 6
        }
    }
}
