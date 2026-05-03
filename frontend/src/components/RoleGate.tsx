import type { ReactNode } from 'react'
import { useSessionStore } from '../store/session.store'
import type { Profile } from '../types/db'

interface Props {
  allowedRoles: Profile['role'][]
  children: ReactNode
}

/** Hides children entirely if user role is not in allowedRoles. Never disables — always hides. */
export default function RoleGate({ allowedRoles, children }: Props) {
  const role = useSessionStore((s) => s.role)
  if (!role || !allowedRoles.includes(role)) return null
  return <>{children}</>
}
