---
name: Verify before claiming "this works"
description: Don't declare readiness from a structural file-read; exercise the actual path before claiming it works.
type: feedback
---

Don't say "this should work" or "this is ready" based on reading files. Exercise the actual path before claiming readiness.

**Why:** A round of "lab is ready"-type assurances missed several real bugs that an end-to-end run surfaced immediately: a chart-breaking `controller.adminUser` rename, the Jenkins controller SA missing RBAC in the agent namespace, distroless `registry.k8s.io/kubectl` having no shell (so `command:["sleep"]` failed at containerd), `<<EOF` heredocs preserving leading whitespace and breaking multi-doc YAML, and `ResourceQuota` requiring all pods to set requests/limits without a paired `LimitRange`. Each was a separate find-and-fix loop because readiness was claimed from structure, not behavior.

**How to apply:**
- For an image: `docker pull` and `docker run ... which sleep / which X` *before* committing it to a manifest.
- For a Helm chart: read its CHANGELOG / `deprecation.yaml` for renamed values; don't trust old docs.
- For a Jenkinsfile: trace through what happens after the obvious stage — quotas, post blocks, RBAC for the controller SA itself, heredoc whitespace, image entrypoints.
- For RBAC: `kubectl auth can-i ... --as=system:serviceaccount:NS:SA -n TARGET_NS` for every verb the pipeline needs. Don't assume the built-in `admin` ClusterRole covers everything (it excludes `resourcequotas` and `limitranges` deliberately).
- When end-to-end verification isn't possible, say so explicitly. List exactly what was checked and what wasn't, and predict the next likely failure points instead of pretending they don't exist.
