import Foundation

enum WeatherSource: String, Codable {
    /// Real forecast (within ~16 days).
    case forecast
    /// Averaged from the same dates in previous years.
    case historical
}

struct DayWeather: Codable, Identifiable, Hashable {
    var date: Date
    var placeName: String
    var high: Double          // °C
    var low: Double           // °C
    var rainChance: Double    // 0–100
    var precipitation: Double // mm
    var snowfall: Double      // cm
    var maxWind: Double       // km/h
    var uvIndex: Double?     // not available for historical days
    var symbolName: String   // SF Symbol from WeatherKit
    var condition: String
    var source: WeatherSource

    var id: String { "\(placeName)-\(date.timeIntervalSince1970)" }
}

struct WeatherSummary: Codable, Hashable {
    var days: [DayWeather]

    var high: Double? { days.map(\.high).max() }
    var low: Double? { days.map(\.low).min() }
    /// Probability it rains at least once during the trip, treating days as independent.
    var rainChanceAnyDay: Double? {
        guard !days.isEmpty else { return nil }
        let dry = days.reduce(1.0) { $0 * (1 - min(max($1.rainChance, 0), 100) / 100) }
        return (1 - dry) * 100
    }
    var wettestDay: DayWeather? { days.max { $0.rainChance < $1.rainChance } }
    var rainyDayCount: Int { days.filter { $0.rainChance >= 50 }.count }
    var totalPrecipitation: Double { days.map(\.precipitation).reduce(0, +) }
    var totalSnowfall: Double { days.map(\.snowfall).reduce(0, +) }
    var maxWind: Double? { days.map(\.maxWind).max() }
    var maxUV: Double? { days.compactMap(\.uvIndex).max() }
    var hasHistoricalDays: Bool { days.contains { $0.source == .historical } }

    func value(for metric: WeatherMetric) -> Double? {
        switch metric {
        case .highTemp: high
        case .lowTemp: low
        case .rainChance: rainChanceAnyDay
        case .snowfall: days.isEmpty ? nil : totalSnowfall
        case .maxWind: maxWind
        case .maxUV: maxUV
        }
    }
}
