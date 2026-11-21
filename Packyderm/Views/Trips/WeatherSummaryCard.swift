import SwiftUI

struct WeatherSummaryCard: View {
    let summary: WeatherSummary
    @Environment(\.units) private var units
    @State private var showDays = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                stat("High", value: summary.high.map(units.temp) ?? "–", symbol: "thermometer.sun.fill", tint: .orange)
                stat("Low", value: summary.low.map(units.temp) ?? "–", symbol: "thermometer.snowflake", tint: .blue)
                stat("Rain", value: summary.rainChanceAnyDay.map { "\(Int($0.rounded()))%" } ?? "–", symbol: "umbrella.fill", tint: .teal)
            }

            let details = detailLines
            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(details, id: \.self) { line in
                        Text(line)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if summary.hasHistoricalDays {
                Label("Some days are beyond the forecast range and use typical weather from past years.", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup(isExpanded: $showDays) {
                VStack(spacing: 8) {
                    ForEach(summary.days) { day in
                        DayWeatherRow(day: day, showPlace: Set(summary.days.map(\.placeName)).count > 1)
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Day by day").font(.subheadline.weight(.medium))
            }
        }
    }

    private var detailLines: [String] {
        var lines: [String] = []
        if let wettest = summary.wettestDay, wettest.rainChance >= 30 {
            let rainy = summary.rainyDayCount
            var line = "Wettest: \(wettest.date.formatted(.dateTime.weekday(.wide))) (\(Int(wettest.rainChance.rounded()))%)"
            if rainy > 1 { line += " · \(rainy) likely-rain days" }
            lines.append(line)
        }
        if summary.totalPrecipitation >= 1 {
            lines.append("Total rain: \(units.precipitation(summary.totalPrecipitation))")
        }
        if summary.totalSnowfall >= 0.5 {
            lines.append("Snow: \(units.snow(summary.totalSnowfall))")
        }
        var misc: [String] = []
        if let wind = summary.maxWind { misc.append("Max wind \(units.wind(wind))") }
        if let uv = summary.maxUV { misc.append("UV up to \(Int(uv.rounded()))") }
        if !misc.isEmpty { lines.append(misc.joined(separator: " · ")) }
        return lines
    }

    private func stat(_ label: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .font(.title3)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DayWeatherRow: View {
    let day: DayWeather
    let showPlace: Bool
    @Environment(\.units) private var units

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.subheadline)
                if showPlace {
                    Text(day.placeName.components(separatedBy: ",").first ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, alignment: .leading)
            Image(systemName: day.symbolName)
                .accessibilityLabel(day.condition)
                .symbolRenderingMode(.multicolor)
                .frame(width: 28)
            Text("\(units.temp(day.low)) / \(units.temp(day.high))")
                .font(.subheadline.monospacedDigit())
            Spacer()
            HStack(spacing: 2) {
                Image(systemName: "drop.fill")
                Text("\(Int(day.rainChance.rounded()))%")
                    .lineLimit(1)
            }
            .font(.caption.monospacedDigit())
            .frame(width: 44, alignment: .trailing)
            .foregroundStyle(day.rainChance >= 50 ? .blue : .secondary)
            if day.source == .historical {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Typical, not forecast")
            }
        }
    }
}
