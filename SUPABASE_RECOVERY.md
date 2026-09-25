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
  "SUPABASE_PUBLISHABLE_KEY": "<Publishable key copied from the dashboard>",
  "SUPABASE_STRICT_REMOTE": true
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
private buckets, tests file replacement and signed URLs, and invokes both
verification Edge Functions. Cleanup runs in `finally` if a later check fails.

For the cross-user RLS and verification-scenario check, provide a second
dashboard-created, auto-confirmed test user in the same shell:

```powershell
$env:SUPABASE_OTHER_TEST_EMAIL = '<second test user email>'
$env:SUPABASE_OTHER_TEST_PASSWORD = '<second test user password>'
dart run tool/supabase_security_check.dart
```

This check proves that another authenticated user cannot update or delete the
owner's report or private hazard photo. It also verifies that missing evidence
stays pending and a rapid same-user duplicate is labelled suspicious. Every
record and object created by the tool is labelled as test data and removed in
`finally`.

Apply the reviewed SQL files to a staging project in this order before running
the validator:

1. `supabase_profile_support.sql`
2. `supabase_hazard_report_verification.sql`
3. `supabase_fcm_push_notifications.sql`
4. `supabase_production_hardening.sql`
5. `supabase_backend_recovery_additive.sql`

The fifth migration creates the missing notification/alert tables and private
Storage buckets without deleting application rows. Review every migration in
the SQL Editor before applying it; repository files do not prove that a remote
migration has run.

## Verified state (2026-09-26)

- DNS, HTTPS, publishable-key authentication, and strict remote CRUD passed.
- `profiles`, `hazard_reports`, `report_confirmations`,
  `notification_preferences`, `push_devices`, and `alerts` are reachable.
- Private buckets `hazard-report-photos` and `profile-pictures` passed upload,
  signed-URL, replacement, ownership, and removal checks.
- `verify-hazard-photo` and `verify-hazard-report` are deployed and invokable.
- Physical Android login, profile update/photo lifecycle, report CRUD, report
  history, map synchronization, and logout passed with temporary test data.
- Firebase Cloud Messaging remains unconfigured. Local notifications remain
  available; remote push delivery is not claimed.
