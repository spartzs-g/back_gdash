import { supabase } from '../lib/supabase'
import type { Customer, LoyaltyTransaction } from '../types/db'

export async function getCustomers(businessId: string) {
  const { data, error } = await supabase
    .from('customers').select('*').eq('business_id', businessId).order('name')
  if (error) throw error
  return data as Customer[]
}

export async function upsertCustomer(customer: Partial<Customer>) {
  const { data, error } = await supabase.from('customers').upsert(customer).select().single()
  if (error) throw error
  return data as Customer
}

export async function getLoyaltyHistory(customerId: string) {
  const { data, error } = await supabase
    .from('loyalty_transactions').select('*').eq('customer_id', customerId).order('created_at', { ascending: false }).limit(50)
  if (error) throw error
  return data as LoyaltyTransaction[]
}

export async function adjustLoyalty(businessId: string, customerId: string, points: number, notes: string) {
  const { error } = await supabase.from('loyalty_transactions').insert({
    business_id: businessId, customer_id: customerId, type: 'adjust', points, notes,
  })
  if (error) throw error
}
