import { useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import { useSessionStore } from '../store/session.store'
import type { Profile, Business } from '../types/db'

async function fetchProfile(userId: string): Promise<{ profile: Profile; business: Business } | null> {
  console.log('[Auth] fetchProfile started for userId:', userId)
  try {
    const { data: profile, error: err1 } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single()
    
    console.log('[Auth] fetchProfile profiles query result:', { profile, err1 })
    if (!profile) return null

    const { data: business, error: err2 } = await supabase
      .from('businesses')
      .select('*')
      .eq('id', profile.business_id)
      .single()

    console.log('[Auth] fetchProfile businesses query result:', { business, err2 })
    if (!business) return null

    return { profile: profile as Profile, business: business as Business }
  } catch (error) {
    console.error('[Auth] fetchProfile threw an error:', error)
    return null
  }
}

export function useAuthHydrator() {
  const { setSession, clear, setLoading } = useSessionStore()

  useEffect(() => {
    let mounted = true
    setLoading(true)

    const handleSession = async (session: any) => {
      try {
        if (!session?.user) {
          if (mounted) clear()
          return
        }
        const result = await fetchProfile(session.user.id)
        if (!mounted) return
        if (result) {
          setSession(result.profile, result.business)
        } else {
          clear()
        }
      } catch (err) {
        console.error('[Auth] Session hydration error:', err)
        if (mounted) clear()
      }
    }

    supabase.auth.getSession().then(({ data: { session }, error }) => {
      if (error) console.error('[Auth] getSession error:', error)
      handleSession(session)
    })

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      handleSession(session)
    })

    return () => {
      mounted = false
      subscription.unsubscribe()
    }
  }, [setSession, clear, setLoading])
}

export function useAuth() {
  const { clear } = useSessionStore()

  const login = useCallback(async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
  }, [])

  const logout = useCallback(async () => {
    await supabase.auth.signOut()
    clear()
  }, [clear])

  return { login, logout }
}
