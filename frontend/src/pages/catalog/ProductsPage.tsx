import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { useSessionStore } from '../../store/session.store'
import { getProducts, getCategories } from '../../services/catalog.service'
import { supabase } from '../../lib/supabase'
import DataTable, { type Column } from '../../components/DataTable'
import StatusBadge from '../../components/StatusBadge'
import RoleGate from '../../components/RoleGate'
import type { Product } from '../../types/db'

export default function ProductsPage() {
  const { businessId } = useSessionStore()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [typeFilter, setTypeFilter] = useState<'all' | 'product' | 'service'>('all')
  const [catFilter, setCatFilter] = useState<string>('all')
  const [search, setSearch] = useState('')

  const { data: products = [], isLoading } = useQuery({
    queryKey: ['products', businessId],
    queryFn: () => getProducts(businessId!),
    enabled: !!businessId,
  })

  const { data: categories = [] } = useQuery({
    queryKey: ['categories', businessId],
    queryFn: () => getCategories(businessId!),
    enabled: !!businessId,
  })

  const toggleActive = useMutation({
    mutationFn: async ({ id, is_active }: { id: string; is_active: boolean }) => {
      const { error } = await supabase.from('products').update({ is_active }).eq('id', id)
      if (error) throw error
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['products'] }),
  })

  const filtered = products.filter((p) => {
    if (typeFilter !== 'all' && p.type !== typeFilter) return false
    if (catFilter !== 'all' && p.category_id !== catFilter) return false
    if (search) {
      const q = search.toLowerCase()
      if (!p.name.toLowerCase().includes(q) && !p.sku?.toLowerCase().includes(q)) return false
    }
    return true
  })

  const columns: Column<Product>[] = [
    { key: 'name', label: 'Name' },
    { key: 'type', label: 'Type', render: (_, r) => <StatusBadge status={r.type} /> },
    { key: 'category', label: 'Category', render: (_, r) => (r as any).category?.name ?? '—' },
    { key: 'selling_price', label: 'Price', render: (v) => `₹${Number(v).toFixed(2)}` },
    { key: 'sku', label: 'SKU', render: (v) => String(v ?? '—') },
    {
      key: 'is_active', label: 'Status',
      render: (_, r) => (
        <RoleGate allowedRoles={['owner', 'manager']}>
          <button
            onClick={(e) => { e.stopPropagation(); toggleActive.mutate({ id: r.id, is_active: !r.is_active }) }}
            className={`text-xs px-2 py-1 rounded-full transition-default ${
              r.is_active ? 'bg-success/20 text-success' : 'bg-gray-500/20 text-gray-400'
            }`}
          >
            {r.is_active ? 'Active' : 'Inactive'}
          </button>
        </RoleGate>
      ),
    },
  ]

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Catalog</h1>
        <RoleGate allowedRoles={['owner', 'manager']}>
          <button
            onClick={() => navigate('/catalog/new')}
            className="px-4 py-2 bg-primary hover:bg-primary-dark text-white text-sm font-medium rounded-lg transition-default"
          >
            + Add Product
          </button>
        </RoleGate>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-4">
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search…"
          className="px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text placeholder:text-text-muted/50 focus:outline-none focus:ring-2 focus:ring-primary/50 w-64"
        />
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value as any)}
          className="px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text focus:outline-none focus:ring-2 focus:ring-primary/50"
        >
          <option value="all">All Types</option>
          <option value="product">Products</option>
          <option value="service">Services</option>
        </select>
        <select
          value={catFilter}
          onChange={(e) => setCatFilter(e.target.value)}
          className="px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text focus:outline-none focus:ring-2 focus:ring-primary/50"
        >
          <option value="all">All Categories</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </select>
      </div>

      <DataTable
        columns={columns}
        data={filtered as any}
        loading={isLoading}
        onRowClick={(row) => navigate(`/catalog/${(row as any).id}/edit`)}
        emptyMessage="No products found. Add your first product!"
      />
    </div>
  )
}
