import { Component, Suspense, type ReactNode, type ErrorInfo } from 'react'

interface FallbackProps { error: Error; retry: () => void }

function ErrorFallback({ error, retry }: FallbackProps) {
  return (
    <div className="flex flex-col items-center justify-center gap-4 p-8 text-center">
      <div className="text-danger text-lg font-semibold">Something went wrong</div>
      <p className="text-text-muted text-sm max-w-md">{error.message}</p>
      <button onClick={retry} className="px-4 py-2 bg-primary hover:bg-primary-dark text-white rounded-lg text-sm transition-default">
        Try again
      </button>
    </div>
  )
}

function LoadingFallback() {
  return (
    <div className="flex items-center justify-center p-12">
      <div className="w-6 h-6 border-2 border-primary border-t-transparent rounded-full animate-spin" />
    </div>
  )
}

interface State { error: Error | null }
interface Props { children: ReactNode }

class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error) {
    return { error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[QueryBoundary]', error, info)
  }

  render() {
    if (this.state.error) {
      return <ErrorFallback error={this.state.error} retry={() => this.setState({ error: null })} />
    }
    return this.props.children
  }
}

/** Suspense + ErrorBoundary wrapper for TanStack Query pages */
export default function QueryBoundary({ children }: Props) {
  return (
    <ErrorBoundary>
      <Suspense fallback={<LoadingFallback />}>
        {children}
      </Suspense>
    </ErrorBoundary>
  )
}
