import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery, useMutation } from '@tanstack/react-query'
import { useSessionStore } from '../../store/session.store'
import { getStaff, bookAppointment } from '../../services/appointments.service'
import { getProducts } from '../../services/catalog.service'
import { supabase } from '../../lib/supabase'
import type { Customer, Product } from '../../types/db'

export default function AppointmentForm() {
  const { businessId } = useSessionStore()
  const navigate = useNavigate()
  const [customerSearch, setCustomerSearch] = useState('')
  const [customerId, setCustomerId] = useState('')
  const [staffId, setStaffId] = useState('')
  const [date, setDate] = useState('')
  const [time, setTime] = useState('10:00')
  const [notes, setNotes] = useState('')
  const [selectedServices, setSelectedServices] = useState<{ product: Product; staff_id: string }[]>([])

  const { data: staff = [] } = useQuery({
    queryKey: ['staff', businessId],
    queryFn: () => getStaff(businessId!),
    enabled: !!businessId,
  })

  const { data: services = [] } = useQuery({
    queryKey: ['products', businessId],
    queryFn: () => getProducts(businessId!),
    enabled: !!businessId,
    select: (d) => d.filter((p) => p.type === 'service'),
  })

  const { data: customers = [] } = useQuery({
    queryKey: ['customer_search_appt', customerSearch],
    queryFn: async () => {
      if (!customerSearch.trim() || !businessId) return []
      const { data } = await supabase.from('customers').select('id, name, phone').eq('business_id', businessId).or(`name.ilike.%${customerSearch}%,phone.ilike.%${customerSearch}%`).limit(10)
      return (data ?? []) as Customer[]
    },
    enabled: customerSearch.length > 1,
  })

  const totalDuration = selectedServices.reduce((s, svc) => s + (svc.product.duration_minutes ?? 30), 0)
  const totalPrice = selectedServices.reduce((s, svc) => s + svc.product.selling_price, 0)

  const mutation = useMutation({
    mutationFn: () => {
      if (!businessId || !customerId || !date) throw new Error('Missing fields')
      const scheduledAt = `${date}T${time}:00`
      return bookAppointment(
        businessId,
        { customer_id: customerId, staff_id: staffId || null, scheduled_at: scheduledAt, duration_minutes: totalDuration, notes: notes || undefined },
        selectedServices.map((s) => ({
          product_id: s.product.id,
          staff_id: s.staff_id || null,
          price: s.product.selling_price, // snapshot
          duration_minutes: s.product.duration_minutes ?? 30,
        })),
      )
    },
    onSuccess: () => navigate('/appointments'),
  })

  const addService = (product: Product) => {
    setSelectedServices([...selectedServices, { product, staff_id: '' }])
  }

  return (
    <div className="max-w-2xl">
      <h1 className="text-2xl font-bold mb-6">Book Appointment</h1>
      <div className="space-y-4">
        {/* Customer */}
        <div className="relative">
          <label className="block text-sm font-medium text-text-muted mb-1">Customer *</label>
          <input type="text" value={customerSearch} onChange={(e) => setCustomerSearch(e.target.value)}
            placeholder="Search by name or phone…"
            className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text focus:outline-none focus:ring-2 focus:ring-primary/50" />
          {customers.length > 0 && (
            <div className="absolute z-10 top-full left-0 right-0 mt-1 bg-surface-card border border-border rounded-lg shadow-xl max-h-32 overflow-y-auto">
              {customers.map((c) => (
                <button key={c.id} onClick={() => { setCustomerId(c.id); setCustomerSearch(c.name) }}
                  className="w-full text-left px-3 py-2 hover:bg-surface-lighter text-sm">{c.name} — {c.phone}</button>
              ))}
            </div>
          )}
        </div>

        {/* Date + Time + Staff */}
        <div className="grid grid-cols-3 gap-3">
          <div>
            <label className="block text-sm font-medium text-text-muted mb-1">Date *</label>
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
          </div>
          <div>
            <label className="block text-sm font-medium text-text-muted mb-1">Time</label>
            <input type="time" value={time} onChange={(e) => setTime(e.target.value)} className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
          </div>
          <div>
            <label className="block text-sm font-medium text-text-muted mb-1">Primary Staff</label>
            <select value={staffId} onChange={(e) => setStaffId(e.target.value)} className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text">
              <option value="">Any available</option>
              {staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
        </div>

        {/* Services */}
        <div>
          <label className="block text-sm font-medium text-text-muted mb-2">Services *</label>
          <div className="flex flex-wrap gap-2 mb-3">
            {services.map((svc) => (
              <button key={svc.id} onClick={() => addService(svc)} className="text-xs px-3 py-1.5 glass hover:border-primary/50 transition-default">
                {svc.name} — ₹{svc.selling_price}
              </button>
            ))}
          </div>
          {selectedServices.length > 0 && (
            <div className="space-y-2">
              {selectedServices.map((s, i) => (
                <div key={i} className="flex items-center gap-2 bg-surface-light rounded-lg p-2 text-sm">
                  <span className="flex-1">{s.product.name} — ₹{s.product.selling_price} ({s.product.duration_minutes ?? 30}min)</span>
                  <select value={s.staff_id} onChange={(e) => { const n = [...selectedServices]; n[i].staff_id = e.target.value; setSelectedServices(n) }} className="px-2 py-1 bg-surface border border-border rounded text-xs text-text">
                    <option value="">Any staff</option>
                    {staff.map((st) => <option key={st.id} value={st.id}>{st.name}</option>)}
                  </select>
                  <button onClick={() => setSelectedServices(selectedServices.filter((_, j) => j !== i))} className="text-danger text-xs">✕</button>
                </div>
              ))}
              <p className="text-sm text-text-muted">Total: {totalDuration}min — ₹{totalPrice}</p>
            </div>
          )}
        </div>

        <textarea value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Notes (optional)" rows={2}
          className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />

        {mutation.isError && <p className="text-sm text-danger">{mutation.error instanceof Error ? mutation.error.message : 'Failed'}</p>}

        <div className="flex gap-3">
          <button onClick={() => mutation.mutate()} disabled={mutation.isPending || !customerId || !date || selectedServices.length === 0}
            className="px-6 py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white font-medium rounded-lg text-sm transition-default">
            {mutation.isPending ? 'Booking…' : 'Book Appointment'}
          </button>
          <button onClick={() => navigate('/appointments')} className="px-6 py-2 bg-surface-light hover:bg-surface-lighter text-text-muted font-medium rounded-lg text-sm transition-default">Cancel</button>
        </div>
      </div>
    </div>
  )
}
