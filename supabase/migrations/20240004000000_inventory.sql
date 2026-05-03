-- ============================================================
-- MIGRATION 004 — Inventory Management
-- Tables: inventory, inventory_transactions,
--         suppliers, purchase_orders, purchase_order_items
-- ============================================================

-- ============================================================
-- INVENTORY
-- Current stock snapshot per product (+ optional variant).
-- Always derived from inventory_transactions — kept in sync
-- by trigger. Never manually edit quantity_in_stock directly.
-- ============================================================
create table public.inventory (
  id                  uuid          primary key default gen_random_uuid(),
  business_id         uuid          not null references public.businesses(id) on delete cascade,
  product_id          uuid          not null references public.products(id) on delete cascade,
  variant_id          uuid          references public.product_variants(id) on delete cascade,
  quantity_in_stock   numeric(12,3) not null default 0,
  low_stock_threshold numeric(12,3) not null default 0 check (low_stock_threshold >= 0),
  unit                text          not null default 'piece',
  last_updated_at     timestamptz   not null default now(),

  unique nulls not distinct (business_id, product_id, variant_id)
);

comment on table  public.inventory                       is 'Live stock snapshot. Updated automatically by trigger on inventory_transactions insert.';
comment on column public.inventory.variant_id            is 'NULL = base product stock. Non-null = variant-level stock.';
comment on column public.inventory.low_stock_threshold   is 'Alert threshold — used by the low_stock_alerts view.';
comment on column public.inventory.quantity_in_stock     is 'Keep this read-only in application code. Trigger maintains it.';

-- ============================================================
-- INVENTORY TRANSACTIONS
-- Immutable audit log of every stock movement.
-- Append-only. Never update or delete rows.
-- ============================================================
create table public.inventory_transactions (
  id           uuid          primary key default gen_random_uuid(),
  business_id  uuid          not null references public.businesses(id) on delete cascade,
  product_id   uuid          not null references public.products(id) on delete restrict,
  variant_id   uuid          references public.product_variants(id) on delete restrict,
  type         text          not null
               check (type in ('purchase','sale','adjustment','return','waste')),
  quantity     numeric(12,3) not null,
  reference_id uuid,
  notes        text,
  created_by   uuid          references public.profiles(id) on delete set null,
  created_at   timestamptz   not null default now()
);

comment on table  public.inventory_transactions              is 'Append-only stock movement ledger. Positive = stock in, negative = stock out.';
comment on column public.inventory_transactions.type         is 'purchase | sale | adjustment | return | waste';
comment on column public.inventory_transactions.quantity     is 'Positive for stock-in (purchase, return), negative for stock-out (sale, waste).';
comment on column public.inventory_transactions.reference_id is 'FK to sales_orders.id or purchase_orders.id depending on type.';

-- ============================================================
-- SUPPLIERS
-- Vendor/distributor master. Linked to purchase orders.
-- ============================================================
create table public.suppliers (
  id          uuid        primary key default gen_random_uuid(),
  business_id uuid        not null references public.businesses(id) on delete cascade,
  name        text        not null,
  phone       text,
  email       text,
  address     text,
  gstin       text,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now()
);

comment on table public.suppliers        is 'Supplier / vendor master. Referenced by purchase_orders.';
comment on column public.suppliers.gstin is 'Supplier GSTIN — required for input tax credit claims.';

-- ============================================================
-- PURCHASE ORDERS
-- Goods receipt from supplier. Changing status to 'received'
-- triggers inventory_transactions (type='purchase').
-- ============================================================
create table public.purchase_orders (
  id           uuid          primary key default gen_random_uuid(),
  business_id  uuid          not null references public.businesses(id) on delete cascade,
  supplier_id  uuid          references public.suppliers(id) on delete set null,
  order_number text          not null,
  status       text          not null default 'draft'
               check (status in ('draft','ordered','partially_received','received','cancelled')),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  notes        text,
  ordered_at   timestamptz,
  received_at  timestamptz,
  created_by   uuid          references public.profiles(id) on delete set null,
  created_at   timestamptz   not null default now(),

  unique (business_id, order_number)
);

comment on table  public.purchase_orders               is 'Goods procurement order from a supplier. Triggers stock-in on status=received.';
comment on column public.purchase_orders.order_number  is 'Human-readable e.g. PO-0042. Auto-generated by application or sequence.';
comment on column public.purchase_orders.ordered_at    is 'Timestamp the order was placed with the supplier (not created in the system).';
comment on column public.purchase_orders.received_at   is 'Timestamp physical goods arrived. Trigger fires inventory_transactions here.';

-- ============================================================
-- PURCHASE ORDER ITEMS
-- Line items per purchase order. Supports partial receiving.
-- ============================================================
create table public.purchase_order_items (
  id                 uuid          primary key default gen_random_uuid(),
  purchase_order_id  uuid          not null references public.purchase_orders(id) on delete cascade,
  product_id         uuid          not null references public.products(id) on delete restrict,
  variant_id         uuid          references public.product_variants(id) on delete restrict,
  quantity_ordered   numeric(12,3) not null check (quantity_ordered > 0),
  quantity_received  numeric(12,3) not null default 0 check (quantity_received >= 0),
  unit_cost          numeric(10,2) not null default 0 check (unit_cost >= 0),
  total_cost         numeric(14,2) generated always as (unit_cost * quantity_received) stored
);

comment on table  public.purchase_order_items                  is 'Line items in a purchase order. quantity_received ≤ quantity_ordered supports partial deliveries.';
comment on column public.purchase_order_items.quantity_received is 'Updated when goods physically arrive. Triggers inventory_transactions.';
comment on column public.purchase_order_items.total_cost        is 'Generated column: unit_cost × quantity_received.';