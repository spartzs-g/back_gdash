# Walkthrough: Schema, RLS & Test Improvements

## Files Changed

### New Migrations

#### [20240014000000_schema_fixes.sql](file:///home/spartzs/code/back_gdash/supabase/migrations/20240014000000_schema_fixes.sql)

| # | Fix | What it does |
|---|---|---|
| 1 | Immutability triggers | `deny_mutation()` blocks UPDATE/DELETE on `inventory_transactions` and `loyalty_transactions`. `restrict_commission_ledger_update()` allows only `status`/`paid_at` changes on `staff_commission_ledger`. |
| 2 | PO received → inventory | `receive_purchase_order_items()` fires on `UPDATE OF quantity_received` on `purchase_order_items`, inserts the delta into `inventory_transactions`. |
| 3 | Order/PO number race fix | `generate_order_number()` and `generate_po_number()` now use `pg_advisory_xact_lock()` to prevent concurrent duplicate numbers. |
| 4 | Missing CHECKs | `quantity_received <= quantity_ordered` on PO items. Partial-day leave requires `start_time`/`end_time` when `is_full_day = false`. |
| 5 | Service package validation | Trigger ensures only `type='service'` products can be added to `service_package_items`. |
| 6 | Auto-earn loyalty | `auto_earn_loyalty_points()` fires on order completion (earns) and refund (reverses). Uses `loyalty_rate` from `business_settings`. |
| 7 | Discount usage tracking | Added `discount_id` FK on `sales_orders`. Trigger auto-increments/decrements `discounts.usage_count`. |
| 8 | buy_x_get_y columns | Added `buy_quantity` and `get_quantity` columns to `discounts` table. |
| 9 | View fix | `low_stock_alerts` restored `is_active = true` and `threshold > 0` filters. |
| 10 | Index cleanup | Dropped redundant `idx_so_created_at_date` (ASC duplicate of existing DESC index). |

#### [20240015000000_rls_fixes.sql](file:///home/spartzs/code/back_gdash/supabase/migrations/20240015000000_rls_fixes.sql)

| # | Fix | What it does |
|---|---|---|
| 1 | Order update policy | Replaced with `can_update_order_status()` function — cashiers can only do `draft→confirmed→completed`, owner/manager can do any transition. |
| 2 | WITH CHECK on FK-scoped policies | Added `WITH CHECK` to `product_variants`, `service_package_items`, `purchase_order_items`, `appointment_services` write policies. |
| 3 | Delete policy | Added `sales_order_items: delete` for draft orders. |

---

### Seed Update

#### [02_seed_usecase.sql](file:///home/spartzs/code/back_gdash/supabase/seeds/02_seed_usecase.sql)

Removed manual `INSERT INTO loyalty_transactions` — the new `auto_earn_loyalty_points` trigger handles this automatically when order status transitions to `completed`.

```diff:02_seed_usecase.sql
-- ============================================================
-- FULL E2E USE CASE SEED SCRIPT
-- Triggers and exercises every table and logic path.
-- ============================================================

DO $$ 
DECLARE
    biz_spa_id UUID := 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID;
    owner_profile_id UUID := 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'::UUID;

    cat_hair_id UUID := gen_random_uuid();
    cat_retail_id UUID := gen_random_uuid();

    prod_shampoo_id UUID := gen_random_uuid();
    var_shampoo_500ml_id UUID := gen_random_uuid();

    serv_haircut_id UUID := gen_random_uuid();
    serv_spa_id UUID := gen_random_uuid();

    pkg_bridal_id UUID := gen_random_uuid();

    supplier_id UUID := gen_random_uuid();
    po_id UUID := gen_random_uuid();

    staff_stylist_id UUID := gen_random_uuid();
    
    cust_vip_id UUID := 'cccccccc-dddd-eeee-ffff-111111111111'::UUID;

    discount_id UUID := gen_random_uuid();

    appt_id UUID := gen_random_uuid();

    order_sale_id UUID := 'dddddddd-eeee-ffff-1111-222222222222'::UUID;
    order_refund_id UUID := 'eeeeeeee-ffff-1111-2222-333333333333'::UUID;

    payment_method_cash_id UUID;
    payment_method_upi_id UUID;
    expense_category_marketing_id UUID;

BEGIN
    -- Only run if the business doesn't exist
    IF NOT EXISTS (SELECT 1 FROM businesses WHERE id = biz_spa_id) THEN

        -- 1. Business & Settings
        INSERT INTO businesses (id, name, type, is_active) 
        VALUES (biz_spa_id, 'Elite Spa & Salon', 'salon', true);
        PERFORM seed_new_business(biz_spa_id);

        -- 2. Profiles
        INSERT INTO auth.users (id, instance_id, role, aud)
        VALUES (owner_profile_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

        INSERT INTO profiles (id, business_id, full_name, role)
        VALUES (owner_profile_id, biz_spa_id, 'Sarah Owner', 'owner');

        -- Get Default Payment Methods created by seed_new_business
        SELECT id INTO payment_method_cash_id FROM payment_methods WHERE business_id = biz_spa_id AND type = 'cash' LIMIT 1;
        SELECT id INTO payment_method_upi_id FROM payment_methods WHERE business_id = biz_spa_id AND type = 'digital' LIMIT 1;

        -- 3. Catalog (Categories, Products, Variants)
        INSERT INTO categories (id, business_id, name, type) VALUES
        (cat_hair_id, biz_spa_id, 'Hair Services', 'service'),
        (cat_retail_id, biz_spa_id, 'Retail Products', 'product');

        INSERT INTO products (id, business_id, category_id, name, type, selling_price, track_inventory, is_active) VALUES
        (serv_haircut_id, biz_spa_id, cat_hair_id, 'Premium Haircut', 'service', 500.00, false, true),
        (serv_spa_id, biz_spa_id, cat_hair_id, 'Hair Spa', 'service', 800.00, false, true),
        (prod_shampoo_id, biz_spa_id, cat_retail_id, 'Argan Oil Shampoo', 'product', 300.00, true, true);

        INSERT INTO product_variants (id, product_id, name, selling_price) VALUES
        (var_shampoo_500ml_id, prod_shampoo_id, '500ml', 450.00);

        -- 4. Service Packages
        INSERT INTO service_packages (id, business_id, name, price, validity_days) VALUES
        (pkg_bridal_id, biz_spa_id, 'Bridal Prep Package', 1200.00, 30);
        
        INSERT INTO service_package_items (package_id, product_id, quantity) VALUES
        (pkg_bridal_id, serv_haircut_id, 1),
        (pkg_bridal_id, serv_spa_id, 1);

        -- 5. Suppliers & Purchase Orders (Triggers inventory_transactions -> inventory upsert)
        INSERT INTO suppliers (id, business_id, name, is_active) VALUES
        (supplier_id, biz_spa_id, 'Loreal Distro', true);

        -- A completed Purchase Order
        INSERT INTO purchase_orders (id, business_id, supplier_id, order_number, status, total_amount, received_at) VALUES
        (po_id, biz_spa_id, supplier_id, 'PO-TEST-001', 'received', 4500.00, NOW());

        -- Receiving this item triggers an inventory adjustment of +10 stock for the shampoo variant
        INSERT INTO purchase_order_items (purchase_order_id, product_id, variant_id, quantity_ordered, quantity_received, unit_cost) VALUES
        (po_id, prod_shampoo_id, var_shampoo_500ml_id, 10.0, 10.0, 450.00);

        -- We insert manually into inventory_transactions to simulate the trigger which only fires from application logic if they transition status. 
        -- Wait, the trigger 'trg_purchase_orders_po_number' handles numbers, but there's no trigger for PO received -> inventory! The schema notes said:
        -- "Receiving triggers inventory_transactions with type=purchase."
        -- Let's explicitly insert the transaction.
        INSERT INTO inventory_transactions (business_id, product_id, variant_id, type, quantity, reference_id) VALUES
        (biz_spa_id, prod_shampoo_id, var_shampoo_500ml_id, 'purchase', 10.0, po_id);

        -- 6. Staff, Availability, Leaves
        INSERT INTO staff (id, business_id, name, role, is_active) VALUES
        (staff_stylist_id, biz_spa_id, 'Mike Stylist', 'stylist', true);

        INSERT INTO staff_availability (staff_id, day_of_week, start_time, end_time, is_available) VALUES
        (staff_stylist_id, 1, '09:00', '18:00', true);

        INSERT INTO staff_leaves (staff_id, leave_date, reason) VALUES
        (staff_stylist_id, CURRENT_DATE + interval '7 days', 'Vacation');

        -- 7. Commissions Rules
        INSERT INTO staff_commissions (business_id, staff_id, product_id, commission_type, commission_value) VALUES
        (biz_spa_id, staff_stylist_id, serv_haircut_id, 'percentage', 20.00), -- 20% on haircut
        (biz_spa_id, staff_stylist_id, null, 'percentage', 5.00);             -- 5% catch-all on retail

        -- 8. Customers & Loyalty
        INSERT INTO customers (id, business_id, name, phone, loyalty_points) VALUES
        (cust_vip_id, biz_spa_id, 'Jane VIP', '555-0101', 0);

        -- 9. Discounts
        INSERT INTO discounts (id, business_id, name, type, value, is_active) VALUES
        (discount_id, biz_spa_id, 'Opening Promo', 'percentage', 10.00, true);

        -- 10. Appointments
        INSERT INTO appointments (id, business_id, customer_id, staff_id, status, scheduled_at, duration_minutes) VALUES
        (appt_id, biz_spa_id, cust_vip_id, staff_stylist_id, 'completed', NOW(), 60);

        INSERT INTO appointment_services (appointment_id, product_id, staff_id, price, duration_minutes) VALUES
        (appt_id, serv_haircut_id, staff_stylist_id, 500.00, 60);

        -- 11. Sales Order (Normal Sale)
        -- Will trigger customer stats increase when status is updated to 'completed'
        INSERT INTO sales_orders (id, business_id, customer_id, appointment_id, status, subtotal, discount_amount, tax_amount, total_amount) VALUES
        (order_sale_id, biz_spa_id, cust_vip_id, appt_id, 'draft', 950.00, 95.00, 0, 855.00);

        -- Update to completed to fire customer stats trigger
        UPDATE sales_orders SET status = 'completed' WHERE id = order_sale_id;

        -- Sales Order Items
        -- Sale of Haircut (triggers commission: 20% of 500 = 100)
        INSERT INTO sales_order_items (order_id, product_id, staff_id, quantity, unit_price, discount_percent, total_price) VALUES
        (order_sale_id, serv_haircut_id, staff_stylist_id, 1.0, 500.00, 10.0, 450.00);
        
        -- Sale of Retail Shampoo (triggers commission: 5% of 450 = 22.5) AND (triggers inventory_transactions -> deducts 1.0 stock -> upserts inventory)
        INSERT INTO sales_order_items (order_id, product_id, variant_id, staff_id, quantity, unit_price, discount_percent, total_price) VALUES
        (order_sale_id, prod_shampoo_id, var_shampoo_500ml_id, staff_stylist_id, 1.0, 450.00, 10.0, 405.00);

        -- Loyalty Transaction (Customer earns 855 points, triggering loyalty update)
        INSERT INTO loyalty_transactions (business_id, customer_id, type, points, reference_id) VALUES
        (biz_spa_id, cust_vip_id, 'earn', 855, order_sale_id);

        -- 12. Sales Order (Refund Scenario)
        -- Creating a 'refunded' order to test the rollback trigger on customer total_spent
        INSERT INTO sales_orders (id, business_id, customer_id, status, subtotal, total_amount) VALUES
        (order_refund_id, biz_spa_id, cust_vip_id, 'refunded', 200.00, 200.00);

        -- (Assuming it was initially completed, then moved to refunded - but for seeding, we can simulate by manually tweaking customers total_spent if the trigger needs an UPDATE, 
        -- but our trigger specifically fires on `UPDATE OF status`. To trigger it properly from seed, we insert as 'completed', then update to 'refunded'!)
        UPDATE sales_orders SET status = 'completed' WHERE id = order_refund_id;
        UPDATE sales_orders SET status = 'refunded' WHERE id = order_refund_id;

        -- 13. Payments (Split Payment)
        INSERT INTO payments (business_id, order_id, payment_method_id, amount, status) VALUES
        (biz_spa_id, order_sale_id, payment_method_cash_id, 400.00, 'completed'),
        (biz_spa_id, order_sale_id, payment_method_upi_id, 455.00, 'completed');

        -- 14. Expenses
        SELECT id INTO expense_category_marketing_id FROM expense_categories WHERE business_id = biz_spa_id AND name = 'Marketing' LIMIT 1;
        INSERT INTO expenses (business_id, category_id, amount, description, date) VALUES
        (biz_spa_id, expense_category_marketing_id, 150.00, 'Facebook Ads', CURRENT_DATE);

    END IF;
END $$;
===
-- ============================================================
-- FULL E2E USE CASE SEED SCRIPT
-- Triggers and exercises every table and logic path.
-- ============================================================

DO $$ 
DECLARE
    biz_spa_id UUID := 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID;
    owner_profile_id UUID := 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'::UUID;

    cat_hair_id UUID := gen_random_uuid();
    cat_retail_id UUID := gen_random_uuid();

    prod_shampoo_id UUID := gen_random_uuid();
    var_shampoo_500ml_id UUID := gen_random_uuid();

    serv_haircut_id UUID := gen_random_uuid();
    serv_spa_id UUID := gen_random_uuid();

    pkg_bridal_id UUID := gen_random_uuid();

    supplier_id UUID := gen_random_uuid();
    po_id UUID := gen_random_uuid();

    staff_stylist_id UUID := gen_random_uuid();
    
    cust_vip_id UUID := 'cccccccc-dddd-eeee-ffff-111111111111'::UUID;

    discount_id UUID := gen_random_uuid();

    appt_id UUID := gen_random_uuid();

    order_sale_id UUID := 'dddddddd-eeee-ffff-1111-222222222222'::UUID;
    order_refund_id UUID := 'eeeeeeee-ffff-1111-2222-333333333333'::UUID;

    payment_method_cash_id UUID;
    payment_method_upi_id UUID;
    expense_category_marketing_id UUID;

BEGIN
    -- Only run if the business doesn't exist
    IF NOT EXISTS (SELECT 1 FROM businesses WHERE id = biz_spa_id) THEN

        -- 1. Business & Settings
        INSERT INTO businesses (id, name, type, is_active) 
        VALUES (biz_spa_id, 'Elite Spa & Salon', 'salon', true);
        PERFORM seed_new_business(biz_spa_id);

        -- 2. Profiles
        INSERT INTO auth.users (id, instance_id, role, aud)
        VALUES (owner_profile_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

        INSERT INTO profiles (id, business_id, full_name, role)
        VALUES (owner_profile_id, biz_spa_id, 'Sarah Owner', 'owner');

        -- Get Default Payment Methods created by seed_new_business
        SELECT id INTO payment_method_cash_id FROM payment_methods WHERE business_id = biz_spa_id AND type = 'cash' LIMIT 1;
        SELECT id INTO payment_method_upi_id FROM payment_methods WHERE business_id = biz_spa_id AND type = 'digital' LIMIT 1;

        -- 3. Catalog (Categories, Products, Variants)
        INSERT INTO categories (id, business_id, name, type) VALUES
        (cat_hair_id, biz_spa_id, 'Hair Services', 'service'),
        (cat_retail_id, biz_spa_id, 'Retail Products', 'product');

        INSERT INTO products (id, business_id, category_id, name, type, selling_price, track_inventory, is_active) VALUES
        (serv_haircut_id, biz_spa_id, cat_hair_id, 'Premium Haircut', 'service', 500.00, false, true),
        (serv_spa_id, biz_spa_id, cat_hair_id, 'Hair Spa', 'service', 800.00, false, true),
        (prod_shampoo_id, biz_spa_id, cat_retail_id, 'Argan Oil Shampoo', 'product', 300.00, true, true);

        INSERT INTO product_variants (id, product_id, name, selling_price) VALUES
        (var_shampoo_500ml_id, prod_shampoo_id, '500ml', 450.00);

        -- 4. Service Packages
        INSERT INTO service_packages (id, business_id, name, price, validity_days) VALUES
        (pkg_bridal_id, biz_spa_id, 'Bridal Prep Package', 1200.00, 30);
        
        INSERT INTO service_package_items (package_id, product_id, quantity) VALUES
        (pkg_bridal_id, serv_haircut_id, 1),
        (pkg_bridal_id, serv_spa_id, 1);

        -- 5. Suppliers & Purchase Orders (Triggers inventory_transactions -> inventory upsert)
        INSERT INTO suppliers (id, business_id, name, is_active) VALUES
        (supplier_id, biz_spa_id, 'Loreal Distro', true);

        -- A completed Purchase Order
        INSERT INTO purchase_orders (id, business_id, supplier_id, order_number, status, total_amount, received_at) VALUES
        (po_id, biz_spa_id, supplier_id, 'PO-TEST-001', 'received', 4500.00, NOW());

        -- Receiving this item triggers an inventory adjustment of +10 stock for the shampoo variant
        INSERT INTO purchase_order_items (purchase_order_id, product_id, variant_id, quantity_ordered, quantity_received, unit_cost) VALUES
        (po_id, prod_shampoo_id, var_shampoo_500ml_id, 10.0, 10.0, 450.00);

        -- We insert manually into inventory_transactions to simulate the trigger which only fires from application logic if they transition status. 
        -- Wait, the trigger 'trg_purchase_orders_po_number' handles numbers, but there's no trigger for PO received -> inventory! The schema notes said:
        -- "Receiving triggers inventory_transactions with type=purchase."
        -- Let's explicitly insert the transaction.
        INSERT INTO inventory_transactions (business_id, product_id, variant_id, type, quantity, reference_id) VALUES
        (biz_spa_id, prod_shampoo_id, var_shampoo_500ml_id, 'purchase', 10.0, po_id);

        -- 6. Staff, Availability, Leaves
        INSERT INTO staff (id, business_id, name, role, is_active) VALUES
        (staff_stylist_id, biz_spa_id, 'Mike Stylist', 'stylist', true);

        INSERT INTO staff_availability (staff_id, day_of_week, start_time, end_time, is_available) VALUES
        (staff_stylist_id, 1, '09:00', '18:00', true);

        INSERT INTO staff_leaves (staff_id, leave_date, reason) VALUES
        (staff_stylist_id, CURRENT_DATE + interval '7 days', 'Vacation');

        -- 7. Commissions Rules
        INSERT INTO staff_commissions (business_id, staff_id, product_id, commission_type, commission_value) VALUES
        (biz_spa_id, staff_stylist_id, serv_haircut_id, 'percentage', 20.00), -- 20% on haircut
        (biz_spa_id, staff_stylist_id, null, 'percentage', 5.00);             -- 5% catch-all on retail

        -- 8. Customers & Loyalty
        INSERT INTO customers (id, business_id, name, phone, loyalty_points) VALUES
        (cust_vip_id, biz_spa_id, 'Jane VIP', '555-0101', 0);

        -- 9. Discounts
        INSERT INTO discounts (id, business_id, name, type, value, is_active) VALUES
        (discount_id, biz_spa_id, 'Opening Promo', 'percentage', 10.00, true);

        -- 10. Appointments
        INSERT INTO appointments (id, business_id, customer_id, staff_id, status, scheduled_at, duration_minutes) VALUES
        (appt_id, biz_spa_id, cust_vip_id, staff_stylist_id, 'completed', NOW(), 60);

        INSERT INTO appointment_services (appointment_id, product_id, staff_id, price, duration_minutes) VALUES
        (appt_id, serv_haircut_id, staff_stylist_id, 500.00, 60);

        -- 11. Sales Order (Normal Sale)
        -- Will trigger customer stats increase when status is updated to 'completed'
        INSERT INTO sales_orders (id, business_id, customer_id, appointment_id, status, subtotal, discount_amount, tax_amount, total_amount) VALUES
        (order_sale_id, biz_spa_id, cust_vip_id, appt_id, 'draft', 950.00, 95.00, 0, 855.00);

        -- Update to completed to fire customer stats trigger
        UPDATE sales_orders SET status = 'completed' WHERE id = order_sale_id;

        -- Sales Order Items
        -- Sale of Haircut (triggers commission: 20% of 500 = 100)
        INSERT INTO sales_order_items (order_id, product_id, staff_id, quantity, unit_price, discount_percent, total_price) VALUES
        (order_sale_id, serv_haircut_id, staff_stylist_id, 1.0, 500.00, 10.0, 450.00);
        
        -- Sale of Retail Shampoo (triggers commission: 5% of 450 = 22.5) AND (triggers inventory_transactions -> deducts 1.0 stock -> upserts inventory)
        INSERT INTO sales_order_items (order_id, product_id, variant_id, staff_id, quantity, unit_price, discount_percent, total_price) VALUES
        (order_sale_id, prod_shampoo_id, var_shampoo_500ml_id, staff_stylist_id, 1.0, 450.00, 10.0, 405.00);

        -- Loyalty points are now auto-earned by the auto_earn_loyalty_points trigger
        -- when the order status transitions to 'completed' (handled above).

        -- 12. Sales Order (Refund Scenario)
        -- Creating a 'refunded' order to test the rollback trigger on customer total_spent
        INSERT INTO sales_orders (id, business_id, customer_id, status, subtotal, total_amount) VALUES
        (order_refund_id, biz_spa_id, cust_vip_id, 'refunded', 200.00, 200.00);

        -- (Assuming it was initially completed, then moved to refunded - but for seeding, we can simulate by manually tweaking customers total_spent if the trigger needs an UPDATE, 
        -- but our trigger specifically fires on `UPDATE OF status`. To trigger it properly from seed, we insert as 'completed', then update to 'refunded'!)
        UPDATE sales_orders SET status = 'completed' WHERE id = order_refund_id;
        UPDATE sales_orders SET status = 'refunded' WHERE id = order_refund_id;

        -- 13. Payments (Split Payment)
        INSERT INTO payments (business_id, order_id, payment_method_id, amount, status) VALUES
        (biz_spa_id, order_sale_id, payment_method_cash_id, 400.00, 'completed'),
        (biz_spa_id, order_sale_id, payment_method_upi_id, 455.00, 'completed');

        -- 14. Expenses
        SELECT id INTO expense_category_marketing_id FROM expense_categories WHERE business_id = biz_spa_id AND name = 'Marketing' LIMIT 1;
        INSERT INTO expenses (business_id, category_id, amount, description, date) VALUES
        (biz_spa_id, expense_category_marketing_id, 150.00, 'Facebook Ads', CURRENT_DATE);

    END IF;
END $$;
```

---

### New Tests (32 total)

| File | Count | Covers |
|---|---|---|
| [triggers.test.sql](file:///home/spartzs/code/back_gdash/supabase/tests/triggers.test.sql) | 14 | Inventory skip for services, trackable deduction, fixed_per_unit commission, percentage catch-all, null-staff no commission, order/PO number format, customer stats on complete/cancel, auto-earn loyalty, loyalty reversal on refund, null-customer refund safety, loyalty floor at 0, discount usage tracking |
| [rls.test.sql](file:///home/spartzs/code/back_gdash/supabase/tests/rls.test.sql) | 9 | Cross-tenant isolation (2), staff can't write products, cashier can't delete customers (2), cashier can't refund orders (2), staff sees only own commissions, owner sees own data |
| [edge_cases.test.sql](file:///home/spartzs/code/back_gdash/supabase/tests/edge_cases.test.sql) | 9 | Variant NULL price inheritance (2), total_spent floor on refund, inventory_transactions immutability, loyalty_transactions immutability, commission ledger restricted update (2), service package type validation, PO quantity constraint, partial-day leave validation |

---

## Verification

Run all tests with:
```bash
supabase db reset && supabase test db
```

The existing `flow.test.sql` (10 tests) and `reports.test.sql` (14 tests) should still pass unchanged — the auto-earn trigger produces the same 855 loyalty points the manual insert did.
