import Foundation
import SwiftData

/// Decides which categories apply to a trip, based on weather triggers.
/// Manual choices the user made are never overridden.
enum CategoryEvaluator {
    @MainActor
    static func apply(to trip: Trip, categories: [PackCategory], units: UnitFormatter, context: ModelContext) {
        let summary = trip.weather
        for category in categories where !category.alwaysIncluded {
            let state = trip.state(for: category) ?? {
                let new = TripCategoryState(isActive: false, source: .none)
                context.insert(new)
                new.category = category
                new.trip = trip
                return new
            }()
            guard state.source != .manual else { continue }

            let matched = summary.map { s in category.triggers.filter { $0.isSatisfied(by: s) } } ?? []
            if matched.isEmpty {
                state.isActive = false
                state.source = .none
                state.reason = ""
            } else {
                state.isActive = true
                state.source = .weather
                state.reason = matched.compactMap { trigger in
                    summary?.value(for: trigger.metric).map { "\(shortLabel(trigger.metric)) \(units.format($0, for: trigger.metric))" }
                }.joined(separator: ", ")
            }
        }
    }

    @MainActor
    static func setManual(_ isActive: Bool, category: PackCategory, trip: Trip, context: ModelContext) {
        let state = trip.state(for: category) ?? {
            let new = TripCategoryState(isActive: false, source: .none)
            context.insert(new)
            new.category = category
            new.trip = trip
            return new
        }()
        state.isActive = isActive
        state.source = .manual
        state.reason = ""
    }

    private static func shortLabel(_ metric: WeatherMetric) -> String {
        switch metric {
        case .highTemp: "High"
        case .lowTemp: "Low"
        case .rainChance: "Rain"
        case .snowfall: "Snow"
        case .maxWind: "Wind"
        case .maxUV: "UV"
        }
    }
}
