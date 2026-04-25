// Pipeline 03 — multi-service system test.
//
// Spins up a 4-service stack (app, redis, postgres, mock-api) in a fresh
// namespace via Helm, runs a test pod against it, collects logs on failure,
// and tears everything down.
//
// Prerequisite: the charts/test-stack Helm chart must be reachable. For the
// lab, we clone it from a git repo or package it. The simplest approach:
// bake the chart into an init container or check it out from SCM.
//
// For now, this pipeline demonstrates the flow by inlining manifests via
// kubectl. A real setup would use `helm install` from a chart repo or git.

pipeline {
  agent {
    kubernetes {
      cloud 'kubernetes-agents'
      yaml '''
        apiVersion: v1
        kind: Pod
        spec:
          serviceAccountName: jenkins-test-runner
          containers:
            - name: kubectl
              image: alpine/k8s:1.34.1
              command: ["sleep"]
              args: ["infinity"]
            - name: helm
              image: ghcr.io/helmfile/helmfile:v0.171.0
              command: ["sleep"]
              args: ["infinity"]
      '''
    }
  }

  options {
    timeout(time: 20, unit: 'MINUTES')
  }

  environment {
    TEST_NS = "systest-${env.BUILD_NUMBER}"
  }

  stages {
    stage('Create namespace with quota') {
      steps {
        container('kubectl') {
          // Heredoc body must be left-aligned: <<EOF preserves leading
          // whitespace and YAML's '---' / root keys break with indentation.
          sh '''
            kubectl create namespace $TEST_NS
            kubectl label namespace $TEST_NS ephemeral=true \
              jenkins-build=$BUILD_NUMBER \
              jenkins-job=system-test

            # Cap total resources this test can consume.
            # The ResourceQuota tracks requests/limits, so every pod must
            # set them. The LimitRange provides defaults so quick pods
            # like `kubectl run` don't have to specify resources inline.
cat <<EOF | kubectl apply -n $TEST_NS -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: test-quota
spec:
  hard:
    requests.cpu: "2"
    requests.memory: "2Gi"
    limits.cpu: "4"
    limits.memory: "4Gi"
    pods: "20"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
spec:
  limits:
    - type: Container
      default:
        cpu: "200m"
        memory: "128Mi"
      defaultRequest:
        cpu: "50m"
        memory: "64Mi"
EOF
          '''
        }
      }
    }

    stage('Deploy stack') {
      steps {
        // Clone or fetch the chart. For the lab, we inline the manifests.
        // In a real setup: git clone, helm install ./charts/test-stack
        container('kubectl') {
          // Heredoc bodies are left-aligned (column 0): <<EOF preserves
          // leading whitespace and YAML's '---' separator only works there.
          sh '''
            # Deploy postgres
cat <<EOF | kubectl apply -n $TEST_NS -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector: { matchLabels: { app: postgres } }
  template:
    metadata: { labels: { app: postgres } }
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          env:
            - { name: POSTGRES_PASSWORD, value: "labpass" }
            - { name: POSTGRES_DB, value: "testdb" }
          ports: [{ containerPort: 5432 }]
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits:   { cpu: "500m", memory: "256Mi" }
---
apiVersion: v1
kind: Service
metadata: { name: postgres }
spec:
  selector: { app: postgres }
  ports: [{ port: 5432, targetPort: 5432 }]
EOF

            # Deploy redis
cat <<EOF | kubectl apply -n $TEST_NS -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: redis }
spec:
  replicas: 1
  selector: { matchLabels: { app: redis } }
  template:
    metadata: { labels: { app: redis } }
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          ports: [{ containerPort: 6379 }]
          resources:
            requests: { cpu: "50m", memory: "64Mi" }
            limits:   { cpu: "200m", memory: "128Mi" }
---
apiVersion: v1
kind: Service
metadata: { name: redis }
spec:
  selector: { app: redis }
  ports: [{ port: 6379, targetPort: 6379 }]
EOF

            # Deploy app + mock-api (both nginx for the lab)
cat <<EOF | kubectl apply -n $TEST_NS -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: app }
spec:
  replicas: 2
  selector: { matchLabels: { app: app } }
  template:
    metadata: { labels: { app: app } }
    spec:
      containers:
        - name: app
          image: nginx:1.27-alpine
          ports: [{ containerPort: 80 }]
          resources:
            requests: { cpu: "50m", memory: "64Mi" }
            limits:   { cpu: "200m", memory: "128Mi" }
---
apiVersion: v1
kind: Service
metadata: { name: app }
spec:
  selector: { app: app }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: mock-api }
spec:
  replicas: 1
  selector: { matchLabels: { app: mock-api } }
  template:
    metadata: { labels: { app: mock-api } }
    spec:
      containers:
        - name: mock-api
          image: nginx:1.27-alpine
          ports: [{ containerPort: 80 }]
          resources:
            requests: { cpu: "50m", memory: "64Mi" }
            limits:   { cpu: "200m", memory: "128Mi" }
---
apiVersion: v1
kind: Service
metadata: { name: mock-api }
spec:
  selector: { app: mock-api }
  ports: [{ port: 80, targetPort: 80 }]
EOF
          '''
        }
      }
    }

    stage('Wait for readiness') {
      steps {
        container('kubectl') {
          sh '''
            kubectl wait --for=condition=available deployment --all \
              -n $TEST_NS --timeout=180s
            kubectl rollout status statefulset/postgres -n $TEST_NS --timeout=180s
            kubectl get all -n $TEST_NS
          '''
        }
      }
    }

    stage('Run integration tests') {
      steps {
        container('kubectl') {
          sh '''
            # Run a test pod that exercises each service.
            kubectl run tests \
              --image=curlimages/curl:8.8.0 \
              --restart=Never \
              --rm -i \
              -n $TEST_NS \
              --command -- sh -c '
                set -e
                echo "== Testing app =="
                curl -sSf http://app | head -3
                echo "== Testing mock-api =="
                curl -sSf http://mock-api | head -3
                echo "All service endpoints responding."
              '
          '''
        }
      }
    }
  }

  post {
    failure {
      container('kubectl') {
        sh '''
          echo "=== FAILURE DIAGNOSTICS ==="
          kubectl get all -n $TEST_NS || true
          kubectl describe pods -n $TEST_NS || true
          echo "=== Recent events ==="
          kubectl get events -n $TEST_NS --sort-by=.lastTimestamp | tail -30 || true
        '''
      }
    }
    always {
      container('kubectl') {
        sh 'kubectl delete namespace $TEST_NS --wait=false || true'
      }
    }
  }
}
