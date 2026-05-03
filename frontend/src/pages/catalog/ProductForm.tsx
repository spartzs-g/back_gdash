import { useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useSessionStore } from '../../store/session.store'
import { getCategories, upsertProduct } from '../../services/catalog.service'
import { supabase } from '../../lib/supabase'
import FormField from '../../components/FormField'
import type { Product } from '../../types/db'

const schema = z.object({
  name: z.string().min(1, 'Required'),
  type: z.enum(['product', 'service']),
  category_id: z.string().nullable().optional(),
  selling_price: z.coerce.number().min(0),
  cost_price: z.coerce.number().min(0),
  tax_rate: z.coerce.number().min(0).max(100),
  sku: z.string().optional(),
  barcode: z.string().optional(),
  unit: z.string().default('piece'),
  track_inventory: z.boolean(),
  duration_minutes: z.coerce.number().positive().optional().nullable(),
  description: z.string().optional(),
})

type FormData = z.infer<typeof schema>

export default function ProductForm() {
  const { id } = useParams()
  const isEdit = !!id
  const { businessId } = useSessionStore()
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  const { data: categories = [] } = useQuery({
    queryKey: ['categories', businessId],
    queryFn: () => getCategories(businessId!),
    enabled: !!businessId,
  })

  const { data: existing } = useQuery({
    queryKey: ['product', id],
    queryFn: async () => {
      if (!id) return null
      const { data, error } = await supabase.from('products').select('*').eq('id', id).single()
      if (error) throw error
      return data as Product
    },
    enabled: isEdit,
  })

  const { register, handleSubmit, formState: { errors }, watch, reset } = useForm<FormData>({
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    resolver: zodResolver(schema) as any,
    defaultValues: {
      type: 'product',
      selling_price: 0,
      cost_price: 0,
      tax_rate: 0,
      unit: 'piece',
      track_inventory: true,
    },
  })

  useEffect(() => {
    if (existing) reset(existing as FormData)
  }, [existing, reset])

  const productType = watch('type')

  const mutation = useMutation({
    mutationFn: (data: FormData) => {
      const payload: Partial<Product> = {
        ...data,
        business_id: businessId!,
        category_id: data.category_id || null,
        duration_minutes: data.type === 'service' ? data.duration_minutes ?? null : null,
        track_inventory: data.type === 'product' ? data.track_inventory : false,
      }
      if (isEdit) payload.id = id
      return upsertProduct(payload)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['products'] })
      navigate('/catalog')
    },
  })

  return (
    <div className="max-w-2xl">
      <h1 className="text-2xl font-bold mb-6">{isEdit ? 'Edit Product' : 'New Product'}</h1>

      <form onSubmit={handleSubmit((d) => mutation.mutate(d as FormData))} className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <FormField label="Name" registration={register('name')} error={errors.name} className="col-span-2" />

          <div>
            <label className="block text-sm font-medium text-text-muted mb-1">Type</label>
            <select {...register('type')} className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text focus:outline-none focus:ring-2 focus:ring-primary/50">
              <option value="product">Product</option>
              <option value="service">Service</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-text-muted mb-1">Category</label>
            <select {...register('category_id')} className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text focus:outline-none focus:ring-2 focus:ring-primary/50">
              <option value="">No category</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </div>

          <FormField label="Selling Price" registration={register('selling_price')} error={errors.selling_price} type="number" />
          <FormField label="Cost Price" registration={register('cost_price')} error={errors.cost_price} type="number" />
          <FormField label="Tax Rate (%)" registration={register('tax_rate')} error={errors.tax_rate} type="number" />
          <FormField label="SKU" registration={register('sku')} error={errors.sku} />
          <FormField label="Barcode" registration={register('barcode')} error={errors.barcode} />
          <FormField label="Unit" registration={register('unit')} error={errors.unit} />

          {productType === 'product' && (
            <div className="flex items-center gap-2">
              <input type="checkbox" {...register('track_inventory')} id="track_inventory" className="rounded" />
              <label htmlFor="track_inventory" className="text-sm text-text-muted">Track Inventory</label>
            </div>
          )}

          {productType === 'service' && (
            <FormField label="Duration (minutes)" registration={register('duration_minutes')} error={errors.duration_minutes} type="number" />
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-text-muted mb-1">Description</label>
          <textarea
            {...register('description')}
            rows={3}
            className="w-full px-3 py-2 bg-surface-light border border-border rounded-lg text-sm text-text placeholder:text-text-muted/50 focus:outline-none focus:ring-2 focus:ring-primary/50"
          />
        </div>

        {mutation.isError && (
          <p className="text-sm text-danger">{mutation.error instanceof Error ? mutation.error.message : 'Failed to save'}</p>
        )}

        <div className="flex gap-3">
          <button
            type="submit"
            disabled={mutation.isPending}
            className="px-6 py-2 bg-primary hover:bg-primary-dark disabled:opacity-50 text-white font-medium rounded-lg text-sm transition-default"
          >
            {mutation.isPending ? 'Saving…' : isEdit ? 'Update' : 'Create'}
          </button>
          <button
            type="button"
            onClick={() => navigate('/catalog')}
            className="px-6 py-2 bg-surface-light hover:bg-surface-lighter text-text-muted font-medium rounded-lg text-sm transition-default"
          >
            Cancel
          </button>
        </div>
      </form>
    </div>
  )
}
