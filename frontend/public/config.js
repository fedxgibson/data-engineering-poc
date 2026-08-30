// Runtime config, read by src/lib/config.ts before import.meta.env.
//
// This file is intentionally checked in with an empty API_URL: locally it
// means "fall back to VITE_API_URL / localhost:8000" (see config.ts). In the
// deployed image, the container's nginx entrypoint (nginx/docker-entrypoint.sh)
// overwrites this exact file at startup with the real backend URL, resolved
// via Terragrunt's dependency block on the backend container app -- one image
// works across environments without a rebuild.
window.__ENV__ = {
  API_URL: "",
};
