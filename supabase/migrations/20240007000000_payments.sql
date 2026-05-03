-- ============================================================
-- MIGRATION 007 — Payments
-- Tables: payment_methods, payments
-- ============================================================

-- ============================================================
-- PAYMENT METHODS
-- Master list of accepted payment modes per business.
-- Pre-seed with Cash + UPI at business onboarding.
-- ============================================================
create table public.payment_methods (
  id          uuid    primary key default gen_random_uuid(),
  business_id uuid    not null references public.businesses(id) on delete cascade,
  name        text    not null,
  type        text    not null default 'digital'
              check (type in ('cash','digital','credit')),
  is_active   boolean not null default true,

  unique (business_id, name)
);

comment on table  public.payment_methods       is 'Payment modes available to the business. Seed at onboarding: Cash, UPI, Card.';
comment on column public.payment_methods.type  is 'cash | digital | credit. Used for end-of-day reconciliation grouping.';

-- ============================================================
-- PAYMENTS
-- One or more payment records per sales_order.
-- Multiple rows per order = split payment (e.g. part cash,
-- part UPI). Sum of amounts should equal order total_amount.
-- ============================================================
create table public.payments (
  id                uuid          primary key default gen_random_uuid(),
  business_id       uuid          not null references public.businesses(id) on delete cascade,
  order_id          uuid          not null references public.sales_orders(id) on delete cascade,
  payment_method_id uuid          not null references public.payment_methods(id) on delete restrict,
  amount            numeric(14,2) not null check (amount > 0),
  status            text          not null default 'pending'
                    check (status in ('pending','completed','failed','refunded')),
  reference_number  text,
  notes             text,
  paid_at           timestamptz,
  created_at        timestamptz   not null default now()
);

comment on table  public.payments                       is 'Payment records. Multiple rows per order support split payments.';
comment on column public.payments.reference_number      is 'UPI transaction ID, card auth code, cheque number etc.';
comment on column public.payments.paid_at               is 'Set when status transitions to completed. NULL while pending.';