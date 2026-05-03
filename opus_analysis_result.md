# Analysis: Schema, Migrations, Docs & Test Gaps

---

## 1. Schema Bugs & Data Integrity Issues

### 1a. Order number generator has a race condition
[generate_order_number](file:///home/spartzs/code/back_gdash/supabase/migrations/20240010000000_triggers_functions.sql#L263-L283) uses `count(*) + 1` to generate sequence numbers. Two concurrent inserts on the same business on the same day will get the **same count**, producing duplicate order numbers and a unique constraint violation.

**Fix:** Use a `SEQUENCE` per business, or an advisory lock, or `SELECT ... FOR UPDATE` on a counter row.

### 1b. PO number generator has the same race condition
[generate_po_number](file:///home/spartzs/code/back_gdash/supabase/migrations/20240010000000_triggers_functions.sql#L290-L310) — identical `count(*) + 1` pattern.

### 1c. `purchase_order_items.total_cost` uses `quantity_received`, not `quantity_ordered`
[Line 113](file:///home/spartzs/code/back_gdash/supabase/migrations/20240004000000_inventory.sql#L113): `total_cost = unit_cost * quantity_received`. This means before receiving, total_cost = 0 for every line item. If you need `total_amount` on the PO header to match the sum of line items, this will be wrong until fully received. Consider whether this should be `quantity_ordered` instead (or add a separate `expected_cost` column).

### 1d. Inventory sync trigger adds `new.quantity` — not the delta
[sync_inventory](file:///home/spartzs/code/back_gdash/supabase/migrations/20240010000000_triggers_functions.sql#L46-L74) only fires on `INSERT`. This is fine as long as `inventory_transactions` is truly append-only. But there's **no trigger preventing UPDATE/DELETE** on `inventory_transactions`. Add an immutability trigger.

### 1e. No immutability enforcement on append-only tables
The docs say `inventory_transactions`, `loyalty_transactions`, and `staff_commission_ledger` are append-only, but nothing in the schema prevents `UPDATE` or `DELETE`. Add:
```sql
CREATE FUNCTION deny_mutation() RETURNS trigger AS $$ BEGIN RAISE EXCEPTION 'This table is append-only'; END; $$ LANGUAGE plpgsql;
-- Then attach BEFORE UPDATE OR DELETE triggers on all three tables.
```

### 1f. `staff_leaves` allows partial-day with NULL times
[staff_leaves](file:///home/spartzs/code/back_gdash/supabase/migrations/20240005000000_appointments_staff.sql#L59-L70): When `is_full_day = false`, `start_time` and `end_time` can be NULL. Add:
```sql
CHECK (is_full_day = true OR (start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time))
```

---

## 2. Missing Triggers / Logic Gaps

### 2a. No trigger for PO received → inventory_transactions
The [architecture doc](file:///home/spartzs/code/back_gdash/architecture.md#L103) says: *"Trigger inserts positive inventory_transactions → sync_inventory upserts inventory snapshot"* when a PO is received. **This trigger does not exist.** The [seed file even acknowledges this](file:///home/spartzs/code/back_gdash/supabase/seeds/02_seed_usecase.sql#L93-L98) with a comment and manually inserts the transaction.

**Need:** A trigger on `purchase_order_items` that fires when `quantity_received` changes, inserting the delta into `inventory_transactions`.

### 2b. No trigger for auto-earning loyalty points on order completion
The architecture says loyalty points auto-update on order completion. Currently, the [seed manually inserts a loyalty_transaction](file:///home/spartzs/code/back_gdash/supabase/seeds/02_seed_usecase.sql#L148-L149). There's no trigger connecting `sales_orders.status = 'completed'` → `INSERT loyalty_transactions`.

### 2c. No trigger for `discounts.usage_count` auto-increment
[discounts table](file:///home/spartzs/code/back_gdash/supabase/migrations/20240006000000_sales.sql#L99) says *"usage_count is auto-incremented by trigger on application"* but no such trigger exists.

### 2d. No check that `service_package_items.product_id` references a service
The [comment says](file:///home/spartzs/code/back_gdash/supabase/migrations/20240002000000_catalog.sql#L117) *"product_id must reference a type=service product"* but there's no CHECK or trigger enforcing this. A product of `type='product'` could be added to a service package.

### 2e. No `quantity_received ≤ quantity_ordered` constraint
[Architecture](file:///home/spartzs/code/back_gdash/architecture.md#L27) mentions this as a constraint, but it's missing from the schema. Add:
```sql
CHECK (quantity_received <= quantity_ordered)
```

---

## 3. Doc ↔ Schema Mismatches

| Doc says | Schema reality |
|---|---|
| *"Order number auto-generated as `INV-YYYYMMDD-XXXX`"* (architecture.md) | Trigger does this, but `seed_new_business` uses `INV-K-001` and `INV-S-001` formats — inconsistent |
| *"PO number auto-generated as `PO-XXXX`"* | Works, but seeds use `PO-TEST-001` bypassing the trigger (trigger only fires when `order_number` is NULL/empty) |
| *"`daily_sales_summary` in 010 migration"* uses `status = 'completed'` only | [reports migration 013](file:///home/spartzs/code/back_gdash/supabase/migrations/20240013000000_reports.sql#L21) redefines it with `status IN ('confirmed','completed')` — the 013 view overrides the 010 view, but the test expectations differ |
| *"low_stock_alerts in 010"* filters `p.is_active = true` and `threshold > 0` | [013 redefines it](file:///home/spartzs/code/back_gdash/supabase/migrations/20240013000000_reports.sql#L29-L46) **without** the `is_active` or `threshold > 0` filters — weaker version |
| features.md lists `buy_x_get_y` discount type | No schema columns exist to define X or Y quantities |

---

## 4. Redundant / Duplicate Code

### 4a. Views defined twice
`daily_sales_summary`, `low_stock_alerts`, and `staff_commission_summary` are created in [010_triggers_functions.sql](file:///home/spartzs/code/back_gdash/supabase/migrations/20240010000000_triggers_functions.sql#L317-L371) and then **dropped and recreated** in [013_reports.sql](file:///home/spartzs/code/back_gdash/supabase/migrations/20240013000000_reports.sql#L3-L63) with slightly different logic. Pick one location, delete the other.

### 4b. Duplicate indexes from unique constraints
The [indexes migration](file:///home/spartzs/code/back_gdash/supabase/migrations/20240012000000_indexes.sql) creates `idx_so_created_at_date` (ASC) and `idx_so_created_at` (DESC) on `(business_id, created_at)`. The DESC index can serve both sort directions — drop the ASC one.

---

## 5. RLS Policy Gaps

### 5a. `sales_orders: update status` policy is too permissive
[Lines 323-329](file:///home/spartzs/code/back_gdash/supabase/migrations/20240011000000_rls_policies.sql#L323-L329): The `WITH CHECK` allows staff/cashier to set `status IN ('confirmed','completed')` but the `USING` clause only checks `business_id` — this means a cashier could update **any** column (not just status) as long as the final status is `confirmed` or `completed`.

**Fix:** Use a more restrictive check or use a `SECURITY DEFINER` function for status transitions.

### 5b. No DELETE policy on `sales_order_items`
There's read and insert, but no delete. If a draft order item needs to be removed, it would be blocked by RLS.

### 5c. `product_variants: write` policy missing `WITH CHECK`
[Lines 120-128](file:///home/spartzs/code/back_gdash/supabase/migrations/20240011000000_rls_policies.sql#L120-L128): The write policy has `USING` but no `WITH CHECK`, meaning it validates existing rows but doesn't constrain new/updated rows. Same issue on `service_package_items`, `purchase_order_items`, and `appointment_services`.

### 5d. `staff_leaves: write` — no role restriction
[Lines 280-287](file:///home/spartzs/code/back_gdash/supabase/migrations/20240011000000_rls_policies.sql#L280-L287): Any authenticated user in the business can create/update/delete leave records. Should this be restricted to owner/manager/the-staff-member-themselves?

### 5e. Views need RLS consideration
Views like `daily_sales_summary` inherit RLS from underlying tables only if not `SECURITY DEFINER`. The `top_selling_products` function is `SECURITY INVOKER` (good), but it accepts a `p_business_id` parameter — a user could pass a different business ID. Since RLS applies on the underlying tables this is safe, but worth a comment/test.

---

## 6. Performance Concerns

### 6a. `my_business_id()` and `my_role()` called per-row in every RLS policy
Both are `SECURITY DEFINER` + `STABLE`, which is correct. But they query `profiles` every time. Consider caching via `current_setting` / session variables set at login, or ensure the Supabase PostgREST `request.jwt.claims` is used instead.

### 6b. `idx_inventory_low_stock` partial index references another column in WHERE
[Line 59-60](file:///home/spartzs/code/back_gdash/supabase/migrations/20240012000000_indexes.sql#L59-L60): `WHERE quantity_in_stock <= low_stock_threshold` — this partial index condition references a **non-constant** column, so it only applies when the planner can prove the condition matches at query time. This index is essentially useless.

---

## 7. Missing Tests

### Current coverage
| File | Tests | Covers |
|---|---|---|
| `flow.test.sql` | 10 | Business settings seed, inventory after PO+sale, loyalty, customer stats, commissions (2), payments (2), refund rollback, expenses |
| `reports.test.sql` | 14 | View existence (5), daily sales (2), low stock, commission summary, net profit, loyalty summary (2), top products function (2) |

### Tests to add

**Trigger correctness:**
1. `inventory_deduction.test.sql` — Insert a `sales_order_items` row for a `track_inventory = false` product → verify **no** `inventory_transactions` row created
2. Commission trigger with `fixed_per_unit` type (only `percentage` is tested)
3. Commission trigger with `staff_id = NULL` on the line item → verify no ledger entry
4. Order number generation — insert two orders for the same business on the same day → verify unique sequential numbers
5. PO number generation — insert two POs → verify sequential

**State machine / status transitions:**
6. `update_customer_stats` trigger: update order from `draft` → `completed` (not just the seed's pattern) — verify increment
7. `update_customer_stats` trigger: update from `completed` → `cancelled` → verify **no** rollback (only `refunded` rolls back)
8. Refund on order with `customer_id = NULL` → verify trigger handles NULL gracefully

**Boundary / edge cases:**
9. Loyalty points: redeem more than balance → verify `loyalty_points` floors at 0
10. Customer `total_spent` refund when total_spent is less than refund amount → verify floors at 0
11. Variant with `selling_price = NULL` → verify inherits from parent product (application-level, but worth a query test)
12. Category self-reference depth (no infinite loop protection exists — at least document)

**RLS / security:**
13. `cashier` role attempting to update `sales_orders.status` to `refunded` → should be blocked
14. `cashier` role attempting to delete a customer → should be blocked
15. `staff` role attempting to write to `products` → should be blocked
16. Staff member reading `staff_commission_ledger` → should only see their own rows
17. Cross-business isolation — user from business A cannot read business B data

**Seed / data integrity:**
18. `seed_new_business` idempotency — calling twice should fail gracefully (unique constraints on payment_methods and expense_categories will throw)
19. `buy_x_get_y` discount type validation — no schema support exists for X/Y params; this is a doc-only feature

---

## 8. Quick Wins Summary

| Priority | Item | Effort |
|---|---|---|
| 🔴 Critical | Add PO received → inventory trigger | Medium |
| 🔴 Critical | Fix order/PO number race condition | Medium |
| 🔴 Critical | Add immutability triggers on append-only tables | Low |
| 🟡 Important | Add `quantity_received <= quantity_ordered` CHECK | Low |
| 🟡 Important | Add `staff_leaves` partial-day validation CHECK | Low |
| 🟡 Important | Fix `sales_orders: update status` RLS policy | Medium |
| 🟡 Important | Remove duplicate view definitions (010 vs 013) | Low |
| 🟡 Important | Add `service_package_items` product type constraint | Low |
| 🟢 Nice-to-have | Add `WITH CHECK` to FK-scoped write policies | Low |
| 🟢 Nice-to-have | Add DELETE policy on `sales_order_items` | Low |
| 🟢 Nice-to-have | Add `buy_x_get_y` schema columns or remove from docs | Low |
| 🟢 Nice-to-have | Drop redundant ASC index on `sales_orders.created_at` | Low |
