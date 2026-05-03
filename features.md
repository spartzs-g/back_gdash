# Features

## Businesses
**Purpose:** Set up and configure a business profile (salon, kirana, clinic, etc.)

**Capabilities:**
- Register a business with name, type, contact, and address
- Configure settings (tax rate, loyalty rate, receipt footer, opening hours)
- Manage accepted payment methods (Cash, UPI, Card, Credit)
- Manage user accounts and assign roles

**Data:**
- Business profile
- Business settings
- User profiles & roles

**Notes:**
- Business type (`kirana | salon | barber | clinic | other`) controls which modules appear in the UI
- Roles: `owner | manager | staff | cashier` — each with different access levels
- Settings are auto-populated on business creation (7 default keys)

---

## Customers
**Purpose:** Maintain a customer directory with loyalty and visit history.

**Capabilities:**
- Add and manage customer profiles (name, phone, DOB, anniversary, tags, notes)
- Track loyalty points earned from purchases and redeem them at checkout
- View lifetime spend, visit count, and last visit date
- Manually adjust loyalty points and log the reason
- Link referrals between customers

**Data:**
- Customer profile
- Loyalty point transactions (earn / redeem / adjust / expire)

**Notes:**
- Loyalty points and total spent auto-update when an order is completed
- Refunding an order rolls back the customer's total spent
- Anonymous (walk-in) sales are allowed — customer is optional on an order

---

## Inventory
**Purpose:** Track stock levels and manage supplier purchases.

**Capabilities:**
- View current stock per product and variant
- Set low-stock alert thresholds and see flagged items
- Create and manage purchase orders from suppliers
- Receive goods (full or partial) to increase stock automatically
- Log manual stock adjustments, returns, and wastage

**Data:**
- Products & variants
- Stock levels
- Suppliers
- Purchase orders & line items

**Notes:**
- Stock updates automatically when a purchase order is marked "received"
- Stock is deducted automatically when a sale is completed
- Services never deduct inventory (only physical products do)

---

## Appointments & Staff
**Purpose:** Book customer appointments and manage staff schedules.

**Capabilities:**
- Book appointments linking a customer to one or more services
- Assign staff to appointments or specific services within a booking
- Set staff weekly availability and log leave/off days
- Automatically convert a completed appointment into an invoice
- Track appointment status (scheduled → confirmed → in-progress → completed / cancelled / no-show)

**Data:**
- Appointments
- Appointment services
- Staff profiles & specializations
- Staff availability & leaves

**Notes:**
- A single appointment can include multiple services with different assigned staff
- Prices are locked at booking time — catalog price changes don't affect existing bookings
- Staff can exist without an app login (for commission and scheduling purposes)

---

## Sales & Payments
**Purpose:** Process sales at the counter (POS) and collect payments.

**Capabilities:**
- Create invoices from POS or from a completed appointment
- Apply item-level discounts and order-level coupon codes
- Accept split payments across multiple methods (e.g. part Cash, part UPI)
- Refund an order and automatically reverse customer stats
- Log business expenses with category, date, and receipt photo

**Data:**
- Sales orders & line items
- Discounts & coupons
- Payments
- Expenses & expense categories

**Notes:**
- Split payment: multiple payment records can be linked to one order; their sum must equal the order total (validated in tests)
- Coupons support percentage, fixed amount, and buy-X-get-Y types with usage limits and validity dates
- Staff member per line item is recorded for commission calculation

---

## Reports
**Purpose:** Give owners a financial and operational overview of the business.

**Capabilities:**
- View daily sales summary (orders, revenue, discounts, taxes, avg order value)
- View daily net profit (revenue minus taxes minus expenses)
- Identify top-selling products by revenue for any date range
- See low-stock alerts for items at or below threshold
- View staff commission summary by month (pending vs. paid)
- View customer loyalty overview (outstanding points, average per customer)

**Data:**
- Daily sales summary
- Net profit summary
- Top products ranking
- Low stock alerts
- Staff commission summary
- Customer loyalty summary
