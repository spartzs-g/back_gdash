-- ============================================================
-- MIGRATION 013 — Seed Data (Onboarding Defaults)
-- These are Postgres FUNCTIONS called after a new business
-- is created to populate sensible defaults.
-- Call: select public.seed_new_business('<business_id>');
-- ============================================================

create or replace function public.seed_new_business(p_business_id uuid)
returns void
language plpgsql
security definer
as $$
begin

  -- --------------------------------------------------------
  -- Payment Methods
  -- --------------------------------------------------------
  insert into public.payment_methods (business_id, name, type) values
    (p_business_id, 'Cash',   'cash'),
    (p_business_id, 'UPI',    'digital'),
    (p_business_id, 'Card',   'digital'),
    (p_business_id, 'Credit', 'credit');

  -- --------------------------------------------------------
  -- Expense Categories
  -- --------------------------------------------------------
  insert into public.expense_categories (business_id, name, icon, sort_order) values
    (p_business_id, 'Rent',        '🏠', 1),
    (p_business_id, 'Salaries',    '👤', 2),
    (p_business_id, 'Utilities',   '💡', 3),
    (p_business_id, 'Stock',       '📦', 4),
    (p_business_id, 'Marketing',   '📣', 5),
    (p_business_id, 'Maintenance', '🔧', 6),
    (p_business_id, 'Other',       '📋', 7);

  -- --------------------------------------------------------
  -- Business Settings Defaults
  -- --------------------------------------------------------
  insert into public.business_settings (business_id, key, value) values
    (p_business_id, 'loyalty_rate',         to_jsonb(1)),          -- 1 point per ₹1 spent
    (p_business_id, 'loyalty_redeem_rate',  to_jsonb(1)),          -- 1 point = ₹1
    (p_business_id, 'default_tax_rate',     to_jsonb(0)),          -- 0% GST default
    (p_business_id, 'receipt_footer',       to_jsonb('Thank you for visiting us! See you again.'::text)),
    (p_business_id, 'currency_symbol',      to_jsonb('₹'::text)),
    (p_business_id, 'invoice_prefix',       to_jsonb('INV'::text)),
    (p_business_id, 'round_off_enabled',    to_jsonb(true));

end;
$$;

comment on function public.seed_new_business is
  'Call once after creating a new business row. Populates default payment methods, expense categories, and settings.';


-- ============================================================
-- MOCK DATA FOR TESTING REPORTS
-- ============================================================
DO $$ 
DECLARE
    biz_kirana_id UUID := '11111111-1111-1111-1111-111111111111'::UUID;
    biz_salon_id UUID := '22222222-2222-2222-2222-222222222222'::UUID;
    
    prod_rice_id UUID := '33333333-3333-3333-3333-333333333333'::UUID;
    prod_haircut_id UUID := '44444444-4444-4444-4444-444444444444'::UUID;
    
    staff_john_id UUID := '55555555-5555-5555-5555-555555555555'::UUID;
    cust_alice_id UUID := '66666666-6666-6666-6666-666666666666'::UUID;
    cust_bob_id UUID := '77777777-7777-7777-7777-777777777777'::UUID;

    order1_id UUID := '88888888-8888-8888-8888-888888888888'::UUID;
    order2_id UUID := '99999999-9999-9999-9999-999999999999'::UUID;
    
    cat_expense_rent UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID;
BEGIN
    -- Only insert if the businesses don't exist yet to be safe
    IF NOT EXISTS (SELECT 1 FROM businesses WHERE id = biz_kirana_id) THEN

        -- Businesses
        INSERT INTO businesses (id, name, type, is_active) VALUES 
        (biz_kirana_id, 'Super Kirana', 'kirana', true),
        (biz_salon_id, 'Style Salon', 'salon', true);

        -- Initialize default settings/categories
        PERFORM seed_new_business(biz_kirana_id);
        PERFORM seed_new_business(biz_salon_id);

        -- Get default expense category Rent for Kirana to log an expense
        SELECT id INTO cat_expense_rent FROM expense_categories WHERE business_id = biz_kirana_id AND name = 'Rent' LIMIT 1;

        -- Products
        INSERT INTO products (id, business_id, name, type, selling_price, track_inventory, is_active) VALUES 
        (prod_rice_id, biz_kirana_id, 'Basmati Rice 1kg', 'product', 100.00, true, true),
        (prod_haircut_id, biz_salon_id, 'Men Haircut', 'service', 200.00, false, true);

        -- Inventory (Kirana only)
        INSERT INTO inventory (id, business_id, product_id, quantity_in_stock, low_stock_threshold, unit) VALUES
        (gen_random_uuid(), biz_kirana_id, prod_rice_id, 5.0, 10.0, 'kg'); -- Triggers low stock alert

        -- Staff
        INSERT INTO staff (id, business_id, name, role, is_active) VALUES
        (staff_john_id, biz_salon_id, 'John Barber', 'barber', true);

        -- Customers
        INSERT INTO customers (id, business_id, name, loyalty_points) VALUES
        (cust_alice_id, biz_kirana_id, 'Alice', 50),
        (cust_bob_id, biz_salon_id, 'Bob', 150);

        -- Expenses
        INSERT INTO expenses (id, business_id, category_id, amount, description, date) VALUES
        (gen_random_uuid(), biz_kirana_id, cat_expense_rent, 500.00, 'Monthly Rent', CURRENT_DATE);

        -- Sales Orders
        INSERT INTO sales_orders (id, business_id, customer_id, order_number, status, subtotal, discount_amount, tax_amount, total_amount, created_at) VALUES
        (order1_id, biz_kirana_id, cust_alice_id, 'INV-K-001', 'completed', 300.00, 0, 15.00, 315.00, NOW()),
        (order2_id, biz_salon_id, cust_bob_id, 'INV-S-001', 'completed', 200.00, 20.00, 18.00, 198.00, NOW());

        -- Sales Order Items
        INSERT INTO sales_order_items (id, order_id, product_id, quantity, unit_price, discount_percent, tax_rate, tax_amount, total_price) VALUES
        (gen_random_uuid(), order1_id, prod_rice_id, 3.0, 100.00, 0, 5.0, 15.00, 315.00),
        ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID, order2_id, prod_haircut_id, 1.0, 200.00, 10.0, 10.0, 18.00, 198.00);

        -- Staff Commission
        INSERT INTO staff_commission_ledger (id, business_id, staff_id, order_id, order_item_id, amount, status, created_at) VALUES
        (gen_random_uuid(), biz_salon_id, staff_john_id, order2_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID, 50.00, 'pending', NOW());
        
    END IF;
END $$;