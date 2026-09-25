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
| MAP-PHYSICAL-01 | Updated facility/radar layers on phone | Three verified references render at fixed coordinates; pan/zoom and details remain correct | PENDING: device is at the sign-in screen and no credentials were stored in the repository or automation environment |

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
