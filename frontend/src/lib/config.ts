// Backend base URL, resolved in priority order:
// 1. window.__ENV__.API_URL -- injected at container start by
//    nginx/docker-entrypoint.sh in the deployed image (public/config.js).
// 2. VITE_API_URL -- baked in at build time, for local `npm run build` previews.
// 3. localhost:8000 -- the FastAPI dev server (api/main.py).
export function getApiUrl(): string {
  const runtime = window.__ENV__?.API_URL
  if (runtime) return runtime.replace(/\/$/, '')

  const buildTime = import.meta.env.VITE_API_URL as string | undefined
  if (buildTime) return buildTime.replace(/\/$/, '')

  return 'http://localhost:8000'
}
