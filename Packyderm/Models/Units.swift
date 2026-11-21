import Foundation
import SwiftUI

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case fahrenheit, celsius
    var id: String { rawValue }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }

    static var localeDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

enum SettingsKey {
    static let temperatureUnit = "temperatureUnit"
    static let homeName = "homeName"
    static let homeLatitude = "homeLatitude"
    static let homeLongitude = "homeLongitude"
    static let lookaheadDays = "lookaheadDays"
    static let speechRate = "speechRate"
    static let pauseBetweenItems = "pauseBetweenItems"
    static let listenTimeout = "listenTimeout"
}

/// Converts between canonical storage units (°C, mm, cm, km/h) and the user's preference.
struct UnitFormatter {
    var temperatureUnit: TemperatureUnit

    var usesImperial: Bool { temperatureUnit == .fahrenheit }

    func temp(_ celsius: Double) -> String {
        "\(Int(displayTemp(celsius).rounded()))°"
    }

    func displayTemp(_ celsius: Double) -> Double {
        usesImperial ? celsius * 9 / 5 + 32 : celsius
    }

    func celsius(fromDisplay value: Double) -> Double {
        usesImperial ? (value - 32) * 5 / 9 : value
    }

    func precipitation(_ mm: Double) -> String {
        usesImperial ? String(format: "%.1f in", mm / 25.4) : String(format: "%.0f mm", mm)
    }

    func snow(_ cm: Double) -> String {
        usesImperial ? String(format: "%.1f in", cm / 2.54) : String(format: "%.0f cm", cm)
    }

    func wind(_ kmh: Double) -> String {
        usesImperial ? "\(Int((kmh / 1.609).rounded())) mph" : "\(Int(kmh.rounded())) km/h"
    }

    // MARK: Trigger thresholds

    func displayValue(_ canonical: Double, for metric: WeatherMetric) -> Double {
        switch metric {
        case .highTemp, .lowTemp: displayTemp(canonical)
        case .snowfall: usesImperial ? canonical / 2.54 : canonical
        case .maxWind: usesImperial ? canonical / 1.609 : canonical
        case .rainChance, .maxUV: canonical
        }
    }

    func canonicalValue(_ display: Double, for metric: WeatherMetric) -> Double {
        switch metric {
        case .highTemp, .lowTemp: celsius(fromDisplay: display)
        case .snowfall: usesImperial ? display * 2.54 : display
        case .maxWind: usesImperial ? display * 1.609 : display
        case .rainChance, .maxUV: display
        }
    }

    func unitLabel(for metric: WeatherMetric) -> String {
        switch metric {
        case .highTemp, .lowTemp: temperatureUnit.symbol
        case .rainChance: "%"
        case .snowfall: usesImperial ? "in" : "cm"
        case .maxWind: usesImperial ? "mph" : "km/h"
        case .maxUV: ""
        }
    }

    func step(for metric: WeatherMetric) -> Double {
        switch metric {
        case .rainChance: 5
        case .snowfall: usesImperial ? 0.5 : 1
        case .maxUV: 1
        default: 1
        }
    }

    func format(_ canonical: Double, for metric: WeatherMetric) -> String {
        switch metric {
        case .highTemp, .lowTemp: temp(canonical)
        case .rainChance: "\(Int(canonical.rounded()))%"
        case .snowfall: snow(canonical)
        case .maxWind: wind(canonical)
        case .maxUV: String(format: "%.0f", canonical)
        }
    }

    func describe(_ trigger: WeatherTrigger) -> String {
        let value = displayValue(trigger.threshold, for: trigger.metric)
        let rounded = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "\(trigger.metric.label) \(trigger.comparison.symbol) \(rounded)\(unitLabel(for: trigger.metric))"
    }
}

extension EnvironmentValues {
    @Entry var units = UnitFormatter(temperatureUnit: .localeDefault)
}
