---
name: Avoid bitnami/* container images
description: Bitnami images are off-limits post-Broadcom relicensing. Pick first-party or well-maintained alternatives.
type: feedback
---

Do not use `bitnami/*` Docker Hub images. Treat any existing `bitnami/*` reference as a bug to fix.

**Why:** Broadcom (post-VMware) relicensed the Bitnami container catalog: most free public images moved to a frozen "Bitnami Legacy" repo, and current secure images sit behind a paid subscription. Pulls may fail, return frozen old images, or hit subscription gates. Lab convention is to avoid them entirely.

**How to apply:**
- For `kubectl` images: prefer `alpine/k8s:<version>` (Docker Hub, has shell + kubectl + helm + jq, verified works as a Jenkins agent sidecar) or `rancher/kubectl:<version>` (kubectl-only). Avoid `registry.k8s.io/kubectl` for *agent sidecars* — it's distroless, no shell, fails `command:["sleep"]`. It's fine for one-shot kubectl runs only.
- For Helm: `alpine/helm:<version>` or `ghcr.io/helmfile/helmfile:<version>` (also bundles helm).
- For Postgres / Redis / Nginx / Maven / Bash / Python / Node: prefer Docker Hub Official Library (`postgres:16-alpine`, `redis:7-alpine`, `nginx:1.27-alpine`, etc.).
- Lab preference order: official upstream registry > Docker Hub Official Library > well-known org on Docker Hub > GHCR > anything else. AWS ECR / Artifactory pull-through caches are the production answer.
- Never pin `:latest`. Pin a version.
