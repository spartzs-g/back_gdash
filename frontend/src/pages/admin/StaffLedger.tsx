import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useSessionStore } from '../../store/session.store'
import { getCommissionSummary, getCommissionLedger, markCommissionPaid } from '../../services/admin.service'
import DataTable, { type Column } from '../../components/DataTable'
import StatusBadge from '../../components/StatusBadge'
import RoleGate from '../../components/RoleGate'
import type { StaffCommissionSummary, StaffCommissionLedger } from '../../types/db'

export default function StaffLedger() {
  const { businessId } = useSessionStore()
  const qc = useQueryClient()
  const [staffId, setStaffId] = useState<string | null>(null)
  const [selected, setSelected] = useState<Set<string>>(new Set())

  const { data: summary = [], isLoading } = useQuery({
    queryKey: ['commission_summary', businessId],
    queryFn: () => getCommissionSummary(businessId!),
    enabled: !!businessId,
  })

  const { data: ledger = [] } = useQuery({
    queryKey: ['commission_ledger', businessId, staffId],
    queryFn: () => getCommissionLedger(businessId!, staffId ?? undefined),
    enabled: !!businessId && !!staffId,
  })

  const payMut = useMutation({
    mutationFn: () => markCommissionPaid(Array.from(selected)),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['commission_summary'] }); qc.invalidateQueries({ queryKey: ['commission_ledger'] }); setSelected(new Set()) },
  })

  const toggleSelect = (id: string) => {
    const next = new Set(selected)
    next.has(id) ? next.delete(id) : next.add(id)
    setSelected(next)
  }

  const summaryColumns: Column<StaffCommissionSummary>[] = [
    { key: 'staff_name', label: 'Staff' },
    { key: 'commission_month', label: 'Month', render: (v) => new Date(v as string).toLocaleDateString('en-IN', { month: 'short', year: 'numeric' }) },
    { key: 'total_commission', label: 'Total', render: (v) => `₹${Number(v).toFixed(2)}` },
    { key: 'pending_commission', label: 'Pending', render: (v) => <span className="text-warning">₹{Number(v).toFixed(2)}</span> },
    { key: 'paid_commission', label: 'Paid', render: (v) => <span className="text-success">₹{Number(v).toFixed(2)}</span> },
  ]

  const ledgerColumns: Column<StaffCommissionLedger>[] = [
    { key: 'created_at', label: 'Date', render: (v) => new Date(v as string).toLocaleDateString() },
    { key: 'amount', label: 'Amount', render: (v) => `₹${Number(v).toFixed(2)}` },
    { key: 'status', label: 'Status', render: (_, r) => <StatusBadge status={r.status} /> },
    {
      key: 'id', label: '',
      render: (_, r) => r.status === 'pending' ? (
        <input type="checkbox" checked={selected.has(r.id)} onChange={() => toggleSelect(r.id)} className="rounded" />
      ) : null,
    },
  ]

  return (
    <RoleGate allowedRoles={['owner', 'manager']}>
      <div>
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-bold">Staff & Commissions</h1>
          <div className="flex gap-3">
            <a href="/admin/expenses" className="px-4 py-2 bg-surface-light hover:bg-surface-lighter text-text-muted text-sm font-medium rounded-lg transition-default">Expenses →</a>
            <a href="/admin/payments" className="px-4 py-2 bg-surface-light hover:bg-surface-lighter text-text-muted text-sm font-medium rounded-lg transition-default">Payments →</a>
          </div>
        </div>

        {!staffId ? (
          <>
            <h2 className="text-lg font-semibold mb-3">Monthly Summary</h2>
            <DataTable columns={summaryColumns} data={summary as any} loading={isLoading} onRowClick={(r) => setStaffId((r as any).staff_id)} />
          </>
        ) : (
          <>
            <button onClick={() => { setStaffId(null); setSelected(new Set()) }} className="text-sm text-accent hover:underline mb-3">← Back to summary</button>
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-lg font-semibold">Ledger Details</h2>
              {selected.size > 0 && (
                <button onClick={() => payMut.mutate()} disabled={payMut.isPending}
                  className="px-4 py-2 bg-success/15 text-success text-sm font-medium rounded-lg hover:bg-success/25 transition-default">
                  Mark {selected.size} as Paid
                </button>
              )}
            </div>
            <DataTable columns={ledgerColumns} data={ledger as any} loading={false} />
          </>
        )}
      </div>
    </RoleGate>
  )
}
