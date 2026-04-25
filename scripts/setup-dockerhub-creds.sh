#!/usr/bin/env bash
# Set up a Docker Hub ImagePullSecret in the 'jenkins-agents' namespace and
# attach it to the 'jenkins-test-runner' ServiceAccount, so all pipeline
# agent pods authenticate to Docker Hub.
#
# Why: kind node containerd does NOT inherit your host's Docker Desktop
# login. Without this, pulls from inside the cluster are anonymous and
# subject to the strict per-IP rate limit.
#
# Usage:
#   DOCKERHUB_USERNAME=myuser DOCKERHUB_TOKEN=dckr_pat_... ./scripts/setup-dockerhub-creds.sh
#
# Idempotent: re-running replaces the secret with the latest credentials.

set -euo pipefail

: "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME env var is required}"
: "${DOCKERHUB_TOKEN:?DOCKERHUB_TOKEN env var is required (use a Personal Access Token, not your password)}"

NS="jenkins-agents"
SECRET_NAME="dockerhub"
SA_NAME="jenkins-test-runner"

if ! kubectl get namespace "$NS" >/dev/null 2>&1; then
  echo "ERROR: namespace '$NS' does not exist. Run ./scripts/bootstrap.sh first."
  exit 1
fi

echo "==> Creating ImagePullSecret '$SECRET_NAME' in namespace '$NS'"
kubectl delete secret "$SECRET_NAME" -n "$NS" --ignore-not-found
kubectl create secret docker-registry "$SECRET_NAME" \
  --docker-server="https://index.docker.io/v1/" \
  --docker-username="$DOCKERHUB_USERNAME" \
  --docker-password="$DOCKERHUB_TOKEN" \
  --docker-email="ignored@example.com" \
  -n "$NS"

echo "==> Patching ServiceAccount '$SA_NAME' to use it"
# Note: this REPLACES any existing imagePullSecrets on the SA. The lab's
# jenkins-test-runner SA has no other secrets attached, so this is safe.
kubectl patch serviceaccount "$SA_NAME" -n "$NS" \
  -p "{\"imagePullSecrets\":[{\"name\":\"$SECRET_NAME\"}]}"

echo ""
echo "Done. Pipeline agent pods will now pull as '$DOCKERHUB_USERNAME' from Docker Hub."
echo "Verify with:  kubectl get sa $SA_NAME -n $NS -o jsonpath='{.imagePullSecrets}'"
