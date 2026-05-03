// ── Row types derived from Supabase migrations ──
// Single source of truth for all frontend types.
// Do NOT re-read migrations — this file captures everything.

export interface Business {
  id: string
  name: string
  type: 'kirana' | 'salon' | 'barber' | 'clinic' | 'other'
  phone: string | null
  email: string | null
  address: string | null
  city: string | null
  state: string | null
  pincode: string | null
  gstin: string | null
  logo_url: string | null
  currency: string
  timezone: string
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface Profile {
  id: string
  business_id: string
  full_name: string | null
  phone: string | null
  role: 'owner' | 'manager' | 'staff' | 'cashier'
  avatar_url: string | null
  is_active: boolean
  created_at: string
}

export interface BusinessSetting {
  id: string
  business_id: string
  key: string
  value: unknown
  created_at: string
}

export interface Category {
  id: string
  business_id: string
  parent_id: string | null
  name: string
  type: 'product' | 'service'
  icon: string | null
  sort_order: number
  is_active: boolean
  created_at: string
}

export interface Product {
  id: string
  business_id: string
  category_id: string | null
  name: string
  description: string | null
  type: 'product' | 'service'
  sku: string | null
  barcode: string | null
  unit: string
  selling_price: number
  cost_price: number
  tax_rate: number
  hsn_code: string | null
  image_url: string | null
  track_inventory: boolean
  duration_minutes: number | null
  is_active: boolean
  created_at: string
  updated_at: string
  // Joined fields
  category?: Category
}

export interface ProductVariant {
  id: string
  product_id: string
  name: string
  sku: string | null
  barcode: string | null
  selling_price: number | null
  cost_price: number | null
  is_active: boolean
}

export interface Customer {
  id: string
  business_id: string
  name: string
  phone: string | null
  email: string | null
  gender: 'male' | 'female' | 'other' | null
  date_of_birth: string | null
  anniversary_date: string | null
  address: string | null
  notes: string | null
  loyalty_points: number
  total_spent: number
  visit_count: number
  last_visit_at: string | null
  referred_by: string | null
  tags: string[]
  created_at: string
  updated_at: string
}

export interface LoyaltyTransaction {
  id: string
  business_id: string
  customer_id: string
  type: 'earn' | 'redeem' | 'adjust' | 'expire'
  points: number
  reference_id: string | null
  notes: string | null
  created_at: string
}

export interface Inventory {
  id: string
  business_id: string
  product_id: string
  variant_id: string | null
  quantity_in_stock: number
  low_stock_threshold: number
  unit: string
  last_updated_at: string
  // Joined
  product?: Product
  variant?: ProductVariant
}

export interface InventoryTransaction {
  id: string
  business_id: string
  product_id: string
  variant_id: string | null
  type: 'purchase' | 'sale' | 'adjustment' | 'return' | 'waste'
  quantity: number
  reference_id: string | null
  notes: string | null
  created_by: string | null
  created_at: string
}

export interface Supplier {
  id: string
  business_id: string
  name: string
  phone: string | null
  email: string | null
  address: string | null
  gstin: string | null
  is_active: boolean
  created_at: string
}

export interface PurchaseOrder {
  id: string
  business_id: string
  supplier_id: string | null
  order_number: string
  status: 'draft' | 'ordered' | 'partially_received' | 'received' | 'cancelled'
  total_amount: number
  notes: string | null
  ordered_at: string | null
  received_at: string | null
  created_by: string | null
  created_at: string
  // Joined
  supplier?: Supplier
  items?: PurchaseOrderItem[]
}

export interface PurchaseOrderItem {
  id: string
  purchase_order_id: string
  product_id: string
  variant_id: string | null
  quantity_ordered: number
  quantity_received: number
  unit_cost: number
  total_cost: number
  // Joined
  product?: Product
}

export interface Staff {
  id: string
  business_id: string
  profile_id: string | null
  name: string
  phone: string | null
  email: string | null
  role: string
  specializations: string[]
  color: string | null
  is_active: boolean
  created_at: string
}

export interface StaffAvailability {
  id: string
  staff_id: string
  day_of_week: number
  start_time: string
  end_time: string
  is_available: boolean
}

export interface StaffLeave {
  id: string
  staff_id: string
  leave_date: string
  reason: string | null
  is_full_day: boolean
  start_time: string | null
  end_time: string | null
  created_at: string
}

export interface Appointment {
  id: string
  business_id: string
  customer_id: string
  staff_id: string | null
  status: 'scheduled' | 'confirmed' | 'in_progress' | 'completed' | 'cancelled' | 'no_show'
  scheduled_at: string
  duration_minutes: number
  notes: string | null
  cancellation_reason: string | null
  sales_order_id: string | null
  created_at: string
  updated_at: string
  // Joined
  customer?: Customer
  staff?: Staff
  services?: AppointmentService[]
}

export interface AppointmentService {
  id: string
  appointment_id: string
  product_id: string
  staff_id: string | null
  price: number
  duration_minutes: number
  // Joined
  product?: Product
  staff?: Staff
}

export interface SalesOrder {
  id: string
  business_id: string
  customer_id: string | null
  appointment_id: string | null
  discount_id: string | null
  order_number: string
  status: 'draft' | 'confirmed' | 'completed' | 'cancelled' | 'refunded'
  subtotal: number
  discount_amount: number
  tax_amount: number
  round_off: number
  total_amount: number
  notes: string | null
  created_by: string | null
  created_at: string
  updated_at: string
  // Joined
  customer?: Customer
  items?: SalesOrderItem[]
  payments?: Payment[]
}

export interface SalesOrderItem {
  id: string
  order_id: string
  product_id: string
  variant_id: string | null
  staff_id: string | null
  quantity: number
  unit_price: number
  discount_percent: number
  tax_rate: number
  tax_amount: number
  total_price: number
  // Joined
  product?: Product
}

export interface Discount {
  id: string
  business_id: string
  name: string
  type: 'percentage' | 'fixed_amount' | 'buy_x_get_y'
  value: number
  code: string | null
  min_order_amount: number
  max_discount_amount: number | null
  is_active: boolean
  valid_from: string | null
  valid_until: string | null
  usage_limit: number | null
  usage_count: number
  buy_quantity: number | null
  get_quantity: number | null
  created_at: string
}

export interface PaymentMethod {
  id: string
  business_id: string
  name: string
  type: 'cash' | 'digital' | 'credit'
  is_active: boolean
}

export interface Payment {
  id: string
  business_id: string
  order_id: string
  payment_method_id: string
  amount: number
  status: 'pending' | 'completed' | 'failed' | 'refunded'
  reference_number: string | null
  notes: string | null
  paid_at: string | null
  created_at: string
  // Joined
  payment_method?: PaymentMethod
}

export interface ExpenseCategory {
  id: string
  business_id: string
  name: string
  icon: string | null
  sort_order: number
  is_active: boolean
}

export interface Expense {
  id: string
  business_id: string
  category_id: string | null
  amount: number
  description: string
  date: string
  payment_method_id: string | null
  receipt_url: string | null
  created_by: string | null
  created_at: string
  // Joined
  category?: ExpenseCategory
}

export interface StaffCommission {
  id: string
  business_id: string
  staff_id: string
  product_id: string | null
  commission_type: 'percentage' | 'fixed_per_unit'
  commission_value: number
  is_active: boolean
}

export interface StaffCommissionLedger {
  id: string
  business_id: string
  staff_id: string
  order_id: string
  order_item_id: string
  amount: number
  status: 'pending' | 'paid'
  paid_at: string | null
  created_at: string
  // Joined
  staff?: Staff
}

// ── Report View Types ──

export interface DailySalesSummary {
  business_id: string
  sale_date: string
  total_orders: number
  total_subtotal: number
  total_discount: number
  total_tax: number
  total_revenue: number
  avg_order_value: number
}

export interface DailyNetProfitSummary {
  business_id: string
  report_date: string
  gross_revenue: number
  total_tax: number
  total_expenses: number
  net_profit: number
}

export interface LowStockAlert {
  business_id: string
  product_id: string
  product_name: string
  variant_id: string | null
  variant_name: string | null
  quantity_in_stock: number
  low_stock_threshold: number
  unit: string
}

export interface StaffCommissionSummary {
  business_id: string
  staff_id: string
  staff_name: string
  commission_month: string
  pending_commission: number
  paid_commission: number
  total_commission: number
}

export interface CustomerLoyaltySummary {
  business_id: string
  total_customers: number
  total_outstanding_points: number
  avg_points_per_customer: number
}

// ── Cart Types (frontend only) ──

export interface CartItem {
  product: Product
  variant: ProductVariant | null
  quantity: number
  unitPrice: number
  discountPercent: number
  taxRate: number
  staffId: string | null
}

// ── Business type → module visibility ──
export const BUSINESS_MODULES: Record<Business['type'], string[]> = {
  salon:   ['pos', 'catalog', 'inventory', 'appointments', 'customers', 'admin', 'reports'],
  barber:  ['pos', 'catalog', 'inventory', 'appointments', 'customers', 'admin', 'reports'],
  clinic:  ['pos', 'catalog', 'inventory', 'appointments', 'customers', 'admin', 'reports'],
  kirana:  ['pos', 'catalog', 'inventory', 'customers', 'admin', 'reports'],
  other:   ['pos', 'catalog', 'inventory', 'appointments', 'customers', 'admin', 'reports'],
}
