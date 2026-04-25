#!/usr/bin/env bash
# Tear down the lab cluster, with a Jenkins backup first by default.
#
# Usage:
#   ./scripts/teardown.sh                # backup then destroy (default, safe)
#   ./scripts/teardown.sh --no-backup    # destroy immediately without backup
#   ./scripts/teardown.sh --backup-only  # backup but don't destroy

set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER_NAME="jenkins-lab"
MODE="backup-and-destroy"

for arg in "$@"; do
  case "$arg" in
    --no-backup)    MODE="destroy-only" ;;
    --backup-only)  MODE="backup-only" ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg (use --help)"
      exit 1
      ;;
  esac
done

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '$CLUSTER_NAME' not found. Nothing to do."
  exit 0
fi

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

if [ "$MODE" != "destroy-only" ]; then
  if kubectl get namespace jenkins >/dev/null 2>&1 && \
     kubectl get pvc -n jenkins jenkins >/dev/null 2>&1; then
    echo "==> Backing up Jenkins before teardown"
    ./scripts/backup-jenkins.sh cold
  else
    echo "==> No Jenkins PVC found, skipping backup"
  fi
fi

if [ "$MODE" != "backup-only" ]; then
  echo "==> Deleting cluster $CLUSTER_NAME"
  kind delete cluster --name "$CLUSTER_NAME"
  echo "Gone. Latest backup is in ./backups/jenkins-latest.tar.gz"
fi
