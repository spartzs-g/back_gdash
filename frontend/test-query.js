import { createClient } from '@supabase/supabase-js'
import dotenv from 'dotenv'
dotenv.config({ path: '.env' })

const supabase = createClient(process.env.VITE_SUPABASE_URL, process.env.VITE_SUPABASE_ANON_KEY)

async function run() {
  const { data, error } = await supabase.auth.signInWithPassword({ email: 'owner@test.com', password: 'password123' })
  const userId = data.session.user.id
  
  const { data: profile } = await supabase.from('profiles').select('*').eq('id', userId).single()
  console.log('Profile business_id:', profile.business_id)
  
  const { data: business, error: bizErr } = await supabase.from('businesses').select('*').eq('id', profile.business_id).single()
  console.log('Business result:', business, 'Error:', bizErr)
}

run()
