-- ============================================================
-- MIGRATION 005 — Appointments & Staff
-- Tables: staff, staff_availability, staff_leaves,
--         appointments, appointment_services
-- ============================================================

-- ============================================================
-- STAFF
-- Staff master — separate from profiles so non-system employees
-- (no app login) can still be assigned to appointments and
-- track commissions.
-- ============================================================
create table public.staff (
  id              uuid        primary key default gen_random_uuid(),
  business_id     uuid        not null references public.businesses(id) on delete cascade,
  profile_id      uuid        references public.profiles(id) on delete set null,
  name            text        not null,
  phone           text,
  email           text,
  role            text        not null default 'staff',
  specializations text[]      not null default '{}',
  color           text,
  is_active       boolean     not null default true,
  created_at      timestamptz not null default now()
);

comment on table  public.staff                   is 'Staff/employee master. Can exist without a profile (no system login needed).';
comment on column public.staff.profile_id        is 'NULL if staff member has no app login. Links to profiles when they do.';
comment on column public.staff.role              is 'Free-text role: stylist | barber | doctor | therapist | cashier | helper etc.';
comment on column public.staff.specializations   is 'Array of product IDs or service tags they are qualified to perform.';
comment on column public.staff.color             is 'Hex color for calendar/scheduler display e.g. #4A90D9.';

-- ============================================================
-- STAFF AVAILABILITY
-- Weekly recurring schedule per staff member.
-- One row per day-of-week. Override with staff_leaves
-- for specific date exceptions.
-- ============================================================
create table public.staff_availability (
  id           uuid    primary key default gen_random_uuid(),
  staff_id     uuid    not null references public.staff(id) on delete cascade,
  day_of_week  int     not null check (day_of_week between 0 and 6),
  start_time   time    not null,
  end_time     time    not null,
  is_available boolean not null default true,

  unique (staff_id, day_of_week),
  check (end_time > start_time)
);

comment on table  public.staff_availability              is 'Weekly recurring schedule. day_of_week: 0=Sun, 1=Mon, … 6=Sat.';
comment on column public.staff_availability.is_available is 'False = day off for this staff member.';

-- ============================================================
-- STAFF LEAVES
-- Specific date overrides — blocks time regardless of
-- the weekly availability schedule.
-- ============================================================
create table public.staff_leaves (
  id          uuid        primary key default gen_random_uuid(),
  staff_id    uuid        not null references public.staff(id) on delete cascade,
  leave_date  date        not null,
  reason      text,
  is_full_day boolean     not null default true,
  start_time  time,
  end_time    time,
  created_at  timestamptz not null default now(),

  unique (staff_id, leave_date)
);

comment on table  public.staff_leaves              is 'Date-specific leave/block override. Takes precedence over staff_availability.';
comment on column public.staff_leaves.is_full_day  is 'True = blocked all day. False = partial block using start_time/end_time.';

-- ============================================================
-- APPOINTMENTS
-- Booking record linking customer + staff + one or more
-- services. On completion → creates or links a sales_order.
-- ============================================================
create table public.appointments (
  id                  uuid        primary key default gen_random_uuid(),
  business_id         uuid        not null references public.businesses(id) on delete cascade,
  customer_id         uuid        not null references public.customers(id) on delete restrict,
  staff_id            uuid        references public.staff(id) on delete set null,
  status              text        not null default 'scheduled'
                      check (status in (
                        'scheduled','confirmed','in_progress',
                        'completed','cancelled','no_show'
                      )),
  scheduled_at        timestamptz not null,
  duration_minutes    int         not null check (duration_minutes > 0),
  notes               text,
  cancellation_reason text,
  -- sales_order_id added via ALTER TABLE in migration 006 (avoids forward FK reference)
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table  public.appointments                    is 'Appointment booking. One row = one customer visit, possibly with multiple services.';
comment on column public.appointments.staff_id           is 'NULL = any available staff. Resolved at confirmation time.';
comment on column public.appointments.duration_minutes   is 'Sum of all appointment_services.duration_minutes for the calendar block.';
-- sales_order_id column and its comment are added in migration 006 via ALTER TABLE.

-- ============================================================
-- APPOINTMENT SERVICES
-- Services booked within an appointment.
-- One appointment can include multiple services
-- with different assigned staff.
-- ============================================================
create table public.appointment_services (
  id               uuid          primary key default gen_random_uuid(),
  appointment_id   uuid          not null references public.appointments(id) on delete cascade,
  product_id       uuid          not null references public.products(id) on delete restrict,
  staff_id         uuid          references public.staff(id) on delete set null,
  price            numeric(10,2) not null check (price >= 0),
  duration_minutes int           not null check (duration_minutes > 0)
);

comment on table  public.appointment_services          is 'Individual services booked in an appointment. staff_id can differ per service.';
comment on column public.appointment_services.price    is 'Price captured at booking time — insulated from future catalog price changes.';