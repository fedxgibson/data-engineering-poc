// The API key is never bundled into the app (it's a secret, domain/06-security.md)
// -- the user pastes it in the UI and it's kept only in this browser's
// localStorage, read fresh on every request.
const STORAGE_KEY = 'port-intel-api-key'

export function getApiKey(): string {
  return localStorage.getItem(STORAGE_KEY) ?? ''
}

export function setApiKey(key: string): void {
  if (key) localStorage.setItem(STORAGE_KEY, key)
  else localStorage.removeItem(STORAGE_KEY)
}
