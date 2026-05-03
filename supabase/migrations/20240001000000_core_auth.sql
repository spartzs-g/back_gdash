-- ============================================================
-- MIGRATION 001 — Core Auth & Tenancy
-- Tables: businesses, profiles, business_settings
-- ============================================================

-- Extensions
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ============================================================
-- BUSINESSES
-- Root multi-tenant entity. Every other table scopes to this.
-- ============================================================
create table public.businesses (
  id          uuid        primary key default gen_random_uuid(),
  name        text        not null,
  type        text        not null default 'other'
                          check (type in ('kirana','salon','barber','clinic','other')),
  phone       text,
  email       text,
  address     text,
  city        text,
  state       text,
  pincode     text,
  gstin       text,
  logo_url    text,
  currency    text        not null default 'INR',
  timezone    text        not null default 'Asia/Kolkata',
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table  public.businesses              is 'Root tenant entity — one row per business registered in the system.';
comment on column public.businesses.type         is 'Determines which modules are shown in the UI: kirana | salon | barber | clinic | other';
comment on column public.businesses.gstin        is 'GST Identification Number (India). Used on tax invoices.';

-- ============================================================
-- PROFILES
-- Extends auth.users. One profile per user per business.
-- ============================================================
create table public.profiles (
  id          uuid        primary key references auth.users(id) on delete cascade,
  business_id uuid        not null references public.businesses(id) on delete cascade,
  full_name   text,
  phone       text,
  role        text        not null default 'staff'
                          check (role in ('owner','manager','staff','cashier')),
  avatar_url  text,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now()
);

comment on table  public.profiles              is 'App-level user profile linked to auth.users. Scoped to one business per row.';
comment on column public.profiles.role         is 'owner | manager | staff | cashier — used for RLS and UI permission gates.';

-- ============================================================
-- BUSINESS SETTINGS
-- Flexible key-value config store per business.
-- ============================================================
create table public.business_settings (
  id          uuid        primary key default gen_random_uuid(),
  business_id uuid        not null references public.businesses(id) on delete cascade,
  key         text        not null,
  value       jsonb       not null,
  created_at  timestamptz not null default now(),

  unique (business_id, key)
);

comment on table  public.business_settings       is 'Key-value settings per business. Keys: receipt_footer, loyalty_rate, default_tax_rate, opening_hours, etc.';
comment on column public.business_settings.value  is 'JSONB — can hold a string, number, boolean, object, or array depending on the key.';