-- FloodGuard AI remote push notification support.
-- Run this in the Supabase SQL editor after the hazard report migration.

create extension if not exists pgcrypto;

create table if not exists public.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  fcm_token text unique not null,
  platform text,
  is_active boolean not null default true,
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
  report_id uuid,
  data jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  expires_at timestamptz
);

alter table public.push_devices enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.alerts enable row level security;

drop policy if exists "Users can read own push devices" on public.push_devices;
drop policy if exists "Users can upsert own push devices" on public.push_devices;
drop policy if exists "Users can update own push devices" on public.push_devices;

create policy "Users can read own push devices"
  on public.push_devices
  for select
  using (auth.uid() = user_id);

create policy "Users can upsert own push devices"
  on public.push_devices
  for insert
  with check (auth.uid() = user_id or user_id is null);

create policy "Users can update own push devices"
  on public.push_devices
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can read own notification preferences"
  on public.notification_preferences;
drop policy if exists "Users can create own notification preferences"
  on public.notification_preferences;
drop policy if exists "Users can update own notification preferences"
  on public.notification_preferences;

create policy "Users can read own notification preferences"
  on public.notification_preferences
  for select
  using (auth.uid() = user_id);

create policy "Users can create own notification preferences"
  on public.notification_preferences
  for insert
  with check (auth.uid() = user_id);

create policy "Users can update own notification preferences"
  on public.notification_preferences
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can read relevant alerts" on public.alerts;
drop policy if exists "Users can update own alert read state" on public.alerts;

create policy "Users can read relevant alerts"
  on public.alerts
  for select
  using (user_id is null or auth.uid() = user_id);

create policy "Users can update own alert read state"
  on public.alerts
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists push_devices_user_id_idx
  on public.push_devices(user_id);

create index if not exists push_devices_active_idx
  on public.push_devices(is_active)
  where is_active = true;

create index if not exists alerts_created_at_idx
  on public.alerts(created_at desc);

create index if not exists alerts_active_idx
  on public.alerts(is_active)
  where is_active = true;
