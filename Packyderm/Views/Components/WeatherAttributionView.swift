import SwiftUI
import WeatherKit

/// Apple Weather mark and legal link, required wherever WeatherKit data is shown.
struct WeatherAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherAttribution?

    var body: some View {
        HStack(spacing: 8) {
            if let attribution {
                AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(attribution.serviceName)
                }
                .frame(height: 12)
                Link("Other data sources", destination: attribution.legalPageURL)
            }
        }
        .font(.caption2)
        .task { attribution = try? await TripWeatherService.attribution() }
    }
}
