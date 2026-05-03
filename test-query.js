import { createClient } from '@supabase/supabase-js'
import dotenv from 'dotenv'
dotenv.config({ path: 'frontend/.env' })

const supabase = createClient(process.env.VITE_SUPABASE_URL, process.env.VITE_SUPABASE_ANON_KEY)

async function run() {
  console.log('Logging in...')
  const { data, error } = await supabase.auth.signInWithPassword({ email: 'owner@test.com', password: 'password123' })
  if (error) {
    console.error('Login error:', error)
    return
  }
  
  const userId = data.session.user.id
  console.log('Logged in user:', userId)
  
  console.log('Fetching profile...')
  const p = await supabase.from('profiles').select('*').eq('id', userId).single()
  console.log('Profile result:', p)
}

run()
