import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useSessionStore } from '../../store/session.store'
import { getCustomers, getLoyaltyHistory, adjustLoyalty, upsertCustomer } from '../../services/customers.service'
import DataTable, { type Column } from '../../components/DataTable'
import Modal from '../../components/Modal'
import RoleGate from '../../components/RoleGate'
import type { Customer } from '../../types/db'

export default function CustomersPage() {
  const { businessId } = useSessionStore()
  const qc = useQueryClient()
  const [search, setSearch] = useState('')
  const [detail, setDetail] = useState<Customer | null>(null)
  const [showAdd, setShowAdd] = useState(false)
  const [adjPoints, setAdjPoints] = useState('')
  const [adjNotes, setAdjNotes] = useState('')
  const [newName, setNewName] = useState('')
  const [newPhone, setNewPhone] = useState('')

  const { data: customers = [], isLoading } = useQuery({
    queryKey: ['customers', businessId],
    queryFn: () => getCustomers(businessId!),
    enabled: !!businessId,
  })

  const { data: loyaltyHistory = [] } = useQuery({
    queryKey: ['loyalty_history', detail?.id],
    queryFn: () => getLoyaltyHistory(detail!.id),
    enabled: !!detail,
  })

  const adjustMut = useMutation({
    mutationFn: () => {
      if (!businessId || !detail) throw new Error('Missing data')
      const pts = parseInt(adjPoints)
      if (isNaN(pts) || pts === 0) throw new Error('Invalid points')
      return adjustLoyalty(businessId, detail.id, pts, adjNotes || 'Manual adjustment')
    },
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['customers'] }); qc.invalidateQueries({ queryKey: ['loyalty_history'] }); setAdjPoints(''); setAdjNotes('') },
  })

  const addMut = useMutation({
    mutationFn: () => upsertCustomer({ business_id: businessId!, name: newName, phone: newPhone || null }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['customers'] }); setShowAdd(false); setNewName(''); setNewPhone('') },
  })

  const filtered = search ? customers.filter((c) => c.name.toLowerCase().includes(search.toLowerCase()) || c.phone?.includes(search)) : customers

  const columns: Column<Customer>[] = [
    { key: 'name', label: 'Name' },
    { key: 'phone', label: 'Phone', render: (v) => String(v ?? '—') },
    { key: 'loyalty_points', label: '🏆 Points', render: (v) => String(v) },
    { key: 'total_spent', label: 'Total Spent', render: (v) => `₹${Number(v).toFixed(0)}` },
    { key: 'visit_count', label: 'Visits', render: (v) => String(v) },
    { key: 'last_visit_at', label: 'Last Visit', render: (v) => v ? new Date(v as string).toLocaleDateString() : '—' },
  ]

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Customers</h1>
        <div className="flex gap-3">
          <input type="text" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search…"
            className="px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text w-48" />
          <button onClick={() => setShowAdd(true)} className="px-4 py-2 bg-primary hover:bg-primary-dark text-white text-sm font-medium rounded-lg transition-default">+ Add</button>
        </div>
      </div>

      <DataTable columns={columns} data={filtered as any} loading={isLoading} onRowClick={(r) => setDetail(r as any)} />

      {/* Customer Detail */}
      <Modal open={!!detail} onClose={() => setDetail(null)} title={detail?.name ?? ''}>
        {detail && (
          <div className="space-y-4">
            <div className="grid grid-cols-3 gap-3 text-center">
              <div className="glass p-3"><p className="text-2xl font-bold text-primary-light">{detail.loyalty_points}</p><p className="text-xs text-text-muted">Points</p></div>
              <div className="glass p-3"><p className="text-2xl font-bold text-success">₹{Number(detail.total_spent).toFixed(0)}</p><p className="text-xs text-text-muted">Spent</p></div>
              <div className="glass p-3"><p className="text-2xl font-bold text-accent">{detail.visit_count}</p><p className="text-xs text-text-muted">Visits</p></div>
            </div>

            <RoleGate allowedRoles={['owner', 'manager']}>
              <div className="flex gap-2">
                <input type="number" value={adjPoints} onChange={(e) => setAdjPoints(e.target.value)} placeholder="Points (+/-)" className="flex-1 px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
                <input type="text" value={adjNotes} onChange={(e) => setAdjNotes(e.target.value)} placeholder="Reason" className="flex-1 px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
                <button onClick={() => adjustMut.mutate()} disabled={adjustMut.isPending} className="px-4 py-2 bg-accent/15 text-accent rounded-lg text-sm font-medium">Adjust</button>
              </div>
            </RoleGate>

            <div>
              <h3 className="text-sm font-medium text-text-muted mb-2">Loyalty History</h3>
              {loyaltyHistory.map((tx) => (
                <div key={tx.id} className="flex justify-between text-sm py-1 border-t border-border/50">
                  <span className="capitalize">{tx.type}</span>
                  <span className={tx.points >= 0 ? 'text-success' : 'text-danger'}>{tx.points >= 0 ? '+' : ''}{tx.points}</span>
                  <span className="text-text-muted text-xs">{new Date(tx.created_at).toLocaleDateString()}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </Modal>

      {/* Add Customer */}
      <Modal open={showAdd} onClose={() => setShowAdd(false)} title="Add Customer" size="sm">
        <div className="space-y-3">
          <input value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="Name *" className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
          <input value={newPhone} onChange={(e) => setNewPhone(e.target.value)} placeholder="Phone" className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
          <button onClick={() => addMut.mutate()} disabled={addMut.isPending || !newName} className="w-full py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white font-medium rounded-lg text-sm transition-default">
            {addMut.isPending ? 'Adding…' : 'Add Customer'}
          </button>
        </div>
      </Modal>
    </div>
  )
}
