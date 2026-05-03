import type { FieldError, UseFormRegisterReturn } from 'react-hook-form'

interface Props {
  label: string
  registration: UseFormRegisterReturn
  error?: FieldError
  type?: string
  placeholder?: string
  className?: string
}

export default function FormField({ label, registration, error, type = 'text', placeholder, className }: Props) {
  return (
    <div className={className}>
      <label className="block text-sm font-medium text-text-muted mb-1">{label}</label>
      <input
        {...registration}
        type={type}
        placeholder={placeholder}
        className={`w-full px-3 py-2 bg-surface-light border rounded-lg text-sm text-text placeholder:text-text-muted/50 focus:outline-none focus:ring-2 focus:ring-primary/50 transition-default ${
          error ? 'border-danger' : 'border-border'
        }`}
      />
      {error && <p className="mt-1 text-xs text-danger">{error.message}</p>}
    </div>
  )
}
