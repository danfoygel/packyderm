# Packyderm

An iPhone packing-list app (SwiftUI + SwiftData, iOS 26+).

## Build & run

```bash
xcodegen generate          # Packyderm.xcodeproj is generated from project.yml (not checked in)
open Packyderm.xcodeproj
```

WeatherKit needs the app's App ID (`com.danfoygel.packyderm`) to have **WeatherKit enabled under both Capabilities and
App Services** in the Apple Developer portal (Certificates, Identifiers & Profiles → Identifiers). New enablement can take
up to ~30 minutes to start working.

Debug builds can seed sample travel events into the simulator's calendar: launch with `-demoCalendar YES`.

## How it works

| Feature | Where |
| --- | --- |
| Categories, items, persistent flags (critical / optional), weather triggers | `Models/Models.swift`, seeded by `Models/SeedData.swift`, edited in `Views/Library` |
| New trip from calendar | `Services/CalendarTripDetector.swift` → confirm/edit in `Views/NewTrip` |
| Weather + summary | `Services/TripWeatherService.swift` (Apple WeatherKit) → `Views/Trips/WeatherSummaryCard.swift` |
| Weather triggers → categories | `Services/CategoryEvaluator.swift` |
| Per-trip flags (didn't use / helpful) and history badges | `TripEntry` + `Models/ItemHistory.swift` |
| Read-aloud with yes/no voice answers | `Services/ReadAloudController.swift`, `Views/ReadAloud` |

### Calendar detection
The first New Trip asks which calendars to scan, pre-checking the default calendar and any with upcoming flights; the
choice is saved and editable in Settings → Calendars (asked again if none of the saved calendars exist any more). Looks
ahead N days (Settings). Events count as travel when their location is >80 km from your home city, or their title
looks like a flight (“Flight to Denver”, “BOS → DEN”), a stay (hotel / Airbnb / multi-day event), or “Trip to Paris”.
Each day gets the strongest signal (flight > hotel > multi-day event > event); away days with ≤2-day gaps form one trip; a
flight home ends it. Between a flight out and the next flight (≤30 days later) you're assumed to be at the destination, and
non-hotel events more than 300 km from it are ignored. Absence notices (“Kate PTO”, “OOO”, “Sabbatical”) and events
someone else organized without inviting you are skipped, since shared calendars are full of other people's plans.
Consecutive days within 40 km merge into one stop.

### Weather
Uses WeatherKit. Days within the 10-day forecast use it directly. Later days use the average of the same dates over the
past 3 years from WeatherKit's historical data (rain chance = smoothed share of those years with ≥1 mm, so it never shows 0% or 100%). “Rain” in the summary is the chance of rain on at least one day.
Trigger thresholds are stored in °C / % / cm / km/h and shown in your preferred units.

### Category state per trip
Always-included categories are always on. Others are off by default, switched on by matching weather triggers,
and can be overridden manually (manual choices survive weather refreshes; “Reset to weather” undoes them).
