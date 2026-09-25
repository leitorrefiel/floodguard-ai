# FloodGuard AI

FloodGuard is a Flutter flood-preparedness app focused on Baliwag, Bulacan. The
normal runtime does not ship demo flood, hazard, or facility markers.

## Active data sources

- Open-Meteo provides modelled current conditions and hourly/daily forecasts.
  These values are labelled as model estimates, not rain-gauge observations.
- RainViewer provides a dynamic historical radar timeline when its coverage mask
  confirms coverage at the selected point. Future nowcast frames are not used.
- DENR-MGB provides the static Detailed Flood Susceptibility map and point
  context. Susceptibility is never presented as a current flood incident.
- Supabase stores authenticated community reports, photos, confirmations, alert
  history, and notification preferences when the production schema is deployed.

PAGASA advisories remain official external references because no documented
public machine API was verified for this integration. No verified machine-readable
Baliwag safety-facility register or public near-real-time rain-gauge API is bundled.
The app therefore shows an honest empty state instead of invented records.

## Run and verify

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

No Supabase project URL or key is checked into the application. Supply values
copied from the intended project's API settings:

```bash
flutter run --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Developer-only notification controls are excluded from ordinary debug builds.
Enable them explicitly with:

```bash
flutter run --dart-define=FLOODGUARD_DEVELOPER_MODE=true
```

See [Production Readiness](docs/production_readiness.md) for data provenance,
deployment steps, security migration, Firebase blockers, and known limitations.
See [Supabase Backend Recovery](SUPABASE_RECOVERY.md) for the exact
configuration and remote-only validation procedure.
