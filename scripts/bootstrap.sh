#!/usr/bin/env bash
# Bootstrap the lab. Auto-restores from ./backups/jenkins-latest.tar.gz
# if present, so multiple sessions pick up where you left off.
#
# Usage:
#   ./scripts/bootstrap.sh                 # create cluster, restore if backup exists
#   ./scripts/bootstrap.sh --fresh         # ignore any backup, start clean
#
# Optional: to wire Docker Hub credentials into the agent SA, run
# ./scripts/setup-dockerhub-creds.sh separately after bootstrap.

set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER_NAME="jenkins-lab"
FRESH="false"

for arg in "$@"; do
  case "$arg" in
    --fresh)    FRESH="true" ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

echo "==> Checking prerequisites"
for cmd in docker kind kubectl helm jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: $cmd not found. Install with: brew install $cmd"
    exit 1
  }
done

echo "==> Creating kind cluster ($CLUSTER_NAME)"
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster already exists. Skipping creation."
else
  kind create cluster --name "$CLUSTER_NAME" --config cluster/kind-config.yaml
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

echo "==> Waiting for all nodes to be Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "==> Applying RBAC"
kubectl apply -f rbac/namespace-manager.yaml

echo "==> Installing Jenkins via Helm"
helm repo add jenkins https://charts.jenkins.io >/dev/null 2>&1 || true
helm repo update >/dev/null

kubectl get namespace jenkins >/dev/null 2>&1 || kubectl create namespace jenkins

# Decide: restore or fresh install?
BACKUP_FILE="./backups/jenkins-latest.tar.gz"
RESTORE="false"
if [ "$FRESH" != "true" ] && [ -f "$BACKUP_FILE" ]; then
  echo "==> Found existing backup: $BACKUP_FILE"
  echo "    Will restore after PVC is provisioned. Use --fresh to skip."
  RESTORE="true"
fi

if [ "$RESTORE" = "true" ]; then
  # Install Helm chart but don't start Jenkins yet — we want to populate the PVC first.
  helm upgrade --install jenkins jenkins/jenkins \
    --namespace jenkins \
    --values jenkins/values.yaml \
    --set controller.replicaCount=0 \
    --wait --timeout 5m

  # Wait for PVC to exist and be bound.
  echo "==> Waiting for Jenkins PVC to be bound"
  for i in $(seq 1 30); do
    PHASE=$(kubectl get pvc -n jenkins jenkins -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    [ "$PHASE" = "Bound" ] && break
    sleep 2
  done

  echo "==> Restoring from backup"
  ./scripts/restore-jenkins.sh "$BACKUP_FILE"

  echo "==> Starting Jenkins with restored state"
  kubectl scale -n jenkins statefulset/jenkins --replicas=1
  kubectl wait -n jenkins --for=condition=Ready pod \
    -l app.kubernetes.io/component=jenkins-controller --timeout=10m
else
  helm upgrade --install jenkins jenkins/jenkins \
    --namespace jenkins \
    --values jenkins/values.yaml \
    --wait --timeout 10m
fi

echo "==> Installing cleanup CronJob"
kubectl apply -f cleanup/cleanup-cronjob.yaml

echo ""
echo "================================================================"
echo "Lab is up."
echo ""
echo "Jenkins URL:  http://localhost:8080"
echo "Admin user:   admin"
if [ "$RESTORE" = "true" ]; then
  echo "Password:     (restored from backup — use your previous password)"
else
  echo "Password:"
  kubectl exec --namespace jenkins -it svc/jenkins -c jenkins -- \
    /bin/cat /run/secrets/additional/chart-admin-password
  echo ""
fi
echo "================================================================"
