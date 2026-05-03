BEGIN;
SELECT plan(14);

-- ====================================================================
-- Test: Daily Sales Summary View
-- ====================================================================
SELECT has_view('public', 'daily_sales_summary', 'View daily_sales_summary should exist');

SELECT results_eq(
    $$ SELECT total_revenue, total_orders FROM public.daily_sales_summary WHERE business_id = '11111111-1111-1111-1111-111111111111'::UUID AND sale_date = CURRENT_DATE $$,
    $$ VALUES (315.00::NUMERIC, 1::BIGINT) $$,
    'daily_sales_summary should show correct total revenue and orders for Kirana'
);

SELECT results_eq(
    $$ SELECT total_revenue, total_orders FROM public.daily_sales_summary WHERE business_id = '22222222-2222-2222-2222-222222222222'::UUID AND sale_date = CURRENT_DATE $$,
    $$ VALUES (198.00::NUMERIC, 1::BIGINT) $$,
    'daily_sales_summary should show correct total revenue and orders for Salon'
);

-- ====================================================================
-- Test: Low Stock Alerts View
-- ====================================================================
SELECT has_view('public', 'low_stock_alerts', 'View low_stock_alerts should exist');

SELECT results_eq(
    $$ SELECT product_id, quantity_in_stock, low_stock_threshold FROM public.low_stock_alerts WHERE business_id = '11111111-1111-1111-1111-111111111111'::UUID $$,
    $$ VALUES ('33333333-3333-3333-3333-333333333333'::UUID, 2.0::NUMERIC, 10.0::NUMERIC) $$,
    'low_stock_alerts should flag Rice since 2 <= 10'
);

-- ====================================================================
-- Test: Staff Commission Summary View
-- ====================================================================
SELECT has_view('public', 'staff_commission_summary', 'View staff_commission_summary should exist');

SELECT results_eq(
    $$ SELECT staff_id, pending_commission, total_commission FROM public.staff_commission_summary WHERE business_id = '22222222-2222-2222-2222-222222222222'::UUID $$,
    $$ VALUES ('55555555-5555-5555-5555-555555555555'::UUID, 50.00::NUMERIC, 50.00::NUMERIC) $$,
    'staff_commission_summary should show correct pending and total commission for John Barber'
);

-- ====================================================================
-- Test: Net Profit Summary View
-- ====================================================================
SELECT has_view('public', 'daily_net_profit_summary', 'View daily_net_profit_summary should exist');

-- Kirana Gross = 315, Tax = 15, Expenses = 500, Net = 315 - 15 - 500 = -200
SELECT results_eq(
    $$ SELECT gross_revenue, total_tax, total_expenses, net_profit FROM public.daily_net_profit_summary WHERE business_id = '11111111-1111-1111-1111-111111111111'::UUID AND report_date = CURRENT_DATE $$,
    $$ VALUES (315.00::NUMERIC, 15.00::NUMERIC, 500.00::NUMERIC, -200.00::NUMERIC) $$,
    'daily_net_profit_summary should calculate correctly for Kirana'
);

-- ====================================================================
-- Test: Customer Loyalty Summary View
-- ====================================================================
SELECT has_view('public', 'customer_loyalty_summary', 'View customer_loyalty_summary should exist');

SELECT results_eq(
    $$ SELECT total_customers, total_outstanding_points FROM public.customer_loyalty_summary WHERE business_id = '11111111-1111-1111-1111-111111111111'::UUID $$,
    $$ VALUES (1::BIGINT, 50::BIGINT) $$,
    'customer_loyalty_summary should show correct totals for Kirana'
);

SELECT results_eq(
    $$ SELECT total_customers, total_outstanding_points FROM public.customer_loyalty_summary WHERE business_id = '22222222-2222-2222-2222-222222222222'::UUID $$,
    $$ VALUES (1::BIGINT, 150::BIGINT) $$,
    'customer_loyalty_summary should show correct totals for Salon'
);

-- ====================================================================
-- Test: Top Selling Products Function
-- ====================================================================
SELECT has_function('public', 'top_selling_products', 'Function top_selling_products should exist');

SELECT results_eq(
    $$ SELECT product_id, total_quantity, total_revenue FROM public.top_selling_products('11111111-1111-1111-1111-111111111111'::UUID, NOW() - interval '1 day', NOW() + interval '1 day') $$,
    $$ VALUES ('33333333-3333-3333-3333-333333333333'::UUID, 3.0::NUMERIC, 315.00::NUMERIC) $$,
    'top_selling_products should return correct data for Rice'
);

SELECT * FROM finish();
ROLLBACK;
