-- FloodGuard production RLS hardening.
-- Review in a staging project, then run after the existing schema scripts.
-- This migration deliberately does not delete or rewrite report data.

begin;

alter table public.push_devices
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists alert_radius_km double precision not null default 10,
  add column if not exists location_updated_at timestamptz;

alter table public.push_devices
  drop constraint if exists push_devices_alert_radius_check;
alter table public.push_devices
  add constraint push_devices_alert_radius_check
  check (alert_radius_km between 1 and 100);

alter table public.alerts
  add column if not exists dedupe_key text;
create unique index if not exists alerts_active_dedupe_key_idx
  on public.alerts (dedupe_key)
  where is_active and dedupe_key is not null;

drop policy if exists "Users can create own hazard reports"
  on public.hazard_reports;
drop policy if exists "Users can update own hazard reports"
  on public.hazard_reports;
drop policy if exists "Users can delete own hazard reports"
  on public.hazard_reports;

create policy "Authenticated users can create own hazard reports"
  on public.hazard_reports
  for insert
  to authenticated
  with check (auth.uid() = user_id and user_id is not null);

create policy "Owners can update own hazard report content"
  on public.hazard_reports
  for update
  to authenticated
  using (auth.uid() = user_id and user_id is not null)
  with check (auth.uid() = user_id and user_id is not null);

create policy "Owners can delete own hazard reports"
  on public.hazard_reports
  for delete
  to authenticated
  using (auth.uid() = user_id and user_id is not null);

create or replace function public.protect_hazard_verification_fields()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') = 'authenticated'
     and pg_trigger_depth() = 1 then
    if tg_op = 'INSERT' then
      new.status := 'pending';
      new.is_verified := false;
      new.confidence_score := 0;
      new.verification_state := 'not_started';
      new.verification_reason := 'Pending server verification.';
      new.verification_evidence := '{}'::jsonb;
      new.ai_image_score := null;
      new.weather_support := false;
      new.hazard_context_support := false;
      new.nearby_report_count := 0;
      new.confirmation_count := 0;
      new.last_verified_at := null;
      new.verification_updated_at := null;
      new.expires_at := least(
        coalesce(new.expires_at, now() + interval '3 days'),
        now() + interval '3 days'
      );
      new.source := 'FloodGuard Community Report';
    else
      new.user_id := old.user_id;
      if new.type is distinct from old.type
         or new.severity is distinct from old.severity
         or new.location is distinct from old.location
         or new.description is distinct from old.description
         or new.latitude is distinct from old.latitude
         or new.longitude is distinct from old.longitude
         or new.photo_path is distinct from old.photo_path
         or new.other_hazard_type is distinct from old.other_hazard_type then
        new.status := 'pending';
        new.is_verified := false;
        new.confidence_score := 0;
        new.verification_state := 'not_started';
        new.verification_reason := 'Report changed; pending server re-verification.';
        new.verification_evidence := '{}'::jsonb;
        new.ai_image_score := null;
        new.weather_support := false;
        new.hazard_context_support := false;
        new.nearby_report_count := 0;
        new.last_verified_at := null;
        new.verification_updated_at := null;
      else
        new.status := old.status;
        new.is_verified := old.is_verified;
        new.confidence_score := old.confidence_score;
        new.verification_state := old.verification_state;
        new.verification_reason := old.verification_reason;
        new.verification_evidence := old.verification_evidence;
        new.ai_image_score := old.ai_image_score;
        new.weather_support := old.weather_support;
        new.hazard_context_support := old.hazard_context_support;
        new.nearby_report_count := old.nearby_report_count;
        new.last_verified_at := old.last_verified_at;
        new.verification_updated_at := old.verification_updated_at;
      end if;
      new.confirmation_count := old.confirmation_count;
      new.source := old.source;
      new.expires_at := old.expires_at;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_hazard_verification_fields
  on public.hazard_reports;
create trigger protect_hazard_verification_fields
before insert or update on public.hazard_reports
for each row execute function public.protect_hazard_verification_fields();

create or replace function public.increment_report_confirmation_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.hazard_reports
  set confirmation_count = (
    select count(*)::integer
    from public.report_confirmations
    where report_id = new.report_id
  )
  where id = new.report_id;
  return new;
end;
$$;

drop trigger if exists increment_report_confirmation_count
  on public.report_confirmations;
create trigger increment_report_confirmation_count
after insert on public.report_confirmations
for each row execute function public.increment_report_confirmation_count();

drop policy if exists "Authenticated users can read hazard report photos"
  on storage.objects;
create policy "Owners can read own hazard report photos"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'hazard-report-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can upsert own push devices"
  on public.push_devices;
create policy "Users can create own push devices"
  on public.push_devices
  for insert
  to authenticated
  with check (auth.uid() = user_id and user_id is not null);

create or replace function public.protect_alert_fields()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') = 'authenticated' then
    new.user_id := old.user_id;
    new.type := old.type;
    new.severity := old.severity;
    new.title := old.title;
    new.message := old.message;
    new.area := old.area;
    new.latitude := old.latitude;
    new.longitude := old.longitude;
    new.source := old.source;
    new.report_id := old.report_id;
    new.data := old.data;
    new.is_active := old.is_active;
    new.created_at := old.created_at;
    new.expires_at := old.expires_at;
    new.dedupe_key := old.dedupe_key;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_alert_fields on public.alerts;
create trigger protect_alert_fields
before update on public.alerts
for each row execute function public.protect_alert_fields();

commit;
