import { useState, useMemo } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useSessionStore } from '../../store/session.store'
import { useCartStore } from '../../store/cart.store'
import { getProducts } from '../../services/catalog.service'
import { getPaymentMethods, validateDiscount, checkout } from '../../services/sales.service'
import type { Product, Customer } from '../../types/db'
import { supabase } from '../../lib/supabase'
import StatusBadge from '../../components/StatusBadge'

export default function POSPage() {
  const { businessId, profile } = useSessionStore()
  const queryClient = useQueryClient()
  const cart = useCartStore()
  const totals = cart.getTotals()

  const [search, setSearch] = useState('')
  const [typeFilter, setTypeFilter] = useState<'all' | 'product' | 'service'>('all')
  const [discountCode, setDiscountCode] = useState('')
  const [discountError, setDiscountError] = useState('')
  const [customerSearch, setCustomerSearch] = useState('')
  const [showCustomers, setShowCustomers] = useState(false)
  const [selectedPaymentMethod, setSelectedPaymentMethod] = useState<string>('')
  const [checkoutSuccess, setCheckoutSuccess] = useState<string | null>(null)

  // ── Queries ──
  const { data: products = [], isLoading: loadingProducts } = useQuery({
    queryKey: ['products', businessId],
    queryFn: () => getProducts(businessId!),
    enabled: !!businessId,
  })

  const { data: paymentMethods = [] } = useQuery({
    queryKey: ['payment_methods', businessId],
    queryFn: () => getPaymentMethods(businessId!),
    enabled: !!businessId,
  })

  const { data: customers = [] } = useQuery({
    queryKey: ['customers_search', businessId, customerSearch],
    queryFn: async () => {
      if (!customerSearch.trim()) return []
      const { data } = await supabase
        .from('customers')
        .select('id, name, phone, loyalty_points')
        .eq('business_id', businessId!)
        .or(`name.ilike.%${customerSearch}%,phone.ilike.%${customerSearch}%`)
        .limit(10)
      return (data ?? []) as Customer[]
    },
    enabled: !!businessId && customerSearch.length > 1,
  })

  // Set default payment method
  if (paymentMethods.length > 0 && !selectedPaymentMethod) {
    setSelectedPaymentMethod(paymentMethods[0].id)
  }

  // ── Filtered products ──
  const filtered = useMemo(() => {
    let items = products
    if (typeFilter !== 'all') items = items.filter((p) => p.type === typeFilter)
    if (search.trim()) {
      const q = search.toLowerCase()
      items = items.filter((p) =>
        p.name.toLowerCase().includes(q) ||
        p.sku?.toLowerCase().includes(q) ||
        p.barcode?.toLowerCase().includes(q),
      )
    }
    return items
  }, [products, search, typeFilter])

  // ── Discount apply ──
  const applyDiscountCode = async () => {
    if (!discountCode.trim() || !businessId) return
    setDiscountError('')
    try {
      const d = await validateDiscount(businessId, discountCode.trim())
      if (d.min_order_amount && totals.subtotal < d.min_order_amount) {
        setDiscountError(`Minimum order ₹${d.min_order_amount}`)
        return
      }
      cart.applyDiscount(d)
    } catch (err) {
      setDiscountError(err instanceof Error ? err.message : 'Invalid code')
    }
  }

  // ── Checkout mutation ──
  const checkoutMutation = useMutation({
    mutationFn: () => {
      if (!businessId || !profile) throw new Error('No session')
      if (cart.items.length === 0) throw new Error('Cart is empty')
      if (!selectedPaymentMethod) throw new Error('Select a payment method')

      return checkout({
        businessId,
        customerId: cart.customerId,
        discountId: cart.discount?.id ?? null,
        items: cart.items,
        totals,
        payments: [{ payment_method_id: selectedPaymentMethod, amount: totals.total }],
        createdBy: profile.id,
      })
    },
    onSuccess: (order) => {
      setCheckoutSuccess(order.order_number)
      cart.clearCart()
      setDiscountCode('')
      setDiscountError('')
      queryClient.invalidateQueries({ queryKey: ['products'] })
      setTimeout(() => setCheckoutSuccess(null), 5000)
    },
  })

  return (
    <div className="flex gap-6 h-[calc(100vh-5rem)]">
      {/* ── LEFT: Product Grid ── */}
      <div className="flex-1 flex flex-col min-w-0">
        <div className="flex items-center gap-3 mb-4">
          <h1 className="text-2xl font-bold">POS</h1>
          {checkoutSuccess && (
            <div className="ml-auto bg-success/15 text-success px-4 py-2 rounded-lg text-sm font-medium animate-pulse">
              ✓ Order {checkoutSuccess} created!
            </div>
          )}
        </div>

        {/* Search + Filter */}
        <div className="flex gap-3 mb-4">
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search products, SKU, barcode…"
            className="flex-1 px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text placeholder:text-text-muted/50 focus:outline-none focus:ring-2 focus:ring-primary/50"
          />
          <div className="flex bg-surface-light border border-border rounded-lg overflow-hidden">
            {(['all', 'product', 'service'] as const).map((t) => (
              <button
                key={t}
                onClick={() => setTypeFilter(t)}
                className={`px-3 py-2 text-xs font-medium transition-default ${
                  typeFilter === t ? 'bg-primary text-white' : 'text-text-muted hover:text-text'
                }`}
              >
                {t === 'all' ? 'All' : t === 'product' ? '📦 Products' : '✂️ Services'}
              </button>
            ))}
          </div>
        </div>

        {/* Product Grid */}
        <div className="flex-1 overflow-y-auto pr-2">
          {loadingProducts ? (
            <div className="flex justify-center p-12">
              <div className="w-6 h-6 border-2 border-primary border-t-transparent rounded-full animate-spin" />
            </div>
          ) : filtered.length === 0 ? (
            <p className="text-center text-text-muted py-12">No products found</p>
          ) : (
            <div className="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
              {filtered.map((product) => (
                <ProductCard key={product.id} product={product} onAdd={() => cart.addItem(product)} />
              ))}
            </div>
          )}
        </div>
      </div>

      {/* ── RIGHT: Cart Panel ── */}
      <div className="w-96 shrink-0 glass flex flex-col p-4">
        <h2 className="text-lg font-semibold mb-3">Cart</h2>

        {/* Customer selector */}
        <div className="relative mb-3">
          <input
            type="text"
            value={customerSearch}
            onChange={(e) => { setCustomerSearch(e.target.value); setShowCustomers(true) }}
            onFocus={() => setShowCustomers(true)}
            placeholder={cart.customerId ? '✓ Customer selected' : 'Search customer (optional)…'}
            className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text placeholder:text-text-muted/50 focus:outline-none focus:ring-2 focus:ring-primary/50"
          />
          {cart.customerId && (
            <button
              onClick={() => { cart.setCustomer(null); setCustomerSearch('') }}
              className="absolute right-2 top-2 text-text-muted hover:text-danger text-xs"
            >
              ✕
            </button>
          )}
          {showCustomers && customers.length > 0 && (
            <div className="absolute z-10 top-full left-0 right-0 mt-1 bg-surface-card border border-border rounded-lg shadow-xl max-h-40 overflow-y-auto">
              {customers.map((c) => (
                <button
                  key={c.id}
                  onClick={() => {
                    cart.setCustomer(c.id)
                    setCustomerSearch(c.name)
                    setShowCustomers(false)
                  }}
                  className="w-full text-left px-3 py-2 hover:bg-surface-lighter text-sm transition-default"
                >
                  <span className="font-medium">{c.name}</span>
                  <span className="text-text-muted ml-2">{c.phone}</span>
                  <span className="text-accent text-xs ml-2">🏆 {c.loyalty_points}</span>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Cart Items */}
        <div className="flex-1 overflow-y-auto space-y-2 mb-3">
          {cart.items.length === 0 ? (
            <p className="text-center text-text-muted py-8 text-sm">Cart is empty</p>
          ) : (
            cart.items.map((item, i) => (
              <div key={`${item.product.id}-${item.variant?.id ?? 'base'}`} className="bg-surface-light rounded-lg p-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="text-sm font-medium truncate">{item.product.name}</p>
                    {item.variant && <p className="text-xs text-text-muted">{item.variant.name}</p>}
                    <p className="text-xs text-text-muted">₹{item.unitPrice} × {item.quantity}</p>
                  </div>
                  <button onClick={() => cart.removeItem(i)} className="text-text-muted hover:text-danger text-xs shrink-0">✕</button>
                </div>
                <div className="flex items-center gap-2 mt-2">
                  <button
                    onClick={() => cart.updateQuantity(i, item.quantity - 1)}
                    className="w-7 h-7 bg-surface-lighter rounded text-sm font-bold hover:bg-border transition-default"
                  >−</button>
                  <span className="text-sm font-medium w-8 text-center">{item.quantity}</span>
                  <button
                    onClick={() => cart.updateQuantity(i, item.quantity + 1)}
                    className="w-7 h-7 bg-surface-lighter rounded text-sm font-bold hover:bg-border transition-default"
                  >+</button>
                  <span className="ml-auto text-sm font-semibold">
                    ₹{(item.unitPrice * item.quantity * (1 - item.discountPercent / 100)).toFixed(2)}
                  </span>
                </div>
              </div>
            ))
          )}
        </div>

        {/* Discount Code */}
        <div className="flex gap-2 mb-3">
          <input
            type="text"
            value={discountCode}
            onChange={(e) => setDiscountCode(e.target.value)}
            placeholder="Discount code"
            className="flex-1 px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text placeholder:text-text-muted/50 focus:outline-none focus:ring-2 focus:ring-primary/50"
          />
          <button
            onClick={applyDiscountCode}
            className="px-3 py-2 bg-accent/15 text-accent rounded-lg text-sm font-medium hover:bg-accent/25 transition-default"
          >
            Apply
          </button>
        </div>
        {discountError && <p className="text-xs text-danger mb-2">{discountError}</p>}
        {cart.discount && (
          <div className="flex items-center justify-between bg-success/10 text-success px-3 py-2 rounded-lg text-sm mb-3">
            <span>🎟️ {cart.discount.name} ({cart.discount.type === 'percentage' ? `${cart.discount.value}%` : `₹${cart.discount.value}`})</span>
            <button onClick={() => cart.applyDiscount(null)} className="text-xs hover:underline">Remove</button>
          </div>
        )}

        {/* Totals */}
        <div className="border-t border-border pt-3 space-y-1 text-sm mb-3">
          <div className="flex justify-between text-text-muted">
            <span>Subtotal</span><span>₹{totals.subtotal.toFixed(2)}</span>
          </div>
          {totals.discountAmount > 0 && (
            <div className="flex justify-between text-success">
              <span>Discount</span><span>−₹{totals.discountAmount.toFixed(2)}</span>
            </div>
          )}
          <div className="flex justify-between text-text-muted">
            <span>Tax</span><span>₹{totals.taxAmount.toFixed(2)}</span>
          </div>
          <div className="flex justify-between text-lg font-bold pt-1">
            <span>Total</span><span>₹{totals.total.toFixed(2)}</span>
          </div>
        </div>

        {/* Payment Method */}
        <select
          value={selectedPaymentMethod}
          onChange={(e) => setSelectedPaymentMethod(e.target.value)}
          className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text mb-3 focus:outline-none focus:ring-2 focus:ring-primary/50"
        >
          {paymentMethods.map((pm) => (
            <option key={pm.id} value={pm.id}>{pm.name}</option>
          ))}
        </select>

        {/* Checkout Button */}
        <button
          onClick={() => checkoutMutation.mutate()}
          disabled={cart.items.length === 0 || checkoutMutation.isPending}
          className="w-full py-3 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white font-semibold rounded-lg transition-default text-sm"
        >
          {checkoutMutation.isPending ? 'Processing…' : `Pay ₹${totals.total.toFixed(2)}`}
        </button>
        {checkoutMutation.isError && (
          <p className="text-xs text-danger mt-2">
            {checkoutMutation.error instanceof Error ? checkoutMutation.error.message : 'Checkout failed'}
          </p>
        )}
      </div>
    </div>
  )
}

// ── Product Card (inline) ──

function ProductCard({ product, onAdd }: { product: Product; onAdd: () => void }) {
  return (
    <button
      onClick={onAdd}
      className="glass p-3 text-left hover:border-primary/50 transition-default group"
    >
      <div className="flex items-start justify-between gap-1">
        <p className="text-sm font-medium truncate group-hover:text-primary-light transition-default">
          {product.name}
        </p>
        <StatusBadge status={product.type} />
      </div>
      {product.category && (
        <p className="text-xs text-text-muted mt-1 truncate">{product.category.name}</p>
      )}
      <p className="text-sm font-bold mt-2 text-primary-light">₹{product.selling_price}</p>
    </button>
  )
}
