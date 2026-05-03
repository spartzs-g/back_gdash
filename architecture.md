# System Overview
Multi-tenant SaaS POS and business-management backend built on Supabase (PostgreSQL).
Serves retail (kirana), salon, barber, and clinic verticals from a single schema, with the `businesses.type` field controlling module visibility per tenant.
All data is isolated per `business_id`; auth and authorization are enforced via Supabase Auth + PostgreSQL Row Level Security.

---

# Core Modules

## 1. Catalog
- **Responsibility:** Unified product and service registry per business.
- **Key Tables:** `categories`, `products`, `product_variants`, `service_packages`, `service_package_items`
- **Relationships:** Categories are hierarchical (self-referencing `parent_id`). Products belong to a category. Variants extend a product with price/SKU overrides. Packages aggregate multiple service products.
- **Important Constraints:**
  - `products.type ∈ {product, service}` — controls inventory tracking and duration handling.
  - `track_inventory = false` for services; triggers skip them on sale deduction.
  - Variant `selling_price = NULL` inherits from parent product.
  - Package items reference `type=service` products only.

## 2. Inventory
- **Responsibility:** Real-time stock tracking with full audit trail.
- **Key Tables:** `inventory`, `inventory_transactions`, `suppliers`, `purchase_orders`, `purchase_order_items`
- **Relationships:** `inventory` is a snapshot maintained by trigger from `inventory_transactions`. Purchase orders link to suppliers and line items; receiving triggers stock-in transactions.
- **Important Constraints:**
  - `inventory_transactions` is append-only (positive = in, negative = out).
  - `inventory.quantity_in_stock` is read-only in application code — trigger-maintained only.
  - Partial delivery supported: `quantity_received ≤ quantity_ordered`.
  - PO status flow: `draft → ordered → partially_received → received | cancelled`.

## 3. Appointments & Staff
- **Responsibility:** Scheduling engine linking customers, staff, and services.
- **Key Tables:** `staff`, `staff_availability`, `staff_leaves`, `appointments`, `appointment_services`
- **Relationships:** Staff exists independently of profiles (no login required). Appointments link one customer to N services, each potentially assigned to a different staff member. `appointments.sales_order_id` is populated on completion.
- **Important Constraints:**
  - Appointment status flow: `scheduled → confirmed → in_progress → completed | cancelled | no_show`.
  - `appointment_services.price` is snapshotted at booking time.
  - `staff_leaves` takes precedence over `staff_availability` for a given date.
  - `staff.color` is used for calendar rendering; `specializations` is a tag array.

## 4. Sales & Payments
- **Responsibility:** POS billing, discount application, split payments, and expense tracking.
- **Key Tables:** `sales_orders`, `sales_order_items`, `discounts`, `payment_methods`, `payments`, `expenses`, `expense_categories`
- **Relationships:** An order has N line items and N payment records (split payment). Line items reference a product and optionally a staff member (for commission). Expenses are independent of orders but share payment methods.
- **Important Constraints:**
  - Order status flow: `draft → confirmed → completed | cancelled | refunded`.
  - `sales_order_items.unit_price` is snapshotted — immune to future catalog changes.
  - Discount types: `percentage | fixed_amount | buy_x_get_y`; `usage_count` is auto-incremented.
  - Order number auto-generated as `INV-YYYYMMDD-XXXX` (per-business, per-day sequence).

## 5. Customers & Commissions
- **Responsibility:** CRM with loyalty ledger and automated staff commission accounting.
- **Key Tables:** `customers`, `loyalty_transactions`, `staff_commissions`, `staff_commission_ledger`
- **Relationships:** Customers accumulate loyalty from orders. Staff commission rules (per-product or catch-all) produce ledger entries per sale line item via trigger.
- **Important Constraints:**
  - `loyalty_transactions` is append-only; `customers.loyalty_points` is a denormalized sync via trigger.
  - Commission rule precedence: product-specific rule beats catch-all (`product_id = NULL`).
  - Commission types: `percentage` of line total or `fixed_per_unit`.
  - Ledger status flow: `pending → paid`; only owner/manager can mark as paid.

---

# Data Model Highlights
- **Multi-tenancy:** Every table carries `business_id` (FK to `businesses`). RLS policies filter all queries to `my_business_id()` (a security-definer helper resolving the caller's profile).
- **Ownership model:** One `auth.users` row → one `profiles` row per business. Staff without app access exist in `staff` only (no profile).
- **Key invariants:**
  - Ledger tables (`inventory_transactions`, `loyalty_transactions`, `staff_commission_ledger`) are append-only; application code must never UPDATE or DELETE rows.
  - Denormalized counters (`customers.loyalty_points`, `customers.total_spent`, `inventory.quantity_in_stock`) are exclusively managed by triggers — treat as read-only in app code.
  - Monetary snapshot pattern: prices on `sales_order_items` and `appointment_services` are captured at creation time.
  - `customers.total_spent` floors at 0 on refund rollback (`GREATEST(value - amount, 0)`).

---

# Security & Access Control
- **Auth model:** Supabase Auth (JWT). `auth.uid()` maps to `profiles.id`. Service role bypasses RLS for server-side functions.
- **Authorization:**
  - `owner` — full write access to all tables including business settings, refunds, and commission payouts.
  - `manager` — same as owner except cannot update the business row itself.
  - `staff / cashier` — can read all, create orders and payments, cannot cancel/refund orders or manage expenses.
  - Commission ledger: staff can read their own rows only (`staff.profile_id = auth.uid()`).
  - RLS on child tables without `business_id` (e.g., `product_variants`) is enforced via EXISTS subquery joining to the parent's `business_id`.

---

# Workflows (High Level)

## Sale (POS Checkout)
1. Create `sales_orders` (status=`draft`; order number auto-generated).
2. Insert `sales_order_items` → triggers: inventory deducted, commission ledger entries created.
3. Apply discount code; advance order to `confirmed` then `completed`.
4. Insert `payments` records (one per payment method; must sum to `total_amount`).
5. Trigger updates `customers.visit_count`, `total_spent`, `last_visit_at`.

## Appointment → Invoice
1. Book appointment (status=`scheduled`); services and prices locked at booking.
2. Confirm → `in_progress` → `completed`.
3. On completion, generate `sales_orders` linked via `appointments.sales_order_id`.
4. Sales order follows the normal checkout flow from step 2 above.

## Inventory Receipt (Purchase Order)
1. Create `purchase_orders` (status=`draft`; PO number auto-generated as `PO-XXXX`).
2. Place order with supplier → status=`ordered`.
3. Receive goods: update `purchase_order_items.quantity_received`; status → `received` (or `partially_received`).
4. Trigger inserts positive `inventory_transactions` → `sync_inventory` upserts `inventory` snapshot.

## Commission Payout
1. Commissions accumulate in `staff_commission_ledger` (status=`pending`) per sale line item.
2. Owner reviews monthly summary via `staff_commission_summary` view.
3. Owner marks ledger entries as `paid` (sets `paid_at`); only owner/manager role permitted.
