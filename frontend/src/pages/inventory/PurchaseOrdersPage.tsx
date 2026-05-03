import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useSessionStore } from '../../store/session.store'
import { getPurchaseOrders, createPurchaseOrder, updatePOItemReceived, updatePOStatus } from '../../services/inventory.service'
import { getProducts } from '../../services/catalog.service'
import { getSuppliers } from '../../services/inventory.service'
import DataTable, { type Column } from '../../components/DataTable'
import StatusBadge from '../../components/StatusBadge'
import Modal from '../../components/Modal'
import type { PurchaseOrder } from '../../types/db'

export default function PurchaseOrdersPage() {
  const { businessId, profile } = useSessionStore()
  const qc = useQueryClient()
  const [showCreate, setShowCreate] = useState(false)
  const [selectedPO, setSelectedPO] = useState<PurchaseOrder | null>(null)
  const [supplierId, setSupplierId] = useState('')
  const [poNotes, setPONotes] = useState('')
  const [lineItems, setLineItems] = useState<{product_id:string;quantity_ordered:number;unit_cost:number}[]>([])

  const { data: orders = [], isLoading } = useQuery({
    queryKey: ['purchase_orders', businessId],
    queryFn: () => getPurchaseOrders(businessId!),
    enabled: !!businessId,
  })
  const { data: suppliers = [] } = useQuery({
    queryKey: ['suppliers', businessId],
    queryFn: () => getSuppliers(businessId!),
    enabled: !!businessId,
  })
  const { data: products = [] } = useQuery({
    queryKey: ['products', businessId],
    queryFn: () => getProducts(businessId!),
    enabled: !!businessId,
  })

  const createMut = useMutation({
    mutationFn: () => createPurchaseOrder(
      { business_id: businessId!, supplier_id: supplierId || null, notes: poNotes || null, created_by: profile?.id },
      lineItems,
    ),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['purchase_orders'] }); setShowCreate(false); setLineItems([]) },
  })

  const statusMut = useMutation({
    mutationFn: ({ id, status }: { id: string; status: PurchaseOrder['status'] }) => updatePOStatus(id, status),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['purchase_orders'] }),
  })

  const receiveMut = useMutation({
    mutationFn: ({ itemId, qty }: { itemId: string; qty: number }) => updatePOItemReceived(itemId, qty),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['purchase_orders'] }),
  })

  const columns: Column<PurchaseOrder>[] = [
    { key: 'order_number', label: 'PO #' },
    { key: 'supplier', label: 'Supplier', render: (_, r) => (r as any).supplier?.name ?? '—' },
    { key: 'status', label: 'Status', render: (_, r) => <StatusBadge status={r.status} /> },
    { key: 'total_amount', label: 'Total', render: (v) => `₹${Number(v).toFixed(2)}` },
    { key: 'created_at', label: 'Created', render: (v) => new Date(v as string).toLocaleDateString() },
  ]

  const addLine = () => setLineItems([...lineItems, { product_id: '', quantity_ordered: 1, unit_cost: 0 }])

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Purchase Orders</h1>
        <button onClick={() => setShowCreate(true)} className="px-4 py-2 bg-primary hover:bg-primary-dark text-white text-sm font-medium rounded-lg transition-default">+ New PO</button>
      </div>

      <DataTable columns={columns} data={orders as any} loading={isLoading} onRowClick={(r) => setSelectedPO(r as any)} />

      {/* Create PO Modal */}
      <Modal open={showCreate} onClose={() => setShowCreate(false)} title="New Purchase Order" size="lg">
        <div className="space-y-3">
          <select value={supplierId} onChange={(e) => setSupplierId(e.target.value)} className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text">
            <option value="">Select Supplier</option>
            {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
          {lineItems.map((li, i) => (
            <div key={i} className="flex gap-2 items-center">
              <select value={li.product_id} onChange={(e) => { const n=[...lineItems]; n[i].product_id=e.target.value; setLineItems(n) }} className="flex-1 px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text">
                <option value="">Product</option>
                {products.filter(p=>p.type==='product').map(p=><option key={p.id} value={p.id}>{p.name}</option>)}
              </select>
              <input type="number" value={li.quantity_ordered} onChange={(e) => { const n=[...lineItems]; n[i].quantity_ordered=+e.target.value; setLineItems(n) }} placeholder="Qty" className="w-20 px-2 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
              <input type="number" value={li.unit_cost} onChange={(e) => { const n=[...lineItems]; n[i].unit_cost=+e.target.value; setLineItems(n) }} placeholder="Cost" className="w-24 px-2 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
              <button onClick={() => setLineItems(lineItems.filter((_,j)=>j!==i))} className="text-danger text-xs">✕</button>
            </div>
          ))}
          <button onClick={addLine} className="text-sm text-accent hover:underline">+ Add Item</button>
          <input value={poNotes} onChange={(e)=>setPONotes(e.target.value)} placeholder="Notes" className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text" />
          <button onClick={()=>createMut.mutate()} disabled={createMut.isPending||lineItems.length===0} className="w-full py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white font-medium rounded-lg text-sm transition-default">
            {createMut.isPending ? 'Creating…' : 'Create PO'}
          </button>
        </div>
      </Modal>

      {/* PO Detail Modal */}
      <Modal open={!!selectedPO} onClose={() => setSelectedPO(null)} title={`PO: ${selectedPO?.order_number ?? ''}`} size="lg">
        {selectedPO && (
          <div className="space-y-4">
            <div className="flex gap-3 items-center">
              <StatusBadge status={selectedPO.status} />
              {selectedPO.status === 'draft' && (
                <button onClick={() => { statusMut.mutate({ id: selectedPO.id, status: 'ordered' }); setSelectedPO(null) }} className="text-xs px-3 py-1 bg-blue-500/20 text-blue-300 rounded-lg">Mark Ordered</button>
              )}
              {(selectedPO.status === 'ordered' || selectedPO.status === 'partially_received') && (
                <button onClick={() => { statusMut.mutate({ id: selectedPO.id, status: 'received' }); setSelectedPO(null) }} className="text-xs px-3 py-1 bg-success/20 text-success rounded-lg">Mark Received</button>
              )}
            </div>
            <table className="w-full text-sm">
              <thead><tr className="text-text-muted text-left"><th className="py-2">Product</th><th>Ordered</th><th>Received</th><th>Action</th></tr></thead>
              <tbody>
                {(selectedPO.items ?? []).map((item: any) => (
                  <tr key={item.id} className="border-t border-border">
                    <td className="py-2">{item.product?.name}</td>
                    <td>{item.quantity_ordered}</td>
                    <td>{item.quantity_received}</td>
                    <td>
                      {selectedPO.status !== 'received' && selectedPO.status !== 'cancelled' && (
                        <input type="number" defaultValue={item.quantity_received} max={item.quantity_ordered}
                          onBlur={(e) => receiveMut.mutate({ itemId: item.id, qty: +e.target.value })}
                          className="w-20 px-2 py-1 bg-surface-light border border-border rounded text-sm text-text" />
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Modal>
    </div>
  )
}
