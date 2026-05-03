-- ============================================================
-- MIGRATION 014 — Schema Fixes & Missing Triggers
-- Addresses: immutability, PO receiving, order number races,
--   missing constraints, auto-earn loyalty, discount tracking,
--   view corrections, redundant index cleanup.
-- ============================================================

-- ============================================================
-- 1. IMMUTABILITY TRIGGERS
-- Enforce append-only semantics on ledger tables.
-- ============================================================
create or replace function public.deny_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Table % is append-only. UPDATE and DELETE are not permitted.', TG_TABLE_NAME;
end;
$$;

comment on function public.deny_mutation is
  'Generic trigger function that blocks UPDATE/DELETE on append-only ledger tables.';

create trigger trg_inventory_transactions_immutable
  before update or delete on public.inventory_transactions
  for each row execute function public.deny_mutation();

create trigger trg_loyalty_transactions_immutable
  before update or delete on public.loyalty_transactions
  for each row execute function public.deny_mutation();

-- staff_commission_ledger: block DELETE, restrict UPDATE to status+paid_at only
create trigger trg_commission_ledger_no_delete
  before delete on public.staff_commission_ledger
  for each row execute function public.deny_mutation();

create or replace function public.restrict_commission_ledger_update()
returns trigger
language plpgsql
as $$
begin
  if new.business_id  <> old.business_id
  or new.staff_id     <> old.staff_id
  or new.order_id     <> old.order_id
  or new.order_item_id<> old.order_item_id
  or new.amount       <> old.amount then
    raise exception 'Only status and paid_at can be updated on staff_commission_ledger.';
  end if;
  return new;
end;
$$;

create trigger trg_commission_ledger_restrict_update
  before update on public.staff_commission_ledger
  for each row execute function public.restrict_commission_ledger_update();

-- ============================================================
-- 2. PO RECEIVED → INVENTORY TRIGGER
-- When quantity_received changes on a PO item, insert the
-- delta into inventory_transactions (type='purchase').
-- ============================================================
create or replace function public.receive_purchase_order_items()
returns trigger
language plpgsql
security definer
as $$
declare
  v_delta      numeric;
  v_business_id uuid;
begin
  v_delta := new.quantity_received - old.quantity_received;

  if v_delta > 0 then
    select business_id into v_business_id
    from public.purchase_orders
    where id = new.purchase_order_id;

    insert into public.inventory_transactions (
      business_id, product_id, variant_id, type, quantity, reference_id
    ) values (
      v_business_id, new.product_id, new.variant_id,
      'purchase', v_delta, new.purchase_order_id
    );
  end if;

  return new;
end;
$$;

comment on function public.receive_purchase_order_items is
  'Trigger: auto-creates inventory_transactions when PO items are received.';

create trigger trg_po_items_receive
  after update of quantity_received on public.purchase_order_items
  for each row
  when (new.quantity_received <> old.quantity_received)
  execute function public.receive_purchase_order_items();

-- ============================================================
-- 3. FIX ORDER/PO NUMBER RACE CONDITIONS
-- Replace count(*)+1 with advisory-lock-protected generation.
-- ============================================================
create or replace function public.generate_order_number()
returns trigger
language plpgsql
as $$
declare
  v_today text;
  v_count int;
begin
  if new.order_number is null or new.order_number = '' then
    v_today := to_char(now(), 'YYYYMMDD');
    -- Advisory lock scoped to business+date prevents concurrent duplicates
    perform pg_advisory_xact_lock(hashtext(new.business_id::text || v_today));

    select count(*) + 1 into v_count
    from public.sales_orders
    where business_id = new.business_id
      and created_at::date = now()::date;

    new.order_number := 'INV-' || v_today || '-' || lpad(v_count::text, 4, '0');
  end if;
  return new;
end;
$$;

create or replace function public.generate_po_number()
returns trigger
language plpgsql
as $$
declare
  v_count int;
begin
  if new.order_number is null or new.order_number = '' then
    perform pg_advisory_xact_lock(hashtext(new.business_id::text || 'po'));

    select count(*) + 1 into v_count
    from public.purchase_orders
    where business_id = new.business_id;

    new.order_number := 'PO-' || lpad(v_count::text, 4, '0');
  end if;
  return new;
end;
$$;

-- ============================================================
-- 4. MISSING CONSTRAINTS
-- ============================================================

-- 4a. Partial delivery: quantity_received must not exceed quantity_ordered
alter table public.purchase_order_items
  add constraint chk_quantity_received_le_ordered
  check (quantity_received <= quantity_ordered);

-- 4b. Staff leaves: partial-day must specify times
alter table public.staff_leaves
  add constraint chk_partial_day_times
  check (
    is_full_day = true
    or (start_time is not null and end_time is not null and end_time > start_time)
  );

-- ============================================================
-- 5. SERVICE PACKAGE ITEMS — TYPE VALIDATION
-- Ensures only type='service' products can be added to packages.
-- ============================================================
create or replace function public.validate_service_package_item()
returns trigger
language plpgsql
as $$
declare
  v_type text;
begin
  select type into v_type
  from public.products
  where id = new.product_id;

  if v_type <> 'service' then
    raise exception 'service_package_items can only reference products with type=service. Got type=%', v_type;
  end if;

  return new;
end;
$$;

create trigger trg_service_package_items_validate
  before insert or update on public.service_package_items
  for each row execute function public.validate_service_package_item();

-- ============================================================
-- 6. AUTO-EARN LOYALTY POINTS ON ORDER COMPLETION
-- Also reverses points on refund.
-- ============================================================
create or replace function public.auto_earn_loyalty_points()
returns trigger
language plpgsql
security definer
as $$
declare
  v_loyalty_rate numeric;
  v_points       int;
begin
  -- Earn on completion
  if new.status = 'completed' and old.status <> 'completed'
     and new.customer_id is not null then
    select (value#>>'{}')::numeric into v_loyalty_rate
    from public.business_settings
    where business_id = new.business_id and key = 'loyalty_rate';

    if v_loyalty_rate is not null and v_loyalty_rate > 0 then
      v_points := floor(new.total_amount * v_loyalty_rate);
      if v_points > 0 then
        insert into public.loyalty_transactions
          (business_id, customer_id, type, points, reference_id, notes)
        values
          (new.business_id, new.customer_id, 'earn', v_points, new.id,
           'Auto-earned from order ' || new.order_number);
      end if;
    end if;
  end if;

  -- Reverse on refund
  if new.status = 'refunded' and old.status = 'completed'
     and new.customer_id is not null then
    select (value#>>'{}')::numeric into v_loyalty_rate
    from public.business_settings
    where business_id = new.business_id and key = 'loyalty_rate';

    if v_loyalty_rate is not null and v_loyalty_rate > 0 then
      v_points := floor(new.total_amount * v_loyalty_rate);
      if v_points > 0 then
        insert into public.loyalty_transactions
          (business_id, customer_id, type, points, reference_id, notes)
        values
          (new.business_id, new.customer_id, 'redeem', -v_points, new.id,
           'Reversed due to order refund');
      end if;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.auto_earn_loyalty_points is
  'Trigger: auto-inserts loyalty_transactions on order completion (earn) and refund (reverse).';

create trigger trg_sales_orders_loyalty
  after update of status on public.sales_orders
  for each row execute function public.auto_earn_loyalty_points();

-- ============================================================
-- 7. DISCOUNT USAGE TRACKING
-- Add discount_id FK to sales_orders, auto-increment usage_count.
-- ============================================================
alter table public.sales_orders
  add column if not exists discount_id uuid
    references public.discounts(id) on delete set null;

comment on column public.sales_orders.discount_id is
  'The coupon/discount applied to this order. NULL if none.';

create or replace function public.track_discount_usage()
returns trigger
language plpgsql
as $$
begin
  -- Increment on new order with discount
  if tg_op = 'INSERT' and new.discount_id is not null then
    update public.discounts
    set usage_count = usage_count + 1
    where id = new.discount_id;
  end if;

  -- Handle UPDATE: discount added, removed, or changed
  if tg_op = 'UPDATE' then
    if old.discount_id is distinct from new.discount_id then
      if old.discount_id is not null then
        update public.discounts
        set usage_count = greatest(usage_count - 1, 0)
        where id = old.discount_id;
      end if;
      if new.discount_id is not null then
        update public.discounts
        set usage_count = usage_count + 1
        where id = new.discount_id;
      end if;
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_sales_orders_discount_usage
  after insert or update of discount_id on public.sales_orders
  for each row execute function public.track_discount_usage();

-- ============================================================
-- 8. BUY_X_GET_Y SCHEMA COLUMNS
-- Add missing columns for the buy_x_get_y discount type.
-- ============================================================
alter table public.discounts
  add column if not exists buy_quantity int check (buy_quantity > 0),
  add column if not exists get_quantity int check (get_quantity > 0);

comment on column public.discounts.buy_quantity is
  'For buy_x_get_y type: how many items the customer must buy.';
comment on column public.discounts.get_quantity is
  'For buy_x_get_y type: how many free/discounted items the customer gets.';

-- ============================================================
-- 9. FIX low_stock_alerts VIEW
-- Restore is_active and threshold>0 filters that were dropped
-- when migration 013 recreated this view.
-- ============================================================
create or replace view public.low_stock_alerts as
select
  i.business_id,
  i.product_id,
  p.name         as product_name,
  i.variant_id,
  pv.name        as variant_name,
  i.quantity_in_stock,
  i.low_stock_threshold,
  i.unit
from public.inventory i
join public.products p on p.id = i.product_id
left join public.product_variants pv on pv.id = i.variant_id
where i.quantity_in_stock <= i.low_stock_threshold
  and i.low_stock_threshold > 0
  and p.is_active = true;

comment on view public.low_stock_alerts is
  'Active products at or below their low_stock_threshold. Use for reorder alerts.';

-- ============================================================
-- 10. DROP REDUNDANT INDEX
-- idx_so_created_at (DESC) can serve both sort directions.
-- ============================================================
drop index if exists public.idx_so_created_at_date;

-- ============================================================
-- 11. ADD INDEX ON NEW discount_id COLUMN
-- ============================================================
create index idx_so_discount_id on public.sales_orders (discount_id)
  where discount_id is not null;
