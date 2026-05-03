# Frontend Architecture

- **Stack:** Vite + React 18 + TypeScript — fast HMR, native ESM, PWA plugin (`vite-plugin-pwa`)
- **State Management:** Zustand — minimal boilerplate for global cart/session state; TanStack Query for all server state (cache, refetch, optimistic updates)
- **Data Layer:** `@supabase/supabase-js` client directly from hooks; no custom REST layer needed. Realtime subscriptions for inventory/appointments. RLS enforced server-side — client never filters by `business_id` manually.
- **Routing:** React Router v6 with `createBrowserRouter`; lazy-loaded module routes via `React.lazy`; role-based redirect guards at the router level

---

# App Structure

```
/src
  /modules
    /pos          # Sales & Payments
    /catalog      # Products, Services, Categories
    /inventory    # Stock, POs, Suppliers
    /appointments # Scheduler, Staff
    /customers    # CRM, Loyalty, Commissions
  /components     # Shared UI (Button, Modal, DataTable, StatusBadge)
  /pages          # Route-level shells (assemble module components)
  /hooks          # useAuth, useRole, useBusinessId, useRealtime
  /services       # supabase.ts client init, typed query helpers per table
  /store          # cart.store.ts (Zustand), session.store.ts
```

---

# Modules → UI Mapping

## POS / Sales
- **Pages:**
  - `POSPage`: Barcode/search → add to cart → checkout
  - `OrdersPage`: List + filter orders by status/date
  - `ExpensesPage`: Log and view operational expenses
- **Components:** `ProductGrid`, `CartPanel`, `SplitPaymentModal`, `DiscountApplicator`, `ReceiptDrawer`
- **Key Interactions:**
  - Add item → Zustand cart state updated locally, no API call yet
  - Checkout → `INSERT sales_orders` → `INSERT sales_order_items` (triggers fire server-side) → `INSERT payments`
  - Refund → `UPDATE sales_orders SET status='refunded'` (owner/manager only; guard by role)
  - Apply coupon → `SELECT discounts WHERE code=?` → validate `usage_count < usage_limit` + date range client-side before applying

## Catalog
- **Pages:**
  - `ProductsPage`: List/search with category filter and type toggle (product/service)
  - `ProductFormPage`: Create/edit product or service with variant sub-form
  - `PackagesPage`: Service package builder
- **Components:** `CategoryTree`, `ProductCard`, `VariantEditor`, `PackageItemPicker`
- **Key Interactions:**
  - Category tree → hierarchical fetch with `parent_id` grouped client-side
  - Save product → upsert `products` then upsert `product_variants` in a batch
  - Toggle active → `PATCH products SET is_active` (manager/owner only)

## Inventory
- **Pages:**
  - `StockPage`: Current levels + low-stock alert badge (from `low_stock_alerts` view)
  - `PurchaseOrdersPage`: PO list with status pipeline
  - `PODetailPage`: Line items, quantity received fields, status advance
- **Components:** `StockTable`, `LowStockBanner`, `POStatusStepper`, `ReceiveGoodsForm`
- **Key Interactions:**
  - Receive goods → `UPDATE purchase_order_items SET quantity_received` → `UPDATE purchase_orders SET status` → trigger handles inventory
  - Manual adjustment → `INSERT inventory_transactions` with `type='adjustment'`
  - Realtime subscription on `inventory` table → `StockTable` auto-refreshes on change

## Appointments & Staff
- **Pages:**
  - `CalendarPage`: Day/week calendar view; staff columns color-coded by `staff.color`
  - `AppointmentFormPage`: Book/edit appointment with multi-service selector
  - `StaffPage`: Staff list, availability grid editor, leave logger
- **Components:** `WeekCalendar`, `AppointmentCard`, `ServicePicker`, `AvailabilityGrid`, `LeaveModal`
- **Key Interactions:**
  - Book → `INSERT appointments` + `INSERT appointment_services` (price snapshotted from current catalog)
  - Complete appointment → `UPDATE appointments SET status='completed'` + `INSERT sales_orders` linked via `sales_order_id`
  - Staff availability → `UPSERT staff_availability` (one row per day-of-week); leaves → `INSERT staff_leaves`

## Customers & Reports
- **Pages:**
  - `CustomersPage`: CRM list with tags, loyalty balance, last visit
  - `CustomerDetailPage`: Profile, loyalty history, visit timeline
  - `ReportsPage`: Dashboard — daily sales, net profit, top products, commission summary
- **Components:** `LoyaltyBadge`, `PointsTimeline`, `CommissionTable`, `SalesChart`, `TopProductsList`
- **Key Interactions:**
  - Loyalty adjust → `INSERT loyalty_transactions` with `type='adjust'`; balance updates via trigger
  - Commission payout → `UPDATE staff_commission_ledger SET status='paid'` (owner/manager only)
  - Reports → query pre-built views (`daily_sales_summary`, `daily_net_profit_summary`, `staff_commission_summary`) with date range params

---

# PWA Setup

- **Offline strategy:** Cache-first for static assets; network-first with stale-while-revalidate for data. POS cart state persisted to `localStorage` via Zustand middleware — survives offline/reload.
- **Caching:** Shell + JS/CSS bundles (precache via Workbox). Products and categories cached for offline POS browsing. Orders and reports: network-only (stale data risk too high).
- **Installability:** `vite-plugin-pwa` auto-generates `manifest.json` and service worker. Add `<link rel="manifest">` + `theme-color`. Prompt install banner on first visit using `beforeinstallprompt` event.

---

# Key Flows

## POS Checkout
1. User searches/scans product → `ProductGrid` filters from TanStack Query cached catalog
2. "Add to cart" → Zustand `cart.store` updated (no API); `CartPanel` recalculates totals locally
3. Apply discount code → validate via Supabase query → store discount in cart state
4. "Checkout" → sequential inserts: `sales_orders` → `sales_order_items` → `payments`; on success clear cart, show `ReceiptDrawer`

## Book Appointment
1. User picks date/staff on `WeekCalendar` → check `staff_availability` + `staff_leaves` to show available slots
2. Select customer (search or quick-create) + add services via `ServicePicker` (prices locked at this moment)
3. `INSERT appointments` + `INSERT appointment_services` in a transaction
4. Card appears on calendar via Realtime subscription; staff sees update instantly

## Commission Payout
1. Owner opens `ReportsPage` → `staff_commission_summary` view queried per month
2. Drills into `CommissionTable` for a staff member → sees pending ledger entries
3. Selects entries → "Mark as Paid" → `UPDATE staff_commission_ledger SET status='paid', paid_at=now()`; RLS blocks non-owner/manager

---

# Notes

- **Role-based UI:** `useRole()` hook reads `profiles.role` from session; wrap sensitive actions/routes in `<RoleGate allowedRoles={['owner','manager']}>`. Hide (not just disable) destructive actions for `staff/cashier`.
- **Error/loading states:** TanStack Query `isLoading`/`isError` states handled at the page level with a shared `<QueryBoundary>` wrapper (Suspense + ErrorBoundary). Mutations show optimistic UI where safe (cart), toast on failure.
- **Form handling:** React Hook Form + Zod schemas mirroring DB constraints (e.g., `selling_price >= 0`, `tax_rate 0–100`). Multi-step forms (PO receipt, appointment booking) use a local wizard state machine — not router steps.
- **`business_id` injection:** Stored in `session.store` post-login; injected into every Supabase insert via a `useInsert` wrapper hook — never passed through component props.
