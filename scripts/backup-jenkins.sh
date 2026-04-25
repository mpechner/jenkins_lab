#!/usr/bin/env bash
# Back up Jenkins state to ./backups/jenkins-<timestamp>.tar.gz
#
# What this does:
#   1. Runs an ephemeral pod in the 'jenkins' namespace that mounts the same
#      PVC as the Jenkins controller (ReadOnlyMany-style access).
#   2. Tars /var/jenkins_home from inside the pod and streams it to stdout.
#   3. kubectl exec pipes that stream to a file on your Mac.
#
# Why not 'kubectl cp'? kubectl cp on a big directory is flaky; tar-over-exec
# is the reliable idiom.
#
# Safety: we quiesce Jenkins first by scaling the controller to 0, so the
# files aren't changing mid-backup. For dev use you can skip quiescing
# (pass --hot) but expect occasional inconsistency.

set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-cold}"       # 'cold' (default) or 'hot'
BACKUP_DIR="$(pwd)/backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/jenkins-${TIMESTAMP}.tar.gz"
LATEST_LINK="${BACKUP_DIR}/jenkins-latest.tar.gz"
NAMESPACE="jenkins"
PVC_NAME="jenkins"      # matches the Helm chart's default
HELPER_POD="jenkins-backup-helper"

mkdir -p "$BACKUP_DIR"

cleanup() {
  kubectl delete pod -n "$NAMESPACE" "$HELPER_POD" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
  if [ "$MODE" = "cold" ]; then
    echo "==> Scaling Jenkins back up"
    kubectl scale -n "$NAMESPACE" statefulset/jenkins --replicas=1 >/dev/null || true
  fi
}
trap cleanup EXIT

if [ "$MODE" = "cold" ]; then
  echo "==> Quiescing: scaling Jenkins controller to 0"
  kubectl scale -n "$NAMESPACE" statefulset/jenkins --replicas=0
  # Wait for the pod to actually terminate (PVC is RWO, helper can't attach otherwise)
  kubectl wait -n "$NAMESPACE" --for=delete pod -l app.kubernetes.io/component=jenkins-controller --timeout=120s || true
fi

echo "==> Launching backup helper pod"
cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${HELPER_POD}
  labels: { role: jenkins-backup }
spec:
  restartPolicy: Never
  containers:
    - name: tar
      image: alpine:3.20
      command: ["sleep", "3600"]
      volumeMounts:
        - name: jenkins-home
          mountPath: /var/jenkins_home
          readOnly: true
  volumes:
    - name: jenkins-home
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
EOF

kubectl wait -n "$NAMESPACE" --for=condition=Ready pod/"$HELPER_POD" --timeout=60s

echo "==> Streaming backup to $BACKUP_FILE"
# -C to change into the parent so the archive contains 'jenkins_home/'
kubectl exec -n "$NAMESPACE" "$HELPER_POD" -- \
  tar czf - -C /var jenkins_home > "$BACKUP_FILE"

# Maintain a 'latest' symlink for convenient restore.
ln -sf "$(basename "$BACKUP_FILE")" "$LATEST_LINK"

SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo ""
echo "================================================================"
echo "Backup complete."
echo "  File:   $BACKUP_FILE   (${SIZE})"
echo "  Latest: $LATEST_LINK -> $(basename "$BACKUP_FILE")"
echo "================================================================"
