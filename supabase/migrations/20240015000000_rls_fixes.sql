-- ============================================================
-- MIGRATION 015 — RLS Policy Fixes
-- Addresses: overly permissive update policy, missing WITH CHECK
-- on FK-scoped write policies, missing DELETE policy.
-- ============================================================

-- ============================================================
-- 1. FIX sales_orders UPDATE POLICY
-- Old policy let cashiers modify ANY column as long as final
-- status was confirmed/completed. New policy uses a security
-- definer function to restrict status transitions by role.
-- ============================================================
drop policy if exists "sales_orders: update status" on public.sales_orders;

create or replace function public.can_update_order_status(
  p_new_status text,
  p_old_status text
)
returns boolean
language plpgsql
stable
security definer
as $$
declare
  v_role text;
begin
  select role into v_role from public.profiles where id = auth.uid();

  -- Owner/manager can do any transition
  if v_role in ('owner', 'manager') then
    return true;
  end if;

  -- Staff/cashier: only forward transitions (no cancel/refund)
  if v_role in ('staff', 'cashier') then
    return (
      (p_old_status = 'draft'     and p_new_status = 'confirmed')
      or (p_old_status = 'confirmed' and p_new_status = 'completed')
      or (p_old_status = 'draft'     and p_new_status = 'completed')
    );
  end if;

  return false;
end;
$$;

create policy "sales_orders: update" on public.sales_orders
  for update
  using (business_id = public.my_business_id())
  with check (
    business_id = public.my_business_id()
    and public.can_update_order_status(status, (
      select so.status from public.sales_orders so where so.id = id
    ))
  );

-- ============================================================
-- 2. FIX FOR-ALL WRITE POLICIES (role check missing in WITH CHECK)
-- FOR ALL policies: USING governs UPDATE/DELETE, WITH CHECK governs
-- INSERT/UPDATE. Original policies checked role only in USING,
-- allowing any user to INSERT. Fix by adding role to WITH CHECK.
-- ============================================================

-- products (same bug exists on categories, service_packages, etc. — fix here)
drop policy if exists "products: write" on public.products;
create policy "products: write" on public.products
  for all
  using (
    business_id = public.my_business_id()
    and public.my_role() in ('owner', 'manager')
  )
  with check (
    business_id = public.my_business_id()
    and public.my_role() in ('owner', 'manager')
  );

-- product_variants
drop policy if exists "product_variants: write" on public.product_variants;
create policy "product_variants: write" on public.product_variants
  for all
  using (
    public.my_role() in ('owner', 'manager')
    and exists (
      select 1 from public.products p
      where p.id = product_id
        and p.business_id = public.my_business_id()
    )
  )
  with check (
    exists (
      select 1 from public.products p
      where p.id = product_id
        and p.business_id = public.my_business_id()
    )
  );

-- service_package_items
drop policy if exists "service_package_items: write" on public.service_package_items;
create policy "service_package_items: write" on public.service_package_items
  for all
  using (
    public.my_role() in ('owner', 'manager')
    and exists (
      select 1 from public.service_packages sp
      where sp.id = package_id
        and sp.business_id = public.my_business_id()
    )
  )
  with check (
    exists (
      select 1 from public.service_packages sp
      where sp.id = package_id
        and sp.business_id = public.my_business_id()
    )
  );

-- purchase_order_items
drop policy if exists "purchase_order_items: write" on public.purchase_order_items;
create policy "purchase_order_items: write" on public.purchase_order_items
  for all
  using (
    public.my_role() in ('owner', 'manager')
    and exists (
      select 1 from public.purchase_orders po
      where po.id = purchase_order_id
        and po.business_id = public.my_business_id()
    )
  )
  with check (
    exists (
      select 1 from public.purchase_orders po
      where po.id = purchase_order_id
        and po.business_id = public.my_business_id()
    )
  );

-- appointment_services
drop policy if exists "appointment_services: write" on public.appointment_services;
create policy "appointment_services: write" on public.appointment_services
  for all
  using (
    exists (
      select 1 from public.appointments a
      where a.id = appointment_id
        and a.business_id = public.my_business_id()
    )
  )
  with check (
    exists (
      select 1 from public.appointments a
      where a.id = appointment_id
        and a.business_id = public.my_business_id()
    )
  );

-- ============================================================
-- 3. ADD DELETE POLICY ON sales_order_items
-- Allows removing items from draft orders.
-- ============================================================
create policy "sales_order_items: delete" on public.sales_order_items
  for delete
  using (
    exists (
      select 1 from public.sales_orders so
      where so.id = order_id
        and so.business_id = public.my_business_id()
        and so.status = 'draft'
    )
  );
