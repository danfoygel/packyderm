import SwiftData
import SwiftUI

@main
struct PackydermApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([PackCategory.self, PackItem.self, WeatherTrigger.self,
                             Trip.self, TripLeg.self, TripCategoryState.self, TripEntry.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Could not open data store: \(error)")
        }
        SeedData.seedIfNeeded(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @AppStorage(SettingsKey.temperatureUnit) private var unitRaw = TemperatureUnit.localeDefault.rawValue

    var body: some View {
        TripsListView()
            .environment(\.units, UnitFormatter(temperatureUnit: TemperatureUnit(rawValue: unitRaw) ?? .localeDefault))
            #if DEBUG
            .task { await DemoCalendar.seedIfRequested() }
            #endif
    }
}
