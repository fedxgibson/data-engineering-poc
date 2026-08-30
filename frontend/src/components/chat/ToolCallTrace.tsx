import { useState } from 'react'
import type { ToolCallRecord } from '@/lib/api'

// Shows which tools the agent called for a given answer -- the audit trail
// domain/06-security.md argues for: never trust the text without being able
// to trace where each number came from.
export function ToolCallTrace({ calls }: { calls: ToolCallRecord[] }) {
  const [open, setOpen] = useState(false)
  if (calls.length === 0) return null

  return (
    <div className="mt-2 text-xs">
      <button
        onClick={() => setOpen(!open)}
        className="text-muted-foreground hover:text-foreground underline underline-offset-2"
      >
        {open ? 'Hide' : 'Show'} {calls.length} tool call{calls.length === 1 ? '' : 's'}
      </button>
      {open && (
        <div className="mt-2 space-y-2">
          {calls.map((call, i) => (
            <div key={i} className="rounded-md border bg-muted/40 p-2 font-mono">
              <div className="font-semibold text-foreground">{call.tool}</div>
              <div className="text-muted-foreground">in: {JSON.stringify(call.input)}</div>
              <div className="text-muted-foreground truncate">out: {JSON.stringify(call.output)}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
