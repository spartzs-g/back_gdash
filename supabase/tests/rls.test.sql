BEGIN;
SELECT plan(8);
-- ====================================================================
-- Setup: two businesses, multiple users with different roles
-- ====================================================================
-- Business A
INSERT INTO public.businesses (id, name, type)
VALUES (
    'a1111111-1111-1111-1111-111111111111'::UUID,
    'RLS Biz A',
    'salon'
  );
SELECT public.seed_new_business('a1111111-1111-1111-1111-111111111111'::UUID);
-- Business B (for cross-tenant isolation tests)
INSERT INTO public.businesses (id, name, type)
VALUES (
    'b2222222-2222-2222-2222-222222222222'::UUID,
    'RLS Biz B',
    'kirana'
  );
SELECT public.seed_new_business('b2222222-2222-2222-2222-222222222222'::UUID);
-- Owner (Biz A)
INSERT INTO auth.users (id, instance_id, role, aud)
VALUES (
    'a0000001-0000-0000-0000-000000000000'::UUID,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated'
  );
INSERT INTO public.profiles (id, business_id, full_name, role)
VALUES (
    'a0000001-0000-0000-0000-000000000000'::UUID,
    'a1111111-1111-1111-1111-111111111111'::UUID,
    'Owner A',
    'owner'
  );
-- Cashier (Biz A)
INSERT INTO auth.users (id, instance_id, role, aud)
VALUES (
    'a0000002-0000-0000-0000-000000000000'::UUID,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated'
  );
INSERT INTO public.profiles (id, business_id, full_name, role)
VALUES (
    'a0000002-0000-0000-0000-000000000000'::UUID,
    'a1111111-1111-1111-1111-111111111111'::UUID,
    'Cashier A',
    'cashier'
  );
-- Staff (Biz A)
INSERT INTO auth.users (id, instance_id, role, aud)
VALUES (
    'a0000003-0000-0000-0000-000000000000'::UUID,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated'
  );
INSERT INTO public.profiles (id, business_id, full_name, role)
VALUES (
    'a0000003-0000-0000-0000-000000000000'::UUID,
    'a1111111-1111-1111-1111-111111111111'::UUID,
    'Staff A',
    'staff'
  );
-- Owner (Biz B)
INSERT INTO auth.users (id, instance_id, role, aud)
VALUES (
    'b0000001-0000-0000-0000-000000000000'::UUID,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated'
  );
INSERT INTO public.profiles (id, business_id, full_name, role)
VALUES (
    'b0000001-0000-0000-0000-000000000000'::UUID,
    'b2222222-2222-2222-2222-222222222222'::UUID,
    'Owner B',
    'owner'
  );
-- Test data for Biz A
INSERT INTO public.products (
    id,
    business_id,
    name,
    type,
    selling_price,
    track_inventory
  )
VALUES (
    'a1110001-0000-0000-0000-000000000000'::UUID,
    'a1111111-1111-1111-1111-111111111111'::UUID,
    'RLS Test Product',
    'product',
    100.00,
    true
  );
INSERT INTO public.customers (id, business_id, name)
VALUES (
    'a1110002-0000-0000-0000-000000000000'::UUID,
    'a1111111-1111-1111-1111-111111111111'::UUID,
    'RLS Test Customer'
  );
INSERT INTO public.sales_orders (
    id,
    business_id,
    customer_id,
    status,
    subtotal,
    total_amount
  )
VALUES (
    'a1110003-0000-0000-0000-000000000000'::UUID,
    'a1111111-1111-1111-1111-111111111111'::UUID,
    'a1110002-0000-0000-0000-000000000000'::UUID,
    'completed',
    100.00,
    100.00
  );
-- Staff record linked to Staff A's profile
INSERT INTO public.staff (id, business_id, profile_id, name, role)
VALUES (
    'a1110004-0000-0000-0000-000000000000'::UUID,
    'a1111111-1111-1111-1111-111111111111'::UUID,
    'a0000003-0000-0000-0000-000000000000'::UUID,
    'Staff A',
    'stylist'
  );
-- Another staff member (not linked to any profile)
INSERT INTO public.staff (id, business_id, name, role)
VALUES (
    'a1110005-0000-0000-0000-000000000000'::UUID,
    'a1111111-1111-1111-1111-111111111111'::UUID,
    'Other Staff',
    'barber'
  );
-- Commission ledger entries for both staff
INSERT INTO public.sales_order_items (
    id,
    order_id,
    product_id,
    staff_id,
    quantity,
    unit_price,
    total_price
  )
VALUES (
    'a1110006-0000-0000-0000-000000000000'::UUID,
    'a1110003-0000-0000-0000-000000000000'::UUID,
    'a1110001-0000-0000-0000-000000000000'::UUID,
    'a1110004-0000-0000-0000-000000000000'::UUID,
    1,
    100,
    100
  );
-- Manually insert commission ledger (trigger may have created one; add another for Other Staff)
INSERT INTO public.staff_commission_ledger (
    business_id,
    staff_id,
    order_id,
    order_item_id,
    amount
  )
VALUES (
    'a1111111-1111-1111-1111-111111111111'::UUID,
    'a1110005-0000-0000-0000-000000000000'::UUID,
    'a1110003-0000-0000-0000-000000000000'::UUID,
    'a1110006-0000-0000-0000-000000000000'::UUID,
    50.00
  );
-- Test data for Biz B
INSERT INTO public.products (
    id,
    business_id,
    name,
    type,
    selling_price,
    track_inventory
  )
VALUES (
    'b2220001-0000-0000-0000-000000000000'::UUID,
    'b2222222-2222-2222-2222-222222222222'::UUID,
    'RLS Biz B Product',
    'product',
    50.00,
    true
  );
-- ====================================================================
-- TEST 1: Cross-business isolation — Biz B owner cannot see Biz A products
-- ====================================================================
SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', 'b0000001-0000-0000-0000-000000000000')::text,
    true
  );
SET LOCAL ROLE authenticated;
SELECT results_eq(
    $$
    SELECT count(*)::INT
    FROM public.products
    WHERE business_id = 'a1111111-1111-1111-1111-111111111111'::UUID $$,
      $$
    VALUES (0::INT) $$,
      'T1: Owner B cannot see Biz A products (cross-tenant isolation)'
  );
RESET ROLE;
-- ====================================================================
-- TEST 2: Biz B owner CAN see their own products
-- ====================================================================
SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', 'b0000001-0000-0000-0000-000000000000')::text,
    true
  );
SET LOCAL ROLE authenticated;
SELECT results_eq(
    $$
    SELECT count(*)::INT
    FROM public.products
    WHERE business_id = 'b2222222-2222-2222-2222-222222222222'::UUID $$,
      $$
    VALUES (1::INT) $$,
      'T2: Owner B can see their own business products'
  );
RESET ROLE;
-- ====================================================================
-- TEST 3: Staff cannot write to products
-- ====================================================================
SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', 'a0000003-0000-0000-0000-000000000000')::text,
    true
  );
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $$
    INSERT INTO public.products (
        business_id,
        name,
        type,
        selling_price,
        track_inventory
      )
    VALUES (
        'a1111111-1111-1111-1111-111111111111'::UUID,
        'Hack Product',
        'product',
        99,
        true
      ) $$,
      NULL,
      NULL,
      'T3: Staff role cannot INSERT into products (blocked by RLS)'
  );
RESET ROLE;
-- ====================================================================
-- TEST 4: Cashier cannot delete customers
-- ====================================================================
SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', 'a0000002-0000-0000-0000-000000000000')::text,
    true
  );
SET LOCAL ROLE authenticated;
-- Cashier tries to delete — RLS should block (only owner/manager can delete)
SELECT lives_ok(
    $$
    DELETE FROM public.customers
    WHERE id = 'a1110002-0000-0000-0000-000000000000'::UUID $$,
      'T4a: DELETE statement executes without error for cashier'
  );
-- Verify the customer still exists (0 rows affected)
RESET ROLE;
SELECT results_eq(
    $$
    SELECT count(*)::INT
    FROM public.customers
    WHERE id = 'a1110002-0000-0000-0000-000000000000'::UUID $$,
      $$
    VALUES (1::INT) $$,
      'T4b: Customer still exists — cashier DELETE was silently blocked by RLS'
  );
-- ====================================================================
-- TEST 5: Cashier cannot set order status to refunded
-- ====================================================================
SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', 'a0000002-0000-0000-0000-000000000000')::text,
    true
  );
SET LOCAL ROLE authenticated;
-- Cashier tries to refund — WITH CHECK rejects and throws 42501
SELECT throws_ok(
    $$
    UPDATE public.sales_orders
    SET status = 'refunded'
    WHERE id = 'a1110003-0000-0000-0000-000000000000'::UUID $$,
      '42501',
      NULL,
      'T5a: Cashier refund attempt is rejected by RLS WITH CHECK (error 42501)'
  );
RESET ROLE;
SELECT results_eq(
    $$
    SELECT status
    FROM public.sales_orders
    WHERE id = 'a1110003-0000-0000-0000-000000000000'::UUID $$,
      $$
    VALUES ('completed'::TEXT) $$,
      'T5b: Order status unchanged — cashier cannot set to refunded'
  );
-- ====================================================================
-- TEST 6: Staff member can only see their own commission ledger entries
-- ====================================================================
SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', 'a0000003-0000-0000-0000-000000000000')::text,
    true
  );
SET LOCAL ROLE authenticated;
-- Staff A should only see their own commissions (staff_id = a1110004), not Other Staff (a1110005)
SELECT results_eq(
    $$
    SELECT count(*)::INT
    FROM public.staff_commission_ledger
    WHERE staff_id = 'a1110005-0000-0000-0000-000000000000'::UUID $$,
      $$
    VALUES (0::INT) $$,
      'T6: Staff member cannot see other staff commission ledger entries'
  );
RESET ROLE;
SELECT *
FROM finish();
ROLLBACK;