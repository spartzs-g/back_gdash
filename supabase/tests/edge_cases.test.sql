BEGIN;
SELECT plan(10);

-- ====================================================================
-- Setup
-- ====================================================================
INSERT INTO public.businesses (id, name, type) VALUES
  ('e1111111-1111-1111-1111-111111111111'::UUID, 'Edge Case Biz', 'salon');
SELECT public.seed_new_business('e1111111-1111-1111-1111-111111111111'::UUID);

INSERT INTO public.products (id, business_id, name, type, selling_price, track_inventory) VALUES
  ('e2222222-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID, 'Edge Shampoo', 'product', 100.00, true),
  ('e3333333-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID, 'Edge Facial',  'service', 300.00, false);

INSERT INTO public.product_variants (id, product_id, name, selling_price) VALUES
  ('e4444444-1111-1111-1111-111111111111'::UUID, 'e2222222-1111-1111-1111-111111111111'::UUID, '500ml', NULL);

INSERT INTO public.customers (id, business_id, name, total_spent) VALUES
  ('e5555555-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID, 'Edge Cust', 50.00);

-- ====================================================================
-- TEST 1: Variant with NULL selling_price inherits from parent
-- (Application-level, but validates schema allows it)
-- ====================================================================
SELECT results_eq(
    $$ SELECT pv.selling_price IS NULL AS is_null
       FROM public.product_variants pv
       WHERE pv.id = 'e4444444-1111-1111-1111-111111111111'::UUID $$,
    $$ VALUES (true) $$,
    'T1: Variant selling_price=NULL is permitted (app resolves to parent price)'
);

-- ====================================================================
-- TEST 2: Effective price via COALESCE (how app should query)
-- ====================================================================
SELECT results_eq(
    $$ SELECT COALESCE(pv.selling_price, p.selling_price)
       FROM public.product_variants pv
       JOIN public.products p ON p.id = pv.product_id
       WHERE pv.id = 'e4444444-1111-1111-1111-111111111111'::UUID $$,
    $$ VALUES (100.00::NUMERIC) $$,
    'T2: COALESCE(variant_price, parent_price) returns parent price when variant is NULL'
);

-- ====================================================================
-- TEST 3: total_spent floors at 0 on refund rollback
-- ====================================================================
INSERT INTO public.sales_orders (id, business_id, customer_id, status, subtotal, total_amount) VALUES
  ('e6666666-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID,
   'e5555555-1111-1111-1111-111111111111'::UUID, 'draft', 9999.00, 9999.00);
UPDATE public.sales_orders SET status = 'completed' WHERE id = 'e6666666-1111-1111-1111-111111111111'::UUID;
UPDATE public.sales_orders SET status = 'refunded'  WHERE id = 'e6666666-1111-1111-1111-111111111111'::UUID;

-- total_spent was 50, completed added 9999 (→10049), refunded removed 9999 (→50)
SELECT results_eq(
    $$ SELECT total_spent FROM public.customers
       WHERE id = 'e5555555-1111-1111-1111-111111111111'::UUID $$,
    $$ VALUES (50.00::NUMERIC) $$,
    'T3: total_spent correctly rolls back on refund'
);

-- ====================================================================
-- TEST 4: Immutability — cannot UPDATE inventory_transactions
-- ====================================================================
INSERT INTO public.inventory_transactions (id, business_id, product_id, type, quantity) VALUES
  ('e7777777-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID,
   'e2222222-1111-1111-1111-111111111111'::UUID, 'purchase', 10);

SELECT throws_ok(
    $$ UPDATE public.inventory_transactions SET quantity = 999
       WHERE id = 'e7777777-1111-1111-1111-111111111111'::UUID $$,
    NULL,
    NULL,
    'T4: Cannot UPDATE inventory_transactions (append-only enforced by trigger)'
);

-- ====================================================================
-- TEST 5: Immutability — cannot DELETE from loyalty_transactions
-- ====================================================================
INSERT INTO public.loyalty_transactions (id, business_id, customer_id, type, points) VALUES
  ('e8888888-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID,
   'e5555555-1111-1111-1111-111111111111'::UUID, 'earn', 100);

SELECT throws_ok(
    $$ DELETE FROM public.loyalty_transactions
       WHERE id = 'e8888888-1111-1111-1111-111111111111'::UUID $$,
    NULL,
    NULL,
    'T5: Cannot DELETE from loyalty_transactions (append-only enforced by trigger)'
);

-- ====================================================================
-- TEST 6: Commission ledger — restrict UPDATE to status/paid_at only
-- ====================================================================
INSERT INTO public.staff (id, business_id, name) VALUES
  ('e9999991-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID, 'Edge Staff');

INSERT INTO public.sales_orders (id, business_id, status, subtotal, total_amount) VALUES
  ('eaaaaaaa-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID, 'draft', 100, 100);

INSERT INTO public.sales_order_items (id, order_id, product_id, staff_id, quantity, unit_price, total_price) VALUES
  ('ebbbb001-1111-1111-1111-111111111111'::UUID, 'eaaaaaaa-1111-1111-1111-111111111111'::UUID,
   'e2222222-1111-1111-1111-111111111111'::UUID, 'e9999991-1111-1111-1111-111111111111'::UUID, 1, 100, 100);

INSERT INTO public.staff_commission_ledger (id, business_id, staff_id, order_id, order_item_id, amount) VALUES
  ('ecccc001-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID,
   'e9999991-1111-1111-1111-111111111111'::UUID, 'eaaaaaaa-1111-1111-1111-111111111111'::UUID,
   'ebbbb001-1111-1111-1111-111111111111'::UUID, 50.00);

-- Allowed: update status and paid_at
SELECT lives_ok(
    $$ UPDATE public.staff_commission_ledger
       SET status = 'paid', paid_at = now()
       WHERE id = 'ecccc001-1111-1111-1111-111111111111'::UUID $$,
    'T6a: UPDATE status and paid_at on commission_ledger is allowed'
);

-- Blocked: update amount
SELECT throws_ok(
    $$ UPDATE public.staff_commission_ledger SET amount = 999
       WHERE id = 'ecccc001-1111-1111-1111-111111111111'::UUID $$,
    NULL,
    NULL,
    'T6b: Cannot UPDATE amount on staff_commission_ledger (restricted by trigger)'
);

-- ====================================================================
-- TEST 7: Service package items — only services allowed
-- ====================================================================
INSERT INTO public.service_packages (id, business_id, name, price) VALUES
  ('edddd001-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID, 'Edge Package', 500);

SELECT throws_ok(
    $$ INSERT INTO public.service_package_items (package_id, product_id, quantity) VALUES
       ('edddd001-1111-1111-1111-111111111111'::UUID, 'e2222222-1111-1111-1111-111111111111'::UUID, 1) $$,
    NULL,
    NULL,
    'T7: Cannot add type=product to service_package_items (trigger validates type=service only)'
);

-- ====================================================================
-- TEST 8: quantity_received cannot exceed quantity_ordered
-- ====================================================================
INSERT INTO public.suppliers (id, business_id, name) VALUES
  ('eeeee001-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID, 'Edge Supplier');

INSERT INTO public.purchase_orders (id, business_id, supplier_id, order_number, status, total_amount) VALUES
  ('effff001-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID,
   'eeeee001-1111-1111-1111-111111111111'::UUID, 'PO-EDGE-001', 'ordered', 100);

SELECT throws_ok(
    $$ INSERT INTO public.purchase_order_items
       (purchase_order_id, product_id, quantity_ordered, quantity_received, unit_cost) VALUES
       ('effff001-1111-1111-1111-111111111111'::UUID, 'e2222222-1111-1111-1111-111111111111'::UUID,
        5, 10, 100.00) $$,
    NULL,
    NULL,
    'T8: quantity_received > quantity_ordered is rejected by CHECK constraint'
);

-- ====================================================================
-- TEST 9: Staff leaves partial-day requires start_time and end_time
-- ====================================================================
INSERT INTO public.staff (id, business_id, name) VALUES
  ('e9999992-1111-1111-1111-111111111111'::UUID, 'e1111111-1111-1111-1111-111111111111'::UUID, 'Leave Staff');

SELECT throws_ok(
    $$ INSERT INTO public.staff_leaves (staff_id, leave_date, is_full_day, start_time, end_time) VALUES
       ('e9999992-1111-1111-1111-111111111111'::UUID, CURRENT_DATE, false, NULL, NULL) $$,
    NULL,
    NULL,
    'T9: Partial-day leave (is_full_day=false) with NULL times is rejected by CHECK'
);

SELECT * FROM finish();
ROLLBACK;
