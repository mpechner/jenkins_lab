# Lab decisions — thought process

A narrative log of the engineering judgments that shaped this lab. Each section records the question, what was being weighed, and the choice — not just the outcome.

---

## Why this lab exists (the originating requirement)

**Problem:** Jenkins on the Docker plugin uses a *count-based* agent cap. That works fine when every build looks the same, but breaks down once you have heterogeneous workload classes — a 128 MiB cron-style bash job, a 2 GiB compile, and a 4 GiB multi-service system test all want to run concurrently. With a count cap, the scheduler has no way to reason about "this node has 8 GiB free, that one has 1 GiB" — it either over-packs and OOMs or under-packs and starves throughput.

**Adjacent need:** Multi-service system tests that spin up several services (app + db + cache + mock API), exercise them, and tear everything down — without contaminating other builds. The Docker-plugin model doesn't give you isolation primitives for that.

**Goal of the lab:** Demonstrate a Jenkins setup where:
1. Build agents run as Kubernetes pods, so the **k8s scheduler** places them by resource request across worker nodes.
2. Each integration-test build creates its own **ephemeral namespace**, deploys a stack, runs tests, tears down — properly isolated.
3. Lifecycle is bounded: a cleanup CronJob removes orphaned namespaces, RBAC is scoped, quotas cap blast radius.

**How the lab embodies this:**
- 3 worker nodes in kind so scheduling decisions are observable, not implicit.
- Pipelines 04/05/06 are the three workload classes (tiny-bash / compile / systemtest) — Milestone 8 runs them concurrently to show the scheduler doing what the count cap couldn't.
- Pipelines 02/03/06 demonstrate the dynamic-namespace pattern at progressively larger scopes.
- Pipeline 07 orchestrates the fan-out so the scheduler behavior is reproducible from a single click.

Every other decision below serves one of those goals.

---

## Readiness verification: structure vs. behavior

**Question:** "Is this ready to start and deploy?"

**Considered:** Reading every file and confirming references line up cluster-side seemed sufficient.

**Learned:** Structural review missed: a chart-breaking `controller.adminUser` rename, the Jenkins controller SA having no RBAC in the agent namespace, distroless `registry.k8s.io/kubectl` having no shell, `<<EOF` heredocs preserving leading whitespace, `ResourceQuota` requiring all pods to set requests/limits without a paired `LimitRange`. Each surfaced only on running.

**Choice:** Future readiness claims must be backed by exercising the path (`docker pull` + sanity-run image, `kubectl auth can-i --as=...`, an actual end-to-end build), not by reading files.

---

## bootstrap.sh as canonical entry point

**Question:** Should the README walk through `kind create cluster` directly, or always use `bootstrap.sh`?

**Considered:** Direct `kind` is more transparent for learning; `bootstrap.sh` is more robust for actual use.

**Choice:** Bootstrap is the canonical path. Milestones 1, 2, 4, 7 all describe what bootstrap already did + a verification command. Raw `kind create cluster` retained only as an "inspection without Jenkins" fallback note.

---

## No `bitnami/*` images, anywhere

**Question:** What's the policy on Bitnami images post-Broadcom relicensing?

**Considered:** Bitnami catalog is partly frozen, partly behind a paid subscription. Pulls may fail, return stale images, or hit subscription gates.

**Choice:** Treat any `bitnami/*` reference as a bug. Preference order: official upstream registry > Docker Hub Official Library > well-known org on Docker Hub > GHCR. Never `:latest`. For kubectl agent sidecars, `alpine/k8s:1.34.1` was verified end-to-end (shell + kubectl + helm). `registry.k8s.io/kubectl` was rejected for sidecar use because it's distroless.

---

## Image pulls: guardrails vs. infrastructure

**Question:** Should the Jenkinsfiles defend against transient image-pull failures (`retry(agentRetry())`, `slaveConnectTimeout`, post-failure `kubectl describe`)?

**Considered:**
- Pattern A: build defenses into every Jenkinsfile so engineers see and copy them.
- Pattern B: solve the problem at the cluster layer with a pull-through cache (Artifactory in production, AWS ECR pull-through cache for EKS), so Jenkinsfiles stay clean.

**Choice:** B is the production answer. For the lab, manual retry on the rare failure is acceptable — no boilerplate in the Jenkinsfiles. Documented the pull-through pattern in the Docker Hub creds section.

---

## Docker Hub credentials: optional and standalone

**Question:** Should bootstrap wire Docker Hub credentials, or should that be a separate step?

**Considered:** Auto-wiring on bootstrap is convenient but couples a security concern (credentials) to cluster setup. Most users won't need it.

**Choice:** `scripts/setup-dockerhub-creds.sh` is a standalone, optional follow-up to bootstrap. Documented inline with Milestone 1 (where a reader would naturally need it), not as a tail appendix. Bootstrap itself does nothing about Docker Hub.

---

## RBAC: two SAs, two scopes

**Question:** Where does the kubernetes-plugin's RBAC need to live?

**Learned:** The Jenkins **controller** runs as `jenkins:jenkins` (the chart's default SA) and is what creates agent pods in `jenkins-agents`. The chart only grants RBAC inside `jenkins`, so without an explicit binding, the controller can't list/create pods in the agent namespace.

**Choice:** Two distinct bindings:
- `jenkins-controller-agents-admin` — RoleBinding in `jenkins-agents` granting the controller SA `admin`.
- `jenkins-in-namespace-admin` + `jenkins-namespace-manager` — for the `jenkins-test-runner` SA used inside agent pods. Extended with `resourcequotas` + `limitranges` verbs because the built-in `admin` ClusterRole deliberately excludes those.

---

## ResourceQuota always with a LimitRange

**Question:** Pipeline 03 sets a `ResourceQuota`. Why did `kubectl run tests` fail with "must specify limits/requests"?

**Learned:** A `ResourceQuota` that tracks `requests.cpu`/`limits.cpu`/etc. forces every pod in the namespace to set those values. Without defaults, quick `kubectl run` invocations get rejected.

**Choice:** Always pair a `ResourceQuota` with a matching `LimitRange` that supplies default `request` and `limit` values. This is the documented Kubernetes pattern; quotas and ranges are designed to work together.

---

## Heredoc whitespace in `sh '''…'''`

**Question:** Why did multi-doc YAML in `cat <<EOF | kubectl apply -f -` fail at line 28?

**Learned:** Two whitespace-preserving layers: Groovy `'''…'''` keeps Jenkinsfile indentation; bash `<<EOF` (no dash) preserves it again. The YAML doc separator `---` only counts at column 0; indented, it becomes a string value.

**Choice:** Heredoc bodies are left-aligned to column 0, regardless of surrounding Groovy indentation. Explicit comments in the Jenkinsfiles call this out.

---

## Plugin update vs. workaround

**Question:** `ModelInterpreter.inDeclarativeAgent` NPE — fix the plugin or rewrite the pipeline?

**Considered:** Rewrote pipeline 01 in scripted form (`podTemplate { node(POD_LABEL) { ... } }`) as a workaround.

**Learned:** A plugin update (pipeline-model-definition was at 96% downloaded) was the actual fix.

**Choice:** Updated the plugin. Kept both pipeline forms as `01-hello-k8s.Jenkinsfile` (declarative, primary) and `01-hello-k8s-scripted.Jenkinsfile` (reference + fallback for similar plugin bugs).

---

## Parallel workload demo: orchestrator over inline duplication

**Question:** How to fan out pipelines 04/05/06 concurrently — one self-contained Jenkinsfile, or an orchestrator that triggers existing jobs?

**Considered:** Inline parallel keeps everything in one file; orchestrator avoids duplicating the three pod templates.

**Choice:** Orchestrator pattern (`07-parallel-workloads.Jenkinsfile`) using `parallel { build job: ... }`. It demonstrates Jenkins parent-child job orchestration cleanly and reuses the existing jobs. Documented in Milestone 8.

---

## Lessons captured for future sessions

**Question:** Should the project record session lessons, or rely on git history?

**Considered:** git history captures fixes-as-code but not the meta-lessons (verify before claiming, doc-with-code, registry hygiene). Those would re-emerge each session.

**Choice:** `.claude/memory/` directory in the project (in git), with sanitized lessons. Sanitization removed in-the-moment quotes so the artifact reads as architectural decision records, not a complaint log.
