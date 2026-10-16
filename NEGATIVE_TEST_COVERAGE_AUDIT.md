# FloodGuard AI Negative-Test Coverage Audit

Audit date: 2026-10-16

Status meanings:

- **ALREADY HANDLED + TESTED** - the current behavior is covered by an automated Flutter test or the existing Supabase integration/security validator.
- **HANDLED BUT NOT AUTOMATED** - the application has a user-safe path, but the platform/plugin behavior is not covered by the automated Flutter suite.
- **ACTUAL GAP (FIXED + TESTED)** - this audit found a defect or missing boundary check; the smallest safe correction and a regression test were added.

| Area | Negative case | Status | Evidence / result |
|---|---|---|---|
| Authentication | Empty email | ALREADY HANDLED + TESTED | Form blocks submission and shows the email validation message. |
| Authentication | Invalid email format | ACTUAL GAP (FIXED + TESTED) | Replaced the former `contains('@')` check with a basic complete-address validator. |
| Authentication | Empty password | ALREADY HANDLED + TESTED | Form blocks submission and requires at least six characters. |
| Authentication | Incorrect password | ALREADY HANDLED + TESTED | `AuthException` remains visible as a recoverable form message. |
| Authentication | Network failure during login | ALREADY HANDLED + TESTED | Generic connection message appears and the loading state ends. |
| Hazard form | Required field missing | ALREADY HANDLED + TESTED | Location and custom hazard-type requirements are enforced. |
| Hazard form | Description over 300 characters | ALREADY HANDLED + TESTED | UI limit is backed by an explicit 300-character validator and service boundary check. |
| Hazard form | No valid coordinates | ACTUAL GAP (FIXED + TESTED) | Null, non-finite, and out-of-range coordinates are rejected before a remote request. |
| Hazard form | Location permission denied | HANDLED BUT NOT AUTOMATED | `LocationAccessException` gives denied/blocked guidance; Geolocator permission dialogs require platform integration testing. |
| Hazard form | Photo upload failure | HANDLED BUT NOT AUTOMATED | The report remains pending, a specific warning is shown, and retry is available; Storage failure branches require emulator/live integration. |
| Hazard form | Network/Supabase submission failure | ALREADY HANDLED + TESTED | Strict remote mode throws and does not create a false local success. |
| CRUD/security | Update another user's report | ALREADY HANDLED + TESTED | Ownership RLS and `tool/supabase_security_check.dart` verify a second user affects zero rows. |
| CRUD/security | Delete another user's report | ALREADY HANDLED + TESTED | Ownership RLS and the two-user security validator verify the record remains. |
| CRUD/security | Delete nonexistent/already-deleted report | ALREADY HANDLED + TESTED | Zero-row delete fails in strict remote mode. |
| CRUD/security | Remote operation affects zero rows | ALREADY HANDLED + TESTED | Update and delete both reject zero-row responses instead of reporting success. |
| CRUD/security | Photo cleanup after report deletion | ALREADY HANDLED + TESTED | A successful delete with `photo_path` issues a Storage removal request. |
| Duplicate reports | Rapid same-user duplicate | ALREADY HANDLED + TESTED | Existing unit and Supabase security tests classify it as suspicious. |
| Duplicate reports | Duplicate falsely becomes official | ALREADY HANDLED + TESTED | Duplicate test asserts suspicious; verification tests prevent local/AI evidence from assigning official verified status. |
| Weather | Open-Meteo unavailable | ALREADY HANDLED + TESTED | No-cache failure returns `WeatherException`; recent cache is explicitly stale. |
| Weather | Timeout | ALREADY HANDLED + TESTED | Short injected timeout confirms retry completion and a bounded error. Production timeout remains 12 seconds. |
| Weather | Incomplete/malformed response | ALREADY HANDLED + TESTED | Missing precipitation and malformed JSON are rejected, never converted to zero. |
| Weather | Stale cached weather | ALREADY HANDLED + TESTED | Cached response is returned with `isStale == true`. |
| Weather | Connectivity restored | ALREADY HANDLED + TESTED | Forced refresh replaces stale data with a fresh provider response. |
| Map/location | GPS permission denied | HANDLED BUT NOT AUTOMATED | Map/report screens show the location-service message; Android permission UI remains a physical test. |
| Map/location | GPS unavailable | HANDLED BUT NOT AUTOMATED | Disabled location service has explicit user guidance; device radio/service behavior remains a physical test. |
| Map/location | GPS timeout | ACTUAL GAP (FIXED + TESTED) | Position timeout is now converted to a clear `LocationAccessException`. |
| Map/location | Report without usable coordinates | ALREADY HANDLED + TESTED | Form/service reject new invalid coordinates; map emits no marker for unmapped legacy rows. |
| Map/location | Expired report appears active | ALREADY HANDLED + TESTED | Verification marks it inactive and map filtering omits it. |
| Map/location | Pan/zoom moves GPS coordinate | HANDLED BUT NOT AUTOMATED | Camera movement has no callback that mutates `_assessmentPoint`; this was also covered by prior physical QA. MapLibre gestures remain a device test. |
| Notification preferences | Persist after restart | ALREADY HANDLED + TESTED | SharedPreferences reload is covered using a recreated cache instance. |
| Notification preferences | Remain tied to authenticated user | ACTUAL GAP (FIXED + TESTED) | Local fallback keys are now namespaced by Supabase user ID. |
| Notification preferences | Supabase unavailable with local state | ALREADY HANDLED + TESTED | Account-scoped local values remain readable without a remote request; remote sync errors are caught. |
| Notification preferences | Remote notification infrastructure unavailable | HANDLED BUT NOT AUTOMATED | Firebase initialization/registration failures are caught and local notifications remain independent; FCM is intentionally not configured here. |

## Tests Added

- Authentication field validation, incorrect-password handling, and login network recovery widget tests.
- Hazard form location/description/coordinate boundary tests.
- Strict-remote submission, zero-row update/delete, nonexistent delete, and report-photo cleanup service tests.
- Open-Meteo unavailable, timeout, malformed JSON, stale-to-restored connectivity tests.
- Expired and unmapped report map-filtering test.
- GPS timeout normalization test.
- Notification preference restart, offline-local, and cross-user isolation tests.

## Final Results

- `flutter analyze`: no issues found.
- `flutter test`: 48 tests passed.
- No Firebase/FCM configuration was changed.
- Real-data sources, Supabase schema/RLS, map layers, rainfall labels, and risk calculations were not changed.
