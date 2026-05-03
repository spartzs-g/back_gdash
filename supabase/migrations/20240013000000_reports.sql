-- Migration to create reporting views and functions

DROP VIEW IF EXISTS public.daily_sales_summary;
DROP VIEW IF EXISTS public.low_stock_alerts;
DROP VIEW IF EXISTS public.staff_commission_summary;

-- 1. Daily Sales Summary View
CREATE OR REPLACE VIEW daily_sales_summary AS
SELECT 
    business_id,
    DATE(created_at) AS sale_date,
    COUNT(id) AS total_orders,
    SUM(subtotal) AS total_subtotal,
    SUM(discount_amount) AS total_discount,
    SUM(tax_amount) AS total_tax,
    SUM(total_amount) AS total_revenue,
    AVG(total_amount) AS avg_order_value
FROM 
    sales_orders
WHERE 
    status IN ('confirmed', 'completed')
GROUP BY 
    business_id, DATE(created_at);

-- Apply RLS to view (requires PostgreSQL 15+ to be seamless, or standard wrapper function)
-- Alternatively, RLS on underlying tables applies automatically to views if the view is not security definer.

-- 2. Low Stock Alerts View
CREATE OR REPLACE VIEW low_stock_alerts AS
SELECT 
    i.business_id,
    i.product_id,
    p.name AS product_name,
    i.variant_id,
    pv.name AS variant_name,
    i.quantity_in_stock,
    i.low_stock_threshold,
    i.unit
FROM 
    inventory i
JOIN 
    products p ON i.product_id = p.id
LEFT JOIN 
    product_variants pv ON i.variant_id = pv.id
WHERE 
    i.quantity_in_stock <= i.low_stock_threshold;

-- 3. Staff Commission Summary View
CREATE OR REPLACE VIEW staff_commission_summary AS
SELECT 
    l.business_id,
    l.staff_id,
    s.name AS staff_name,
    DATE_TRUNC('month', l.created_at) AS commission_month,
    SUM(CASE WHEN l.status = 'pending' THEN l.amount ELSE 0 END) AS pending_commission,
    SUM(CASE WHEN l.status = 'paid' THEN l.amount ELSE 0 END) AS paid_commission,
    SUM(l.amount) AS total_commission
FROM 
    staff_commission_ledger l
JOIN 
    staff s ON l.staff_id = s.id
GROUP BY 
    l.business_id, l.staff_id, s.name, DATE_TRUNC('month', l.created_at);

-- 4. Top Selling Products Function
CREATE OR REPLACE FUNCTION top_selling_products(
    p_business_id UUID,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ,
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    product_id UUID,
    product_name TEXT,
    total_quantity NUMERIC,
    total_revenue NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        i.product_id,
        p.name AS product_name,
        SUM(i.quantity) AS total_quantity,
        SUM(i.total_price) AS total_revenue
    FROM 
        sales_order_items i
    JOIN 
        sales_orders o ON i.order_id = o.id
    JOIN 
        products p ON i.product_id = p.id
    WHERE 
        o.business_id = p_business_id
        AND o.status IN ('confirmed', 'completed')
        AND o.created_at >= p_start_date
        AND o.created_at <= p_end_date
    GROUP BY 
        i.product_id, p.name
    ORDER BY 
        total_revenue DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- 5. Net Profit Summary View
-- Net Profit = (Total Revenue) - (Total Taxes) - (Total Expenses)
-- Simplified daily net profit calculation
CREATE OR REPLACE VIEW daily_net_profit_summary AS
WITH sales AS (
    SELECT 
        business_id,
        DATE(created_at) AS report_date,
        SUM(total_amount) AS gross_revenue,
        SUM(tax_amount) AS total_tax,
        SUM(discount_amount) AS total_discount
    FROM sales_orders
    WHERE status IN ('confirmed', 'completed')
    GROUP BY business_id, DATE(created_at)
),
daily_expenses AS (
    SELECT 
        business_id,
        date AS report_date,
        SUM(amount) AS total_expenses
    FROM expenses
    GROUP BY business_id, date
)
SELECT 
    COALESCE(s.business_id, e.business_id) AS business_id,
    COALESCE(s.report_date, e.report_date) AS report_date,
    COALESCE(s.gross_revenue, 0) AS gross_revenue,
    COALESCE(s.total_tax, 0) AS total_tax,
    COALESCE(e.total_expenses, 0) AS total_expenses,
    (COALESCE(s.gross_revenue, 0) - COALESCE(s.total_tax, 0) - COALESCE(e.total_expenses, 0)) AS net_profit
FROM sales s
FULL OUTER JOIN daily_expenses e 
    ON s.business_id = e.business_id AND s.report_date = e.report_date;

-- 6. Customer Loyalty Summary View
CREATE OR REPLACE VIEW customer_loyalty_summary AS
SELECT 
    business_id,
    COUNT(id) AS total_customers,
    SUM(loyalty_points) AS total_outstanding_points,
    AVG(loyalty_points) AS avg_points_per_customer
FROM 
    customers
WHERE 
    loyalty_points > 0
GROUP BY 
    business_id;
