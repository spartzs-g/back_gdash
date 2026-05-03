import type { ReactNode } from 'react'

export interface Column<T> {
  key: string
  label: string
  render?: (value: unknown, row: T) => ReactNode
}

interface Props<T> {
  columns: Column<T>[]
  data: T[]
  onRowClick?: (row: T) => void
  loading?: boolean
  emptyMessage?: string
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export default function DataTable<T extends Record<string, any>>({
  columns, data, onRowClick, loading, emptyMessage = 'No data found',
}: Props<T>) {
  if (loading) {
    return (
      <div className="flex justify-center p-8">
        <div className="w-6 h-6 border-2 border-primary border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  if (!data.length) {
    return <p className="text-center text-text-muted py-8">{emptyMessage}</p>
  }

  return (
    <div className="overflow-x-auto rounded-xl border border-border">
      <table className="w-full text-sm">
        <thead>
          <tr className="bg-surface-light text-text-muted text-left">
            {columns.map((col) => (
              <th key={col.key} className="px-4 py-3 font-medium whitespace-nowrap">{col.label}</th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-border">
          {data.map((row, i) => (
            <tr
              key={(row as Record<string, unknown>).id as string ?? i}
              onClick={() => onRowClick?.(row)}
              className={`hover:bg-surface-lighter transition-default ${onRowClick ? 'cursor-pointer' : ''}`}
            >
              {columns.map((col) => (
                <td key={col.key} className="px-4 py-3 whitespace-nowrap">
                  {col.render ? col.render(row[col.key], row) : String(row[col.key] ?? '—')}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
