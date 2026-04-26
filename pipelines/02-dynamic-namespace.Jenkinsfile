// Pipeline 02 — dynamic per-build namespace.
//
// Creates a unique namespace for this build, deploys a tiny workload into it,
// verifies the workload is running, then tears it all down in post { always }.
//
// This is the pattern you'll use for real integration tests.

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
      '''
    }
  }

  options {
    timeout(time: 15, unit: 'MINUTES')
    ansiColor('xterm')
  }

  environment {
    // Build a safe, unique namespace name.
    // Lowercase, alphanumeric + '-', max 63 chars, starts/ends alphanumeric.
    TEST_NS = "test-build-${env.BUILD_NUMBER}"
  }

  stages {
    stage('Create namespace') {
      steps {
        container('kubectl') {
          sh '''
            printf "\\033[36m▶ Creating namespace %s\\033[0m\\n" "$TEST_NS"
            kubectl create namespace $TEST_NS
            kubectl label namespace $TEST_NS \
              ephemeral=true \
              jenkins-build=$BUILD_NUMBER \
              jenkins-job=dynamic-namespace
            kubectl get namespace $TEST_NS
            printf "\\033[32m✓ Namespace %s created and labeled\\033[0m\\n" "$TEST_NS"
          '''
        }
      }
    }

    stage('Deploy workload') {
      steps {
        container('kubectl') {
          // Heredoc body must be left-aligned: YAML doc separator '---'
          // only works at column 0, and <<EOF (no dash) preserves leading
          // whitespace literally.
          sh '''
cat <<EOF | kubectl apply -n $TEST_NS -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "128Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
EOF
          '''
        }
      }
    }

    stage('Wait for readiness') {
      steps {
        container('kubectl') {
          sh '''
            printf "\\033[36m▶ Waiting for nginx deployment to be available\\033[0m\\n"
            if kubectl wait --for=condition=available deployment/nginx \
                 -n $TEST_NS --timeout=120s; then
              kubectl get pods,svc -n $TEST_NS
              printf "\\033[32m✓ Deployment ready\\033[0m\\n"
            else
              printf "\\033[31m✗ Deployment did not become ready in 120s\\033[0m\\n"
              exit 1
            fi
          '''
        }
      }
    }

    stage('Smoke test') {
      steps {
        container('kubectl') {
          sh '''
            printf "\\033[36m▶ Curling nginx via cluster DNS\\033[0m\\n"
            if kubectl run curl-test \
                 --image=curlimages/curl:8.8.0 \
                 --restart=Never \
                 --rm -i \
                 -n $TEST_NS \
                 --command -- curl -sSf http://nginx.$TEST_NS.svc.cluster.local; then
              printf "\\033[32m✓ Smoke test passed: nginx is reachable\\033[0m\\n"
            else
              printf "\\033[31m✗ Smoke test failed: nginx not reachable\\033[0m\\n"
              exit 1
            fi
          '''
        }
      }
    }
  }

  post {
    always {
      // Always delete the namespace, even if earlier stages failed.
      // --wait=false: don't block the build on the async delete.
      container('kubectl') {
        sh '''
          printf "\\033[33m! Tearing down %s\\033[0m\\n" "$TEST_NS"
          kubectl delete namespace $TEST_NS --wait=false || true
        '''
      }
    }
  }
}
