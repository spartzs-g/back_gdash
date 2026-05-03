-- ============================================================
-- MIGRATION 010 — Triggers & Functions
-- ============================================================

-- ============================================================
-- 1. GENERIC updated_at TRIGGER
-- Reusable function attached to every table that has
-- an updated_at column.
-- ============================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Attach to all relevant tables
create trigger trg_businesses_updated_at
  before update on public.businesses
  for each row execute function public.set_updated_at();

create trigger trg_products_updated_at
  before update on public.products
  for each row execute function public.set_updated_at();

create trigger trg_customers_updated_at
  before update on public.customers
  for each row execute function public.set_updated_at();

create trigger trg_appointments_updated_at
  before update on public.appointments
  for each row execute function public.set_updated_at();

create trigger trg_sales_orders_updated_at
  before update on public.sales_orders
  for each row execute function public.set_updated_at();

-- ============================================================
-- 2. INVENTORY SYNC TRIGGER
-- On insert into inventory_transactions → upsert the
-- inventory snapshot row for (business, product, variant).
-- ============================================================
create or replace function public.sync_inventory()
returns trigger
language plpgsql
as $$
begin
  insert into public.inventory (
    business_id,
    product_id,
    variant_id,
    quantity_in_stock,
    unit,
    last_updated_at
  )
  values (
    new.business_id,
    new.product_id,
    new.variant_id,
    new.quantity,
    (select unit from public.products where id = new.product_id),
    now()
  )
  on conflict (business_id, product_id, variant_id)
  do update set
    quantity_in_stock = public.inventory.quantity_in_stock + excluded.quantity_in_stock,
    last_updated_at   = now();

  return new;
end;
$$;

create trigger trg_inventory_transactions_sync
  after insert on public.inventory_transactions
  for each row execute function public.sync_inventory();

-- ============================================================
-- 3. CUSTOMER STATS TRIGGER
-- When a sales_order status changes to 'completed':
--   • increment customers.visit_count
--   • add total_amount to customers.total_spent
--   • set customers.last_visit_at = now()
-- When a completed order is 'refunded':
--   • decrement visit_count and total_spent
-- ============================================================
create or replace function public.update_customer_stats()
returns trigger
language plpgsql
as $$
begin
  -- Newly completed
  if new.status = 'completed' and old.status <> 'completed'
     and new.customer_id is not null then
    update public.customers
    set
      visit_count   = visit_count + 1,
      total_spent   = total_spent + new.total_amount,
      last_visit_at = now(),
      updated_at    = now()
    where id = new.customer_id;
  end if;

  -- Completion rolled back to refunded
  if new.status = 'refunded' and old.status = 'completed'
     and new.customer_id is not null then
    update public.customers
    set
      visit_count = greatest(visit_count - 1, 0),
      total_spent = greatest(total_spent - new.total_amount, 0),
      updated_at  = now()
    where id = new.customer_id;
  end if;

  return new;
end;
$$;

create trigger trg_sales_orders_customer_stats
  after update of status on public.sales_orders
  for each row execute function public.update_customer_stats();

-- ============================================================
-- 4. AUTO DEDUCT INVENTORY ON SALE TRIGGER
-- When a sales_order_items row is inserted and the related
-- product has track_inventory = true, write a negative
-- inventory_transaction automatically.
-- ============================================================
create or replace function public.deduct_inventory_on_sale()
returns trigger
language plpgsql
as $$
declare
  v_track_inventory boolean;
  v_business_id     uuid;
begin
  select track_inventory into v_track_inventory
  from public.products where id = new.product_id;

  if v_track_inventory then
    select business_id into v_business_id
    from public.sales_orders where id = new.order_id;

    insert into public.inventory_transactions (
      business_id,
      product_id,
      variant_id,
      type,
      quantity,
      reference_id
    ) values (
      v_business_id,
      new.product_id,
      new.variant_id,
      'sale',
      -(new.quantity),   -- negative = stock out
      new.order_id
    );
  end if;

  return new;
end;
$$;

create trigger trg_sales_order_items_deduct_inventory
  after insert on public.sales_order_items
  for each row execute function public.deduct_inventory_on_sale();

-- ============================================================
-- 5. COMMISSION LEDGER TRIGGER
-- On insert into sales_order_items: look up the best-matching
-- staff_commissions rule (product-specific > catch-all),
-- compute amount, and insert into staff_commission_ledger.
-- ============================================================
create or replace function public.record_staff_commission()
returns trigger
language plpgsql
as $$
declare
  v_rule    record;
  v_amount  numeric(10,2);
  v_biz_id  uuid;
begin
  if new.staff_id is null then
    return new;
  end if;

  -- Prefer product-specific rule, fall back to catch-all (product_id is null)
  select * into v_rule
  from public.staff_commissions
  where staff_id = new.staff_id
    and is_active = true
    and (product_id = new.product_id or product_id is null)
  order by (product_id is not null) desc   -- specific rule first
  limit 1;

  if not found then
    return new;
  end if;

  if v_rule.commission_type = 'percentage' then
    v_amount := round((new.total_price * v_rule.commission_value / 100.0)::numeric, 2);
  else  -- fixed_per_unit
    v_amount := round((new.quantity * v_rule.commission_value)::numeric, 2);
  end if;

  select business_id into v_biz_id
  from public.sales_orders where id = new.order_id;

  insert into public.staff_commission_ledger (
    business_id,
    staff_id,
    order_id,
    order_item_id,
    amount
  ) values (
    v_biz_id,
    new.staff_id,
    new.order_id,
    new.id,
    v_amount
  );

  return new;
end;
$$;

create trigger trg_sales_order_items_commission
  after insert on public.sales_order_items
  for each row execute function public.record_staff_commission();

-- ============================================================
-- 6. LOYALTY POINTS SYNC TRIGGER
-- When a loyalty_transaction row is inserted, update the
-- denormalized customers.loyalty_points balance.
-- ============================================================
create or replace function public.sync_loyalty_points()
returns trigger
language plpgsql
as $$
begin
  update public.customers
  set
    loyalty_points = greatest(loyalty_points + new.points, 0),
    updated_at     = now()
  where id = new.customer_id;

  return new;
end;
$$;

create trigger trg_loyalty_transactions_sync
  after insert on public.loyalty_transactions
  for each row execute function public.sync_loyalty_points();

-- ============================================================
-- 7. ORDER NUMBER GENERATOR
-- Generates INV-YYYYMMDD-XXXX format on sales_orders insert.
-- Sequence is per-business-per-day.
-- ============================================================
create or replace function public.generate_order_number()
returns trigger
language plpgsql
as $$
declare
  v_today  text;
  v_count  int;
  v_num    text;
begin
  if new.order_number is null or new.order_number = '' then
    v_today := to_char(now(), 'YYYYMMDD');
    select count(*) + 1 into v_count
    from public.sales_orders
    where business_id = new.business_id
      and created_at::date = now()::date;

    new.order_number := 'INV-' || v_today || '-' || lpad(v_count::text, 4, '0');
  end if;
  return new;
end;
$$;

create trigger trg_sales_orders_order_number
  before insert on public.sales_orders
  for each row execute function public.generate_order_number();

-- Same pattern for purchase orders
create or replace function public.generate_po_number()
returns trigger
language plpgsql
as $$
declare
  v_count int;
begin
  if new.order_number is null or new.order_number = '' then
    select count(*) + 1 into v_count
    from public.purchase_orders
    where business_id = new.business_id;

    new.order_number := 'PO-' || lpad(v_count::text, 4, '0');
  end if;
  return new;
end;
$$;

create trigger trg_purchase_orders_po_number
  before insert on public.purchase_orders
  for each row execute function public.generate_po_number();

-- ============================================================
-- 8. HELPFUL VIEWS
-- ============================================================

-- Low stock alerts
create or replace view public.low_stock_alerts as
select
  i.business_id,
  p.id         as product_id,
  p.name       as product_name,
  pv.name      as variant_name,
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
  'Products at or below their low_stock_threshold. Use for reorder alerts.';

-- Daily sales summary
create or replace view public.daily_sales_summary as
select
  business_id,
  created_at::date         as sale_date,
  count(*)                 as order_count,
  sum(total_amount)        as revenue,
  sum(discount_amount)     as total_discounts,
  sum(tax_amount)          as total_tax,
  avg(total_amount)        as avg_ticket,
  count(customer_id)       as orders_with_customer
from public.sales_orders
where status = 'completed'
group by business_id, created_at::date;

comment on view public.daily_sales_summary is
  'Per-day revenue aggregation for the dashboard. Filter by business_id.';

-- Staff commission summary (current month)
create or replace view public.staff_commission_summary as
select
  scl.business_id,
  scl.staff_id,
  s.name                          as staff_name,
  date_trunc('month', scl.created_at) as month,
  count(*)                        as transaction_count,
  sum(scl.amount)                 as total_earned,
  sum(case when scl.status = 'paid' then scl.amount else 0 end) as total_paid,
  sum(case when scl.status = 'pending' then scl.amount else 0 end) as total_pending
from public.staff_commission_ledger scl
join public.staff s on s.id = scl.staff_id
group by scl.business_id, scl.staff_id, s.name,
         date_trunc('month', scl.created_at);

comment on view public.staff_commission_summary is
  'Monthly commission totals per staff member with paid vs pending breakdown.';