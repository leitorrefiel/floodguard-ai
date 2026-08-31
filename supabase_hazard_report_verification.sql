-- FloodGuard AI community hazard report verification support.
-- Run this in the Supabase SQL editor for a new or existing FloodGuard project.

create extension if not exists pgcrypto;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'hazard-report-photos',
  'hazard-report-photos',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.hazard_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  type text not null,
  severity text not null default 'Moderate',
  location text not null default '',
  description text not null default '',
  latitude double precision,
  longitude double precision,
  photo_url text,
  photo_path text,
  status text not null default 'pending',
  is_verified boolean not null default false,
  confidence_score integer not null default 0,
  verification_state text not null default 'not_started',
  verification_reason text not null default 'Pending verification.',
  verification_evidence jsonb not null default '{}'::jsonb,
  ai_image_score numeric,
  weather_support boolean not null default false,
  hazard_context_support boolean not null default false,
  nearby_report_count integer not null default 0,
  confirmation_count integer not null default 0,
  last_verified_at timestamptz,
  verification_updated_at timestamptz,
  expires_at timestamptz,
  other_hazard_type text,
  source text not null default 'FloodGuard Community Report',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.hazard_reports enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'hazard_reports'
      and policyname = 'Users can read hazard reports'
  ) then
    create policy "Users can read hazard reports"
      on public.hazard_reports
      for select
      using (true);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'hazard_reports'
      and policyname = 'Users can create own hazard reports'
  ) then
    create policy "Users can create own hazard reports"
      on public.hazard_reports
      for insert
      with check (auth.uid() = user_id or user_id is null);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'hazard_reports'
      and policyname = 'Users can update own hazard reports'
  ) then
    create policy "Users can update own hazard reports"
      on public.hazard_reports
      for update
      using (auth.uid() = user_id or user_id is null)
      with check (auth.uid() = user_id or user_id is null);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'hazard_reports'
      and policyname = 'Users can delete own hazard reports'
  ) then
    create policy "Users can delete own hazard reports"
      on public.hazard_reports
      for delete
      using (auth.uid() = user_id or user_id is null);
  end if;
end
$$;

alter table public.hazard_reports
  add column if not exists photo_path text,
  add column if not exists confidence_score integer not null default 0,
  add column if not exists verification_state text not null default 'not_started',
  add column if not exists verification_reason text not null default 'Pending verification.',
  add column if not exists verification_evidence jsonb not null default '{}'::jsonb,
  add column if not exists ai_image_score numeric,
  add column if not exists weather_support boolean not null default false,
  add column if not exists hazard_context_support boolean not null default false,
  add column if not exists nearby_report_count integer not null default 0,
  add column if not exists last_verified_at timestamptz,
  add column if not exists verification_updated_at timestamptz;

alter table public.hazard_reports
  drop constraint if exists hazard_reports_status_check;

alter table public.hazard_reports
  add constraint hazard_reports_status_check
  check (
    status in (
      'pending',
      'high_confidence',
      'verified',
      'suspicious',
      'rejected',
      'resolved',
      'expired'
    )
  );

alter table public.hazard_reports
  drop constraint if exists hazard_reports_verification_state_check;

alter table public.hazard_reports
  add constraint hazard_reports_verification_state_check
  check (
    verification_state in (
      'not_started',
      'running',
      'completed',
      'failed'
    )
  );

update public.hazard_reports
set
  status = 'pending',
  verification_reason = 'Pending verification.',
  verification_updated_at = now(),
  updated_at = now()
where status = 'suspicious'
  and confidence_score = 0
  and verification_state in ('not_started', 'running');

create table if not exists public.report_confirmations (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.hazard_reports(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (report_id, user_id)
);

alter table public.report_confirmations enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'report_confirmations'
      and policyname = 'Users can read report confirmations'
  ) then
    create policy "Users can read report confirmations"
      on public.report_confirmations
      for select
      using (true);
  end if;
end
$$;

drop policy if exists "Authenticated users can read hazard report photos"
  on storage.objects;
drop policy if exists "Users can upload own hazard report photos"
  on storage.objects;
drop policy if exists "Users can update own hazard report photos"
  on storage.objects;
drop policy if exists "Users can delete own hazard report photos"
  on storage.objects;

create policy "Authenticated users can read hazard report photos"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'hazard-report-photos');

create policy "Users can upload own hazard report photos"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'hazard-report-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp', 'heic')
  );

create policy "Users can update own hazard report photos"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'hazard-report-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  )
  with check (
    bucket_id = 'hazard-report-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp', 'heic')
  );

create policy "Users can delete own hazard report photos"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'hazard-report-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'report_confirmations'
      and policyname = 'Users can confirm once'
  ) then
    create policy "Users can confirm once"
      on public.report_confirmations
      for insert
      with check (auth.uid() = user_id);
  end if;
end
$$;
