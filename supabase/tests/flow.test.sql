BEGIN;
SELECT plan(10);

-- ====================================================================
-- Test: End-to-End Flow Validation
-- Uses data from 02_seed_usecase.sql (Elite Spa & Salon)
-- ====================================================================

-- 1. Business Setup & Defaults
SELECT results_eq(
    $$ SELECT count(*)::INT FROM public.business_settings WHERE business_id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID $$,
    $$ VALUES (7::INT) $$,
    'E2E: Business settings should be auto-populated by seed_new_business function'
);

-- 2. Purchase Order & Inventory (Receiving goods triggers stock increase)
-- We seeded a PO that received 10 units. Then a sale deducted 1 unit.
SELECT results_eq(
    $$ SELECT quantity_in_stock FROM public.inventory WHERE business_id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID $$,
    $$ VALUES (9.000::NUMERIC) $$,
    'E2E: Inventory should correctly reflect PO receipt (+10) and Sales deduction (-1) -> 9.0'
);

-- 3. Customer Loyalty Points
-- The VIP customer earned 855 points from the 855.00 order.
SELECT results_eq(
    $$ SELECT loyalty_points FROM public.customers WHERE id = 'cccccccc-dddd-eeee-ffff-111111111111'::UUID $$,
    $$ VALUES (855::INT) $$,
    'E2E: Loyalty transactions trigger should accumulate 855 points'
);

-- 4. Customer Visit Count & Total Spent
SELECT results_eq(
    $$ SELECT visit_count, total_spent FROM public.customers WHERE id = 'cccccccc-dddd-eeee-ffff-111111111111'::UUID $$,
    $$ VALUES (1::INT, 855.00::NUMERIC) $$,
    'E2E: Sales order status update to completed should correctly increment visit count and total spent'
);

-- 5. Staff Commission Calculations
-- Haircut (Total 450) @ 20% = 90.00
-- Shampoo (Total 405) @ 5% = 20.25
-- Total Pending = 110.25
SELECT results_eq(
    $$ SELECT count(*)::INT FROM public.staff_commission_ledger WHERE business_id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID $$,
    $$ VALUES (2::INT) $$,
    'E2E: Commission trigger should generate exactly two ledger entries for the two order items'
);

SELECT results_eq(
    $$ SELECT SUM(amount) FROM public.staff_commission_ledger WHERE business_id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID $$,
    $$ VALUES (110.25::NUMERIC) $$,
    'E2E: Commission trigger should correctly calculate 20% (90.00) and 5% (20.25) rules'
);

-- 6. Payments
SELECT results_eq(
    $$ SELECT count(*)::INT FROM public.payments WHERE business_id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID $$,
    $$ VALUES (2::INT) $$,
    'E2E: Split payments should be properly recorded'
);

SELECT results_eq(
    $$ SELECT SUM(amount) FROM public.payments WHERE business_id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID $$,
    $$ VALUES (855.00::NUMERIC) $$,
    'E2E: Total payments should match the order total amount'
);

-- 7. Refund Rollback Trigger Check
-- We created a 200.00 order, completed it, then refunded it. 
-- The VIP customer's total spent should STILL only be 855.00 (the valid order).
SELECT results_eq(
    $$ SELECT total_spent FROM public.customers WHERE id = 'cccccccc-dddd-eeee-ffff-111111111111'::UUID $$,
    $$ VALUES (855.00::NUMERIC) $$,
    'E2E: Updating a completed order to refunded should successfully roll back the customer total_spent'
);

-- 8. Expense Logging
SELECT results_eq(
    $$ SELECT SUM(amount) FROM public.expenses WHERE business_id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID $$,
    $$ VALUES (150.00::NUMERIC) $$,
    'E2E: Marketing expense should be properly recorded'
);

SELECT * FROM finish();
ROLLBACK;
