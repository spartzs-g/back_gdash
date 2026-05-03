-- ============================================================
-- MIGRATION 008 — Expenses
-- Tables: expense_categories, expenses
-- ============================================================

-- ============================================================
-- EXPENSE CATEGORIES
-- User-defined categories for classifying outflows.
-- Pre-seed with: Rent, Salaries, Utilities, Stock, Other.
-- ============================================================
create table public.expense_categories (
  id          uuid    primary key default gen_random_uuid(),
  business_id uuid    not null references public.businesses(id) on delete cascade,
  name        text    not null,
  icon        text,
  sort_order  int     not null default 0,
  is_active   boolean not null default true,

  unique (business_id, name)
);

comment on table public.expense_categories       is 'Expense classification categories. Seed at onboarding: Rent, Salaries, Utilities, Stock, Other.';
comment on column public.expense_categories.icon is 'Emoji or icon key for UI display e.g. 🏠 for Rent.';

-- ============================================================
-- EXPENSES
-- Daily operational cost entries. Combined with sales_orders
-- to produce a net profit view for any date range.
-- ============================================================
create table public.expenses (
  id                uuid          primary key default gen_random_uuid(),
  business_id       uuid          not null references public.businesses(id) on delete cascade,
  category_id       uuid          references public.expense_categories(id) on delete set null,
  amount            numeric(14,2) not null check (amount > 0),
  description       text          not null,
  date              date          not null,
  payment_method_id uuid          references public.payment_methods(id) on delete set null,
  receipt_url       text,
  created_by        uuid          references public.profiles(id) on delete set null,
  created_at        timestamptz   not null default now()
);

comment on table  public.expenses                       is 'Operational expense entries. Used alongside sales_orders to compute net profit.';
comment on column public.expenses.date                  is 'Business date of the expense (may differ from created_at if entered retroactively).';
comment on column public.expenses.payment_method_id     is 'How the expense was paid — useful for cash-flow reconciliation.';
comment on column public.expenses.receipt_url           is 'Supabase Storage URL for a receipt photo or PDF.';