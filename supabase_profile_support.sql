-- FloodGuard AI profile support.
-- Run this in the Supabase SQL editor if Edit Profile cannot read or save.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists display_name text,
  add column if not exists avatar_path text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

alter table public.profiles enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Users can read own profile'
  ) then
    create policy "Users can read own profile"
      on public.profiles
      for select
      using (auth.uid() = id);
  end if;
end
$$;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'profile-pictures',
  'profile-pictures',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users can read own profile pictures"
  on storage.objects;
drop policy if exists "Users can upload own profile pictures"
  on storage.objects;
drop policy if exists "Users can update own profile pictures"
  on storage.objects;
drop policy if exists "Users can delete own profile pictures"
  on storage.objects;

create policy "Users can read own profile pictures"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'profile-pictures'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "Users can upload own profile pictures"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'profile-pictures'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
  );

create policy "Users can update own profile pictures"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'profile-pictures'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  )
  with check (
    bucket_id = 'profile-pictures'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
  );

create policy "Users can delete own profile pictures"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'profile-pictures'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Users can create own profile'
  ) then
    create policy "Users can create own profile"
      on public.profiles
      for insert
      with check (auth.uid() = id);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Users can update own profile'
  ) then
    create policy "Users can update own profile"
      on public.profiles
      for update
      using (auth.uid() = id)
      with check (auth.uid() = id);
  end if;
end
$$;
