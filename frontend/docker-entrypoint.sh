#!/bin/sh
# Runtime config injection: one built image, backend URL supplied per
# environment via the API_URL env var (Azure Container Apps env vars,
# src/lib/config.ts). Dropped into /docker-entrypoint.d/, the official nginx
# image's own entrypoint runs every script there before starting nginx --
# no custom ENTRYPOINT needed, and no rebuild needed to point at a different
# backend.
set -eu

cat > /usr/share/nginx/html/config.js <<EOF
window.__ENV__ = {
  API_URL: "${API_URL:-}",
};
EOF
