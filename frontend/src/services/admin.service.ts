import { supabase } from '../lib/supabase'
import type { StaffCommissionLedger, StaffCommissionSummary, ExpenseCategory, Expense, DailySalesSummary, DailyNetProfitSummary, CustomerLoyaltySummary } from '../types/db'

export async function getCommissionSummary(businessId: string) {
  const { data, error } = await supabase.from('staff_commission_summary').select('*').eq('business_id', businessId)
  if (error) throw error
  return data as StaffCommissionSummary[]
}

export async function getCommissionLedger(businessId: string, staffId?: string) {
  let q = supabase.from('staff_commission_ledger').select('*, staff:staff(id, name)').eq('business_id', businessId).order('created_at', { ascending: false })
  if (staffId) q = q.eq('staff_id', staffId)
  const { data, error } = await q
  if (error) throw error
  return data as StaffCommissionLedger[]
}

export async function markCommissionPaid(ids: string[]) {
  const { error } = await supabase.from('staff_commission_ledger').update({ status: 'paid', paid_at: new Date().toISOString() }).in('id', ids)
  if (error) throw error
}

export async function getExpenseCategories(businessId: string) {
  const { data, error } = await supabase.from('expense_categories').select('*').eq('business_id', businessId).order('sort_order')
  if (error) throw error
  return data as ExpenseCategory[]
}

export async function getExpenses(businessId: string, limit = 50) {
  const { data, error } = await supabase.from('expenses').select('*, category:expense_categories(id, name, icon)').eq('business_id', businessId).order('date', { ascending: false }).limit(limit)
  if (error) throw error
  return data as Expense[]
}

export async function createExpense(expense: Partial<Expense>) {
  const { data, error } = await supabase.from('expenses').insert(expense).select().single()
  if (error) throw error
  return data as Expense
}

// Reports
export async function getDailySales(businessId: string, limit = 30) {
  const { data, error } = await supabase.from('daily_sales_summary').select('*').eq('business_id', businessId).order('sale_date', { ascending: false }).limit(limit)
  if (error) throw error
  return data as DailySalesSummary[]
}

export async function getNetProfit(businessId: string, limit = 30) {
  const { data, error } = await supabase.from('daily_net_profit_summary').select('*').eq('business_id', businessId).order('report_date', { ascending: false }).limit(limit)
  if (error) throw error
  return data as DailyNetProfitSummary[]
}

export async function getLowStockCount(businessId: string) {
  const { data, error } = await supabase.from('low_stock_alerts').select('product_id').eq('business_id', businessId)
  if (error) throw error
  return (data ?? []).length
}

export async function getTopProducts(businessId: string, startDate: string, endDate: string) {
  const { data, error } = await supabase.rpc('top_selling_products', {
    p_business_id: businessId, p_start_date: startDate, p_end_date: endDate, p_limit: 10,
  })
  if (error) throw error
  return data as { product_id: string; product_name: string; total_quantity: number; total_revenue: number }[]
}

export async function getLoyaltySummary(businessId: string) {
  const { data, error } = await supabase.from('customer_loyalty_summary').select('*').eq('business_id', businessId).single()
  if (error && error.code !== 'PGRST116') throw error
  return data as CustomerLoyaltySummary | null
}
