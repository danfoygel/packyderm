import CoreLocation
import Foundation
import MapKit

struct Place: Hashable, Codable, Identifiable {
    var name: String
    var latitude: Double
    var longitude: Double

    var id: String { "\(name)|\(latitude)|\(longitude)" }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    func distanceKm(to other: Place) -> Double {
        location.distance(from: other.location) / 1000
    }
}

/// Turns free-form location strings into coordinates, with an in-memory cache.
@MainActor
final class Geocoder {
    static let shared = Geocoder()
    private var cache: [String: Place?] = [:]

    func place(for query: String) async -> Place? {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        let result: Place?
        if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
            result = Self.place(from: item, fallbackName: query)
        } else {
            result = nil
        }
        cache[key] = result
        return result
    }

    /// Short, human-friendly name for a coordinate (usually the city).
    func cityName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        return Self.firstNonBlank(item.addressRepresentations?.cityWithContext, item.addressRepresentations?.cityName, item.name)
    }

    static func firstNonBlank(_ candidates: String?...) -> String? {
        candidates.lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    func search(_ query: String) async -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
        return items.prefix(8).map { Self.place(from: $0, fallbackName: query) }
    }

    static func place(from item: MKMapItem, fallbackName: String) -> Place {
        let coordinate = item.location.coordinate
        let name = firstNonBlank(item.addressRepresentations?.cityWithContext, item.name) ?? fallbackName
        return Place(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/// One-shot current location, used for setting the home city.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    func currentLocation() async -> CLLocation? {
        manager.delegate = self
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            default:
                finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
            case .notDetermined: break
            default: self.finish(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
