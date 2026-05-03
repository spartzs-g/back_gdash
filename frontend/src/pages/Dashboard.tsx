import { useQuery } from '@tanstack/react-query'
import { useSessionStore } from '../store/session.store'
import { getDailySales, getNetProfit, getLowStockCount, getTopProducts, getCommissionSummary } from '../services/admin.service'

function MetricCard({ label, value, sub, color = 'text-primary-light' }: { label: string; value: string; sub?: string; color?: string }) {
  return (
    <div className="glass p-5">
      <p className="text-sm text-text-muted mb-1">{label}</p>
      <p className={`text-2xl font-bold ${color}`}>{value}</p>
      {sub && <p className="text-xs text-text-muted mt-1">{sub}</p>}
    </div>
  )
}

export default function Dashboard() {
  const { businessId, business } = useSessionStore()

  const { data: sales = [] } = useQuery({
    queryKey: ['daily_sales', businessId],
    queryFn: () => getDailySales(businessId!, 7),
    enabled: !!businessId,
  })

  const { data: profit = [] } = useQuery({
    queryKey: ['net_profit', businessId],
    queryFn: () => getNetProfit(businessId!, 7),
    enabled: !!businessId,
  })

  const { data: lowStock = 0 } = useQuery({
    queryKey: ['low_stock_count', businessId],
    queryFn: () => getLowStockCount(businessId!),
    enabled: !!businessId,
  })

  const { data: topProducts = [] } = useQuery({
    queryKey: ['top_products', businessId],
    queryFn: () => {
      const end = new Date().toISOString()
      const start = new Date(Date.now() - 30 * 86400000).toISOString()
      return getTopProducts(businessId!, start, end)
    },
    enabled: !!businessId,
  })

  const { data: commissions = [] } = useQuery({
    queryKey: ['commission_summary', businessId],
    queryFn: () => getCommissionSummary(businessId!),
    enabled: !!businessId,
  })

  const today = sales[0]
  const todayProfit = profit[0]
  const pendingCommission = commissions.reduce((s, c) => s + Number(c.pending_commission), 0)

  return (
    <div>
      <h1 className="text-2xl font-bold mb-1">Dashboard</h1>
      <p className="text-sm text-text-muted mb-6">{business?.name} — {new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</p>

      {/* Metric Cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <MetricCard label="Today's Revenue" value={today ? `₹${Number(today.total_revenue).toLocaleString()}` : '₹0'} sub={today ? `${today.total_orders} orders` : 'No orders yet'} color="text-success" />
        <MetricCard label="Avg Ticket" value={today ? `₹${Number(today.avg_order_value).toFixed(0)}` : '—'} />
        <MetricCard label="Net Profit (Today)" value={todayProfit ? `₹${Number(todayProfit.net_profit).toLocaleString()}` : '—'} color={todayProfit && Number(todayProfit.net_profit) >= 0 ? 'text-success' : 'text-danger'} />
        <MetricCard label="Low Stock Alerts" value={String(lowStock)} color={lowStock > 0 ? 'text-warning' : 'text-success'} sub={lowStock > 0 ? 'Items need reorder' : 'All stocked'} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Top Products */}
        <div className="glass p-5">
          <h2 className="text-lg font-semibold mb-4">Top Products (30 days)</h2>
          {topProducts.length === 0 ? (
            <p className="text-sm text-text-muted">No sales data yet</p>
          ) : (
            <div className="space-y-2">
              {topProducts.map((p, i) => (
                <div key={p.product_id} className="flex items-center gap-3">
                  <span className="text-xs text-text-muted w-6 text-right">{i + 1}.</span>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{p.product_name}</p>
                    <div className="w-full bg-surface-lighter rounded-full h-1.5 mt-1">
                      <div
                        className="bg-primary rounded-full h-1.5 transition-all"
                        style={{ width: `${Math.min((Number(p.total_revenue) / Number(topProducts[0].total_revenue)) * 100, 100)}%` }}
                      />
                    </div>
                  </div>
                  <span className="text-sm font-medium text-primary-light shrink-0">₹{Number(p.total_revenue).toLocaleString()}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Recent Sales */}
        <div className="glass p-5">
          <h2 className="text-lg font-semibold mb-4">Sales (Last 7 Days)</h2>
          {sales.length === 0 ? (
            <p className="text-sm text-text-muted">No sales data yet</p>
          ) : (
            <div className="space-y-2">
              {sales.map((day) => (
                <div key={day.sale_date} className="flex items-center justify-between text-sm">
                  <span className="text-text-muted">{new Date(day.sale_date).toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short' })}</span>
                  <div className="flex gap-4">
                    <span>{day.total_orders} orders</span>
                    <span className="font-medium text-success">₹{Number(day.total_revenue).toLocaleString()}</span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Commission Pending */}
        <div className="glass p-5">
          <h2 className="text-lg font-semibold mb-4">Pending Commissions</h2>
          <p className="text-3xl font-bold text-warning mb-2">₹{pendingCommission.toLocaleString()}</p>
          <p className="text-xs text-text-muted">{commissions.length} staff members with commissions</p>
        </div>
      </div>
    </div>
  )
}
