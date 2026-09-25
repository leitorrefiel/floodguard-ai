# Production Readiness

Verified on 2026-09-25 for Baliwag, Bulacan (approximately 14.9547, 120.8969).

## Data inventory

| Dataset | Runtime use | Coverage and freshness | Status |
| --- | --- | --- | --- |
| Open-Meteo Forecast API | Current model estimate, hourly and daily precipitation | Selected coordinates, `Asia/Manila`; 10-minute fresh cache, stale fallback up to 6 hours | Active |
| RainViewer Weather Maps API | Historical radar raster tiles and timeline | Provider coverage-mask checked per location; past two hours, roughly 10-minute frames; metadata over 35 minutes is stale | Active when covered |
| DENR-MGB Detailed Flood Susceptibility | Static MapLibre raster and point classification | Philippines where MGB polygons exist; static planning context, not a live incident | Active |
| PAGASA NCR PRSD advisories | Official link/reference | Bulacan is in the NCR PRSD warning area; no documented public API was verified | Manual reference |
| DOST-ASTI PhilSensors | Potential observed rain/water-level source | API access requires a formal data request | Blocked pending access |
| FloodGuard community reports | User-submitted coordinates, time, photo, status and source | Local-only reports remain explicitly unverified | Blocked: configured Supabase host is NXDOMAIN |
| Baliwag safety facilities | Evacuation, hospital, fire and related records | No authoritative machine-readable list with verified coordinates/open status was found | Empty by design |

Required attribution is shown on the radar/map UI. RainViewer identifies the
Philippines source as Panahon.gov.ph. Base-map attribution remains managed by the
existing MapLibre style.

## Requested-source decision record

Rechecked against the providers' published pages and live endpoints on
2026-09-25:

| Provider | Access and terms found | FloodGuard decision |
| --- | --- | --- |
| Open-Meteo | Documented coordinate-based forecast API; free endpoint is non-commercial with published call limits; data are CC BY 4.0 and require linked attribution | Active for modelled current conditions and forecasts. It is never labelled as a rain-gauge observation. Linked attribution is displayed beside weather-derived data. |
| RainViewer | Documented public Weather Maps API for personal, educational, and small-scale community use; no API key; mandatory visible attribution; no SLA or posted hard limit | Active for historical radar only when the provider coverage mask confirms the selected point. Responses are cached and failures degrade to an unavailable state. Commercial or high-volume deployment requires contacting RainViewer. |
| PAGASA FloodCaster | Public web application was reachable and describes satellite-derived rainfall plus model forecasts updated twice daily, but no documented public machine API, integration licence, or stable endpoint contract was found | Official external reference only. FloodGuard does not scrape its interface or internal requests and does not present FloodCaster output as an observation. |
| HazardHunterPH | Public basic assessment UI; advanced access is for GeoRiskPH partner organizations. Terms prohibit republishing, copying, or redistributing site material unless specifically allowed | Official external reference only. FloodGuard does not scrape or republish HazardHunterPH layers. Permission or an agency-issued data/service agreement is required before direct integration. |

The RainViewer live payload returned 13 `radar.past` frames and an empty
`radar.nowcast` array during this verification. FloodGuard intentionally parses
only documented historical frames and does not advertise a future nowcast.

## Interpretation rules

- Open-Meteo `current` is modelled/interpolated weather. It is not an observed
  Baliwag rain-gauge measurement.
- A provider-supplied `0` is a valid dry estimate. Missing, null, malformed,
  timed-out, or outdated precipitation is never changed to zero.
- MGB flood susceptibility describes static terrain/hazard context. It does not
  mean a location is flooded now and does not independently confirm a report.
- Community reports remain pending/unverified unless the server has adequate
  independent corroboration. An image score alone cannot create an official
  incident. `verified` is reserved for an authoritative/manual server process.
- The FloodGuard score is a documented rule-based estimate, not trained AI and
  not an official warning. Stale weather yields `Insufficient current data`.
- No reports is not evidence that an area is flood-free.

## Supabase deployment

The configured project `folbvzmvxqjmfzzssshm.supabase.co` returned NXDOMAIN
from both the local router and Google DNS on 2026-09-25. Create or restore a
Supabase project, then run the app with `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY` dart-defines. Until then, remote CRUD, photo upload,
Edge verification, synchronized alert history, and FCM delivery are unavailable;
the app labels its local fallback as unsynced/cache data.

Review and apply scripts to a staging project in this order:

1. Existing `supabase_hazard_report_verification.sql`.
2. Existing `supabase_fcm_push_notifications.sql`.
3. `supabase_production_hardening.sql`.

The hardening migration prevents null-owner report/device writes, protects
server-owned verification and alert fields, makes pending photos owner-readable,
counts independent confirmations server-side, adds geographic push fields, and
adds active-alert deduplication. It does not delete existing reports.

Deploy the updated functions:

```bash
supabase functions deploy verify-hazard-photo
supabase functions deploy verify-hazard-report
supabase functions deploy send-floodguard-notification
supabase secrets set OPENAI_API_KEY=... OPENAI_VISION_MODEL=gpt-5-mini
supabase secrets set FLOODGUARD_ALERT_INGEST_SECRET=<at-least-32-random-characters>
supabase secrets set FIREBASE_PROJECT_ID=... FIREBASE_CLIENT_EMAIL=... FIREBASE_PRIVATE_KEY=...
```

Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY` to deployed functions. Never place service-role,
OpenAI, Firebase private-key, or ingest secrets in the Flutter app.

Broad alert calls must carry `x-floodguard-ingest-secret`, coordinates, a stable
`data.dedupe_key`, and an expiry. Devices without a saved location, or with a
location older than 30 days, are excluded from geographic broadcasts. Per-user
notification preferences are applied before FCM delivery.

## Firebase blocker

Remote FCM is not production-ready in this checkout: `android/app/google-services.json`
is absent and deployed Firebase secrets have not been verified. Local Android
notifications continue to work. Add the Android app in Firebase, place its
generated `google-services.json` in `android/app`, configure the listed Supabase
secrets, then validate one permitted and one disabled preference on physical
devices before claiming remote delivery.

## External-source limitations

- HazardHunterPH/GeoRisk content must not be republished without appropriate
  permission. Its public UI is linked as an official reference; it is not scraped.
- The tested GeoRisk MGB service detail required a token. FloodGuard instead uses
  the anonymously available DENR-MGB public control-map service.
- PAGASA Floodcaster did not provide a verified documented production API during
  this audit. The app does not screen-scrape it.
- Request PhilSensors API access from DOST-ASTI before adding observed rainfall.
- Obtain a signed/current Baliwag CDRRMO facility register containing coordinates,
  category, address, source date, and activation status before populating safety
  facilities. Schools, hospitals, and city hall must not be inferred as open
  evacuation centers.

## Validation record

Automated tests cover dry zero values, missing precipitation, offline stale-cache
fallback, outdated weather, radar no-coverage behavior, pending/high-confidence/
suspicious/expired community reports, and unauthenticated app startup.

Commands run on 2026-09-25:

```text
flutter analyze  -> No issues found
flutter test     -> 16 tests passed
npx deno check   -> 2 Edge Functions passed type checking
```

Live endpoint checks confirmed an Open-Meteo response for Baliwag, current
RainViewer historical metadata, a usable RainViewer coverage-mask pixel, and an
MGB `LF` point classification at the checked Baliwag coordinate. `LF` is recorded
only as static low susceptibility; it is not a city-wide classification or proof
of current safety. Real rainy-condition accuracy still requires comparison with
an independent PAGASA/DOST-ASTI observation at the same time and location.

## Test matrix and observations

| Case | Actual result |
| --- | --- |
| Dry weather | Live Open-Meteo probe returned `0.00 mm` at model time `2026-09-25T17:15`; phone UI showed `Rain estimate 0.0 mm / Modelled` |
| Actual rainy conditions | Not available during this run; synthetic parsing/risk paths passed, but real accuracy is not claimed |
| Missing precipitation | Unit test passed: missing current precipitation throws instead of becoming zero |
| Outdated weather | Unit test passed: a current estimate older than two hours is rejected |
| Offline weather | Unit test passed: failed refresh uses a clearly stale cached response |
| Radar current/coverage | Live metadata returned 13 historical frames and coverage HTTP 200; phone rendered the timestamp, timeline, opacity, legend, and attribution |
| Radar unavailable | Unit test passed: unusable coverage data yields `hasCoverage=false` and no invented raster |
| No official incidents | No machine incident API was asserted; app keeps official advisories separate and shows no fabricated incidents |
| No community reports | Phone showed `0 floods / 0 hazards` and `No confirmed incidents` without declaring the area flood-free |
| Suspicious/expired reports | Existing verification tests passed for duplicate-suspicious and expired/inactive behavior |
| Map pan and layers | Physical-phone pan preserved the GPS marker's geographic position; RainViewer and MGB raster toggles rendered |
| Facilities | `0 facilities` shown; coordinate validation remains blocked pending an authoritative Baliwag register |
| Failed Supabase | Physical phone and desktop both logged DNS failure; UI fell back within the bounded timeout |
| Successful Supabase | Blocked because the configured project is NXDOMAIN; must be retested against the replacement project |
| Notifications | Preference filtering, geographic filtering, dedupe, expiry, and trusted-ingest checks are implemented; end-to-end FCM remains blocked by missing Firebase configuration |
