import { createBrowserRouter, RouterProvider } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useAuthHydrator } from './hooks/useAuth'
import ProtectedRoute from './components/ProtectedRoute'
import Layout from './components/Layout'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import { lazy, Suspense } from 'react'

// Lazy-loaded pages (created in later phases)
const POSPage = lazy(() => import('./pages/pos/POSPage'))
const ProductsPage = lazy(() => import('./pages/catalog/ProductsPage'))
const ProductForm = lazy(() => import('./pages/catalog/ProductForm'))
const StockPage = lazy(() => import('./pages/inventory/StockPage'))
const PurchaseOrdersPage = lazy(() => import('./pages/inventory/PurchaseOrdersPage'))
const CalendarPage = lazy(() => import('./pages/appointments/CalendarPage'))
const AppointmentForm = lazy(() => import('./pages/appointments/AppointmentForm'))
const CustomersPage = lazy(() => import('./pages/customers/CustomersPage'))
const StaffLedger = lazy(() => import('./pages/admin/StaffLedger'))
const ExpensesPage = lazy(() => import('./pages/admin/ExpensesPage'))

const LazyFallback = () => (
  <div className="flex items-center justify-center p-12">
    <div className="w-6 h-6 border-2 border-primary border-t-transparent rounded-full animate-spin" />
  </div>
)

function SuspenseWrap({ children }: { children: React.ReactNode }) {
  return <Suspense fallback={<LazyFallback />}>{children}</Suspense>
}

const router = createBrowserRouter([
  { path: '/login', element: <Login /> },
  {
    element: <ProtectedRoute />,
    children: [
      {
        element: <Layout />,
        children: [
          { index: true, element: <Dashboard /> },
          // POS
          { path: 'pos', element: <SuspenseWrap><POSPage /></SuspenseWrap> },
          // Catalog
          { path: 'catalog', element: <SuspenseWrap><ProductsPage /></SuspenseWrap> },
          { path: 'catalog/new', element: <SuspenseWrap><ProductForm /></SuspenseWrap> },
          { path: 'catalog/:id/edit', element: <SuspenseWrap><ProductForm /></SuspenseWrap> },
          // Inventory
          { path: 'inventory', element: <SuspenseWrap><StockPage /></SuspenseWrap> },
          { path: 'inventory/purchase-orders', element: <SuspenseWrap><PurchaseOrdersPage /></SuspenseWrap> },
          // Appointments
          { path: 'appointments', element: <SuspenseWrap><CalendarPage /></SuspenseWrap> },
          { path: 'appointments/new', element: <SuspenseWrap><AppointmentForm /></SuspenseWrap> },
          { path: 'appointments/:id/edit', element: <SuspenseWrap><AppointmentForm /></SuspenseWrap> },
          // Customers
          { path: 'customers', element: <SuspenseWrap><CustomersPage /></SuspenseWrap> },
          // Admin
          { path: 'admin', element: <SuspenseWrap><StaffLedger /></SuspenseWrap> },
          { path: 'admin/expenses', element: <SuspenseWrap><ExpensesPage /></SuspenseWrap> },
        ],
      },
    ],
  },
])

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 1000 * 60 * 2, retry: 1 },
  },
})

function AuthHydrator({ children }: { children: React.ReactNode }) {
  useAuthHydrator()
  return <>{children}</>
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AuthHydrator>
        <RouterProvider router={router} />
      </AuthHydrator>
    </QueryClientProvider>
  )
}
