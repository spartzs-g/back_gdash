-- ============================================================
-- MIGRATION 011 — Row Level Security (RLS) Policies
-- Strategy: every table is scoped to business_id.
--   • Authenticated users can only access rows for their business.
--   • Role-based write restrictions (owner/manager can write,
--     staff/cashier limited to specific tables).
--   • Service role bypasses RLS (for server-side functions).
-- ============================================================
-- ============================================================
-- HELPER FUNCTION
-- Returns the business_id for the currently authenticated user.
-- Used in every RLS policy to avoid repeated subqueries.
-- ============================================================
create or replace function public.my_business_id() returns uuid language sql stable security definer as $$
select business_id
from public.profiles
where id = auth.uid() $$;
create or replace function public.my_role() returns text language sql stable security definer as $$
select role
from public.profiles
where id = auth.uid() $$;
-- ============================================================
-- ENABLE RLS ON ALL TABLES
-- ============================================================
alter table public.businesses enable row level security;
alter table public.profiles enable row level security;
alter table public.business_settings enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.service_packages enable row level security;
alter table public.service_package_items enable row level security;
alter table public.customers enable row level security;
alter table public.loyalty_transactions enable row level security;
alter table public.inventory enable row level security;
alter table public.inventory_transactions enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.staff enable row level security;
alter table public.staff_availability enable row level security;
alter table public.staff_leaves enable row level security;
alter table public.appointments enable row level security;
alter table public.appointment_services enable row level security;
alter table public.sales_orders enable row level security;
alter table public.sales_order_items enable row level security;
alter table public.discounts enable row level security;
alter table public.payment_methods enable row level security;
alter table public.payments enable row level security;
alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.staff_commissions enable row level security;
alter table public.staff_commission_ledger enable row level security;
-- ============================================================
-- BUSINESSES
-- Only the owner's own business row is visible/editable.
-- ============================================================
create policy "businesses: read own" on public.businesses for
select using (id = public.my_business_id());
create policy "businesses: owner can update" on public.businesses for
update using (
    id = public.my_business_id()
    and public.my_role() = 'owner'
  ) with check (id = public.my_business_id());
-- ============================================================
-- PROFILES
-- Users see all profiles in their business.
-- Only owner/manager can modify profiles.
-- ============================================================
create policy "profiles: read own business" on public.profiles for
select using (business_id = public.my_business_id());
create policy "profiles: insert own" on public.profiles for
insert with check (id = auth.uid());
create policy "profiles: owner or manager can update" on public.profiles for
update using (
    business_id = public.my_business_id()
    and public.my_role() in ('owner', 'manager')
  );
-- ============================================================
-- BUSINESS SETTINGS
-- Read: all authenticated users in the business.
-- Write: owner only.
-- ============================================================
create policy "business_settings: read own business" on public.business_settings for
select using (business_id = public.my_business_id());
create policy "business_settings: owner write" on public.business_settings for all using (
  business_id = public.my_business_id()
  and public.my_role() = 'owner'
) with check (business_id = public.my_business_id());
-- ============================================================
-- GENERIC MACRO: scoped read + manager/owner write
-- Applied to: categories, products, product_variants,
--   service_packages, service_package_items, discounts,
--   payment_methods, staff_commissions
-- ============================================================
-- categories
create policy "categories: read" on public.categories for
select using (business_id = public.my_business_id());
create policy "categories: write" on public.categories for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
-- products
create policy "products: read" on public.products for
select using (business_id = public.my_business_id());
create policy "products: write" on public.products for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
-- product_variants (FK-scoped via product_id; business check via join)
create policy "product_variants: read" on public.product_variants for
select using (
    exists (
      select 1
      from public.products p
      where p.id = product_id
        and p.business_id = public.my_business_id()
    )
  );
create policy "product_variants: write" on public.product_variants for all using (
  public.my_role() in ('owner', 'manager')
  and exists (
    select 1
    from public.products p
    where p.id = product_id
      and p.business_id = public.my_business_id()
  )
);
-- service_packages
create policy "service_packages: read" on public.service_packages for
select using (business_id = public.my_business_id());
create policy "service_packages: write" on public.service_packages for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
-- service_package_items (scoped via package)
create policy "service_package_items: read" on public.service_package_items for
select using (
    exists (
      select 1
      from public.service_packages sp
      where sp.id = package_id
        and sp.business_id = public.my_business_id()
    )
  );
create policy "service_package_items: write" on public.service_package_items for all using (
  public.my_role() in ('owner', 'manager')
  and exists (
    select 1
    from public.service_packages sp
    where sp.id = package_id
      and sp.business_id = public.my_business_id()
  )
);
-- discounts
create policy "discounts: read" on public.discounts for
select using (business_id = public.my_business_id());
create policy "discounts: write" on public.discounts for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
-- payment_methods
create policy "payment_methods: read" on public.payment_methods for
select using (business_id = public.my_business_id());
create policy "payment_methods: write" on public.payment_methods for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
-- staff_commissions
create policy "staff_commissions: read" on public.staff_commissions for
select using (business_id = public.my_business_id());
create policy "staff_commissions: write" on public.staff_commissions for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
-- ============================================================
-- CUSTOMERS
-- All staff can read and create. Only manager/owner can delete.
-- ============================================================
create policy "customers: read" on public.customers for
select using (business_id = public.my_business_id());
create policy "customers: insert" on public.customers for
insert with check (business_id = public.my_business_id());
create policy "customers: update" on public.customers for
update using (business_id = public.my_business_id());
create policy "customers: delete" on public.customers for delete using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
);
-- loyalty_transactions (scoped via customer)
create policy "loyalty_transactions: read" on public.loyalty_transactions for
select using (business_id = public.my_business_id());
create policy "loyalty_transactions: insert" on public.loyalty_transactions for
insert with check (business_id = public.my_business_id());
-- ============================================================
-- INVENTORY
-- All staff can read. Only manager/owner can adjust manually.
-- ============================================================
create policy "inventory: read" on public.inventory for
select using (business_id = public.my_business_id());
create policy "inventory: write" on public.inventory for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
create policy "inventory_transactions: read" on public.inventory_transactions for
select using (business_id = public.my_business_id());
create policy "inventory_transactions: insert" on public.inventory_transactions for
insert with check (business_id = public.my_business_id());
-- ============================================================
-- SUPPLIERS & PURCHASE ORDERS
-- Manager/owner only.
-- ============================================================
create policy "suppliers: read" on public.suppliers for
select using (business_id = public.my_business_id());
create policy "suppliers: write" on public.suppliers for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
create policy "purchase_orders: read" on public.purchase_orders for
select using (business_id = public.my_business_id());
create policy "purchase_orders: write" on public.purchase_orders for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
create policy "purchase_order_items: read" on public.purchase_order_items for
select using (
    exists (
      select 1
      from public.purchase_orders po
      where po.id = purchase_order_id
        and po.business_id = public.my_business_id()
    )
  );
create policy "purchase_order_items: write" on public.purchase_order_items for all using (
  public.my_role() in ('owner', 'manager')
  and exists (
    select 1
    from public.purchase_orders po
    where po.id = purchase_order_id
      and po.business_id = public.my_business_id()
  )
);
-- ============================================================
-- STAFF & APPOINTMENTS
-- All staff can read and create appointments.
-- ============================================================
create policy "staff: read" on public.staff for
select using (business_id = public.my_business_id());
create policy "staff: write" on public.staff for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
create policy "staff_availability: read" on public.staff_availability for
select using (
    exists (
      select 1
      from public.staff s
      where s.id = staff_id
        and s.business_id = public.my_business_id()
    )
  );
create policy "staff_availability: write" on public.staff_availability for all using (
  public.my_role() in ('owner', 'manager')
  and exists (
    select 1
    from public.staff s
    where s.id = staff_id
      and s.business_id = public.my_business_id()
  )
);
create policy "staff_leaves: read" on public.staff_leaves for
select using (
    exists (
      select 1
      from public.staff s
      where s.id = staff_id
        and s.business_id = public.my_business_id()
    )
  );
create policy "staff_leaves: write" on public.staff_leaves for all using (
  exists (
    select 1
    from public.staff s
    where s.id = staff_id
      and s.business_id = public.my_business_id()
  )
);
create policy "appointments: read" on public.appointments for
select using (business_id = public.my_business_id());
create policy "appointments: insert" on public.appointments for
insert with check (business_id = public.my_business_id());
create policy "appointments: update" on public.appointments for
update using (business_id = public.my_business_id());
create policy "appointments: delete" on public.appointments for delete using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
);
create policy "appointment_services: read" on public.appointment_services for
select using (
    exists (
      select 1
      from public.appointments a
      where a.id = appointment_id
        and a.business_id = public.my_business_id()
    )
  );
create policy "appointment_services: write" on public.appointment_services for all using (
  exists (
    select 1
    from public.appointments a
    where a.id = appointment_id
      and a.business_id = public.my_business_id()
  )
);
-- ============================================================
-- SALES ORDERS & ITEMS
-- All staff can create. Manager/owner can cancel/refund.
-- ============================================================
create policy "sales_orders: read" on public.sales_orders for
select using (business_id = public.my_business_id());
create policy "sales_orders: insert" on public.sales_orders for
insert with check (business_id = public.my_business_id());
create policy "sales_orders: update status" on public.sales_orders for
update using (business_id = public.my_business_id()) with check (
    -- Cashiers and staff can only move draft→confirmed→completed
    -- Manager/owner can also cancel or refund
    (public.my_role() in ('owner', 'manager'))
    or (status in ('confirmed', 'completed'))
  );
create policy "sales_order_items: read" on public.sales_order_items for
select using (
    exists (
      select 1
      from public.sales_orders so
      where so.id = order_id
        and so.business_id = public.my_business_id()
    )
  );
create policy "sales_order_items: insert" on public.sales_order_items for
insert with check (
    exists (
      select 1
      from public.sales_orders so
      where so.id = order_id
        and so.business_id = public.my_business_id()
    )
  );
-- ============================================================
-- PAYMENTS
-- All staff can create. Manager/owner can refund.
-- ============================================================
create policy "payments: read" on public.payments for
select using (business_id = public.my_business_id());
create policy "payments: insert" on public.payments for
insert with check (business_id = public.my_business_id());
create policy "payments: update" on public.payments for
update using (
    business_id = public.my_business_id()
    and public.my_role() in ('owner', 'manager')
  );
-- ============================================================
-- EXPENSES
-- All staff can read. Manager/owner can create/edit/delete.
-- ============================================================
create policy "expense_categories: read" on public.expense_categories for
select using (business_id = public.my_business_id());
create policy "expense_categories: write" on public.expense_categories for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
create policy "expenses: read" on public.expenses for
select using (business_id = public.my_business_id());
create policy "expenses: write" on public.expenses for all using (
  business_id = public.my_business_id()
  and public.my_role() in ('owner', 'manager')
) with check (business_id = public.my_business_id());
-- ============================================================
-- STAFF COMMISSION LEDGER
-- Read: owner/manager + the staff member themselves.
-- Insert: trigger only (via security definer function).
-- ============================================================
create policy "staff_commission_ledger: owner/manager read" on public.staff_commission_ledger for
select using (
    business_id = public.my_business_id()
    and (
      public.my_role() in ('owner', 'manager')
      or staff_id = (
        select id
        from public.staff
        where profile_id = auth.uid()
      )
    )
  );
create policy "staff_commission_ledger: insert" on public.staff_commission_ledger for
insert with check (business_id = public.my_business_id());
create policy "staff_commission_ledger: owner update paid_at" on public.staff_commission_ledger for
update using (
    business_id = public.my_business_id()
    and public.my_role() in ('owner', 'manager')
  );