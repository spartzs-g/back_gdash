-- ============================================================
-- MIGRATION 003 — Customers & Loyalty
-- Tables: customers, loyalty_transactions
-- ============================================================

-- ============================================================
-- CUSTOMERS
-- Central CRM. Shared across kirana walk-ins, salon regulars,
-- clinic patients. Denormalized counters updated by triggers.
-- ============================================================
create table public.customers (
  id               uuid          primary key default gen_random_uuid(),
  business_id      uuid          not null references public.businesses(id) on delete cascade,
  name             text          not null,
  phone            text,
  email            text,
  gender           text          check (gender in ('male','female','other')),
  date_of_birth    date,
  anniversary_date date,
  address          text,
  notes            text,
  loyalty_points   int           not null default 0 check (loyalty_points >= 0),
  total_spent      numeric(14,2) not null default 0 check (total_spent >= 0),
  visit_count      int           not null default 0 check (visit_count >= 0),
  last_visit_at    timestamptz,
  referred_by      uuid          references public.customers(id) on delete set null,
  tags             text[]        not null default '{}',
  created_at       timestamptz   not null default now(),
  updated_at       timestamptz   not null default now(),

  unique (business_id, phone)
);

comment on table  public.customers                 is 'Unified CRM — works for kirana walk-ins, salon regulars, and clinic patients.';
comment on column public.customers.loyalty_points  is 'Denormalized current balance. Source of truth is loyalty_transactions.';
comment on column public.customers.total_spent     is 'Denormalized lifetime spend. Updated by trigger on sales_orders completion.';
comment on column public.customers.visit_count     is 'Denormalized total completed visits. Updated by trigger on sales_orders completion.';
comment on column public.customers.referred_by     is 'Self-referencing FK — the customer who referred this one.';
comment on column public.customers.tags            is 'Free-form labels e.g. VIP, allergy-nuts, diabetic, walk-in.';
comment on column public.customers.notes           is 'Staff-facing notes: medical history, preferences, special instructions.';

-- ============================================================
-- LOYALTY TRANSACTIONS
-- Immutable ledger. Never update rows — append only.
-- Balance = sum(points) filtered by customer_id.
-- ============================================================
create table public.loyalty_transactions (
  id           uuid        primary key default gen_random_uuid(),
  business_id  uuid        not null references public.businesses(id) on delete cascade,
  customer_id  uuid        not null references public.customers(id) on delete cascade,
  type         text        not null
               check (type in ('earn','redeem','adjust','expire')),
  points       int         not null,
  reference_id uuid,
  notes        text,
  created_at   timestamptz not null default now()
);

comment on table  public.loyalty_transactions              is 'Append-only ledger of loyalty point movements. Do NOT update or delete rows.';
comment on column public.loyalty_transactions.type         is 'earn = points added. redeem = points used (negative). adjust = manual correction. expire = points expired.';
comment on column public.loyalty_transactions.points       is 'Positive for earn/adjust-up, negative for redeem/expire/adjust-down.';
comment on column public.loyalty_transactions.reference_id is 'Optional FK to sales_orders.id or any other source document.';