-- FloodGuard additive backend recovery.
-- Verified missing remotely on 2026-09-26.
-- This migration does not delete, truncate, or update existing application rows.

begin;

create extension if not exists pgcrypto;

create table if not exists public.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fcm_token text unique not null,
  platform text,
  is_active boolean not null default true,
  latitude double precision,
  longitude double precision,
  alert_radius_km double precision not null default 10
    check (alert_radius_km between 1 and 100),
  location_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  flood_warnings boolean not null default true,
  nearby_hazards boolean not null default true,
  severe_rainfall boolean not null default true,
  evacuation_advisories boolean not null default true,
  community_updates boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  type text not null default 'flood_warning',
  severity text not null default 'info',
  title text not null,
  message text not null,
  area text,
  latitude double precision,
  longitude double precision,
  source text not null default 'FloodGuard',
  report_id uuid references public.hazard_reports(id) on delete set null,
  data jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  is_read boolean not null default false,
  dedupe_key text,
  created_at timestamptz not null default now(),
  expires_at timestamptz
);

alter table public.push_devices enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.alerts enable row level security;

drop policy if exists "Users can read own push devices" on public.push_devices;
drop policy if exists "Users can create own push devices" on public.push_devices;
drop policy if exists "Users can update own push devices" on public.push_devices;
drop policy if exists "Users can delete own push devices" on public.push_devices;
create policy "Users can read own push devices"
  on public.push_devices for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Users can create own push devices"
  on public.push_devices for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Users can update own push devices"
  on public.push_devices for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Users can delete own push devices"
  on public.push_devices for delete to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can read own notification preferences"
  on public.notification_preferences;
drop policy if exists "Users can create own notification preferences"
  on public.notification_preferences;
drop policy if exists "Users can update own notification preferences"
  on public.notification_preferences;
create policy "Users can read own notification preferences"
  on public.notification_preferences for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Users can create own notification preferences"
  on public.notification_preferences for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Users can update own notification preferences"
  on public.notification_preferences for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can read relevant alerts" on public.alerts;
drop policy if exists "Users can update own alert read state" on public.alerts;
create policy "Users can read relevant alerts"
  on public.alerts for select to authenticated
  using (user_id is null or (select auth.uid()) = user_id);
create policy "Users can update own alert read state"
  on public.alerts for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.push_devices to authenticated;
grant select, insert, update on public.notification_preferences to authenticated;
grant select, update on public.alerts to authenticated;

create index if not exists push_devices_user_id_idx
  on public.push_devices(user_id);
create index if not exists push_devices_active_idx
  on public.push_devices(is_active) where is_active = true;
create index if not exists alerts_created_at_idx
  on public.alerts(created_at desc);
create index if not exists alerts_active_idx
  on public.alerts(is_active) where is_active = true;
create unique index if not exists alerts_active_dedupe_key_idx
  on public.alerts(dedupe_key)
  where is_active and dedupe_key is not null;

create or replace function public.protect_alert_fields()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if (select auth.role()) = 'authenticated' then
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

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values
  (
    'hazard-report-photos',
    'hazard-report-photos',
    false,
    10485760,
    array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
  ),
  (
    'profile-pictures',
    'profile-pictures',
    false,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
  )
on conflict (id) do nothing;

drop policy if exists "Owners can read own hazard report photos"
  on storage.objects;
drop policy if exists "Users can upload own hazard report photos"
  on storage.objects;
drop policy if exists "Users can update own hazard report photos"
  on storage.objects;
drop policy if exists "Users can delete own hazard report photos"
  on storage.objects;
create policy "Owners can read own hazard report photos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'hazard-report-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );
create policy "Users can upload own hazard report photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'hazard-report-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp', 'heic')
  );
create policy "Users can update own hazard report photos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'hazard-report-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  )
  with check (
    bucket_id = 'hazard-report-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );
create policy "Users can delete own hazard report photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'hazard-report-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can read own profile pictures"
  on storage.objects;
drop policy if exists "Users can upload own profile pictures"
  on storage.objects;
drop policy if exists "Users can update own profile pictures"
  on storage.objects;
drop policy if exists "Users can delete own profile pictures"
  on storage.objects;
create policy "Users can read own profile pictures"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'profile-pictures'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );
create policy "Users can upload own profile pictures"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'profile-pictures'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
  );
create policy "Users can update own profile pictures"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'profile-pictures'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  )
  with check (
    bucket_id = 'profile-pictures'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );
create policy "Users can delete own profile pictures"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'profile-pictures'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

commit;
