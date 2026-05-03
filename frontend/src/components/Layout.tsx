import { NavLink, Outlet, useLocation } from 'react-router-dom'
import { useState, useEffect } from 'react'
import { useSessionStore } from '../store/session.store'
import { useAuth } from '../hooks/useAuth'
import { BUSINESS_MODULES } from '../types/db'

const allNavItems = [
  { path: '/',              label: 'Dashboard',    icon: '📊', module: 'reports' },
  { path: '/pos',           label: 'POS',          icon: '🛒', module: 'pos' },
  { path: '/catalog',       label: 'Catalog',      icon: '📦', module: 'catalog' },
  { path: '/inventory',     label: 'Inventory',    icon: '📋', module: 'inventory', subItems: [
    { path: '/inventory', label: 'Stock Overview' },
    { path: '/inventory/purchase-orders', label: 'Purchase Orders' },
  ] },
  { path: '/appointments',  label: 'Appointments', icon: '📅', module: 'appointments' },
  { path: '/customers',     label: 'Customers',    icon: '👥', module: 'customers' },
  { path: '/admin',         label: 'Admin',        icon: '⚙️', module: 'admin', subItems: [
    { path: '/admin', label: 'Commissions' },
    { path: '/admin/expenses', label: 'Expenses' },
    { path: '/admin/payments', label: 'Payments' },
  ] },
]

export default function Layout() {
  const { business, profile } = useSessionStore()
  const { logout } = useAuth()
  const location = useLocation()
  const businessType = business?.type ?? 'other'
  const enabledModules = BUSINESS_MODULES[businessType]
  const navItems = allNavItems.filter((item) => enabledModules.includes(item.module))

  const [openMenus, setOpenMenus] = useState<Record<string, boolean>>({})

  useEffect(() => {
    const current = navItems.find(item => item.subItems && (location.pathname === item.path || location.pathname.startsWith(item.path + '/')))
    if (current) {
      setOpenMenus(prev => {
        if (prev[current.path]) return prev
        return { ...prev, [current.path]: true }
      })
    }
  }, [location.pathname])

  const toggleMenu = (path: string) => {
    setOpenMenus(prev => ({ ...prev, [path]: !prev[path] }))
  }

  return (
    <div className="flex min-h-screen">
      {/* Sidebar */}
      <aside className="w-60 shrink-0 bg-surface-card border-r border-border flex flex-col">
        {/* Logo / Business Name */}
        <div className="p-5 border-b border-border">
          <h1 className="text-lg font-bold bg-gradient-to-r from-primary-light to-accent bg-clip-text text-transparent">
            {business?.name ?? 'GDash POS'}
          </h1>
          <p className="text-xs text-text-muted mt-1 capitalize">{businessType} • {profile?.role}</p>
        </div>

        {/* Nav Links */}
        <nav className="flex-1 p-3 space-y-1 overflow-y-auto">
          {navItems.map((item) => (
            <div key={item.path}>
              {item.subItems ? (
                <>
                  <div
                    onClick={() => toggleMenu(item.path)}
                    className={`flex items-center justify-between px-3 py-2.5 rounded-lg text-sm cursor-pointer transition-default ${
                      (location.pathname === item.path || location.pathname.startsWith(item.path + '/')) && !openMenus[item.path]
                        ? 'bg-primary/15 text-primary-light font-medium'
                        : 'text-text-muted hover:bg-surface-lighter hover:text-text'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <span className="text-base">{item.icon}</span>
                      {item.label}
                    </div>
                    <span className="text-xs opacity-50">{openMenus[item.path] ? '▲' : '▼'}</span>
                  </div>
                  {openMenus[item.path] && (
                    <div className="ml-9 mt-1 space-y-1">
                      {item.subItems.map(sub => (
                        <NavLink
                          key={sub.path}
                          to={sub.path}
                          end={sub.path === item.path || sub.path === '/'}
                          className={({ isActive }) =>
                            `block px-3 py-2 rounded-lg text-sm transition-default ${
                              isActive
                                ? 'bg-primary/15 text-primary-light font-medium'
                                : 'text-text-muted hover:bg-surface-lighter hover:text-text'
                            }`
                          }
                        >
                          {sub.label}
                        </NavLink>
                      ))}
                    </div>
                  )}
                </>
              ) : (
                <NavLink
                  to={item.path}
                  end={item.path === '/'}
                  className={({ isActive }) =>
                    `flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-default ${
                      isActive
                        ? 'bg-primary/15 text-primary-light font-medium'
                        : 'text-text-muted hover:bg-surface-lighter hover:text-text'
                    }`
                  }
                >
                  <span className="text-base">{item.icon}</span>
                  {item.label}
                </NavLink>
              )}
            </div>
          ))}
        </nav>

        {/* User / Logout */}
        <div className="p-4 border-t border-border">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center text-sm text-primary-light font-semibold">
              {profile?.full_name?.[0]?.toUpperCase() ?? '?'}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium truncate">{profile?.full_name ?? 'User'}</p>
              <p className="text-xs text-text-muted capitalize">{profile?.role}</p>
            </div>
            <button onClick={logout} title="Logout" className="text-text-muted hover:text-danger transition-default">
              <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
              </svg>
            </button>
          </div>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 overflow-y-auto">
        <div className="p-6 max-w-7xl mx-auto">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
