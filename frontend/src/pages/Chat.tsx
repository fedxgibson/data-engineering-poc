import { type FormEvent, useRef, useState } from 'react'
import { ApiKeyDialog } from '@/components/chat/ApiKeyDialog'
import { SuggestedQuestions } from '@/components/chat/SuggestedQuestions'
import { ToolCallTrace } from '@/components/chat/ToolCallTrace'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ScrollArea } from '@/components/ui/scroll-area'
import { type ApiError, askAgent, type ToolCallRecord } from '@/lib/api'
import { getApiKey } from '@/lib/api-key'

interface Message {
  role: 'user' | 'assistant' | 'error'
  content: string
  toolCalls?: ToolCallRecord[]
}

export function Chat() {
  const [messages, setMessages] = useState<Message[]>([])
  const [question, setQuestion] = useState('')
  const [loading, setLoading] = useState(false)
  const [, forceUpdate] = useState(0)
  const bottomRef = useRef<HTMLDivElement>(null)

  // Accepts an explicit question so a click on a suggested question sends
  // that exact text immediately, rather than depending on a state update
  // to the input box landing before send() reads it.
  async function send(text?: string) {
    const q = (text ?? question).trim()
    if (!q || loading) return

    setMessages((prev) => [...prev, { role: 'user', content: q }])
    setQuestion('')
    setLoading(true)

    try {
      const apiKey = getApiKey()
      if (!apiKey) throw new Error('Set your API key above first.')

      const res = await askAgent(q, apiKey)
      setMessages((prev) => [
        ...prev,
        { role: 'assistant', content: res.answer, toolCalls: res.tool_calls },
      ])
    } catch (err) {
      const message = (err as ApiError | Error).message
      setMessages((prev) => [...prev, { role: 'error', content: message }])
    } finally {
      setLoading(false)
      setTimeout(() => bottomRef.current?.scrollIntoView({ behavior: 'smooth' }), 50)
    }
  }

  return (
    <div className="mx-auto flex h-svh max-w-4xl">
      <SuggestedQuestions onSelect={(q) => void send(q)} disabled={loading} />

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between border-b px-4 py-3">
          <div>
            <h1 className="text-sm font-semibold">Port Intelligence Agent</h1>
            <p className="text-xs text-muted-foreground">Aarhus AIS data, Aug 2025 (14-day window)</p>
          </div>
          <ApiKeyDialog onSaved={() => forceUpdate((n) => n + 1)} />
        </header>

        <ScrollArea className="flex-1 px-4">
          <div className="flex flex-col gap-3 py-4">
            {messages.length === 0 && (
              <p className="text-sm text-muted-foreground">
                Ask about vessel traffic, port congestion, or a specific ship's history -- or pick a
                suggestion on the left.
              </p>
            )}
            {messages.map((m, i) => (
              <div
                key={i}
                className={`max-w-[85%] rounded-lg px-3 py-2 text-sm ${
                  m.role === 'user'
                    ? 'ml-auto bg-primary text-primary-foreground'
                    : m.role === 'error'
                      ? 'bg-destructive/10 text-destructive'
                      : 'bg-muted'
                }`}
              >
                <p className="whitespace-pre-wrap">{m.content}</p>
                {m.toolCalls && <ToolCallTrace calls={m.toolCalls} />}
              </div>
            ))}
            {loading && <p className="text-sm text-muted-foreground">Thinking…</p>}
            <div ref={bottomRef} />
          </div>
        </ScrollArea>

        <form
          className="flex gap-2 border-t p-3"
          onSubmit={(e: FormEvent) => {
            e.preventDefault()
            void send()
          }}
        >
          <Input
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            placeholder="Which vessels are currently in the Port of Aarhus?"
            disabled={loading}
          />
          <Button type="submit" disabled={loading || !question.trim()}>
            Send
          </Button>
        </form>
      </div>
    </div>
  )
}
