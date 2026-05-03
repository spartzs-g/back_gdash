import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { useSessionStore } from '../../store/session.store'
import { getAppointments, updateAppointmentStatus, completeAndInvoice } from '../../services/appointments.service'
import { getPaymentMethods } from '../../services/sales.service'
import StatusBadge from '../../components/StatusBadge'
import Modal from '../../components/Modal'
import type { Appointment } from '../../types/db'

const STATUS_ACTIONS: Record<string, { label: string; next: Appointment['status']; color: string }[]> = {
  scheduled:   [{ label: 'Confirm', next: 'confirmed', color: 'bg-blue-500/20 text-blue-300' }, { label: 'Cancel', next: 'cancelled', color: 'bg-danger/20 text-danger' }],
  confirmed:   [{ label: 'Start', next: 'in_progress', color: 'bg-accent/20 text-accent' }, { label: 'No Show', next: 'no_show', color: 'bg-gray-500/20 text-gray-400' }],
  in_progress: [{ label: '✓ Complete & Invoice', next: 'completed', color: 'bg-success/20 text-success' }],
}

export default function CalendarPage() {
  const { businessId, profile } = useSessionStore()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [detail, setDetail] = useState<Appointment | null>(null)
  const [invoiceResult, setInvoiceResult] = useState<string | null>(null)

  const { data: appointments = [], isLoading } = useQuery({
    queryKey: ['appointments', businessId, date],
    queryFn: () => getAppointments(businessId!, date),
    enabled: !!businessId,
  })

  const { data: paymentMethods = [] } = useQuery({
    queryKey: ['payment_methods', businessId],
    queryFn: () => getPaymentMethods(businessId!),
    enabled: !!businessId,
  })

  const statusMut = useMutation({
    mutationFn: ({ id, status }: { id: string; status: Appointment['status'] }) => updateAppointmentStatus(id, status),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['appointments'] }); setDetail(null) },
  })

  const invoiceMut = useMutation({
    mutationFn: (appt: Appointment) => {
      const pmId = paymentMethods[0]?.id
      if (!pmId || !businessId || !profile) throw new Error('Missing data')
      return completeAndInvoice(appt, businessId, profile.id, pmId)
    },
    onSuccess: (order) => {
      setInvoiceResult(order.order_number)
      qc.invalidateQueries({ queryKey: ['appointments'] })
      setDetail(null)
      setTimeout(() => setInvoiceResult(null), 5000)
    },
  })

  // Group by hour for simple timeline
  const hours = Array.from({ length: 14 }, (_, i) => i + 7) // 7 AM to 8 PM

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold">Appointments</h1>
          {invoiceResult && <p className="text-sm text-success mt-1">✓ Invoice {invoiceResult} created!</p>}
        </div>
        <div className="flex gap-3">
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} className="px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
          <button onClick={() => navigate('/appointments/new')} className="px-4 py-2 bg-primary hover:bg-primary-dark text-white text-sm font-medium rounded-lg transition-default">+ Book</button>
        </div>
      </div>

      {isLoading ? (
        <div className="flex justify-center p-12"><div className="w-6 h-6 border-2 border-primary border-t-transparent rounded-full animate-spin" /></div>
      ) : appointments.length === 0 ? (
        <p className="text-center text-text-muted py-12">No appointments for {date}</p>
      ) : (
        <div className="space-y-1">
          {hours.map((hour) => {
            const hourAppts = appointments.filter((a) => new Date(a.scheduled_at).getHours() === hour)
            return (
              <div key={hour} className="flex gap-3">
                <div className="w-16 text-right text-xs text-text-muted pt-2 shrink-0">{hour}:00</div>
                <div className="flex-1 min-h-[3rem] border-t border-border/50 pt-1 flex flex-wrap gap-2">
                  {hourAppts.map((appt) => (
                    <button
                      key={appt.id}
                      onClick={() => setDetail(appt)}
                      className="glass px-3 py-2 text-left text-sm hover:border-primary/50 transition-default"
                      style={{ borderLeftColor: appt.staff?.color ?? '#6366f1', borderLeftWidth: 3 }}
                    >
                      <div className="font-medium">{appt.customer?.name}</div>
                      <div className="text-xs text-text-muted">{appt.staff?.name} • {appt.duration_minutes}min</div>
                      <StatusBadge status={appt.status} />
                    </button>
                  ))}
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* Appointment Detail Modal */}
      <Modal open={!!detail} onClose={() => setDetail(null)} title="Appointment Details">
        {detail && (
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3 text-sm">
              <div><span className="text-text-muted">Customer:</span> {detail.customer?.name}</div>
              <div><span className="text-text-muted">Staff:</span> {detail.staff?.name ?? 'Any'}</div>
              <div><span className="text-text-muted">Time:</span> {new Date(detail.scheduled_at).toLocaleTimeString()}</div>
              <div><span className="text-text-muted">Duration:</span> {detail.duration_minutes} min</div>
            </div>
            <div>
              <h3 className="text-sm font-medium text-text-muted mb-2">Services</h3>
              {(detail.services ?? []).map((svc) => (
                <div key={svc.id} className="flex justify-between text-sm py-1 border-t border-border/50">
                  <span>{svc.product?.name} {svc.staff ? `(${svc.staff.name})` : ''}</span>
                  <span className="font-medium">₹{svc.price}</span>
                </div>
              ))}
              <div className="flex justify-between text-sm font-bold pt-2 border-t border-border">
                <span>Total</span>
                <span>₹{(detail.services ?? []).reduce((s, svc) => s + svc.price, 0)}</span>
              </div>
            </div>
            <div className="flex flex-wrap gap-2">
              <StatusBadge status={detail.status} />
              {(STATUS_ACTIONS[detail.status] ?? []).map((action) => (
                <button
                  key={action.next}
                  onClick={() => {
                    if (action.next === 'completed') invoiceMut.mutate(detail)
                    else statusMut.mutate({ id: detail.id, status: action.next })
                  }}
                  disabled={statusMut.isPending || invoiceMut.isPending}
                  className={`text-xs px-3 py-1.5 rounded-lg font-medium transition-default ${action.color}`}
                >
                  {action.label}
                </button>
              ))}
            </div>
            {(statusMut.isError || invoiceMut.isError) && <p className="text-xs text-danger">Operation failed</p>}
          </div>
        )}
      </Modal>
    </div>
  )
}
