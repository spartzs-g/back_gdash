const statusColors: Record<string, string> = {
  // Sales
  draft:              'bg-gray-500/20 text-gray-300',
  confirmed:          'bg-blue-500/20 text-blue-300',
  completed:          'bg-success/20 text-success',
  cancelled:          'bg-danger/20 text-danger',
  refunded:           'bg-warning/20 text-warning',
  // Appointments
  scheduled:          'bg-blue-500/20 text-blue-300',
  in_progress:        'bg-accent/20 text-accent',
  no_show:            'bg-gray-500/20 text-gray-400',
  // PO
  ordered:            'bg-blue-500/20 text-blue-300',
  partially_received: 'bg-warning/20 text-warning',
  received:           'bg-success/20 text-success',
  // Commission
  pending:            'bg-warning/20 text-warning',
  paid:               'bg-success/20 text-success',
  // Payments
  failed:             'bg-danger/20 text-danger',
  // Inventory
  active:             'bg-success/20 text-success',
  inactive:           'bg-gray-500/20 text-gray-400',
}

export default function StatusBadge({ status }: { status: string }) {
  const cls = statusColors[status] ?? 'bg-gray-500/20 text-gray-300'
  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${cls}`}>
      {status.replace(/_/g, ' ')}
    </span>
  )
}
