import CoreLocation
import Foundation
import WeatherKit

/// Weather from Apple WeatherKit.
/// Days within the 10-day forecast window use the forecast; later days use an
/// average of the same dates over the previous three years.
struct TripWeatherService {
    struct LegRequest {
        var place: Place
        var start: Date
        var end: Date
    }

    static let forecastHorizonDays = 9
    private static let historyYears = 3

    private var calendar: Calendar { .current }
    private var service: WeatherKit.WeatherService { .shared }

    func summary(for legs: [LegRequest]) async throws -> WeatherSummary {
        var days: [DayWeather] = []
        for leg in legs {
            days += try await weather(for: leg)
        }
        days.sort { $0.date < $1.date }
        return WeatherSummary(days: days)
    }

    static func attribution() async throws -> WeatherAttribution {
        try await WeatherKit.WeatherService.shared.attribution
    }

    private func weather(for leg: LegRequest) async throws -> [DayWeather] {
        let today = calendar.startOfDay(for: .now)
        let horizon = calendar.date(byAdding: .day, value: Self.forecastHorizonDays, to: today)!
        let start = calendar.startOfDay(for: leg.start)
        let end = calendar.startOfDay(for: max(leg.end, leg.start))

        var result: [DayWeather] = []
        if start <= horizon {
            result += try await forecast(place: leg.place, from: start, to: min(end, horizon))
        }
        if end > horizon {
            let histStart = max(start, calendar.date(byAdding: .day, value: 1, to: horizon)!)
            result += try await historical(place: leg.place, from: histStart, to: end)
        }
        return result
    }

    // MARK: Forecast

    private func forecast(place: Place, from start: Date, to end: Date) async throws -> [DayWeather] {
        try await dailyWeather(place: place, from: start, to: end).map { day in
            convert(day, place: place, date: localDay(day.date, place: place),
                    rainChance: day.precipitationChance * 100, source: .forecast)
        }
    }

    // MARK: Historical averages

    private func historical(place: Place, from start: Date, to end: Date) async throws -> [DayWeather] {
        var samples: [DayWeather] = []
        var lastError: Error?
        for yearsBack in 1...Self.historyYears {
            guard let s = calendar.date(byAdding: .year, value: -yearsBack, to: start),
                  let e = calendar.date(byAdding: .year, value: -yearsBack, to: end) else { continue }
            let days: [WeatherKit.DayWeather]
            do {
                days = try await dailyWeather(place: place, from: s, to: e)
            } catch {
                lastError = error
                continue
            }
            for day in days {
                guard let shifted = calendar.date(byAdding: .year, value: yearsBack, to: localDay(day.date, place: place)) else { continue }
                samples.append(convert(day, place: place, date: shifted, rainChance: 0, source: .historical))
            }
        }
        guard !samples.isEmpty else { throw lastError ?? TripWeatherError.noData }

        // Average each calendar day across the years we got.
        let grouped = Dictionary(grouping: samples) { $0.date }
        return grouped.keys.sorted().compactMap { date in
            guard let samples = grouped[date], let first = samples.first else { return nil }
            let n = Double(samples.count)
            func avg(_ key: KeyPath<DayWeather, Double>) -> Double { samples.map { $0[keyPath: key] }.reduce(0, +) / n }
            let wetYears = samples.filter { $0.precipitation >= 1 }.count
            // Most common condition across years
            let typical = Dictionary(grouping: samples, by: \.symbolName).max { $0.value.count < $1.value.count }?.value.first ?? first
            return DayWeather(
                date: date, placeName: place.name,
                high: avg(\.high), low: avg(\.low),
                // Smoothed so a handful of years never reads as 0% or 100% certain.
                rainChance: (Double(wetYears) + 0.5) / (n + 1) * 100,
                precipitation: avg(\.precipitation), snowfall: avg(\.snowfall), maxWind: avg(\.maxWind),
                uvIndex: nil,
                symbolName: typical.symbolName, condition: typical.condition,
                source: .historical)
        }
    }

    // MARK: Plumbing

    /// Daily weather whose local date falls within [start, end].
    private func dailyWeather(place: Place, from start: Date, to end: Date) async throws -> [WeatherKit.DayWeather] {
        // Pad a day each side: WeatherKit days begin at local midnight in the destination's time zone.
        let queryStart = calendar.date(byAdding: .day, value: -1, to: start)!
        let queryEnd = calendar.date(byAdding: .day, value: 2, to: end)!
        let forecast: Forecast<WeatherKit.DayWeather>
        do {
            forecast = try await service.weather(for: place.location, including: .daily(startDate: queryStart, endDate: queryEnd))
        } catch {
            throw TripWeatherError.unavailable(error)
        }
        return forecast.forecast.filter {
            let day = localDay($0.date, place: place)
            return day >= start && day <= end
        }
    }

    /// The destination-local calendar date of a WeatherKit day, as start-of-day in the device calendar.
    private func localDay(_ date: Date, place: Place) -> Date {
        // Approximate the destination's time zone from longitude; only the date matters,
        // and local noon is far from midnight either way.
        let offsetHours = (place.longitude / 15).rounded()
        var destination = Calendar(identifier: .gregorian)
        destination.timeZone = TimeZone(secondsFromGMT: Int(offsetHours) * 3600) ?? .gmt
        let parts = destination.dateComponents([.year, .month, .day], from: date.addingTimeInterval(12 * 3600))
        return calendar.date(from: parts).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: date)
    }

    private func convert(_ day: WeatherKit.DayWeather, place: Place, date: Date, rainChance: Double, source: WeatherSource) -> DayWeather {
        let amounts = day.precipitationAmountByType
        let wind = day.highWindSpeed ?? day.wind.speed
        return DayWeather(
            date: date, placeName: place.name,
            high: day.highTemperature.converted(to: .celsius).value,
            low: day.lowTemperature.converted(to: .celsius).value,
            rainChance: rainChance,
            precipitation: amounts.precipitation.converted(to: .millimeters).value,
            snowfall: amounts.snowfallAmount.amount.converted(to: .centimeters).value,
            maxWind: wind.converted(to: .kilometersPerHour).value,
            uvIndex: source == .forecast ? Double(day.uvIndex.value) : nil,
            symbolName: day.symbolName,
            condition: day.condition.description,
            source: source)
    }
}

enum TripWeatherError: LocalizedError {
    case noData
    case unavailable(Error)

    var errorDescription: String? {
        switch self {
        case .noData: "No weather data available for these dates."
        case .unavailable: "Couldn't reach Apple Weather. Check your connection and that WeatherKit is enabled for this app."
        }
    }
}
