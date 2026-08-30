import { getApiUrl } from '@/lib/config'

export interface ToolCallRecord {
  tool: string
  input: Record<string, unknown>
  output: unknown
}

export interface QueryResponse {
  answer: string
  tool_calls: ToolCallRecord[]
}

export class ApiError extends Error {
  status: number

  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

// Mirrors POST /query in api/main.py: natural-language question in, agent
// answer + the tool calls it made in, so the UI can show its work rather than
// asking the user to trust an unaudited answer (domain/06-security.md).
export async function askAgent(question: string, apiKey: string): Promise<QueryResponse> {
  const res = await fetch(`${getApiUrl()}/query`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': apiKey,
    },
    body: JSON.stringify({ question }),
  })

  if (!res.ok) {
    const body = await res.json().catch(() => null)
    throw new ApiError(body?.detail ?? `request failed with status ${res.status}`, res.status)
  }

  return res.json()
}
