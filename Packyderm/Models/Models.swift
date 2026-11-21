import Foundation
import SwiftData

// MARK: - Library (persistent across trips)

@Model
final class PackCategory {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "suitcase"
    var sortOrder: Int = 0
    /// Always part of every trip (e.g. Essentials).
    var alwaysIncluded: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \PackItem.category)
    var items: [PackItem] = []
    @Relationship(deleteRule: .cascade, inverse: \WeatherTrigger.category)
    var triggers: [WeatherTrigger] = []

    init(name: String, symbol: String, sortOrder: Int, alwaysIncluded: Bool = false) {
        self.name = name
        self.symbol = symbol
        self.sortOrder = sortOrder
        self.alwaysIncluded = alwaysIncluded
    }

    var sortedItems: [PackItem] {
        items.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
}

@Model
final class PackItem {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    var notes: String = ""
    // Persistent flags
    var isCritical: Bool = false
    var isOptional: Bool = false
    var category: PackCategory?

    init(name: String, sortOrder: Int, isCritical: Bool = false, isOptional: Bool = false) {
        self.name = name
        self.sortOrder = sortOrder
        self.isCritical = isCritical
        self.isOptional = isOptional
    }
}

enum WeatherMetric: String, Codable, CaseIterable, Identifiable {
    case highTemp, lowTemp, rainChance, snowfall, maxWind, maxUV

    var id: String { rawValue }

    var label: String {
        switch self {
        case .highTemp: "Highest temperature"
        case .lowTemp: "Lowest temperature"
        case .rainChance: "Chance of rain"
        case .snowfall: "Total snowfall"
        case .maxWind: "Max wind"
        case .maxUV: "Max UV index"
        }
    }

    var symbol: String {
        switch self {
        case .highTemp: "thermometer.sun"
        case .lowTemp: "thermometer.snowflake"
        case .rainChance: "cloud.rain"
        case .snowfall: "snowflake"
        case .maxWind: "wind"
        case .maxUV: "sun.max"
        }
    }
}

enum TriggerComparison: String, Codable, CaseIterable, Identifiable {
    case atLeast, atMost
    var id: String { rawValue }
    var symbol: String { self == .atLeast ? "≥" : "≤" }
}

/// Activates its category when the trip's weather summary meets the condition.
/// Thresholds are stored in canonical units: °C, %, cm, km/h, UV index.
@Model
final class WeatherTrigger {
    var id: UUID = UUID()
    var metricRaw: String = WeatherMetric.rainChance.rawValue
    var comparisonRaw: String = TriggerComparison.atLeast.rawValue
    var threshold: Double = 0
    var category: PackCategory?

    init(metric: WeatherMetric, comparison: TriggerComparison, threshold: Double) {
        self.metricRaw = metric.rawValue
        self.comparisonRaw = comparison.rawValue
        self.threshold = threshold
    }

    var metric: WeatherMetric {
        get { WeatherMetric(rawValue: metricRaw) ?? .rainChance }
        set { metricRaw = newValue.rawValue }
    }

    var comparison: TriggerComparison {
        get { TriggerComparison(rawValue: comparisonRaw) ?? .atLeast }
        set { comparisonRaw = newValue.rawValue }
    }

    func isSatisfied(by summary: WeatherSummary) -> Bool {
        guard let value = summary.value(for: metric) else { return false }
        return comparison == .atLeast ? value >= threshold : value <= threshold
    }
}

// MARK: - Trips

@Model
final class Trip {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var startDate: Date = Date()
    var endDate: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \TripLeg.trip)
    var legs: [TripLeg] = []
    @Relationship(deleteRule: .cascade, inverse: \TripCategoryState.trip)
    var categoryStates: [TripCategoryState] = []
    @Relationship(deleteRule: .cascade, inverse: \TripEntry.trip)
    var entries: [TripEntry] = []
    var weatherData: Data?
    var weatherFetchedAt: Date?

    init(name: String, startDate: Date, endDate: Date) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
    }

    var sortedLegs: [TripLeg] {
        legs.sorted { $0.startDate < $1.startDate }
    }

    var weather: WeatherSummary? {
        get { weatherData.flatMap { try? JSONDecoder().decode(WeatherSummary.self, from: $0) } }
        set { weatherData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var isPast: Bool { endDate < Calendar.current.startOfDay(for: .now) }

    func state(for category: PackCategory) -> TripCategoryState? {
        categoryStates.first { $0.category?.id == category.id }
    }

    func isActive(_ category: PackCategory) -> Bool {
        category.alwaysIncluded || (state(for: category)?.isActive ?? false)
    }

    func entry(for item: PackItem) -> TripEntry? {
        entries.first { $0.item?.id == item.id }
    }

    /// Returns the entry for an item, creating it if needed.
    func ensureEntry(for item: PackItem, in context: ModelContext) -> TripEntry {
        if let existing = entry(for: item) { return existing }
        let entry = TripEntry(itemName: item.name)
        context.insert(entry)
        entry.item = item
        entry.trip = self
        return entry
    }
}

@Model
final class TripLeg {
    var id: UUID = UUID()
    var placeName: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var startDate: Date = Date()
    var endDate: Date = Date()
    var trip: Trip?

    init(placeName: String, latitude: Double, longitude: Double, startDate: Date, endDate: Date) {
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.startDate = startDate
        self.endDate = endDate
    }
}

enum ActivationSource: String, Codable {
    case manual, weather, none
}

@Model
final class TripCategoryState {
    var id: UUID = UUID()
    var isActive: Bool = false
    var sourceRaw: String = ActivationSource.none.rawValue
    /// Human-readable explanation, e.g. "Rain chance 72%".
    var reason: String = ""
    var category: PackCategory?
    var trip: Trip?

    init(isActive: Bool, source: ActivationSource, reason: String = "") {
        self.isActive = isActive
        self.sourceRaw = source.rawValue
        self.reason = reason
    }

    var source: ActivationSource {
        get { ActivationSource(rawValue: sourceRaw) ?? .none }
        set { sourceRaw = newValue.rawValue }
    }
}

@Model
final class TripEntry {
    var id: UUID = UUID()
    /// Snapshot so history survives item deletion.
    var itemName: String = ""
    var isPacked: Bool = false
    // Per-trip flags
    var didntUse: Bool = false
    var helpful: Bool = false
    var item: PackItem?
    var trip: Trip?

    init(itemName: String) {
        self.itemName = itemName
    }
}
