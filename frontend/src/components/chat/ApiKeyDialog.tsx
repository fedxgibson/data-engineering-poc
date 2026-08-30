import { type ChangeEvent, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { getApiKey, setApiKey } from '@/lib/api-key'

// Deliberately not a modal/portal component to keep the shadcn dependency
// surface small for a chat-only MVP -- an inline reveal is enough here.
export function ApiKeyDialog({ onSaved }: { onSaved: () => void }) {
  const [value, setValue] = useState(getApiKey())

  return (
    <div className="flex items-center gap-2">
      <Input
        type="password"
        placeholder="X-API-Key"
        value={value}
        onChange={(e: ChangeEvent<HTMLInputElement>) => setValue(e.target.value)}
        className="h-8 w-40 text-xs"
      />
      <Button
        size="sm"
        variant="secondary"
        onClick={() => {
          setApiKey(value)
          onSaved()
        }}
      >
        Save
      </Button>
    </div>
  )
}
