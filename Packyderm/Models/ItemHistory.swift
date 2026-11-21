import Foundation

/// What past trips say about an item.
struct ItemHistory {
    /// Number of most recent trips in a row where the item was marked "didn't use".
    var unusedStreak: Int = 0
    var helpfulCount: Int = 0
    var tripsTaken: Int = 0

    var badges: [String] {
        var result: [String] = []
        if unusedStreak >= 2 {
            result.append("Didn't use last \(unusedStreak) trips")
        } else if unusedStreak == 1 {
            result.append("Didn't use last trip")
        }
        if helpfulCount > 0 {
            result.append(helpfulCount == 1 ? "Helpful once" : "Helpful \(helpfulCount)×")
        }
        return result
    }

    var isEmpty: Bool { unusedStreak == 0 && helpfulCount == 0 }

    /// Builds history for every item, looking only at trips that ended before `trip` started.
    static func build(for trip: Trip, allTrips: [Trip]) -> [UUID: ItemHistory] {
        let previous = allTrips
            .filter { $0.id != trip.id && $0.startDate < trip.startDate }
            .sorted { $0.startDate > $1.startDate }

        var result: [UUID: ItemHistory] = [:]
        var streakBroken: Set<UUID> = []

        for past in previous {
            for entry in past.entries {
                guard let itemID = entry.item?.id else { continue }
                // Only count trips where the item was actually packed or reviewed.
                guard entry.isPacked || entry.didntUse || entry.helpful else { continue }
                var history = result[itemID] ?? ItemHistory()
                history.tripsTaken += 1
                if entry.helpful { history.helpfulCount += 1 }
                if !streakBroken.contains(itemID) {
                    if entry.didntUse {
                        history.unusedStreak += 1
                    } else {
                        streakBroken.insert(itemID)
                    }
                }
                result[itemID] = history
            }
        }
        return result
    }
}
