import { supabase } from '../lib/supabase'
import type { Product, Category, ProductVariant } from '../types/db'

export async function getProducts(businessId: string) {
  const { data, error } = await supabase
    .from('products')
    .select('*, category:categories(*)')
    .eq('business_id', businessId)
    .eq('is_active', true)
    .order('name')
  if (error) throw error
  return data as (Product & { category: Category | null })[]
}

export async function getCategories(businessId: string) {
  const { data, error } = await supabase
    .from('categories')
    .select('*')
    .eq('business_id', businessId)
    .eq('is_active', true)
    .order('sort_order')
  if (error) throw error
  return data as Category[]
}

export async function getProductVariants(productId: string) {
  const { data, error } = await supabase
    .from('product_variants')
    .select('*')
    .eq('product_id', productId)
    .eq('is_active', true)
  if (error) throw error
  return data as ProductVariant[]
}

export async function upsertProduct(product: Partial<Product>) {
  const { data, error } = await supabase
    .from('products')
    .upsert(product)
    .select()
    .single()
  if (error) throw error
  return data as Product
}

export async function upsertVariants(productId: string, variants: Partial<ProductVariant>[]) {
  const rows = variants.map((v) => ({ ...v, product_id: productId }))
  const { data, error } = await supabase
    .from('product_variants')
    .upsert(rows)
    .select()
  if (error) throw error
  return data as ProductVariant[]
}
