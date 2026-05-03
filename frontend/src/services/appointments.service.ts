import { supabase } from '../lib/supabase'
import type { Staff, Appointment, SalesOrder, SalesOrderItem } from '../types/db'

export async function getStaff(businessId: string) {
  const { data, error } = await supabase.from('staff').select('*').eq('business_id', businessId).eq('is_active', true).order('name')
  if (error) throw error
  return data as Staff[]
}

export async function getAppointments(businessId: string, date: string) {
  const startOfDay = `${date}T00:00:00`
  const endOfDay = `${date}T23:59:59`
  const { data, error } = await supabase
    .from('appointments')
    .select('*, customer:customers(id, name, phone), staff:staff(id, name, color), services:appointment_services(*, product:products(id, name, selling_price), staff:staff(id, name))')
    .eq('business_id', businessId)
    .gte('scheduled_at', startOfDay)
    .lte('scheduled_at', endOfDay)
    .order('scheduled_at')
  if (error) throw error
  return data as Appointment[]
}

export async function bookAppointment(
  businessId: string,
  data: { customer_id: string; staff_id: string | null; scheduled_at: string; duration_minutes: number; notes?: string },
  services: { product_id: string; staff_id: string | null; price: number; duration_minutes: number }[],
) {
  const { data: appt, error } = await supabase
    .from('appointments')
    .insert({ ...data, business_id: businessId })
    .select()
    .single()
  if (error) throw error

  const svcRows = services.map((s) => ({ ...s, appointment_id: (appt as Appointment).id }))
  const { error: svcErr } = await supabase.from('appointment_services').insert(svcRows)
  if (svcErr) throw svcErr

  return appt as Appointment
}

export async function updateAppointmentStatus(id: string, status: Appointment['status'], reason?: string) {
  const updates: Record<string, unknown> = { status }
  if (reason) updates.cancellation_reason = reason
  const { error } = await supabase.from('appointments').update(updates).eq('id', id)
  if (error) throw error
}

export async function completeAndInvoice(
  appt: Appointment,
  businessId: string,
  createdBy: string,
  paymentMethodId: string,
) {
  // 1. Create sales order from appointment services
  const services = appt.services ?? []
  const subtotal = services.reduce((s, svc) => s + svc.price, 0)

  const { data: order, error: oErr } = await supabase
    .from('sales_orders')
    .insert({
      business_id: businessId,
      customer_id: appt.customer_id,
      appointment_id: appt.id,
      order_number: '',
      status: 'completed',
      subtotal,
      discount_amount: 0,
      tax_amount: 0,
      total_amount: subtotal,
      created_by: createdBy,
    })
    .select()
    .single()
  if (oErr) throw oErr
  const salesOrder = order as SalesOrder

  // 2. Insert line items
  const items: Partial<SalesOrderItem>[] = services.map((svc) => ({
    order_id: salesOrder.id,
    product_id: svc.product_id,
    staff_id: svc.staff_id,
    quantity: 1,
    unit_price: svc.price,
    discount_percent: 0,
    tax_rate: 0,
    tax_amount: 0,
    total_price: svc.price,
  }))
  const { error: iErr } = await supabase.from('sales_order_items').insert(items)
  if (iErr) throw iErr

  // 3. Insert payment
  const { error: pErr } = await supabase.from('payments').insert({
    business_id: businessId,
    order_id: salesOrder.id,
    payment_method_id: paymentMethodId,
    amount: subtotal,
    status: 'completed',
    paid_at: new Date().toISOString(),
  })
  if (pErr) throw pErr

  // 4. Link appointment
  await supabase.from('appointments').update({ sales_order_id: salesOrder.id, status: 'completed' }).eq('id', appt.id)

  return salesOrder
}
