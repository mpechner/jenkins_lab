# Jenkins + Kubernetes Lab (Mac + Docker Desktop + kind)

A hands-on lab to build a Jenkins CI system that runs jobs as Kubernetes pods,
with dynamic per-build namespaces for multi-service integration tests.

**Target environment:** macOS, Docker Desktop, `kind` for Kubernetes.

---

## Lab goals

By the end, you'll have:

1. A multi-node `kind` cluster running on your Mac
2. Jenkins installed in the cluster via Helm
3. The Kubernetes plugin configured to run build agents as pods
4. A pipeline that spins up a dynamic namespace per build
5. A multi-service test stack deployed into that namespace via Helm
6. Proper RBAC, resource quotas, and automatic cleanup

Each milestone is independently verifiable. Don't move on until the previous one works.

---

## Prerequisites

You'll install these in Milestone 0. Listed here so you know what's coming.

- Docker Desktop (you have this)
- Homebrew
- `kind` — Kubernetes in Docker
- `kubectl` — Kubernetes CLI
- `helm` — Kubernetes package manager
- `jq` — JSON processor (used in scripts)

**Resource planning:** Docker Desktop needs at least 8 GB RAM allocated
(Settings → Resources). 12 GB is more comfortable. Check current allocation
before starting.

---

## Milestone 0 — Install tools

```bash
# Install CLI tools
brew install kind kubectl helm jq

# Verify
kind --version         # kind v0.23+ recommended
kubectl version --client
helm version
docker version         # confirm Docker Desktop is running
```

Bump Docker Desktop memory if needed: **Docker Desktop → Settings → Resources → Memory → 8–12 GB**, then Apply & Restart.

**Checkpoint:** all four tools report versions, `docker version` shows both Client and Server.

---

## Milestone 1 — Create a multi-node kind cluster

### Why multi-node?

A single-node cluster can't show you scheduling decisions. With 3 workers,
you'll see pods spread across nodes, which is the whole point of using k8s
for a build farm.

### Create the cluster

See `cluster/kind-config.yaml` in this lab. It defines:

- 1 control-plane node
- 3 worker nodes
- Port mappings so you can reach Jenkins from your Mac

Use the bootstrap script — it creates the cluster, applies RBAC, installs
Jenkins, and (if a backup exists) restores prior state in one shot:

```bash
./scripts/bootstrap.sh

# Then verify the cluster:
kubectl cluster-info --context kind-jenkins-lab
kubectl get nodes
```

You should see 4 nodes, all `Ready`.

> If you only want the bare cluster (no Jenkins yet) for inspection, you can
> run `kind create cluster --name jenkins-lab --config cluster/kind-config.yaml`
> directly — but for the lab, prefer `./scripts/bootstrap.sh`, which is what
> Milestones 2, 4, and 7 also depend on.

### Optional: wire Docker Hub credentials

Image pulls from inside the kind cluster are **anonymous** by default — your
host's `docker login` doesn't propagate into the kind nodes' containerd, so
pulls are subject to the strict Docker Hub per-IP rate limit (100 / 6 h).
For a lab you usually won't hit it, but if you do, wire a Docker Hub Personal
Access Token into the agent ServiceAccount:

```bash
DOCKERHUB_USERNAME=yourname \
DOCKERHUB_TOKEN=dckr_pat_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  ./scripts/setup-dockerhub-creds.sh
```

What it does:

- Creates a `dockerhub` Secret (type `dockerconfigjson`) in `jenkins-agents`
- Patches `serviceaccount/jenkins-test-runner` to attach it as `imagePullSecrets`

Every pipeline agent pod (which runs as `jenkins-test-runner`) authenticates
from then on. No Jenkinsfile changes. Idempotent — re-run to rotate the token.

This step is **optional** and intentionally not part of `bootstrap.sh`. Run
it once between bootstrap and your first pipeline run if you need it.

In production you'd avoid this entirely by putting a pull-through cache
(Artifactory, Harbor, or AWS ECR pull-through cache for EKS) in front of
upstream registries.

### Useful context commands

```bash
kubectl config current-context              # should show kind-jenkins-lab
kubectl config use-context kind-jenkins-lab # switch back to it anytime
```

**Checkpoint:** `kubectl get nodes` shows 1 control-plane + 3 workers, all Ready.

---

## Milestone 2 — Verify Jenkins is up

### Why in-cluster Jenkins?

Running Jenkins inside the same cluster it schedules jobs on makes networking
trivial (pods reach the controller by service name) and mirrors a realistic
production setup.

### What bootstrap.sh already did

`./scripts/bootstrap.sh` (Milestone 1) used the `jenkins` Helm chart with
`jenkins/values.yaml` to install the controller into the `jenkins` namespace.
Modest resources, NodePort `30080`, and kind's port mapping forwards it to
`localhost:8080` on your Mac.

If you want to re-run the install by hand (e.g. after editing values), the
script's idempotent — just run it again.

### Verify the controller is up

```bash
kubectl get pods -n jenkins -w
```

Wait for `jenkins-0` to be `Running` and `2/2 Ready` (takes 2–3 minutes on
first pull).

### Get the admin password and log in

`bootstrap.sh` prints the password at the end. To fetch it again later:

```bash
kubectl get secret -n jenkins jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d; echo
```

Open http://localhost:8080 and log in as `admin` with that password.

**Checkpoint:** Jenkins UI loads, you can log in, the Dashboard is empty.

---

## Milestone 3 — Verify the kubernetes-plugin works

The Helm chart pre-installs and pre-configures the kubernetes-plugin. You just
need to run a trivial pipeline to confirm it can create agent pods.

### Create the first pipeline

In the Jenkins UI:
1. **New Item** → name: `hello-k8s` → **Pipeline** → OK
2. Scroll to **Pipeline** section → **Definition: Pipeline script**
3. Paste the contents of `pipelines/01-hello-k8s.Jenkinsfile`
4. Save → **Build Now**

### What to watch

While the build runs, in another terminal:

```bash
kubectl get pods -n jenkins -w
```

You should see a pod named something like `hello-k8s-1-abc-xyz` appear,
complete the build, and disappear. That's the agent pod being dynamically
provisioned.

**Checkpoint:** build succeeds (green), console output shows `kubectl get nodes`
listing your 4 nodes, the agent pod is gone after the build.

---

## Milestone 4 — RBAC for namespace management

### What bootstrap.sh already did

Before jobs can create namespaces, the agent pod's ServiceAccount needs
permission. `./scripts/bootstrap.sh` already applied `rbac/namespace-manager.yaml`,
which creates:

- Namespace `jenkins-agents` (where agent pods run)
- ServiceAccount `jenkins-test-runner` in that namespace
- ClusterRole allowing namespace create/delete/label
- A binding granting in-namespace admin so jobs can deploy into the
  ephemeral namespaces they create

If you edit `rbac/namespace-manager.yaml`, re-apply with:

```bash
kubectl apply -f rbac/namespace-manager.yaml
```

The pre-installed Jenkins kubernetes-cloud config (`kubernetes-agents`, set via
JCasC in `jenkins/values.yaml`) already points agents at the `jenkins-agents`
namespace. Pipelines can also reference the SA directly in their pod spec —
which is what the next pipeline does.

**Checkpoint:**
```bash
kubectl get sa -n jenkins-agents jenkins-test-runner
kubectl get clusterrole jenkins-namespace-manager
```
Both return without errors.

---

## Milestone 5 — Pipeline that creates its own namespace

Create a new pipeline `dynamic-namespace` using
`pipelines/02-dynamic-namespace.Jenkinsfile`.

This pipeline:
1. Runs an agent pod with the `jenkins-test-runner` SA
2. Creates `test-build-${BUILD_NUMBER}` namespace, labeled `ephemeral=true`
3. Deploys a simple nginx into it
4. Verifies it's reachable (pod-to-pod)
5. Deletes the namespace in `post { always }`

Run it. In parallel, watch:

```bash
watch -n1 'kubectl get ns | grep -E "test-|NAME"'
```

You'll see the namespace appear, then disappear.

**Checkpoint:** build succeeds, namespace is gone after build. Run it 3 times —
each run should produce a unique namespace name and clean up.

---

## Milestone 6 — Multi-service system test

Now the real thing: deploy a stack of services into a per-build namespace and
run tests against it.

The lab includes a minimal Helm chart at `charts/test-stack/` with:

- `app` — a tiny web service (nginx with custom config)
- `redis` — cache
- `postgres` — database
- `mock-api` — a second nginx pretending to be an external API

Create a new pipeline `system-test` using
`pipelines/03-system-test.Jenkinsfile`.

It:
1. Creates namespace, applies a ResourceQuota
2. `helm install`s the stack, waits for readiness
3. Runs a test pod that curls each service
4. Collects logs on failure
5. Tears everything down

**Checkpoint:** build succeeds, you see all 4 services come up, the test pod
verifies them, and everything is cleaned up.

---

## Milestone 7 — Cleanup safety net

### What bootstrap.sh already did

`./scripts/bootstrap.sh` applied `cleanup/cleanup-cronjob.yaml`, which installs
a CronJob that deletes orphaned `ephemeral=true` namespaces older than 1 hour
(tunable via `THRESHOLD_SECONDS` in the manifest). Jobs crash, pipelines get
cancelled — this keeps the cluster tidy.

If you tune the threshold or schedule, re-apply with:

```bash
kubectl apply -f cleanup/cleanup-cronjob.yaml
```

Verify it's installed and run it on demand:

```bash
kubectl get cronjob -n jenkins-agents
kubectl create job --from=cronjob/cleanup-stale-namespaces manual-test-1 -n jenkins-agents
kubectl logs -n jenkins-agents job/manual-test-1
```

**Checkpoint:** CronJob exists and a manual run executes without errors (it
won't find anything to delete yet, which is correct).

---

## Milestone 8 — Heterogeneous workload classes

Add pipelines that demonstrate different resource classes (the original
motivating problem):

- `pipelines/04-tiny-bash.Jenkinsfile` — 128Mi / 100m CPU
- `pipelines/05-compile.Jenkinsfile` — 2Gi / 1 CPU
- `pipelines/06-systemtest.Jenkinsfile` — 4Gi / 2 CPU, uses dynamic namespace

Create three Jenkins Pipeline jobs from these files. Suggested names
(matched by pipeline 07 below): `tiny-bash`, `compile`, `systemtest`.

### Run them concurrently

Two ways to fan out:

**A. Manually** — open three browser tabs and click **Build Now** on each
of the three jobs.

**B. Orchestrator pipeline (recommended)** — create a fourth Pipeline job
(e.g. `parallel-workloads`) from `pipelines/07-parallel-workloads.Jenkinsfile`.
That job uses `parallel { ... }` + `build job: '<name>'` to trigger all
three children at the same time and waits for them to finish. Adjust the
child job names in 07 if you named yours differently.

While the parallel build runs, watch in another terminal:

```bash
watch -n1 'kubectl get pods -A -o wide | grep -E "NAMESPACE|jenkins-agents|systest-"'
```

You'll see pods scheduled across the 3 worker nodes based on resource
requests. That's the k8s scheduler doing its job — the thing you couldn't get
with the Docker plugin's count-based cap.

**Checkpoint:** 3 different resource shapes run concurrently, scheduled across
multiple nodes.

---

## Multi-session workflow (backup & restore)

The Helm chart stores all Jenkins state (jobs, config, credentials,
plugins, build history) in a PersistentVolumeClaim. When you delete the
kind cluster, that PVC goes with it — so **without a backup, every session
starts from scratch**.

The lab includes backup/restore scripts that preserve state across `kind
delete` cycles.

### Start of day

```bash
./scripts/bootstrap.sh
```

If `./backups/jenkins-latest.tar.gz` exists, this automatically restores it.
Otherwise, it does a clean install.

### End of day

```bash
./scripts/teardown.sh
```

This **backs up Jenkins before destroying the cluster**, then deletes it.
Your state is saved to `./backups/jenkins-<timestamp>.tar.gz` with a
`jenkins-latest.tar.gz` symlink.

### Backup on demand

```bash
./scripts/backup-jenkins.sh              # cold: quiesces Jenkins, consistent
./scripts/backup-jenkins.sh hot          # hot: no downtime, slight inconsistency risk
```

Cold backups scale the controller to 0 during the backup (~30 seconds of
Jenkins downtime). Safer. Use this before destructive experiments.

### Start fresh (skip existing backup)

```bash
./scripts/bootstrap.sh --fresh
```

### Skip the backup on teardown

```bash
./scripts/teardown.sh --no-backup
```

### What gets backed up

Everything under `/var/jenkins_home`:

- Job definitions and build history
- Credentials and secrets
- Installed plugins
- User accounts and permissions
- Global config and JCasC-applied config

Typical backup size for the lab: **100–500 MB** (mostly plugins). Grows
with build history.

### Important caveats

- **Don't commit backups to git.** They contain credentials. The included
  `.gitignore` excludes `backups/`.
- **Restoring into a different Jenkins version is risky.** If the Helm chart
  pins a newer Jenkins image than your backup was taken with, startup may
  fail. Pin `controller.tag` in `jenkins/values.yaml` if you care.
- **Restore overwrites everything.** The restore script wipes the PVC
  contents before untarring. There's no merge.
- **Plugin state vs. plugin list.** The backup contains the plugins you had
  installed. If `jenkins/values.yaml` also lists plugins, the Helm chart
  will reconcile on startup — usually fine but can cause startup noise.

---

## Teardown

```bash
./scripts/teardown.sh                  # backup + destroy (default)
./scripts/teardown.sh --no-backup      # just destroy
./scripts/teardown.sh --backup-only    # just backup, leave cluster running
```

Or raw: `kind delete cluster --name jenkins-lab`. This skips the backup.

---

## Troubleshooting

### Jenkins pod won't start

```bash
kubectl describe pod -n jenkins -l app.kubernetes.io/component=jenkins-controller
kubectl logs -n jenkins -l app.kubernetes.io/component=jenkins-controller -c jenkins
```

Usually either OOM (bump Docker Desktop memory) or image pull taking a while.

### Agent pod stuck in `Pending`

```bash
kubectl describe pod -n jenkins-agents <agent-pod-name>
```

Look at Events. Common causes: insufficient CPU/memory on any node, image
pull errors, SA doesn't exist.

### Jenkins can't create agent pods ("403 Forbidden")

The Jenkins controller's own SA needs permission. The Helm chart sets this
up by default — verify with:

```bash
kubectl get rolebinding -n jenkins
kubectl auth can-i create pods --as=system:serviceaccount:jenkins:jenkins -n jenkins
```

### Pipeline fails with "namespaces is forbidden"

The agent pod's SA isn't `jenkins-test-runner`, or the RBAC wasn't applied.
Check `serviceAccountName` in the pod yaml block of your Jenkinsfile.

### Port 8080 already in use

Edit `cluster/kind-config.yaml` and change `hostPort: 8080` to something
free like `18080`. Recreate the cluster.

### Everything is slow

Docker Desktop RAM is probably too low. Give it 12 GB. Also check:

```bash
docker stats
```

to see if the kind nodes are memory-pressured.

---

## What to explore after the lab

Once the core lab works, these are natural next steps:

- **Kaniko** for building container images inside pipelines (no privileged Docker)
- **Kyverno** policies to enforce that only `ephemeral=true` namespaces can be created by Jenkins
- **Configuration as Code (JCasC)** to manage Jenkins config via Git instead of clicking
- **Shared libraries** to hide the namespace-creation boilerplate behind a one-liner
- **Multi-branch pipelines** to run these per PR
- **Monitoring** via kube-prometheus-stack to see pod resource usage in Grafana

Each is a day of work and pays off quickly.

---

## File map

```
jenkins_lab/
├── README.md                              ← this file
├── .gitignore                             ← excludes backups/
├── scripts/
│   ├── bootstrap.sh                       ← set up cluster (auto-restores backup)
│   ├── teardown.sh                        ← backup + delete cluster
│   ├── backup-jenkins.sh                  ← tar PVC contents to ./backups/
│   ├── restore-jenkins.sh                 ← untar a backup into fresh PVC
│   └── setup-dockerhub-creds.sh           ← optional: wire Docker Hub PAT into agent SA
├── cluster/
│   └── kind-config.yaml                   ← multi-node cluster definition
├── jenkins/
│   └── values.yaml                        ← Helm values for Jenkins
├── rbac/
│   └── namespace-manager.yaml             ← SA + ClusterRole for jobs
├── pipelines/
│   ├── 01-hello-k8s.Jenkinsfile           ← smoke test
│   ├── 02-dynamic-namespace.Jenkinsfile   ← per-build namespace
│   ├── 03-system-test.Jenkinsfile         ← multi-service stack
│   ├── 04-tiny-bash.Jenkinsfile           ← 128Mi class
│   ├── 05-compile.Jenkinsfile             ← 2Gi class
│   ├── 06-systemtest.Jenkinsfile          ← 4Gi class
│   └── 07-parallel-workloads.Jenkinsfile  ← orchestrator: runs 04+05+06 in parallel
├── charts/
│   └── test-stack/                        ← Helm chart with 4 services
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── app.yaml
│           ├── redis.yaml
│           ├── postgres.yaml
│           └── mock-api.yaml
├── backups/                               ← git-ignored; holds *.tar.gz
└── cleanup/
    └── cleanup-cronjob.yaml               ← orphan namespace janitor
```
