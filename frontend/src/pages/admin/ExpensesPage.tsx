import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useSessionStore } from '../../store/session.store'
import { getExpenses, getExpenseCategories, createExpense } from '../../services/admin.service'
import { getPaymentMethods } from '../../services/sales.service'
import DataTable, { type Column } from '../../components/DataTable'
import Modal from '../../components/Modal'
import RoleGate from '../../components/RoleGate'
import type { Expense } from '../../types/db'

export default function ExpensesPage() {
  const { businessId, profile } = useSessionStore()
  const qc = useQueryClient()
  const [showAdd, setShowAdd] = useState(false)
  const [amount, setAmount] = useState('')
  const [desc, setDesc] = useState('')
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [catId, setCatId] = useState('')
  const [pmId, setPmId] = useState('')

  const { data: expenses = [], isLoading } = useQuery({
    queryKey: ['expenses', businessId],
    queryFn: () => getExpenses(businessId!),
    enabled: !!businessId,
  })

  const { data: categories = [] } = useQuery({
    queryKey: ['expense_categories', businessId],
    queryFn: () => getExpenseCategories(businessId!),
    enabled: !!businessId,
  })

  const { data: paymentMethods = [] } = useQuery({
    queryKey: ['payment_methods', businessId],
    queryFn: () => getPaymentMethods(businessId!),
    enabled: !!businessId,
  })

  const addMut = useMutation({
    mutationFn: () => createExpense({
      business_id: businessId!,
      category_id: catId || null,
      amount: parseFloat(amount),
      description: desc,
      date,
      payment_method_id: pmId || null,
      created_by: profile?.id,
    }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['expenses'] }); setShowAdd(false); setAmount(''); setDesc('') },
  })

  const columns: Column<Expense>[] = [
    { key: 'date', label: 'Date', render: (v) => new Date(v as string).toLocaleDateString() },
    { key: 'description', label: 'Description' },
    { key: 'category', label: 'Category', render: (_, r) => (r as any).category?.name ?? '—' },
    { key: 'amount', label: 'Amount', render: (v) => `₹${Number(v).toFixed(2)}` },
  ]

  return (
    <RoleGate allowedRoles={['owner', 'manager']}>
      <div>
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-bold">Expenses</h1>
          <div className="flex gap-3">
            <a href="/admin" className="px-4 py-2 bg-surface-light hover:bg-surface-lighter text-text-muted text-sm font-medium rounded-lg transition-default">← Commissions</a>
            <a href="/admin/payments" className="px-4 py-2 bg-surface-light hover:bg-surface-lighter text-text-muted text-sm font-medium rounded-lg transition-default">Payments →</a>
            <button onClick={() => setShowAdd(true)} className="px-4 py-2 bg-primary hover:bg-primary-dark text-white text-sm font-medium rounded-lg transition-default">+ Add Expense</button>
          </div>
        </div>

        <DataTable columns={columns} data={expenses as any} loading={isLoading} />

        <Modal open={showAdd} onClose={() => setShowAdd(false)} title="Add Expense" size="sm">
          <div className="space-y-3">
            <input value={desc} onChange={(e) => setDesc(e.target.value)} placeholder="Description *" className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
            <input type="number" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="Amount *" className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
            <select value={catId} onChange={(e) => setCatId(e.target.value)} className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text">
              <option value="">Category (optional)</option>
              {categories.map((c) => <option key={c.id} value={c.id}>{c.icon ?? ''} {c.name}</option>)}
            </select>
            <select value={pmId} onChange={(e) => setPmId(e.target.value)} className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text">
              <option value="">Payment Method</option>
              {paymentMethods.map((pm) => <option key={pm.id} value={pm.id}>{pm.name}</option>)}
            </select>
            <button onClick={() => addMut.mutate()} disabled={addMut.isPending || !desc || !amount}
              className="w-full py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white font-medium rounded-lg text-sm transition-default">
              {addMut.isPending ? 'Saving…' : 'Add Expense'}
            </button>
          </div>
        </Modal>
      </div>
    </RoleGate>
  )
}
