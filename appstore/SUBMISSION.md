# App Store submission: Packyderm 1.0

Every App Store Connect field, in the order the site asks for it. Copy each value as-is. Items marked **☐ you** need
something only you can supply. Character limits are noted where they apply, and every value below fits.

---

## 0. Before you start (one-time)

- The support and privacy pages are in `docs/` and served by GitHub Pages from `main`:
  <https://danfoygel.github.io/packyderm/> and <https://danfoygel.github.io/packyderm/privacy.html>.
- WeatherKit has to be enabled for `com.danfoygel.packyderm` under both **Capabilities** and **App Services** in
  Certificates, Identifiers & Profiles (see README). Without it the shipped app gets no weather.

## 1. New App (My Apps → **+** → New App)

| Field | Value |
| --- | --- |
| Platforms | iOS |
| Name | `Packyderm: Packing List` |
| Primary Language | English (U.S.) |
| Bundle ID | `com.danfoygel.packyderm` |
| SKU | `packyderm-ios` |
| User Access | Full Access |

If the name is taken, try `Packyderm – Packing Lists` or `Packyderm Trip Packing`.

## 2. App Information (General → App Information)

| Field | Value |
| --- | --- |
| Subtitle (30) | `Calendar trips, weather-ready` |
| Category: Primary | Travel |
| Category: Secondary | Productivity |
| Content Rights | **Yes**, it shows third-party content (Apple Weather data), and **Yes**, I have the rights to use it (WeatherKit terms). |
| Age Rating | See §6. Result: **4+** |
| Privacy Policy URL | `https://danfoygel.github.io/packyderm/privacy.html` |

**Digital Services Act (EU) trader status:** ☐ you. If you aren't selling the app or running a business, choose
**"This is not a trader account"**. If you choose trader, your address and phone number show publicly in the EU.

## 3. Version page (iOS App → 1.0 Prepare for Submission)

### Promotional Text (170)
```
Add a trip and Packyderm reads your calendar, checks the forecast for each stop, and builds a packing list that adds rain gear, warm layers or sunscreen as needed.
```

### Description (4000)
```
Packyderm builds your packing list from where you're actually going and the weather you'll actually get.

FROM YOUR CALENDAR
Tap New Trip and Packyderm scans the calendars you choose for flights, hotel stays and events far from home. "Flight to Denver", "Hotel Teatro" and a workshop in Boulder become a single trip with dates and stops, ready to confirm or edit. No travel on your calendar? Enter the trip yourself in a few taps.

PACKS FOR THE WEATHER
Packyderm checks Apple Weather for every day and every stop. It uses the 10-day forecast where it can, and typical weather from past years for trips further out. You get one simple summary: the high, the low, the chance of rain, snow and UV. Categories switch on to match: rain gear when showers are likely, warm layers when it's cold, sunscreen when the UV is high. You can always override them.

A LIST THAT LEARNS
Start with a ready-made library covering essentials, clothing, toiletries, tech, flying, international, business, beach and hiking, then make it your own. Mark items as critical so they're never forgotten, or optional so they don't nag you. After each trip, note what you didn't use and what saved the day. Next time, Packyderm reminds you: "Didn't use last 2 trips" or "Helpful 3×".

HANDS-FREE PACKING
Read-aloud mode reads your list one item at a time while you pack. Answer "yes" or "no" out loud, or say "repeat", "back" or "stop". At the end, you can go back over anything you skipped. You can adjust the speaking speed and the pause between items.

PRIVATE BY DESIGN
No account, no ads, no tracking. Your trips and lists stay on your iPhone. Calendar events are read on the device to find trips and are never uploaded.

• Detects trips from flights, hotels, multi-day events and "Trip to…" entries
• Ignores coworkers' out-of-office and other people's plans on shared calendars
• Day-by-day weather for multi-city trips
• Fahrenheit or Celsius, with matching rain, snow and wind units
• Weather triggers you can customize for any category
```

### Keywords (100)
```
travel,checklist,trip,planner,luggage,suitcase,weather,forecast,vacation,flight,itinerary,pack,todo
```

| Field | Value |
| --- | --- |
| Support URL | `https://danfoygel.github.io/packyderm/` |
| Marketing URL | *(optional)* `https://danfoygel.github.io/packyderm/` |
| Version | `1.0` (already set in the build) |
| Copyright | `2026 Dan Foygel` |
| Routing App Coverage File | *(leave blank)* |

### Screenshots
Upload in filename order. App Store Connect asks for the 6.3" size ("iPhone with Dynamic Island (medium display)"):

- `appstore/screenshots/6.3-inch/`: 1206 × 2622, for the required 6.3" slot
- `appstore/screenshots/`: 1320 × 2868 (6.9"), taken on the iPhone 17 Pro Max simulator; the 6.3" set is scaled from these

Packyderm is iPhone-only, so the iPad and Apple Watch tabs don't need screenshots.

### Build
Pick the uploaded 1.0 (1) build (see §8).

### App Review Information

| Field | Value |
| --- | --- |
| Sign-in required | **No** |
| Contact first / last name | Dan / Foygel |
| Phone | ☐ you (only Apple sees the contact fields) |
| Email | ☐ you |

**Notes:**
```
Packyderm needs no account. All data stays on the device.

To try the main flow:
1. Tap New Trip. When asked for a home city, search for any city (e.g. "Boston").
2. Allow calendar access, then choose which calendars to scan. Packyderm looks for flights, hotels and events more than ~50 miles from home. If the review device has no such events, tap "Enter trip manually", tap "Add destination" (e.g. "Denver"), set dates, and tap "Create trip & check weather".
3. The trip shows a weather summary from Apple WeatherKit and a packing list. Categories like Rainy weather or Cold weather switch on automatically from the forecast.
4. The speaker icon on a trip starts Read-aloud: the app speaks each item and listens for "yes" or "no" (microphone + speech recognition, on-device when supported). Yes/No buttons work without the microphone too.

Permissions: Calendar (find trips, read only), Location (optional, "Use current location" for the home city in Settings), Microphone and Speech Recognition (Read-aloud only). Everything works if any permission is denied: trips can be entered manually and Read-aloud has buttons.
```

### Version Release
Recommended: **Manually release this version**, so you can pick the launch moment after approval.

## 4. Pricing and Availability

| Field | Value |
| --- | --- |
| Price | Free (USD 0) |
| Availability | All countries or regions |
| Pre-orders | No |

## 5. App Privacy (General → App Privacy)

**Privacy Policy URL:** same as §2.

**"Do you or your third-party partners collect data from this app?" → No, we do not collect data from this app.**

Why that's accurate: Packyderm has no server, account, analytics, ads or third-party SDKs. Calendar events, the home
location, trips and lists stay on the device. Weather lookups (WeatherKit), place search (MapKit) and speech
recognition, when it isn't on-device, go to Apple. Apple's privacy-label rules don't make developers disclose data
collected by Apple. The label will read **"Data Not Collected"**. The bundled `PrivacyInfo.xcprivacy` declares the same:
no tracking and no collected data.

## 6. Age Ratings questionnaire

Answer **None** to every content-frequency question: violence (cartoon, realistic, prolonged or graphic), sexual
content or nudity, profanity or crude humor, horror or fear themes, alcohol, tobacco or drug use, mature or suggestive
themes, simulated gambling, medical or treatment information, guns or other weapons, contests.

Answer **No** to each in-app feature question: unrestricted web access, user-generated content, messaging or chat,
advertising, gambling, loot boxes, parental controls, age assurance, health or wellness topics.

Result: **4+**.

## 7. Export compliance

Already handled. The build's Info.plist sets `ITSAppUsesNonExemptEncryption = NO`, so App Store Connect won't ask.
The app only uses HTTPS through Apple frameworks, which is exempt.

## 8. Upload the build

```bash
xcodegen generate
open Packyderm.xcodeproj
```

In Xcode: choose **Any iOS Device (arm64)** as the destination, then **Product → Archive**. In the Organizer, use
**Distribute App → App Store Connect → Upload**. Once it finishes processing (about 10–30 min), it appears under the
version's **Build** section. For each later upload, bump `CURRENT_PROJECT_VERSION` in `project.yml`.

## 9. Then

**Add for Review → Submit to App Review.**
