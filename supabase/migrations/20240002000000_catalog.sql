-- ============================================================
-- MIGRATION 002 — Product & Service Catalog
-- Tables: categories, products, product_variants,
--         service_packages, service_package_items
-- ============================================================

-- ============================================================
-- CATEGORIES
-- Hierarchical (self-referencing parent_id).
-- type='product' for goods, type='service' for services.
-- ============================================================
create table public.categories (
  id          uuid    primary key default gen_random_uuid(),
  business_id uuid    not null references public.businesses(id) on delete cascade,
  parent_id   uuid    references public.categories(id) on delete set null,
  name        text    not null,
  type        text    not null default 'product'
                      check (type in ('product','service')),
  icon        text,
  sort_order  int     not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

comment on table  public.categories            is 'Hierarchical product/service categories. Use parent_id for subcategories (e.g. Hair → Hair Colour).';
comment on column public.categories.parent_id  is 'Self-referencing FK. NULL = top-level category.';

-- ============================================================
-- PRODUCTS
-- Unified table for both physical goods and services.
-- Use type='product' for stockable items (rice, shampoo).
-- Use type='service' for billable work (haircut, consultation).
-- Set track_inventory=false for services.
-- ============================================================
create table public.products (
  id               uuid           primary key default gen_random_uuid(),
  business_id      uuid           not null references public.businesses(id) on delete cascade,
  category_id      uuid           references public.categories(id) on delete set null,
  name             text           not null,
  description      text,
  type             text           not null default 'product'
                                  check (type in ('product','service')),
  sku              text,
  barcode          text,
  unit             text           not null default 'piece',
  selling_price    numeric(10,2)  not null default 0 check (selling_price >= 0),
  cost_price       numeric(10,2)  not null default 0 check (cost_price >= 0),
  tax_rate         numeric(5,2)   not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  hsn_code         text,
  image_url        text,
  track_inventory  boolean        not null default true,
  duration_minutes int            check (duration_minutes > 0),
  is_active        boolean        not null default true,
  created_at       timestamptz    not null default now(),
  updated_at       timestamptz    not null default now(),

  unique (business_id, sku)
);

comment on table  public.products                  is 'Unified catalog for physical goods and services. type flag controls behavior.';
comment on column public.products.type             is 'product = trackable stock item. service = billable work with optional duration.';
comment on column public.products.sku              is 'Stock Keeping Unit — unique per business. Auto-generated or manually set.';
comment on column public.products.barcode          is 'EAN-13, QR, or any scannable code for POS barcode reader.';
comment on column public.products.hsn_code         is 'HSN (goods) or SAC (services) code for Indian GST filing.';
comment on column public.products.track_inventory  is 'False for services — they are never deducted from stock.';
comment on column public.products.duration_minutes is 'Only relevant for services. Used to block time in appointment scheduler.';

-- ============================================================
-- PRODUCT VARIANTS
-- Size / colour / packaging variants of a product.
-- Inherits most attributes from parent; overrides price/sku.
-- ============================================================
create table public.product_variants (
  id            uuid          primary key default gen_random_uuid(),
  product_id    uuid          not null references public.products(id) on delete cascade,
  name          text          not null,
  sku           text,
  barcode       text,
  selling_price numeric(10,2) check (selling_price >= 0),
  cost_price    numeric(10,2) check (cost_price >= 0),
  is_active     boolean       not null default true
);

comment on table  public.product_variants               is 'Packaging/size variants of a product. NULL price fields mean inherit from parent product.';
comment on column public.product_variants.selling_price is 'NULL = inherit parent product selling_price.';

-- ============================================================
-- SERVICE PACKAGES
-- Bundled services sold at a combined price with an expiry.
-- E.g. "Monthly Facial Package" = 4 facials for ₹2000.
-- ============================================================
create table public.service_packages (
  id            uuid          primary key default gen_random_uuid(),
  business_id   uuid          not null references public.businesses(id) on delete cascade,
  name          text          not null,
  description   text,
  price         numeric(10,2) not null default 0 check (price >= 0),
  validity_days int           not null default 30 check (validity_days > 0),
  is_active     boolean       not null default true,
  created_at    timestamptz   not null default now()
);

comment on table  public.service_packages               is 'Bundled service offerings sold as a unit. Items defined in service_package_items.';
comment on column public.service_packages.validity_days is 'Days from date of purchase before the package expires.';

-- ============================================================
-- SERVICE PACKAGE ITEMS
-- Line items within a package — which service and how many.
-- ============================================================
create table public.service_package_items (
  id         uuid primary key default gen_random_uuid(),
  package_id uuid not null references public.service_packages(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity   int  not null default 1 check (quantity > 0)
);

comment on table  public.service_package_items           is 'Services included in a service_package. product_id must reference a type=service product.';
comment on column public.service_package_items.quantity  is 'Number of sessions / uses of this service in the package.';