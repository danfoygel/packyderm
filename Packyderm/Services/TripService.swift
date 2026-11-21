import Foundation
import SwiftData

@MainActor
enum TripService {
    static func createTrip(name: String, legs: [DetectedLeg], context: ModelContext) -> Trip {
        let start = legs.map(\.start).min() ?? .now
        let end = legs.map(\.end).max() ?? start
        let trip = Trip(name: name, startDate: start, endDate: end)
        context.insert(trip)
        for leg in legs {
            let model = TripLeg(placeName: leg.place.name, latitude: leg.place.latitude, longitude: leg.place.longitude,
                                startDate: leg.start, endDate: leg.end)
            context.insert(model)
            model.trip = trip
        }
        return trip
    }

    /// Fetches weather for every leg and re-evaluates weather-triggered categories.
    static func refreshWeather(for trip: Trip, units: UnitFormatter, context: ModelContext) async throws {
        let requests = trip.sortedLegs.map {
            TripWeatherService.LegRequest(place: Place(name: $0.placeName, latitude: $0.latitude, longitude: $0.longitude),
                                      start: $0.startDate, end: $0.endDate)
        }
        let summary = try await TripWeatherService().summary(for: requests)
        trip.weather = summary
        trip.weatherFetchedAt = .now
        reevaluateCategories(for: trip, units: units, context: context)
    }

    static func reevaluateCategories(for trip: Trip, units: UnitFormatter, context: ModelContext) {
        let categories = (try? context.fetch(FetchDescriptor<PackCategory>())) ?? []
        CategoryEvaluator.apply(to: trip, categories: categories, units: units, context: context)
        try? context.save()
    }
}
