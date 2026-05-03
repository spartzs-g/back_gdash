# Frontend Implementation Plan — Multi-Tenant POS

## Summary

Build a Vite + React 18 + TypeScript + TailwindCSS frontend for the Supabase POS backend.
7 phases, priority-ordered. Each phase is self-contained and session-resumable.

---

## Upgrades Over Original Plan

| Area | Original | Upgraded |
|---|---|---|
| **State** | Raw `useState` arrays | **Zustand** cart store + **TanStack Query** for server state (per `frontend_architecture.md`) |
| **Routing** | Implicit | `react-router-dom` v6 with `createBrowserRouter`, lazy routes, `<RoleGate>` |
| **Auth** | Context-only | Zustand `session.store` + `useAuth` hook (smaller re-renders) |
| **Multi-tenancy** | Manual `business_id` props | `useInsert()` wrapper auto-injects `business_id` from store — **never in props** |
| **Data** | Inline Supabase calls | Typed `services/*.ts` query helpers per table; reusable across pages |
| **UI** | Unstyled HTML | Tailwind utility classes + shared `<DataTable>`, `<Modal>`, `<StatusBadge>` components |
| **Forms** | Raw inputs | React Hook Form + Zod schemas mirroring DB constraints |
| **Error Handling** | None | `<QueryBoundary>` (Suspense + ErrorBoundary) + toast on mutation failure |
| **Offline** | None | Zustand `persist` middleware for cart → survives reload |
| **Reports** | Missing | Phase 6 — queries existing DB views (`daily_sales_summary`, `daily_net_profit_summary`, etc.) |

---

## Token Optimization Strategy

> [!TIP]
> **Rules for every session to minimize token usage:**
> 1. **Never re-read migrations** — schema is fully captured in the type file (`types/db.ts`) generated in P0.
> 2. **Never re-read this plan** — check `task.md` for current progress, jump to the uncompleted phase.
> 3. **Shared code first** — services, hooks, components are written once and imported everywhere.
> 4. **One file = one concern** — no god-files. Each page < 150 lines.
> 5. **Copy-paste reduction** — generic `<DataTable>`, `useCrud` hook, `useInsert` wrapper.

### Session Resumption Protocol

At the start of each new session:
1. Read `task.md` → find the first `[ ]` item.
2. Read the **target file** listed for that item.
3. Do NOT re-read `implementation_plan.md`, migrations, or completed files.

---

## File Tree (Final State)

```
src/
├── main.tsx                    # ReactDOM.createRoot + RouterProvider
├── App.tsx                     # createBrowserRouter definition
├── vite-env.d.ts
├── types/
│   └── db.ts                   # Hand-typed Supabase row/insert types (from migrations)
├── lib/
│   └── supabase.ts             # createClient singleton
├── store/
│   ├── session.store.ts        # Zustand: profile, business_id, role
│   └── cart.store.ts           # Zustand + persist: cart items, totals, checkout
├── hooks/
│   ├── useAuth.ts              # Login/logout, session hydration
│   ├── useSession.ts           # Shortcut: useSessionStore selectors
│   ├── useInsert.ts            # Auto-injects business_id on every insert
│   └── useCrud.ts              # Generic list/create/update/delete with TanStack Query
├── services/
│   ├── catalog.service.ts      # products, categories, variants queries
│   ├── inventory.service.ts    # inventory, transactions, suppliers, POs
│   ├── sales.service.ts        # orders, items, payments, discounts
│   ├── appointments.service.ts # appointments, services, staff
│   ├── customers.service.ts    # customers, loyalty
│   └── admin.service.ts        # commissions, expenses, reports
├── components/
│   ├── Layout.tsx              # Sidebar + top bar + <Outlet/>
│   ├── ProtectedRoute.tsx      # Redirect to /login if no session
│   ├── RoleGate.tsx            # Hide children if role not in allowedRoles
│   ├── QueryBoundary.tsx       # Suspense + ErrorBoundary wrapper
│   ├── DataTable.tsx           # Generic table: columns config → rendered table
│   ├── Modal.tsx               # Reusable modal shell
│   ├── StatusBadge.tsx         # Color-coded status pill
│   └── FormField.tsx           # Label + input + error wrapper for RHF
├── pages/
│   ├── Login.tsx
│   ├── Dashboard.tsx           # Reports overview (P6)
│   ├── catalog/
│   │   ├── ProductsPage.tsx
│   │   └── ProductForm.tsx
│   ├── inventory/
│   │   ├── StockPage.tsx
│   │   └── PurchaseOrdersPage.tsx
│   ├── pos/
│   │   └── POSPage.tsx
│   ├── appointments/
│   │   ├── CalendarPage.tsx
│   │   └── AppointmentForm.tsx
│   ├── customers/
│   │   └── CustomersPage.tsx
│   └── admin/
│       ├── StaffLedger.tsx
│       └── ExpensesPage.tsx
└── index.css                   # Tailwind directives + custom tokens
```

---

## Phase 0: Scaffold (5 min)

**Goal:** Vite project + deps installed. Zero custom code yet.

### Steps
1. `npx -y create-vite@latest ./ --template react-ts` inside a new `frontend/` directory
2. Install deps:
   ```
   npm i @supabase/supabase-js zustand @tanstack/react-query react-router-dom react-hook-form @hookform/resolvers zod
   npm i -D tailwindcss @tailwindcss/vite
   ```
3. Configure Tailwind (v4 — CSS-only, no `tailwind.config.js`):
   - `index.css`: `@import "tailwindcss";`
4. Create `.env` with `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`
5. Verify `npm run dev` works with blank page.

### Files Created
- `frontend/` scaffold (Vite template)
- `frontend/.env` (gitignored)
- `frontend/src/index.css`

---

## Phase 1: Auth & Global State

**Goal:** Login → profile loaded → `business_id` + `role` in Zustand → protected routes.

**DB Tables Used:** `profiles`, `businesses`
**RLS Note:** `my_business_id()` and `my_role()` are server-side helpers; client just reads `profiles` row for `auth.uid()`.

### Files

#### `src/types/db.ts`
Hand-typed interfaces from migrations. **This is the single source of truth for all phases.**

Key types needed:
```
Business, Profile, Category, Product, ProductVariant,
Customer, LoyaltyTransaction, Inventory, InventoryTransaction,
Supplier, PurchaseOrder, PurchaseOrderItem,
Staff, StaffAvailability, StaffLeave,
Appointment, AppointmentService,
SalesOrder, SalesOrderItem, Discount,
PaymentMethod, Payment,
ExpenseCategory, Expense,
StaffCommission, StaffCommissionLedger
```

#### `src/lib/supabase.ts`
- `createClient(VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY)`
- Export singleton `supabase`

#### `src/store/session.store.ts`
Zustand store:
- State: `profile | null`, `businessId | null`, `role | null`, `isLoading`
- Actions: `setSession(profile)`, `clear()`

#### `src/hooks/useAuth.ts`
- On mount: `supabase.auth.getSession()` → if session, fetch `profiles` row → `sessionStore.setSession()`
- `login(email, password)` → `supabase.auth.signInWithPassword`
- `logout()` → `supabase.auth.signOut` → `sessionStore.clear()`
- Subscribe to `onAuthStateChange`

#### `src/hooks/useInsert.ts`
```ts
// Wraps supabase.from(table).insert(data)
// Auto-merges { business_id: sessionStore.businessId } into every insert
```

#### `src/components/ProtectedRoute.tsx`
- If no session → redirect to `/login`
- Else → `<Outlet />`

#### `src/components/Layout.tsx`
- Sidebar nav with links to each module
- Top bar showing business name + user role
- `<Outlet />` for page content

#### `src/components/RoleGate.tsx`
- Props: `allowedRoles: string[]`, `children`
- If `role` not in `allowedRoles` → render nothing (hide, don't disable)

#### `src/pages/Login.tsx`
- Email + password form → `useAuth().login()`

#### `src/App.tsx`
- `createBrowserRouter` with:
  - `/login` → `<Login />`
  - `/` → `<ProtectedRoute>` → `<Layout>` → child routes (lazy-loaded in later phases)

### Verification
- Login with valid Supabase credentials
- Console shows `business_id` and `role`
- Navigating to `/` without login redirects to `/login`

---

## Phase 2: Catalog & Inventory

**Goal:** CRUD for products/categories. View inventory levels. Manual stock adjustments.

**DB Tables:** `categories`, `products`, `product_variants`, `inventory`, `inventory_transactions`, `suppliers`, `purchase_orders`, `purchase_order_items`

**DB Rules (do NOT replicate in frontend):**
- `inventory.quantity_in_stock` — trigger-maintained, read-only
- `sync_inventory()` trigger fires on `inventory_transactions` insert
- `receive_purchase_order_items()` trigger fires on PO item `quantity_received` update

### Files

#### `src/services/catalog.service.ts`
Query helpers:
- `getProducts(businessId)` → `products` with optional join to `categories`
- `getCategories(businessId)` → `categories` ordered by `sort_order`
- `upsertProduct(data)` → insert or update `products`
- `upsertVariants(productId, variants[])` → batch upsert `product_variants`

#### `src/services/inventory.service.ts`
- `getInventory(businessId)` → `inventory` joined to `products`
- `getLowStockAlerts(businessId)` → `low_stock_alerts` view
- `insertTransaction(data)` → `inventory_transactions` (type = `adjustment`)
- `getSuppliers(businessId)` → `suppliers`
- `getPurchaseOrders(businessId)` → `purchase_orders`
- `updatePOItemReceived(id, qty)` → `purchase_order_items` update `quantity_received`

#### `src/pages/catalog/ProductsPage.tsx`
- List products in `<DataTable>` with columns: name, type, price, category, active
- Filter by type (product/service) and category
- "Add Product" button → opens `ProductForm`

#### `src/pages/catalog/ProductForm.tsx`
- React Hook Form + Zod schema
- Fields: name, type (product/service), category, selling_price, cost_price, tax_rate, sku, barcode, track_inventory, duration_minutes (show only if type=service)
- Variant sub-form (add/remove rows)

#### `src/pages/inventory/StockPage.tsx`
- `<DataTable>` showing `inventory` rows: product name, variant, qty, low_stock_threshold, unit
- Low-stock badge for items at/below threshold
- "Adjust Stock" button → modal with type=adjustment, quantity, notes → `insertTransaction()`

#### `src/pages/inventory/PurchaseOrdersPage.tsx`
- List POs with status badge
- Create PO form (supplier, line items)
- "Receive" action → update `quantity_received` per item

### Verification
- Add a product (type=product, track_inventory=true)
- Add a service (type=service, track_inventory=false)
- Insert an adjustment transaction → verify `inventory.quantity_in_stock` updates (trigger)
- Create a PO → receive items → verify inventory updates

---

## Phase 3: POS & Sales (Core Loop)

**Goal:** Product search → cart → checkout → payment. The primary revenue-generating feature.

**DB Tables:** `sales_orders`, `sales_order_items`, `discounts`, `payment_methods`, `payments`

**DB Rules (do NOT replicate):**
- `generate_order_number()` trigger auto-creates `INV-YYYYMMDD-XXXX`
- `deduct_inventory_on_sale()` trigger fires on `sales_order_items` insert
- `record_staff_commission()` trigger fires on `sales_order_items` insert
- `update_customer_stats()` trigger fires on `sales_orders` status change
- `auto_earn_loyalty_points()` trigger fires on `sales_orders` status change
- `track_discount_usage()` trigger fires on `sales_orders` insert/update

### Files

#### `src/store/cart.store.ts`
Zustand + persist middleware:
```ts
State: {
  items: CartItem[]  // { product, variant?, quantity, unitPrice, discountPercent, taxRate, staffId? }
  customerId: string | null
  discountId: string | null
}
Actions: {
  addItem(product, variant?, staffId?)
  removeItem(index)
  updateQuantity(index, qty)
  setCustomer(id | null)
  applyDiscount(discount)
  clearCart()
  // Computed (derived in selectors):
  subtotal, discountAmount, taxAmount, total
}
```

#### `src/services/sales.service.ts`
- `getPaymentMethods(businessId)`
- `validateDiscount(businessId, code)` → check `discounts` where code, is_active, date range, usage
- `checkout(businessId, cart, paymentSplits[])`:
  1. Insert `sales_orders` (status='completed', computed totals, order_number='' to let trigger generate)
  2. Insert `sales_order_items[]` (snapshot prices from cart)
  3. Insert `payments[]` (one per split)
  4. Return order

#### `src/pages/pos/POSPage.tsx`
Two-column layout:
- **Left:** Product search/grid (from TanStack Query cached catalog)
- **Right:** Cart panel
  - Line items with qty +/- and remove
  - Customer selector (optional)
  - Discount code input + validate
  - Subtotal / discount / tax / total display
  - Payment method selector (supports split)
  - "Checkout" button → calls `sales.service.checkout()`
  - On success: clear cart, show receipt/toast

### Verification
- Search product → add to cart → quantities update
- Apply discount code → verify validation
- Checkout → verify `sales_orders` created with auto-generated order number
- Verify inventory deducted (trigger) for tracked products
- Verify customer stats updated (trigger) if customer linked

---

## Phase 4: Appointments & Staff

**Goal:** Book appointments, manage staff, complete → generate invoice.

**DB Tables:** `staff`, `staff_availability`, `staff_leaves`, `appointments`, `appointment_services`

**DB Rules:**
- `appointment_services.price` snapshotted at booking time
- On completion: create `sales_orders` linked via `appointments.sales_order_id`
- No DB trigger for appointment→sale conversion — this is **app logic**

### Files

#### `src/services/appointments.service.ts`
- `getStaff(businessId)` → `staff` active
- `getStaffAvailability(staffId)` → `staff_availability`
- `getStaffLeaves(staffId, dateRange)` → `staff_leaves`
- `getAppointments(businessId, date)` → `appointments` with `appointment_services`
- `bookAppointment(data)` → insert `appointments` + `appointment_services[]`
- `updateAppointmentStatus(id, status)`
- `completeAndInvoice(appointmentId)`:
  1. Fetch appointment + services
  2. Create `sales_orders` (status='completed') with appointment_id
  3. Insert `sales_order_items` from appointment_services (prices already snapshotted)
  4. Insert payment
  5. Update `appointments.sales_order_id` and status='completed'

#### `src/pages/appointments/CalendarPage.tsx`
- Day view: time slots with appointment blocks (color by `staff.color`)
- Click slot → open `AppointmentForm`
- Click appointment → show detail with status actions (confirm, start, complete, cancel)
- "Complete" action → calls `completeAndInvoice()` → shows generated invoice number

#### `src/pages/appointments/AppointmentForm.tsx`
- Customer selector (search existing or quick-create)
- Staff selector
- Service multi-picker (type='service' products only) — prices locked at selection
- Date/time picker
- Duration auto-calculated from sum of service durations

### Verification
- Book appointment with 2 services → verify `appointment_services` prices match catalog
- Complete appointment → verify `sales_orders` created with `appointment_id`
- Verify inventory NOT deducted (services have `track_inventory=false`)

---

## Phase 5: CRM & Admin

**Goal:** Customer list with loyalty. Commission payouts. Expense tracking.

**DB Tables:** `customers`, `loyalty_transactions`, `staff_commission_ledger`, `staff_commissions`, `expense_categories`, `expenses`

**DB Rules:**
- `customers.loyalty_points` — trigger-maintained, read-only
- `customers.total_spent`, `visit_count` — trigger-maintained, read-only
- `staff_commission_ledger` — trigger-generated, only `status` + `paid_at` updatable
- Commission ledger: staff sees own rows only; owner/manager sees all (RLS)

### Files

#### `src/services/customers.service.ts`
- `getCustomers(businessId)` → `customers`
- `upsertCustomer(data)`
- `getLoyaltyHistory(customerId)` → `loyalty_transactions`
- `adjustLoyalty(customerId, points, notes)` → insert `loyalty_transactions` type='adjust'

#### `src/services/admin.service.ts`
- `getCommissionSummary(businessId)` → `staff_commission_summary` view
- `getCommissionLedger(businessId, staffId?)` → `staff_commission_ledger`
- `markCommissionPaid(ids[])` → update `status='paid'`, `paid_at=now()`
- `getExpenseCategories(businessId)`
- `getExpenses(businessId, dateRange)`
- `createExpense(data)`

#### `src/pages/customers/CustomersPage.tsx`
- `<DataTable>`: name, phone, loyalty_points, total_spent, visit_count, last_visit
- Click row → detail modal with loyalty history timeline
- "Adjust Points" button (owner/manager only via `<RoleGate>`)

#### `src/pages/admin/StaffLedger.tsx`
- **Wrapped in `<RoleGate allowedRoles={['owner','manager']}>`**
- Monthly commission summary table (from view)
- Drill into staff → individual ledger entries
- Multi-select pending entries → "Mark as Paid" button

#### `src/pages/admin/ExpensesPage.tsx`
- **Wrapped in `<RoleGate allowedRoles={['owner','manager']}>`**
- Expense list with category, amount, date, payment method
- Add expense form (category, amount, description, date, payment method)

### Verification
- View customer with auto-updated loyalty (from previous POS sales)
- Adjust loyalty manually → verify `loyalty_points` updates (trigger)
- View commission ledger entries → mark as paid → verify status change
- Add expense → verify appears in list

---

## Phase 6: Reports & Polish

**Goal:** Dashboard with key metrics. Final UI polish.

**DB Views Used:** `daily_sales_summary`, `daily_net_profit_summary`, `staff_commission_summary`, `low_stock_alerts`, `customer_loyalty_summary`
**DB Function:** `top_selling_products(business_id, start, end, limit)`

### Files

#### `src/pages/Dashboard.tsx`
- **Cards:** Today's revenue, order count, avg ticket value (from `daily_sales_summary`)
- **Cards:** Net profit (from `daily_net_profit_summary`)
- **Low stock alerts** count with link to inventory
- **Top products** list (from `top_selling_products()` RPC)
- **Commission pending** total (from `staff_commission_summary`)
- Date range picker for historical data

### Verification
- Dashboard loads with real data from views
- Date range filter works
- Low stock count matches `StockPage` alerts

---

## Shared Components (Built in P1, Used Everywhere)

### `DataTable.tsx`
```ts
Props: {
  columns: { key: string, label: string, render?: (val, row) => ReactNode }[]
  data: any[]
  onRowClick?: (row) => void
  loading?: boolean
}
```

### `Modal.tsx`
```ts
Props: { open: boolean, onClose: () => void, title: string, children: ReactNode }
```

### `StatusBadge.tsx`
```ts
Props: { status: string }
// Maps status strings to Tailwind color classes
```

### `QueryBoundary.tsx`
```ts
// Suspense fallback + ErrorBoundary with retry
```

### `FormField.tsx`
```ts
// RHF register + error display + label
```

---

## Technical Constraints Checklist

- [x] Stack: React, TypeScript, TailwindCSS, @supabase/supabase-js
- [x] Multi-tenancy: `useInsert` auto-injects `business_id`; queries use `businessId` from session store
- [x] No frontend triggers: inventory math, loyalty points, commission calc, order numbers — all DB triggers
- [x] Snapshot prices: `sales_order_items.unit_price` and `appointment_services.price` captured at creation
- [x] RLS: Client never manually filters by `business_id` — RLS does it. But inserts need `business_id` column
- [x] Append-only tables: `inventory_transactions`, `loyalty_transactions` — insert only, never update/delete
- [x] `staff_commission_ledger` — only `status` + `paid_at` updatable
- [x] Role-based UI: `<RoleGate>` hides (not disables) owner/manager-only actions

---

## Resolved Questions

1. **Supabase credentials:** Placeholder `.env` values
2. **Login flow:** Email/password only for pre-created users. No sign-up.
3. **Business type filtering:** YES — sidebar hides modules based on `businesses.type`
4. **Tailwind version:** v4 (CSS-only config, no `tailwind.config.js`)

---

## Priority Execution Order

```
P0 → P1 → P3 → P2 → P4 → P5 → P6
         ↑ POS first (revenue feature)
```

> [!NOTE]
> POS (P3) is promoted above Catalog (P2) in execution because it's the core revenue loop.
> However, P3 depends on having products to sell, so P2's `catalog.service.ts` and a minimal
> `ProductsPage` will be created as part of P3 setup.
