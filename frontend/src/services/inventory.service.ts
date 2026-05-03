import { supabase } from '../lib/supabase'
import type { Inventory, InventoryTransaction, Supplier, PurchaseOrder, PurchaseOrderItem } from '../types/db'

export async function getInventory(businessId: string) {
  const { data, error } = await supabase
    .from('inventory')
    .select('*, product:products(id, name, type, sku, unit), variant:product_variants(id, name)')
    .eq('business_id', businessId)
    .order('last_updated_at', { ascending: false })
  if (error) throw error
  return data as Inventory[]
}

export async function getLowStockAlerts(businessId: string) {
  const { data, error } = await supabase
    .from('low_stock_alerts')
    .select('*')
    .eq('business_id', businessId)
  if (error) throw error
  return data
}

export async function insertInventoryTransaction(tx: Partial<InventoryTransaction>) {
  const { data, error } = await supabase
    .from('inventory_transactions')
    .insert(tx)
    .select()
    .single()
  if (error) throw error
  return data as InventoryTransaction
}

export async function getSuppliers(businessId: string) {
  const { data, error } = await supabase
    .from('suppliers')
    .select('*')
    .eq('business_id', businessId)
    .eq('is_active', true)
    .order('name')
  if (error) throw error
  return data as Supplier[]
}

export async function getPurchaseOrders(businessId: string) {
  const { data, error } = await supabase
    .from('purchase_orders')
    .select('*, supplier:suppliers(id, name), items:purchase_order_items(*, product:products(id, name))')
    .eq('business_id', businessId)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data as PurchaseOrder[]
}

export async function createPurchaseOrder(po: Partial<PurchaseOrder>, items: Partial<PurchaseOrderItem>[]) {
  const { data: order, error: poErr } = await supabase
    .from('purchase_orders')
    .insert({ ...po, order_number: '' }) // trigger generates
    .select()
    .single()
  if (poErr) throw poErr

  const lineItems = items.map((item) => ({
    ...item,
    purchase_order_id: (order as PurchaseOrder).id,
  }))
  const { error: itemErr } = await supabase
    .from('purchase_order_items')
    .insert(lineItems)
  if (itemErr) throw itemErr

  return order as PurchaseOrder
}

export async function updatePOItemReceived(itemId: string, quantityReceived: number) {
  const { error } = await supabase
    .from('purchase_order_items')
    .update({ quantity_received: quantityReceived })
    .eq('id', itemId)
  if (error) throw error
}

export async function updatePOStatus(poId: string, status: PurchaseOrder['status']) {
  const updates: Record<string, unknown> = { status }
  if (status === 'received') updates.received_at = new Date().toISOString()
  if (status === 'ordered') updates.ordered_at = new Date().toISOString()

  const { error } = await supabase
    .from('purchase_orders')
    .update(updates)
    .eq('id', poId)
  if (error) throw error
}
