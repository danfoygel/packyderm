import Foundation
import SwiftData

enum SeedData {
    private struct Seed {
        var name: String
        var symbol: String
        var always = false
        var triggers: [(WeatherMetric, TriggerComparison, Double)] = []
        var items: [String]
        var critical: Set<String> = []
        var optional: Set<String> = []
    }

    private static let seeds: [Seed] = [
        Seed(name: "Essentials", symbol: "star", always: true,
             items: ["Wallet", "Phone", "Keys", "ID / Driver's license", "Medications", "Glasses / contacts"],
             critical: ["Wallet", "Phone", "Keys", "ID / Driver's license", "Medications"]),
        Seed(name: "Clothing", symbol: "tshirt", always: true,
             items: ["Underwear", "Socks", "T-shirts", "Pants", "Pajamas", "Comfortable shoes", "Belt"],
             optional: ["Belt"]),
        Seed(name: "Toiletries", symbol: "shower", always: true,
             items: ["Toothbrush", "Toothpaste", "Deodorant", "Shampoo", "Razor", "Hairbrush", "Lip balm"],
             optional: ["Shampoo"]),
        Seed(name: "Tech", symbol: "bolt", always: true,
             items: ["Phone charger", "Laptop", "Laptop charger", "Headphones", "Power bank", "Travel adapter"],
             critical: ["Phone charger"], optional: ["Power bank", "Travel adapter"]),
        Seed(name: "Rainy weather", symbol: "cloud.rain",
             triggers: [(.rainChance, .atLeast, 40)],
             items: ["Rain jacket", "Umbrella", "Waterproof shoes"],
             optional: ["Waterproof shoes"]),
        Seed(name: "Cold weather", symbol: "thermometer.snowflake",
             triggers: [(.lowTemp, .atMost, 7)],
             items: ["Warm coat", "Sweater", "Hat", "Gloves", "Scarf", "Thermal layer"],
             optional: ["Thermal layer"]),
        Seed(name: "Snow", symbol: "snowflake",
             triggers: [(.snowfall, .atLeast, 1)],
             items: ["Snow boots", "Wool socks", "Hand warmers"]),
        Seed(name: "Hot weather", symbol: "sun.max",
             triggers: [(.highTemp, .atLeast, 27)],
             items: ["Shorts", "Sandals", "Sun hat", "Light shirts", "Water bottle"]),
        Seed(name: "Strong sun", symbol: "sunglasses",
             triggers: [(.maxUV, .atLeast, 6)],
             items: ["Sunscreen", "Sunglasses", "After-sun lotion"],
             optional: ["After-sun lotion"]),
        Seed(name: "Flying", symbol: "airplane",
             items: ["Boarding pass", "Passport", "Neck pillow", "Snacks", "Liquids bag"],
             critical: ["Boarding pass"], optional: ["Neck pillow"]),
        Seed(name: "International", symbol: "globe",
             items: ["Passport", "Visa documents", "Foreign currency", "Travel insurance info"],
             critical: ["Passport"]),
        Seed(name: "Business", symbol: "briefcase",
             items: ["Dress shirts", "Blazer", "Dress shoes", "Notebook", "Business cards"],
             optional: ["Business cards"]),
        Seed(name: "Beach / swimming", symbol: "beach.umbrella",
             items: ["Swimsuit", "Beach towel", "Flip-flops", "Goggles"],
             optional: ["Goggles"]),
        Seed(name: "Hiking", symbol: "figure.hiking",
             items: ["Hiking boots", "Daypack", "Trail snacks", "First-aid kit", "Headlamp"],
             optional: ["Headlamp"]),
    ]

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<PackCategory>())) ?? 0
        guard count == 0 else { return }

        for (index, seed) in seeds.enumerated() {
            let category = PackCategory(name: seed.name, symbol: seed.symbol, sortOrder: index, alwaysIncluded: seed.always)
            context.insert(category)
            for (itemIndex, name) in seed.items.enumerated() {
                let item = PackItem(name: name, sortOrder: itemIndex,
                                    isCritical: seed.critical.contains(name),
                                    isOptional: seed.optional.contains(name))
                context.insert(item)
                item.category = category
            }
            for (metric, comparison, threshold) in seed.triggers {
                let trigger = WeatherTrigger(metric: metric, comparison: comparison, threshold: threshold)
                context.insert(trigger)
                trigger.category = category
            }
        }
        try? context.save()
    }
}
