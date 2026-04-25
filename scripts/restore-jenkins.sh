#!/usr/bin/env bash
# Restore Jenkins state from a backup tarball.
#
# Usage:
#   ./scripts/restore-jenkins.sh                      # uses backups/jenkins-latest.tar.gz
#   ./scripts/restore-jenkins.sh backups/foo.tar.gz   # specific file
#
# Prerequisites:
#   - Cluster exists (kind create cluster)
#   - Jenkins namespace exists and PVC is bound, BUT controller hasn't started
#     populating it yet — OR you're willing to overwrite what's there.
#
# Typical flow in our lab:
#   1. ./scripts/bootstrap.sh            # creates cluster, installs Jenkins
#   2. kubectl scale -n jenkins sts/jenkins --replicas=0
#   3. ./scripts/restore-jenkins.sh
#   4. kubectl scale -n jenkins sts/jenkins --replicas=1

set -euo pipefail

cd "$(dirname "$0")/.."

BACKUP_FILE="${1:-$(pwd)/backups/jenkins-latest.tar.gz}"
NAMESPACE="jenkins"
PVC_NAME="jenkins"
HELPER_POD="jenkins-restore-helper"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: backup file not found: $BACKUP_FILE"
  echo "Available backups:"
  ls -lh ./backups/ 2>/dev/null || echo "  (none)"
  exit 1
fi

# Resolve symlink so we log the real file being restored.
REAL_FILE="$(readlink -f "$BACKUP_FILE" 2>/dev/null || echo "$BACKUP_FILE")"
echo "==> Restoring from: $REAL_FILE"

# Refuse to run if the Jenkins controller is up — PVC is ReadWriteOnce.
REPLICAS=$(kubectl get statefulset -n "$NAMESPACE" jenkins -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
if [ "$REPLICAS" != "0" ]; then
  echo "ERROR: Jenkins controller is running (replicas=$REPLICAS)."
  echo "Scale it down first:  kubectl scale -n $NAMESPACE sts/jenkins --replicas=0"
  exit 1
fi

# Also wait for the pod to be gone.
kubectl wait -n "$NAMESPACE" --for=delete pod -l app.kubernetes.io/component=jenkins-controller --timeout=120s 2>/dev/null || true

cleanup() {
  kubectl delete pod -n "$NAMESPACE" "$HELPER_POD" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Launching restore helper pod"
cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${HELPER_POD}
  labels: { role: jenkins-restore }
spec:
  restartPolicy: Never
  containers:
    - name: tar
      image: alpine:3.20
      command: ["sleep", "3600"]
      volumeMounts:
        - name: jenkins-home
          mountPath: /var/jenkins_home
  volumes:
    - name: jenkins-home
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
EOF

kubectl wait -n "$NAMESPACE" --for=condition=Ready pod/"$HELPER_POD" --timeout=60s

echo "==> Wiping existing PVC contents"
# Be conservative: delete only the children so the mount point itself stays.
kubectl exec -n "$NAMESPACE" "$HELPER_POD" -- sh -c 'rm -rf /var/jenkins_home/* /var/jenkins_home/.[!.]* 2>/dev/null || true'

echo "==> Streaming archive into PVC"
# The archive contains 'jenkins_home/...' so we extract into /var.
kubectl exec -i -n "$NAMESPACE" "$HELPER_POD" -- \
  tar xzf - -C /var < "$REAL_FILE"

# Ownership: Jenkins runs as uid 1000 by default in the official image.
echo "==> Fixing ownership (uid/gid 1000)"
kubectl exec -n "$NAMESPACE" "$HELPER_POD" -- chown -R 1000:1000 /var/jenkins_home

echo ""
echo "================================================================"
echo "Restore complete. Start Jenkins with:"
echo "  kubectl scale -n $NAMESPACE statefulset/jenkins --replicas=1"
echo "================================================================"
