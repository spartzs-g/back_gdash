import { useQuery } from '@tanstack/react-query'
import { useSessionStore } from '../../store/session.store'
import { getPayments } from '../../services/sales.service'
import DataTable, { type Column } from '../../components/DataTable'
import StatusBadge from '../../components/StatusBadge'
import RoleGate from '../../components/RoleGate'
import type { Payment } from '../../types/db'

export default function PaymentsPage() {
  const { businessId } = useSessionStore()

  const { data: payments = [], isLoading } = useQuery({
    queryKey: ['payments', businessId],
    queryFn: () => getPayments(businessId!),
    enabled: !!businessId,
  })

  const columns: Column<Payment>[] = [
    { key: 'paid_at', label: 'Date', render: (v) => v ? new Date(v as string).toLocaleString() : '—' },
    { key: 'payment_method', label: 'Method', render: (_, r) => (r as any).payment_method?.name ?? '—' },
    { key: 'amount', label: 'Amount', render: (v) => `₹${Number(v).toFixed(2)}` },
    { key: 'status', label: 'Status', render: (_, r) => <StatusBadge status={r.status} /> },
    { key: 'reference_number', label: 'Ref Number', render: (v) => (v as string) || '—' },
  ]

  return (
    <RoleGate allowedRoles={['owner', 'manager']}>
      <div>
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-bold">Payments</h1>
          <div className="flex gap-3">
            <a href="/admin" className="px-4 py-2 bg-surface-light hover:bg-surface-lighter text-text-muted text-sm font-medium rounded-lg transition-default">← Admin</a>
          </div>
        </div>

        <DataTable columns={columns} data={payments as any} loading={isLoading} />
      </div>
    </RoleGate>
  )
}
