# Frontend — chat UI

React + TypeScript + Vite + react-router + shadcn/ui. A single-page chat against the Phase 3 API
([../api/main.py](../api/main.py)): the message list, the tool-call audit trail per answer, and a
sidebar of suggested questions (`src/components/chat/`).

## Local development

```bash
npm install
npm run dev
```

Talks to `http://localhost:8000` by default (`src/lib/config.ts`). The API key is entered in the UI
and kept only in this browser's `localStorage` — never bundled, never committed
([src/lib/api-key.ts](src/lib/api-key.ts)).

## Deployment

Built into a static bundle served by nginx ([Dockerfile](Dockerfile)), deployed as its own Azure
Container App reusing the same Terraform module as the backend
([../infra/live/dev/frontend-app](../infra/live/dev/frontend-app)). The backend URL is injected at
container *start* time, not baked into the build — see
[docker-entrypoint.sh](docker-entrypoint.sh) and [../infra/README.md](../infra/README.md).
