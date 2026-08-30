import { Button } from '@/components/ui/button'

// Curated from eval/eval_set.yaml -- real questions the agent answers well
// with a single tool call each, one per tool (port_lookup, port_congestion,
// vessel_history), so a first-time user sees the full capability surface.
const SUGGESTED_QUESTIONS = [
  'What is the port_id for Aarhus?',
  'How was congestion in Aarhus between 2025-02-13 and 2025-02-26?',
  "What's the call history for the vessel with MMSI 249637000?",
  "How long was the vessel MMSI 219036000's last call at Aarhus?",
] as const

export function SuggestedQuestions({
  onSelect,
  disabled,
}: {
  onSelect: (question: string) => void
  disabled?: boolean
}) {
  return (
    <aside className="hidden w-56 shrink-0 flex-col border-r px-3 py-4 sm:flex">
      <h2 className="mb-2 text-xs font-semibold text-muted-foreground uppercase tracking-wide">
        Suggested questions
      </h2>
      <div className="flex flex-col gap-1.5">
        {SUGGESTED_QUESTIONS.map((q) => (
          <Button
            key={q}
            variant="ghost"
            disabled={disabled}
            onClick={() => onSelect(q)}
            className="h-auto justify-start whitespace-normal text-left text-xs font-normal"
          >
            {q}
          </Button>
        ))}
      </div>
    </aside>
  )
}
