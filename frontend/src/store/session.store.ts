import { create } from 'zustand'
import type { Profile, Business } from '../types/db'

interface SessionState {
  profile: Profile | null
  business: Business | null
  businessId: string | null
  role: Profile['role'] | null
  isLoading: boolean
  setSession: (profile: Profile, business: Business) => void
  clear: () => void
  setLoading: (v: boolean) => void
}

export const useSessionStore = create<SessionState>((set) => ({
  profile: null,
  business: null,
  businessId: null,
  role: null,
  isLoading: true,
  setSession: (profile, business) =>
    set({ profile, business, businessId: profile.business_id, role: profile.role, isLoading: false }),
  clear: () =>
    set({ profile: null, business: null, businessId: null, role: null, isLoading: false }),
  setLoading: (isLoading) => set({ isLoading }),
}))
