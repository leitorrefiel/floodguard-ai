# Supabase Backend Recovery

FloodGuard has no checked-in Supabase URL or API key. Supply both at build time.

## Dashboard values

From the intended Supabase project, copy:

1. **Project URL** from the project's **Connect** dialog into `SUPABASE_URL`.
2. **Publishable key** (`sb_publishable_...`) from the **Connect** dialog or
   **Settings > API Keys** into `SUPABASE_PUBLISHABLE_KEY`. A legacy `anon` key
   is also accepted, but the publishable key is preferred.

Never put `service_role`, secret keys, database passwords, or JWT signing keys
in Flutter arguments or committed files.

Run the app with:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY `
  --dart-define=SUPABASE_STRICT_REMOTE=true
```

Use `SUPABASE_STRICT_REMOTE=true` for the physical-device validation cycle. In
this mode report reads and CRUD operations throw on remote failure instead of
reading from or writing to SharedPreferences. Omit it for normal production use,
where the clearly labelled offline cache remains available during outages.

For repeatable local builds, create ignored `config/supabase.local.json`:

```json
{
  "SUPABASE_URL": "<Project URL copied from the dashboard>",
  "SUPABASE_PUBLISHABLE_KEY": "<Publishable key copied from the dashboard>"
}
```

Then use `flutter run --dart-define-from-file=config/supabase.local.json`.

## Remote-only validation

Create a dedicated authenticated test user in the project, then set its login
only in the current shell:

```powershell
$env:SUPABASE_TEST_EMAIL = '<test user email>'
$env:SUPABASE_TEST_PASSWORD = '<test user password>'
dart run tool/supabase_backend_check.dart
```

The validator uses Supabase directly and never imports SharedPreferences. It
checks authentication and all required tables, creates/reads/updates/deletes a
temporary non-geocoded test report, uploads and removes a test JPEG from both
private buckets, and invokes both verification Edge Functions. Cleanup runs in
`finally` if a later check fails.

Apply the reviewed SQL files to a staging project in this order before running
the validator:

1. `supabase_profile_support.sql`
2. `supabase_hazard_report_verification.sql`
3. `supabase_fcm_push_notifications.sql`
4. `supabase_production_hardening.sql`
