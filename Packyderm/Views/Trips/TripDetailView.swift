import SwiftData
import SwiftUI

struct TripDetailView: View {
    @Bindable var trip: Trip

    @Environment(\.modelContext) private var context
    @Environment(\.units) private var units
    @Query(sort: \PackCategory.sortOrder) private var categories: [PackCategory]
    @Query private var allTrips: [Trip]

    @State private var loadingWeather = false
    @State private var weatherError: String?
    @State private var showingCategories = false
    @State private var showingReadAloud = false
    @State private var hidePacked = false
    @State private var addingTo: PackCategory?
    @State private var newItemName = ""
    @State private var renaming = false
    @State private var renameText = ""

    private var activeCategories: [PackCategory] { categories.filter { trip.isActive($0) } }
    private var activeItems: [PackItem] { activeCategories.flatMap(\.sortedItems) }
    private var history: [UUID: ItemHistory] { ItemHistory.build(for: trip, allTrips: allTrips) }

    private var packedCount: Int { activeItems.filter { trip.entry(for: $0)?.isPacked == true }.count }
    private var criticalRemaining: Int {
        activeItems.filter { $0.isCritical && trip.entry(for: $0)?.isPacked != true }.count
    }

    var body: some View {
        let history = history
        List {
            Section {
                itinerary
            }

            Section("Weather") {
                weatherSection
            }

            Section {
                Button { showingCategories = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Packing for").font(.subheadline).foregroundStyle(.secondary)
                            CategoryChips(categories: activeCategories, trip: trip)
                        }
                        Spacer()
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                .foregroundStyle(.primary)
            }

            Section {
                ProgressRow(packed: packedCount, total: activeItems.count, criticalRemaining: criticalRemaining)
            }

            ForEach(activeCategories) { category in
                let items = category.sortedItems.filter { !hidePacked || trip.entry(for: $0)?.isPacked != true }
                Section {
                    ForEach(items) { item in
                        ChecklistRow(item: item, entry: trip.entry(for: item), history: history[item.id],
                                     onToggle: { toggle(item) },
                                     onDidntUse: { flip(item, \.didntUse) },
                                     onHelpful: { flip(item, \.helpful) })
                    }
                    Button("Add item", systemImage: "plus") {
                        newItemName = ""
                        addingTo = category
                    }
                    .font(.subheadline)
                } header: {
                    Label(category.name, systemImage: category.symbol)
                }
            }
        }
        .navigationTitle(trip.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingReadAloud = true } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .accessibilityLabel("Read aloud")
                .disabled(activeItems.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Hide packed items", systemImage: "eye.slash", isOn: $hidePacked)
                    Button("Refresh weather", systemImage: "arrow.clockwise") { Task { await loadWeather() } }
                    Button("Rename trip", systemImage: "pencil") {
                        renameText = trip.name
                        renaming = true
                    }
                    Button("Uncheck everything", systemImage: "arrow.uturn.backward") {
                        trip.entries.forEach { $0.isPacked = false }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingCategories) {
            TripCategoriesSheet(trip: trip)
        }
        .fullScreenCover(isPresented: $showingReadAloud) {
            ReadAloudView(trip: trip, items: activeItems.filter { trip.entry(for: $0)?.isPacked != true })
        }
        .alert("Add to \(addingTo?.name ?? "")", isPresented: Binding(get: { addingTo != nil }, set: { if !$0 { addingTo = nil } })) {
            TextField("Item name", text: $newItemName)
            Button("Add") { addItem() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Adds the item to this category for all future trips too.")
        }
        .alert("Rename trip", isPresented: $renaming) {
            TextField("Name", text: $renameText)
            Button("Save") { if !renameText.isEmpty { trip.name = renameText } }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            if trip.weather == nil && !trip.isPast { await loadWeather() }
        }
    }

    // MARK: Sections

    private var itinerary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DateRange.format(trip.startDate, trip.endDate))
                .font(.headline)
            ForEach(trip.sortedLegs) { leg in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.tint)
                    Text(leg.placeName)
                    Spacer()
                    if trip.legs.count > 1 {
                        Text(DateRange.format(leg.startDate, leg.endDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var weatherSection: some View {
        if let summary = trip.weather, !summary.days.isEmpty {
            WeatherSummaryCard(summary: summary)
            HStack {
                WeatherAttributionView()
                Spacer()
                if let fetched = trip.weatherFetchedAt {
                    Text("Updated \(fetched.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } else if loadingWeather {
            HStack { ProgressView(); Text("Checking the weather…").foregroundStyle(.secondary) }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let weatherError {
                    Text(weatherError).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Check weather", systemImage: "cloud.sun") { Task { await loadWeather() } }
            }
        }
    }

    // MARK: Actions

    private func loadWeather() async {
        loadingWeather = true
        weatherError = nil
        do {
            try await TripService.refreshWeather(for: trip, units: units, context: context)
        } catch {
            weatherError = error.localizedDescription
        }
        loadingWeather = false
    }

    private func toggle(_ item: PackItem) {
        let entry = trip.ensureEntry(for: item, in: context)
        entry.isPacked.toggle()
    }

    private func flip(_ item: PackItem, _ flag: ReferenceWritableKeyPath<TripEntry, Bool>) {
        let entry = trip.ensureEntry(for: item, in: context)
        entry[keyPath: flag].toggle()
    }

    private func addItem() {
        guard let category = addingTo else { return }
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let item = PackItem(name: name, sortOrder: (category.items.map(\.sortOrder).max() ?? 0) + 1)
        context.insert(item)
        item.category = category
        addingTo = nil
    }
}

// MARK: - Rows

struct ChecklistRow: View {
    let item: PackItem
    let entry: TripEntry?
    let history: ItemHistory?
    var onToggle: () -> Void
    var onDidntUse: () -> Void
    var onHelpful: () -> Void

    private var packed: Bool { entry?.isPacked ?? false }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: packed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(packed ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .strikethrough(packed, color: .secondary)
                            .foregroundStyle(packed ? .secondary : .primary)
                        if item.isCritical { FlagBadge(text: "Critical", color: .red) }
                        if item.isOptional { FlagBadge(text: "Optional", color: .gray) }
                    }
                    let tags = tripTags
                    let badges = history?.badges ?? []
                    if !tags.isEmpty || !badges.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.0) { FlagBadge(text: $0.0, color: $0.1, filled: true) }
                            ForEach(badges, id: \.self) { badge in
                                Label(badge, systemImage: badge.hasPrefix("Didn't") ? "zzz" : "hand.thumbsup")
                                    .font(.caption2)
                                    .foregroundStyle(badge.hasPrefix("Didn't") ? .orange : .green)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button(action: onDidntUse) {
                Label(entry?.didntUse == true ? "Used it" : "Didn't use", systemImage: "zzz")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(action: onHelpful) {
                Label(entry?.helpful == true ? "Not helpful" : "Helpful", systemImage: "hand.thumbsup")
            }
            .tint(.green)
        }
        .contextMenu {
            Button(entry?.didntUse == true ? "Clear “Didn't use”" : "Didn't use", systemImage: "zzz", action: onDidntUse)
            Button(entry?.helpful == true ? "Clear “Helpful”" : "Helpful", systemImage: "hand.thumbsup", action: onHelpful)
        }
    }

    private var tripTags: [(String, Color)] {
        var tags: [(String, Color)] = []
        if entry?.didntUse == true { tags.append(("Didn't use", .orange)) }
        if entry?.helpful == true { tags.append(("Helpful", .green)) }
        return tags
    }
}

struct FlagBadge: View {
    let text: String
    let color: Color
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(filled ? .white : color)
            .background(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.15)), in: .capsule)
    }
}

private struct ProgressRow: View {
    let packed: Int
    let total: Int
    let criticalRemaining: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(packed) of \(total) packed").font(.subheadline.weight(.medium))
                Spacer()
                if criticalRemaining > 0 {
                    Label("\(criticalRemaining) critical left", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if total > 0 && packed == total {
                    Label("All packed!", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            ProgressView(value: total == 0 ? 0 : Double(packed) / Double(total))
                .tint(.green)
        }
    }
}

private struct CategoryChips: View {
    let categories: [PackCategory]
    let trip: Trip

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(categories) { category in
                let weather = trip.state(for: category)?.source == .weather
                HStack(spacing: 4) {
                    Image(systemName: category.symbol)
                    Text(category.name)
                    if weather { Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor) }
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.tint.opacity(0.12), in: .capsule)
            }
        }
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
