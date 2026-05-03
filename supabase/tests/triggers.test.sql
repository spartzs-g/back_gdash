BEGIN;
SELECT plan(14);

-- ====================================================================
-- Setup: create an isolated test business inline
-- ====================================================================
INSERT INTO public.businesses (id, name, type)
VALUES ('11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, 'Trigger Test Biz', 'salon');

SELECT public.seed_new_business('11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID);

-- Products: one trackable, one service
INSERT INTO public.products (id, business_id, name, type, selling_price, track_inventory) VALUES
  ('22222222-aaaa-bbbb-cccc-dddddddddddd'::UUID, '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, 'Shampoo',  'product', 100.00, true),
  ('33333333-aaaa-bbbb-cccc-dddddddddddd'::UUID, '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, 'Haircut',  'service', 200.00, false);

-- Staff
INSERT INTO public.staff (id, business_id, name, role) VALUES
  ('44444444-aaaa-bbbb-cccc-dddddddddddd'::UUID, '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, 'Tester', 'stylist');

-- Commission rules: percentage and fixed_per_unit
INSERT INTO public.staff_commissions (business_id, staff_id, product_id, commission_type, commission_value) VALUES
  ('11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, '44444444-aaaa-bbbb-cccc-dddddddddddd'::UUID,
   '22222222-aaaa-bbbb-cccc-dddddddddddd'::UUID, 'fixed_per_unit', 10.00),
  ('11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, '44444444-aaaa-bbbb-cccc-dddddddddddd'::UUID,
   NULL, 'percentage', 15.00);

-- Customer
INSERT INTO public.customers (id, business_id, name, phone) VALUES
  ('55555555-aaaa-bbbb-cccc-dddddddddddd'::UUID, '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, 'Test Customer', '555-9999');

-- Seed inventory via transactions
INSERT INTO public.inventory_transactions (business_id, product_id, variant_id, type, quantity) VALUES
  ('11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, '22222222-aaaa-bbbb-cccc-dddddddddddd'::UUID, NULL, 'purchase', 50);

-- ====================================================================
-- TEST 1: No inventory deduction for services (track_inventory=false)
-- ====================================================================
INSERT INTO public.sales_orders (id, business_id, customer_id, status, subtotal, total_amount) VALUES
  ('66666666-aaaa-bbbb-cccc-dddddddddddd'::UUID, '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID,
   '55555555-aaaa-bbbb-cccc-dddddddddddd'::UUID, 'draft', 200.00, 200.00);

INSERT INTO public.sales_order_items (order_id, product_id, staff_id, quantity, unit_price, total_price) VALUES
  ('66666666-aaaa-bbbb-cccc-dddddddddddd'::UUID, '33333333-aaaa-bbbb-cccc-dddddddddddd'::UUID,
   '44444444-aaaa-bbbb-cccc-dddddddddddd'::UUID, 1.0, 200.00, 200.00);

SELECT results_eq(
    $$ SELECT count(*)::INT FROM public.inventory_transactions
       WHERE business_id = '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID
         AND product_id  = '33333333-aaaa-bbbb-cccc-dddddddddddd'::UUID
         AND type = 'sale' $$,
    $$ VALUES (0::INT) $$,
    'T1: Service product (track_inventory=false) should NOT create inventory_transactions on sale'
);

-- ====================================================================
-- TEST 2: Inventory IS deducted for trackable products
-- ====================================================================
INSERT INTO public.sales_order_items (order_id, product_id, staff_id, quantity, unit_price, total_price) VALUES
  ('66666666-aaaa-bbbb-cccc-dddddddddddd'::UUID, '22222222-aaaa-bbbb-cccc-dddddddddddd'::UUID,
   '44444444-aaaa-bbbb-cccc-dddddddddddd'::UUID, 3.0, 100.00, 300.00);

SELECT results_eq(
    $$ SELECT quantity FROM public.inventory_transactions
       WHERE business_id = '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID
         AND product_id  = '22222222-aaaa-bbbb-cccc-dddddddddddd'::UUID
         AND type = 'sale' $$,
    $$ VALUES (-3.000::NUMERIC) $$,
    'T2: Trackable product should create a -3.0 sale inventory_transaction'
);

-- ====================================================================
-- TEST 3: Commission with fixed_per_unit type
-- ====================================================================
SELECT results_eq(
    $$ SELECT amount FROM public.staff_commission_ledger
       WHERE staff_id = '44444444-aaaa-bbbb-cccc-dddddddddddd'::UUID
         AND order_id = '66666666-aaaa-bbbb-cccc-dddddddddddd'::UUID
       ORDER BY amount DESC LIMIT 1
       OFFSET 1 $$,
    $$ VALUES (30.00::NUMERIC) $$,
    'T3: fixed_per_unit commission: 3 units × ₹10 = ₹30'
);

-- ====================================================================
-- TEST 4: Commission with percentage catch-all (service, no specific rule → catch-all 15%)
-- ====================================================================
SELECT results_eq(
    $$ SELECT amount FROM public.staff_commission_ledger
       WHERE staff_id = '44444444-aaaa-bbbb-cccc-dddddddddddd'::UUID
         AND order_id = '66666666-aaaa-bbbb-cccc-dddddddddddd'::UUID
       ORDER BY amount ASC LIMIT 1 $$,
    $$ VALUES (30.00::NUMERIC) $$,
    'T4: Percentage catch-all commission: 15% of 200.00 = 30.00'
);

-- ====================================================================
-- TEST 5: No commission when staff_id is NULL
-- ====================================================================
INSERT INTO public.sales_order_items (order_id, product_id, staff_id, quantity, unit_price, total_price) VALUES
  ('66666666-aaaa-bbbb-cccc-dddddddddddd'::UUID, '22222222-aaaa-bbbb-cccc-dddddddddddd'::UUID,
   NULL, 1.0, 100.00, 100.00);

SELECT results_eq(
    $$ SELECT count(*)::INT FROM public.staff_commission_ledger
       WHERE order_id = '66666666-aaaa-bbbb-cccc-dddddddddddd'::UUID $$,
    $$ VALUES (2::INT) $$,
    'T5: No commission ledger entry created when staff_id is NULL on line item'
);

-- ====================================================================
-- TEST 6: Order number auto-generation (unique sequential)
-- ====================================================================
INSERT INTO public.sales_orders (id, business_id, status, subtotal, total_amount) VALUES
  ('77777777-aaaa-bbbb-cccc-dddddddddddd'::UUID, '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, 'draft', 0, 0);

SELECT matches(
    (SELECT order_number FROM public.sales_orders WHERE id = '77777777-aaaa-bbbb-cccc-dddddddddddd'::UUID),
    '^INV-[0-9]{8}-[0-9]{4}$',
    'T6: Auto-generated order number matches INV-YYYYMMDD-XXXX format'
);

-- ====================================================================
-- TEST 7: PO number auto-generation
-- ====================================================================
INSERT INTO public.purchase_orders (id, business_id, status, total_amount) VALUES
  ('88888888-aaaa-bbbb-cccc-dddddddddddd'::UUID, '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, 'draft', 0);

SELECT matches(
    (SELECT order_number FROM public.purchase_orders WHERE id = '88888888-aaaa-bbbb-cccc-dddddddddddd'::UUID),
    '^PO-[0-9]{4}$',
    'T7: Auto-generated PO number matches PO-XXXX format'
);

-- ====================================================================
-- TEST 8: Customer stats — draft → completed increments
-- ====================================================================
UPDATE public.sales_orders SET status = 'completed'
WHERE id = '66666666-aaaa-bbbb-cccc-dddddddddddd'::UUID;

SELECT results_eq(
    $$ SELECT visit_count, total_spent FROM public.customers
       WHERE id = '55555555-aaaa-bbbb-cccc-dddddddddddd'::UUID $$,
    $$ VALUES (1::INT, 200.00::NUMERIC) $$,
    'T8: Completing order increments visit_count and total_spent'
);

-- ====================================================================
-- TEST 9: completed → cancelled does NOT roll back stats
-- (only refunded triggers rollback per the trigger logic)
-- ====================================================================
UPDATE public.sales_orders SET status = 'cancelled'
WHERE id = '66666666-aaaa-bbbb-cccc-dddddddddddd'::UUID;

SELECT results_eq(
    $$ SELECT visit_count, total_spent FROM public.customers
       WHERE id = '55555555-aaaa-bbbb-cccc-dddddddddddd'::UUID $$,
    $$ VALUES (1::INT, 200.00::NUMERIC) $$,
    'T9: Cancelling a completed order does NOT roll back customer stats (only refund does)'
);

-- ====================================================================
-- TEST 10: Auto-earn loyalty on completion
-- ====================================================================
-- The order was completed in T8 with total_amount=200 and loyalty_rate=1
-- → should have auto-earned 200 points
SELECT results_eq(
    $$ SELECT loyalty_points FROM public.customers
       WHERE id = '55555555-aaaa-bbbb-cccc-dddddddddddd'::UUID $$,
    $$ VALUES (200::INT) $$,
    'T10: Auto-earn loyalty trigger awards floor(total_amount × loyalty_rate) points on completion'
);

-- ====================================================================
-- TEST 11: Loyalty reversal on refund
-- ====================================================================
-- Create, complete, then refund a second order
INSERT INTO public.sales_orders (id, business_id, customer_id, status, subtotal, total_amount) VALUES
  ('99999999-aaaa-bbbb-cccc-dddddddddddd'::UUID, '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID,
   '55555555-aaaa-bbbb-cccc-dddddddddddd'::UUID, 'draft', 100.00, 100.00);

UPDATE public.sales_orders SET status = 'completed'
WHERE id = '99999999-aaaa-bbbb-cccc-dddddddddddd'::UUID;

-- Now customer has 200 + 100 = 300 points, visit_count=2, total_spent=300
UPDATE public.sales_orders SET status = 'refunded'
WHERE id = '99999999-aaaa-bbbb-cccc-dddddddddddd'::UUID;

SELECT results_eq(
    $$ SELECT loyalty_points FROM public.customers
       WHERE id = '55555555-aaaa-bbbb-cccc-dddddddddddd'::UUID $$,
    $$ VALUES (200::INT) $$,
    'T11: Refund reverses auto-earned loyalty points (300 - 100 = 200)'
);

-- ====================================================================
-- TEST 12: Refund with NULL customer — no crash
-- ====================================================================
INSERT INTO public.sales_orders (id, business_id, customer_id, status, subtotal, total_amount) VALUES
  ('aaaaaaaa-aaaa-bbbb-cccc-dddddddddddd'::UUID, '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID,
   NULL, 'draft', 50.00, 50.00);
UPDATE public.sales_orders SET status = 'completed' WHERE id = 'aaaaaaaa-aaaa-bbbb-cccc-dddddddddddd'::UUID;
UPDATE public.sales_orders SET status = 'refunded'  WHERE id = 'aaaaaaaa-aaaa-bbbb-cccc-dddddddddddd'::UUID;

SELECT pass('T12: Refund on order with NULL customer_id does not crash');

-- ====================================================================
-- TEST 13: Loyalty floor at 0 (redeem more than balance)
-- ====================================================================
INSERT INTO public.loyalty_transactions (business_id, customer_id, type, points) VALUES
  ('11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, '55555555-aaaa-bbbb-cccc-dddddddddddd'::UUID,
   'redeem', -9999);

SELECT results_eq(
    $$ SELECT loyalty_points FROM public.customers
       WHERE id = '55555555-aaaa-bbbb-cccc-dddddddddddd'::UUID $$,
    $$ VALUES (0::INT) $$,
    'T13: Loyalty points floor at 0 when redeeming more than balance'
);

-- ====================================================================
-- TEST 14: Discount usage_count auto-increment
-- ====================================================================
INSERT INTO public.discounts (id, business_id, name, type, value, is_active) VALUES
  ('bbbbbbbb-aaaa-bbbb-cccc-dddddddddddd'::UUID, '11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID,
   'Test Coupon', 'percentage', 10.00, true);

INSERT INTO public.sales_orders (business_id, discount_id, status, subtotal, total_amount) VALUES
  ('11111111-aaaa-bbbb-cccc-dddddddddddd'::UUID, 'bbbbbbbb-aaaa-bbbb-cccc-dddddddddddd'::UUID,
   'draft', 100, 90);

SELECT results_eq(
    $$ SELECT usage_count FROM public.discounts
       WHERE id = 'bbbbbbbb-aaaa-bbbb-cccc-dddddddddddd'::UUID $$,
    $$ VALUES (1::INT) $$,
    'T14: Discount usage_count auto-incremented when discount_id is set on order'
);

SELECT * FROM finish();
ROLLBACK;
