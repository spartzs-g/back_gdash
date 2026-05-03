import { Navigate, Outlet } from 'react-router-dom'
import { useSessionStore } from '../store/session.store'

export default function ProtectedRoute() {
  const { profile, isLoading } = useSessionStore()

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  if (!profile) return <Navigate to="/login" replace />

  return <Outlet />
}
