# FloodGuard Field Validation

Verification date: 2026-09-26 (Philippine Standard Time)  
Focus area: Baliwag, Bulacan  
Physical test point: `14.981354, 120.883107` (network/fused fix, 100 m reported accuracy)  
Better available GPS fix: `14.981923, 120.883057` (28.3 m reported accuracy)

## Evidence Rules

- Open-Meteo current values are 15-minute weather-model estimates, not rain-gauge observations.
- RainViewer shows historical composite radar reflectivity. A frame time is a generation time and radar silence does not prove zero rainfall at ground level.
- DENR-MGB flood susceptibility is static hazard context, not a current flood incident.
- A community report remains a community report unless authoritative evidence confirms it.
- `Verified reference` means facility identity and coordinates were cross-checked. It does not mean open, active, safe, or designated for evacuation today.

## Completed Checks

| Test ID | Scenario | Expected | Actual | Result | Evidence |
|---|---|---|---|---|---|
| RF-01 | Physical-device location | Real device coordinate and accuracy, without moving the GPS marker on map taps | Fused/network `14.981354,120.883107`, 100 m; GPS fix `14.981923,120.883057`, 28.3 m | PASS | `adb dumpsys location`, 2026-09-26 |
| RF-02 | Open-Meteo live request | Correct coordinates/timezone; current values labelled model estimates | Requested device point; provider grid `14.938489,120.895515`; `Asia/Manila`; valid 02:45; precipitation 0.00 mm model estimate | PASS | `dart run tool/field_provider_check.dart 14.981354 120.883107` |
| RF-03 | RainViewer metadata | Dynamic historical frames, fresh timestamp, no hardcoded frame URL | 13 frames; generated and latest frame 02:50 PST; coverage mask transparent at Baliwag test point | PASS | RainViewer metadata and coordinate coverage requests, 2026-09-26 |
| RF-04 | Latest radar pixel | No invented rain graphics | Latest tile center was transparent; recorded only as no radar echo at the tested pixel | PASS | Dynamic RainViewer frame path from metadata, 2026-09-26 |
| MAP-01 | MGB context at device point | Susceptibility kept separate from incidents | ArcGIS query returned `MF` (moderate flood susceptibility); UI labels it static | PASS | DENR-MGB FeatureServer query, 2026-09-26 |
| FAC-01 | Safety-facility provenance | Only cross-checked records load; no active evacuation claim | CDRRMO, fire station, and district hospital loaded as verified references with unknown current operating status | PASS | LGU/Provincial sources plus OSM coordinates, verified 2026-09-26 |
| FAC-02 | Official evacuation centers | No inferred school/shelter markers | No evacuation-center records loaded because the available LGU notices do not publish a named coordinate list | PASS | `assets/data/verified_safety_facilities.json` |
| AUTO-01 | Missing rain value | Must not become 0 mm | Parser throws `WeatherException` | PASS | `test/weather_and_radar_service_test.dart` |
| AUTO-02 | Stale/offline weather | Recent cache explicitly marked stale; old/missing cache rejected | Automated cache and outdated-response tests pass | PASS | `flutter test` |
| AUTO-03 | Radar unavailable | No synthetic radar layer | Automated test returns `hasCoverage=false` | PASS | `flutter test` |
| DEVICE-01 | Updated physical-device build | Install without clearing production data; strict Supabase mode retained | Debug APK built from ignored local config and installed with `adb install -r` | PASS | Connected Android device, 2026-09-26 |

## Not Yet Field-Tested

| Test ID | Scenario | Expected | Status / reason |
|---|---|---|---|
| FIELD-RAIN-01 | Rain visibly falling at the device | Record human observation, start/end time, intensity notes, Open-Meteo model valid time/value, RainViewer frame/echo, and official advisory independently | NOT TESTED: no contemporaneous human rain observation was supplied; provider values were not treated as ground truth |
| FIELD-DRY-01 | Visibly dry conditions | Human observation agrees or disagrees with model/radar without forcing either source to be truth | NOT TESTED: requires observer confirmation at the device location |
| REPORT-REAL-01 | Genuine community flood report | Real photo/time/GPS; remains pending or community-qualified; map/history synchronize | NOT TESTED: no genuine incident was available and no incident was fabricated |
| ADVISORY-01 | Current Baliwag-specific official advisory | Show publisher, issue time, geographic scope, and original link | NOT TESTED: no documented machine-readable Baliwag live-advisory feed was available during this check |
| OFFLINE-PHYSICAL-01 | Physical device API outage | Existing map remains usable; cached weather is clearly stale; no false Low Risk | PENDING physical-device network isolation test |
| MAP-PHYSICAL-01 | Updated facility/radar layers on phone | Three verified references render at fixed coordinates; pan/zoom and details remain correct | PASS on 2026-10-14; see final physical-device follow-up below |

## Rain Event Procedure

1. Stand at the test location and wait for a fresh GPS fix; record latitude, longitude, accuracy, and PST time.
2. Independently record `no rain`, `drizzle`, `light`, `moderate`, or `heavy` based on direct observation. Do not derive this entry from FloodGuard.
3. Refresh FloodGuard. Record selected location, Open-Meteo model valid time, current precipitation, forecast hour, fetched time, and freshness badge.
4. Open the map radar. Record the selected historical frame generation time, whether the location has coverage, whether an echo is visible, and radar opacity.
5. Check PAGASA and Baliwag CDRRMO/LGU notices. Record only an advisory that explicitly covers the location and preserve its original issue time/link.
6. Take screenshots of Home, radar controls/legend, selected map point, and any official source page. Never submit a fake community report or send a public alert.
7. Repeat every 10 minutes for at least 30 minutes, then compare source timing and disagreements.

## Rain Event Results Template

| Test ID | Date/time PST | GPS + accuracy | Direct observation | Open-Meteo model valid time / mm | Forecast | RainViewer frame / echo | Official observation/advisory | Expected | Actual | Result | Screenshot |
|---|---|---|---|---|---|---|---|---|---|---|---|
| FIELD-RAIN-___ | YYYY-MM-DD HH:mm | lat, lon, ±m | observer entry | time / value or missing | hour / probability / mm | time / coverage / echo | source + issue time, or none | Labels and timestamps remain distinct | Fill during event | PASS / FAIL / NOT TESTED | path |

## Facility Import

The production dataset is `assets/data/verified_safety_facilities.json`. Use `docs/baliwag_facility_import_template.json` for a CDRRMO-provided list. A record must have an official identity/category source, a traceable coordinate source, a verification date, and a truthful operating-status statement. The loader excludes anything not marked `verified_reference` and rejects non-HTTPS sources or coordinates outside the Baliwag validation area.

## Remaining Limitations

- FloodGuard has no direct Baliwag rain-gauge observation feed. Open-Meteo remains a model source.
- RainViewer coverage exists at the tested point, but composite radar can differ from ground rain and its frames are historical.
- No named, coordinate-bearing, currently active evacuation-center list was found in the reviewed Baliwag LGU pages.
- OpenStreetMap supplies facility coordinates under ODbL; government pages supply facility identity/category. Coordinate survey accuracy has not been independently measured onsite.
- A genuine rainy-event comparison and physical offline cycle still require field conditions and an observer.

## Physical Device Follow-up - 2026-10-14

Device: Infinix X6877 over wireless ADB

Test area: Baliwag, Bulacan

App mode: `SUPABASE_STRICT_REMOTE=true`

Validation after the map isolation fix: `flutter analyze` clean; `flutter test` 22/22 passed.

| Test ID | Scenario | Expected | Actual | Result | Screenshot / log |
|---|---|---|---|---|---|
| DEV-20261014-01 | Home weather labels | Current rainfall is explicitly modelled and timestamped | Open-Meteo valid time 19:30 PHT; 0.0 mm shown as `Modelled`; daily forecast 7.6 mm kept separate | PASS | `docs/field-evidence/2026-10-14-home.png` |
| DEV-20261014-02 | GPS and Locate | Map uses device position; map taps do not redefine GPS | Fused fix `14.981341,120.883174` (100 m); available GPS fix `14.981258,120.883067` (20.2 m); Locate recentered the blue marker | PASS | `docs/field-evidence/2026-10-14-map-relocated.png`; `adb dumpsys location` |
| DEV-20261014-03 | Radar history | Dynamic frame timestamp, coverage, legend, opacity and playback work | Baliwag coverage rendered; latest loaded frame 19:40 PHT; playback changed selection to 19:10 PHT; legend and opacity control visible | PASS | `docs/field-evidence/2026-10-14-radar.png` |
| DEV-20261014-04 | MGB layer separation | Static susceptibility is visually separate from incidents | `MGB Static` toggled independently; provider query at GPS point returned `MF`; incident count remained zero | PASS | `docs/field-evidence/2026-10-14-radar-mgb-facilities.png` |
| DEV-20261014-05 | Verified facility details | Marker shows category, authority, date, coordinate source and cautious status | Baliwag Fire Station marker showed `VERIFIED`, official city-directory source, OSM coordinate source, verification date, and unconfirmed response availability | PASS | `docs/field-evidence/2026-10-14-fire-station-detail.png` |
| DEV-20261014-06 | Map pan and zoom | Geographic sources remain MapLibre-attached; controls do not alter GPS | Pan changed the rendered viewport; mouse-wheel zoom changed scale; Locate returned to the device coordinate | PASS | `docs/field-evidence/2026-10-14-map-after-pan.png`, `2026-10-14-map-after-zoom.png`, `2026-10-14-map-relocated.png` |
| DEV-20261014-07 | Community backend unavailable | No cached community reports in strict mode; independent layers remain usable | Invalid configured project hostname returned NXDOMAIN. App showed zero reports with a visible warning while retaining three verified facilities, radar and MGB | PASS after isolation fix | `docs/field-evidence/2026-10-14-map-offline-reports-3-facilities.png` |
| DEV-20261014-08 | Current provider comparison | Use one coordinate and PHT; never call model/radar a gauge | At 19:45 PHT Open-Meteo returned 0.0 mm model precipitation; RainViewer returned 12 historical frames generated at 19:50 PHT; MGB returned `MF` | PASS | `dart run tool/field_provider_check.dart 14.981341 120.883174` |
| DEV-20261014-09 | Direct rain observation | Independent human observation must be recorded | No observer confirmation was supplied; 0.0 mm model output was not treated as proof of dry ground | NOT TESTED | Await field observer |
| DEV-20261014-10 | Genuine community report synchronization | Genuine report appears in history/map and updates remotely | NOT TESTED during this cycle; no incident was fabricated | NOT TESTED | Requires genuine event and working remote backend |

The earlier NXDOMAIN condition was resolved before the final follow-up below. The restored FloodGuard project resolved through DNS, returned HTTP 200 from the authenticated health endpoint, and was used by the strict-remote physical build. The unrelated `elikha` project was never adopted and no data in it was changed.

PAGASA's 4:25 PM thunderstorm advisory covered parts of Bulacan but did not name Baliwag; a broader thunderstorm watch included Bulacan. Neither was converted into a confirmed Baliwag flood incident. The Baliwag LGU weather page supplied regional weather and dam context, not a local rain-gauge observation at the device point.

## Final Physical Device Validation - 2026-10-14

Device: Infinix X6877 over wireless ADB and scrcpy

Location shown by FloodGuard: `14.98134, 120.88317`

Backend mode: `SUPABASE_STRICT_REMOTE=true`

Backend source shown by the app: `Supabase API`

### Passed Checks

| Test ID | Scenario | Actual result | Result | Evidence |
|---|---|---|---|---|
| FINAL-GPS-01 | Current GPS marker | Blue accuracy marker rendered at the device coordinate near Rose Street; map taps did not redefine it | PASS | `2026-10-14-map-supabase-live.png` |
| FINAL-MAP-02 | Pan, zoom and Locate | The GPS marker moved with map geography during pan, left the viewport after zoom, and returned to the same mapped location with Locate | PASS | `2026-10-14-live-gps-reset.png`, `2026-10-14-live-gps-pan-clean.png`, `2026-10-14-live-gps-zoom-clean.png`, `2026-10-14-live-gps-locate-return.png` |
| FINAL-RADAR-03 | RainViewer historical radar | Dynamic radar loaded with provider frame `10:10 PM PHT`, play control, timeline, opacity, Light/Moderate/Heavy legend, historical wording and RainViewer attribution | PASS | `2026-10-14-live-rainviewer-radar.png` |
| FINAL-MGB-04 | Static susceptibility separation | Layer control says `MGB Static`; details say `Moderate flood susceptibility (static susceptibility, not a current flood)` while current incidents remain zero | PASS | `2026-10-14-live-radar-mgb-static.png`, `2026-10-14-live-mgb-static-label.png` |
| FINAL-FAC-05 | Three verified-reference facilities | Fire Station, CDRRMO and District Hospital retain distinct categories, addresses, sources, verification date and unconfirmed operating status | PASS | `2026-10-14-live-three-facilities.png`, `2026-10-14-live-cdrrmo-detail.png`, earlier fire-station detail evidence |
| FINAL-EVAC-06 | No authoritative evacuation centers | Evacuation Centers mode now shows zero facility markers and the explicit empty state because no official named geocoded list is loaded | PASS after bug fix | `2026-10-14-live-zero-evacuation-centers.png` |
| FINAL-DEMO-07 | No demo content | No demo flood, hazard or facility marker appeared in Home, Hazard Map or Evacuation Centers mode | PASS | Physical screen inspection and production asset loader tests |
| FINAL-SYNC-08 | Supabase report synchronization | Strict-remote app read two remote reports. Both were `suspicious` but expired on 2026-09-02 and 2026-09-05, so the active map correctly showed zero reports instead of stale incidents | PASS | `[Supabase] connected`, `[Supabase] read success count=2`, `[Hazard Map] ... visible=0` |
| FINAL-LINK-09 | Source links | RainViewer attribution opened secure `rainviewer.com`; Open-Meteo source opened secure `open-meteo.com` on the phone | PASS | Android Chrome package/focus and URL-bar UI dumps |
| FINAL-UI-10 | Controls, details and marker selection | Layer controls, radar playback, opacity, facility selection, map details sheet and source metadata rendered and responded on the phone | PASS | Layer, details and CDRRMO screenshots above |

### Issue Found And Fixed

The initial Evacuation Centers physical test incorrectly listed the fire station, CDRRMO and hospital as evacuation centers. The mode now filters strictly for `EmergencyFacilityType.evacuation`; the production dataset contains zero such records. The three records remain available in the general safety-facilities layer. A regression test was added for this filter.

### Screenshots Captured

- `docs/field-evidence/2026-10-14-map-supabase-live.png`
- `docs/field-evidence/2026-10-14-live-layer-controls.png`
- `docs/field-evidence/2026-10-14-live-rainviewer-radar.png`
- `docs/field-evidence/2026-10-14-live-radar-mgb-static.png`
- `docs/field-evidence/2026-10-14-live-mgb-static-label.png`
- `docs/field-evidence/2026-10-14-live-three-facilities.png`
- `docs/field-evidence/2026-10-14-live-cdrrmo-detail.png`
- `docs/field-evidence/2026-10-14-live-gps-reset.png`
- `docs/field-evidence/2026-10-14-live-gps-pan-clean.png`
- `docs/field-evidence/2026-10-14-live-gps-zoom-clean.png`
- `docs/field-evidence/2026-10-14-live-gps-locate-return.png`
- `docs/field-evidence/2026-10-14-live-zero-evacuation-centers.png`

### Data Sources Used

- Open-Meteo forecast/model API for modelled weather and precipitation.
- RainViewer Weather Maps API for dynamic historical composite radar frames.
- DENR-MGB/GeoRisk ArcGIS service for static flood susceptibility.
- FloodGuard Supabase `hazard_reports` for community-report synchronization.
- City Government of Baliwag CDRRMO and city directory pages for facility identity/category.
- Bulacan Provincial Government for Baliuag District Hospital identity.
- OpenStreetMap contributors for facility coordinates and base-map context.

### Failed Or Not Tested

- No check remains failed after the evacuation-center filter fix and physical retest.
- Real rainy-condition validation remains **NOT TESTED** because no direct human observation of falling rain was recorded during this run.
- A genuine active community incident lifecycle remains **NOT TESTED** because the only remote reports were expired and no incident was fabricated.
- No current Baliwag-specific official flood advisory was available for an incident-level test.
- Physical offline/network-loss behavior was not repeated in this final online run; automated stale/offline tests remain the available evidence.

### Known Limitations

- Open-Meteo values are model estimates, not Baliwag rain-gauge observations.
- RainViewer frames are historical composite reflectivity and do not prove surface rainfall or flooding.
- MGB susceptibility is static context and is never treated as a current incident.
- Facility identity and coordinates are verified references, but current opening, emergency availability and evacuation designation remain unconfirmed.
- There is still no authoritative named and geocoded Baliwag evacuation-center list in the app.

## Final QA Follow-up - 2026-10-16

Device: Infinix X6877 over wireless ADB and scrcpy

Location shown by FloodGuard: `14.98134, 120.88317`

Backend mode: `SUPABASE_STRICT_REMOTE=true`

### Offline Physical Test

Android's per-package firewall denied all networking to `com.example.floodguard` while the physical phone, app, and mirror remained observable. The firewall state was restored to its original `allow` / chain-disabled state after the test.

| Test ID | Scenario | Actual result | Result | Evidence |
|---|---|---|---|---|
| QA-OFFLINE-01 | Relaunch with app networking denied | App opened without a crash or freeze; loading completed after the bounded retry period | PASS | `docs/field-evidence/2026-10-16-qa-network-denied-home.png` |
| QA-OFFLINE-02 | Weather and risk during outage | Cached Open-Meteo data was explicitly marked `cached/stale`; combined risk changed to `Insufficient current data` and warned against using it for a safety decision | PASS | `2026-10-16-qa-network-denied-home.png`; physical UI dump |
| QA-OFFLINE-03 | Strict-remote reports during outage | Supabase failed with `SocketException: Failed host lookup`; Home showed `Remote community reports unavailable`; strict mode displayed no local report as a remote success | PASS | Device logcat and Home screenshot |
| QA-OFFLINE-04 | Navigation and local-safe screens | Forecast remained usable and marked its model data `cached/stale`; cached profile and local Safety Tips/checklist remained navigable | PASS | `2026-10-16-qa-network-denied-forecast.png`, physical UI dump, `2026-10-16-qa-network-unavailable-safety-tips.png` |
| QA-OFFLINE-05 | Restore connectivity | Package networking returned to `allow`; Supabase connected and read two existing rows; current Open-Meteo model time advanced to 20:15 PHT | PASS | `2026-10-16-qa-online-resynchronized.png`; `[Supabase] connected`; `[Supabase] read success count=2` |

This test used Android's device-native per-package firewall rather than turning off the Wi-Fi radio, because wireless ADB and scrcpy depend on that radio. It exercised the installed app's real no-network paths for Open-Meteo and Supabase without losing physical observation.

### Temporary Active Incident Lifecycle

One authenticated test-only report was created through the normal Report Hazard UI and then completely removed. Its ID was `edeb544b-a314-4d23-9f02-037c45493f9d`; no pre-existing community row was modified or deleted.

| Stage | Actual result | Result | Evidence |
|---|---|---|---|
| CREATE | Supabase created the temporary report at GPS `14.9813431,120.8831741`; photo uploaded under the authenticated user's path; initial status was `pending` | PASS | `[Supabase] create success`; `2026-10-16-qa-report-created.png` |
| READ | Report History showed 3/3 rows and the map showed one community flood marker while still stating `No confirmed incidents` | PASS | `2026-10-16-qa-report-history.png`, `2026-10-16-qa-report-map-pending.png` |
| UPDATE | Severity changed from Moderate to High and the description changed; direct Supabase read and map detail both reflected the update | PASS | `[Supabase] update success`; `2026-10-16-qa-report-map-updated.png` |
| VERIFICATION | Status remained `pending`, confidence was 25/100, and reason stated that image verification was temporarily unavailable; it was never labelled official or confirmed | PASS | Direct Supabase read and `2026-10-16-qa-report-map-details.png` |
| DELETE | UI deletion removed the row and its exact photo path; history returned to 2/2, direct REST read returned zero rows, and report confirmations returned zero rows | PASS | `[Supabase] delete success`; `[Supabase] photo delete success`; `2026-10-16-qa-report-deleted.png` |

### Map Integrity Recheck

- Refreshed strict-remote map after cleanup: two stored rows read, zero active/visible community incidents, zero flood markers, zero other-hazard markers, and three verified-reference facilities.
- Evacuation Centers mode: zero markers and the explicit authoritative-list empty state.
- No demo flood, hazard, facility, or fake evacuation-center data appeared.
- RainViewer remains a historical radar layer; DENR-MGB remains static susceptibility; neither is counted as a current incident.

Evidence: `docs/field-evidence/2026-10-16-qa-map-clean-after-delete.png` and `docs/field-evidence/2026-10-16-qa-zero-evacuation-centers.png`.

### Actual Rain Validation: PENDING REAL RAIN

Use this checklist only while rain is directly observed at the physical test location:

- [ ] Record date and Philippine local time.
- [ ] Record physical location, GPS coordinates, and accuracy.
- [ ] Record direct human observation: `no rain`, `light`, `moderate`, or `heavy`.
- [ ] Record Open-Meteo model precipitation and model-valid timestamp.
- [ ] Record the selected RainViewer historical frame timestamp, coverage, and visible echo.
- [ ] Record FloodGuard's displayed condition and freshness label.
- [ ] Capture Home and radar screenshots with timestamps visible.
- [ ] Note any official advisory separately with publisher, scope, issue time, and source link.
- [ ] Compare timing and labels without treating Open-Meteo as a rain-gauge observation.

Status: **PENDING REAL RAIN**. No falling-rain observation was recorded during this QA cycle.

### 2026-10-16 Screenshots Captured

- `docs/field-evidence/2026-10-16-qa-network-denied-home.png`
- `docs/field-evidence/2026-10-16-qa-network-denied-forecast.png`
- `docs/field-evidence/2026-10-16-qa-network-unavailable-safety-tips.png`
- `docs/field-evidence/2026-10-16-qa-online-resynchronized.png`
- `docs/field-evidence/2026-10-16-qa-report-created.png`
- `docs/field-evidence/2026-10-16-qa-report-history.png`
- `docs/field-evidence/2026-10-16-qa-report-map-pending.png`
- `docs/field-evidence/2026-10-16-qa-report-map-details.png`
- `docs/field-evidence/2026-10-16-qa-report-map-updated.png`
- `docs/field-evidence/2026-10-16-qa-report-deleted.png`
- `docs/field-evidence/2026-10-16-qa-map-clean-after-delete.png`
- `docs/field-evidence/2026-10-16-qa-zero-evacuation-centers.png`

### Final Known Limitations

- Actual rainy-condition comparison remains pending direct human observation.
- Open-Meteo is a weather-model source, not a Baliwag rain gauge.
- RainViewer is historical composite radar and cannot confirm ground rainfall or flooding.
- No authoritative named/geocoded Baliwag evacuation-center list is available in the app.
- Facility opening, active emergency availability, and evacuation designation are not claimed.
- Firebase Cloud Messaging remains unconfigured; local notifications are unaffected.
- The standalone `tool/supabase_backend_check.dart` was invoked on 2026-10-16 but could not authenticate because this shell does not contain `SUPABASE_TEST_EMAIL` or `SUPABASE_TEST_PASSWORD`. The physical strict-remote app independently reconnected, authenticated its saved session, logged `[Supabase] connected`, and read the original two rows after network restoration.

### Final Automated Validation

- `flutter analyze`: PASS, no issues found (89.4 seconds).
- `flutter test`: PASS, 23/23 tests.
- Physical strict-remote reconnection: PASS, authenticated saved session and `[Supabase] read success count=2`.
- Standalone backend validator: BLOCKED by missing process-only test-account credentials; no credential was printed or committed.
