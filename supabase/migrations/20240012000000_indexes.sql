-- ============================================================
-- MIGRATION 012 — Performance Indexes
-- Strategy:
--   1. Every business_id FK gets an index (tenant isolation).
--   2. Every FK used in JOIN queries gets an index.
--   3. Common filter/sort columns (status, created_at, date).
--   4. Unique constraints already create indexes implicitly.
-- ============================================================

-- ============================================================
-- BUSINESSES & PROFILES
-- ============================================================
create index idx_profiles_business_id   on public.profiles (business_id);
create index idx_profiles_role          on public.profiles (business_id, role);

create index idx_business_settings_biz  on public.business_settings (business_id, key);

-- ============================================================
-- CATALOG
-- ============================================================
create index idx_categories_business_id  on public.categories (business_id);
create index idx_categories_parent_id    on public.categories (parent_id);
create index idx_categories_type         on public.categories (business_id, type);

create index idx_products_business_id    on public.products (business_id);
create index idx_products_category_id    on public.products (category_id);
create index idx_products_type           on public.products (business_id, type);
create index idx_products_barcode        on public.products (business_id, barcode)
  where barcode is not null;
create index idx_products_is_active      on public.products (business_id, is_active);

create index idx_product_variants_product_id on public.product_variants (product_id);
create index idx_product_variants_barcode    on public.product_variants (barcode)
  where barcode is not null;

create index idx_service_packages_biz        on public.service_packages (business_id);
create index idx_service_package_items_pkg   on public.service_package_items (package_id);
create index idx_service_package_items_prod  on public.service_package_items (product_id);

-- ============================================================
-- CUSTOMERS
-- ============================================================
create index idx_customers_business_id   on public.customers (business_id);
create index idx_customers_phone         on public.customers (business_id, phone)
  where phone is not null;
create index idx_customers_last_visit    on public.customers (business_id, last_visit_at desc);
create index idx_customers_loyalty       on public.customers (business_id, loyalty_points desc);
create index idx_customers_tags          on public.customers using gin (tags);

create index idx_loyalty_tx_customer_id  on public.loyalty_transactions (customer_id);
create index idx_loyalty_tx_business_id  on public.loyalty_transactions (business_id);
create index idx_loyalty_tx_created_at   on public.loyalty_transactions (business_id, created_at desc);

-- ============================================================
-- INVENTORY
-- ============================================================
create index idx_inventory_business_id    on public.inventory (business_id);
create index idx_inventory_product_id     on public.inventory (product_id);
create index idx_inventory_low_stock      on public.inventory (business_id, quantity_in_stock)
  where quantity_in_stock <= low_stock_threshold;

create index idx_inv_tx_business_id       on public.inventory_transactions (business_id);
create index idx_inv_tx_product_id        on public.inventory_transactions (product_id);
create index idx_inv_tx_type              on public.inventory_transactions (business_id, type);
create index idx_inv_tx_created_at        on public.inventory_transactions (business_id, created_at desc);
create index idx_inv_tx_reference_id      on public.inventory_transactions (reference_id)
  where reference_id is not null;

create index idx_suppliers_business_id    on public.suppliers (business_id);

create index idx_po_business_id           on public.purchase_orders (business_id);
create index idx_po_supplier_id           on public.purchase_orders (supplier_id);
create index idx_po_status                on public.purchase_orders (business_id, status);
create index idx_po_created_at            on public.purchase_orders (business_id, created_at desc);

create index idx_po_items_order_id        on public.purchase_order_items (purchase_order_id);
create index idx_po_items_product_id      on public.purchase_order_items (product_id);

-- ============================================================
-- STAFF & APPOINTMENTS
-- ============================================================
create index idx_staff_business_id        on public.staff (business_id);
create index idx_staff_profile_id         on public.staff (profile_id)
  where profile_id is not null;
create index idx_staff_is_active          on public.staff (business_id, is_active);

create index idx_staff_avail_staff_id     on public.staff_availability (staff_id);
create index idx_staff_leaves_staff_id    on public.staff_leaves (staff_id);
create index idx_staff_leaves_date        on public.staff_leaves (staff_id, leave_date);

create index idx_appointments_business_id on public.appointments (business_id);
create index idx_appointments_customer_id on public.appointments (customer_id);
create index idx_appointments_staff_id    on public.appointments (staff_id);
create index idx_appointments_status      on public.appointments (business_id, status);
-- Critical for calendar view: date range queries
create index idx_appointments_scheduled   on public.appointments (business_id, scheduled_at);
create index idx_appointments_scheduled_staff on public.appointments (staff_id, scheduled_at)
  where staff_id is not null;

create index idx_appt_svc_appointment_id  on public.appointment_services (appointment_id);
create index idx_appt_svc_product_id      on public.appointment_services (product_id);
create index idx_appt_svc_staff_id        on public.appointment_services (staff_id);

-- ============================================================
-- SALES ORDERS & ITEMS
-- ============================================================
create index idx_so_business_id           on public.sales_orders (business_id);
create index idx_so_customer_id           on public.sales_orders (customer_id)
  where customer_id is not null;
create index idx_so_appointment_id        on public.sales_orders (appointment_id)
  where appointment_id is not null;
create index idx_so_status                on public.sales_orders (business_id, status);
-- Critical for daily reports
create index idx_so_created_at_date       on public.sales_orders (business_id, created_at);
create index idx_so_created_at            on public.sales_orders (business_id, created_at desc);

create index idx_soi_order_id             on public.sales_order_items (order_id);
create index idx_soi_product_id           on public.sales_order_items (product_id);
create index idx_soi_staff_id             on public.sales_order_items (staff_id)
  where staff_id is not null;

create index idx_discounts_business_id    on public.discounts (business_id);
create index idx_discounts_code           on public.discounts (business_id, code)
  where code is not null;
create index idx_discounts_active_dates   on public.discounts (business_id, is_active, valid_from, valid_until);

-- ============================================================
-- PAYMENTS
-- ============================================================
create index idx_payments_business_id     on public.payments (business_id);
create index idx_payments_order_id        on public.payments (order_id);
create index idx_payments_method_id       on public.payments (payment_method_id);
create index idx_payments_status          on public.payments (business_id, status);
-- For cash reconciliation by date
create index idx_payments_paid_at         on public.payments (business_id, paid_at desc)
  where paid_at is not null;

-- ============================================================
-- EXPENSES
-- ============================================================
create index idx_expense_cats_business_id  on public.expense_categories (business_id);
create index idx_expenses_business_id      on public.expenses (business_id);
create index idx_expenses_category_id      on public.expenses (category_id);
create index idx_expenses_date             on public.expenses (business_id, date desc);
create index idx_expenses_created_at       on public.expenses (business_id, created_at desc);

-- ============================================================
-- COMMISSIONS
-- ============================================================
create index idx_staff_comm_business_id   on public.staff_commissions (business_id);
create index idx_staff_comm_staff_id      on public.staff_commissions (staff_id);
create index idx_staff_comm_product_id    on public.staff_commissions (product_id)
  where product_id is not null;

create index idx_comm_ledger_business_id  on public.staff_commission_ledger (business_id);
create index idx_comm_ledger_staff_id     on public.staff_commission_ledger (staff_id);
create index idx_comm_ledger_order_id     on public.staff_commission_ledger (order_id);
create index idx_comm_ledger_status       on public.staff_commission_ledger (business_id, status);
-- Monthly payout queries
create index idx_comm_ledger_created_at   on public.staff_commission_ledger
  (business_id, staff_id, created_at);