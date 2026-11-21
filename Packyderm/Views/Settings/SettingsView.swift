import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.temperatureUnit) private var unitRaw = TemperatureUnit.localeDefault.rawValue
    @AppStorage(SettingsKey.homeName) private var homeName = ""
    @AppStorage(SettingsKey.homeLatitude) private var homeLatitude = 0.0
    @AppStorage(SettingsKey.homeLongitude) private var homeLongitude = 0.0
    @AppStorage(SettingsKey.lookaheadDays) private var lookaheadDays = 60
    @AppStorage(SettingsKey.speechRate) private var speechRate = ReadAloudDefaults.rate
    @AppStorage(SettingsKey.pauseBetweenItems) private var pause = ReadAloudDefaults.pause
    @AppStorage(SettingsKey.listenTimeout) private var listenTimeout = ReadAloudDefaults.listenTimeout
    @State private var locating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !homeName.isEmpty {
                        Label(homeName, systemImage: "house.fill")
                    }
                    PlacePicker(title: homeName.isEmpty ? "Search for your city" : "Change home city") { place in
                        setHome(place)
                    }
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        HStack {
                            Label("Use current location", systemImage: "location")
                            if locating { Spacer(); ProgressView() }
                        }
                    }
                } header: {
                    Text("Home")
                } footer: {
                    Text("Calendar events more than about 50 miles from home are treated as travel.")
                }

                Section("Calendar") {
                    Stepper("Look ahead \(lookaheadDays) days", value: $lookaheadDays, in: 14...180, step: 7)
                }

                Section("Units") {
                    Picker("Temperature", selection: $unitRaw) {
                        ForEach(TemperatureUnit.allCases) { Text($0.symbol).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Read-aloud") {
                    ReadAloudSpeedControls(rate: $speechRate, pause: $pause)
                    Stepper("Listen up to \(Int(listenTimeout)) s", value: $listenTimeout, in: 3...15, step: 1)
                }

                Section("Weather data") {
                    WeatherAttributionView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func setHome(_ place: Place) {
        homeName = place.name
        homeLatitude = place.latitude
        homeLongitude = place.longitude
    }

    private func useCurrentLocation() async {
        locating = true
        defer { locating = false }
        guard let location = await LocationFetcher().currentLocation() else { return }
        let name = await Geocoder.shared.cityName(for: location) ?? "Current location"
        setHome(Place(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
    }
}
