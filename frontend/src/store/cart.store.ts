import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { CartItem, Product, ProductVariant, Discount } from '../types/db'
import { calcCartTotals } from '../services/sales.service'

interface CartState {
  items: CartItem[]
  customerId: string | null
  discount: Discount | null

  // Actions
  addItem: (product: Product, variant?: ProductVariant | null, staffId?: string | null) => void
  removeItem: (index: number) => void
  updateQuantity: (index: number, qty: number) => void
  setItemDiscount: (index: number, pct: number) => void
  setCustomer: (id: string | null) => void
  applyDiscount: (d: Discount | null) => void
  clearCart: () => void

  // Computed (call these as selectors)
  getTotals: () => ReturnType<typeof calcCartTotals>
}

export const useCartStore = create<CartState>()(
  persist(
    (set, get) => ({
      items: [],
      customerId: null,
      discount: null,

      addItem: (product, variant = null, staffId = null) => {
        const items = [...get().items]
        const existing = items.findIndex(
          (i) => i.product.id === product.id && (i.variant?.id ?? null) === (variant?.id ?? null),
        )
        if (existing >= 0) {
          items[existing] = { ...items[existing], quantity: items[existing].quantity + 1 }
        } else {
          const unitPrice = variant?.selling_price ?? product.selling_price
          items.push({
            product,
            variant,
            quantity: 1,
            unitPrice,
            discountPercent: 0,
            taxRate: product.tax_rate,
            staffId,
          })
        }
        set({ items })
      },

      removeItem: (index) => {
        const items = get().items.filter((_, i) => i !== index)
        set({ items })
      },

      updateQuantity: (index, qty) => {
        if (qty <= 0) return get().removeItem(index)
        const items = [...get().items]
        items[index] = { ...items[index], quantity: qty }
        set({ items })
      },

      setItemDiscount: (index, pct) => {
        const items = [...get().items]
        items[index] = { ...items[index], discountPercent: Math.min(Math.max(pct, 0), 100) }
        set({ items })
      },

      setCustomer: (customerId) => set({ customerId }),
      applyDiscount: (discount) => set({ discount }),
      clearCart: () => set({ items: [], customerId: null, discount: null }),

      getTotals: () => calcCartTotals(get().items, get().discount),
    }),
    {
      name: 'gdash-cart',
      // Only persist items, customer, discount — not functions
      partialize: (state) => ({
        items: state.items,
        customerId: state.customerId,
        discount: state.discount,
      }),
    },
  ),
)
