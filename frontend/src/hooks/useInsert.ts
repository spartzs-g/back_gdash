import { useCallback } from 'react'
import { supabase } from '../lib/supabase'
import { useSessionStore } from '../store/session.store'

/**
 * Auto-injects business_id into every insert.
 * Usage: const insert = useInsert(); await insert('products', { name: 'X', ... })
 */
export function useInsert() {
  const businessId = useSessionStore((s) => s.businessId)

  return useCallback(
    async <T extends Record<string, unknown>>(table: string, data: T | T[]) => {
      if (!businessId) throw new Error('No business_id in session')
      const rows = Array.isArray(data) ? data : [data]
      const withBiz = rows.map((r) => ({ ...r, business_id: businessId }))
      const { data: result, error } = await supabase.from(table).insert(withBiz).select()
      if (error) throw error
      return result
    },
    [businessId],
  )
}
