// Pipeline 01 — smoke test for the kubernetes plugin (declarative).
//
// Goal: prove that Jenkins can dynamically provision an agent pod on the
// cluster and run a shell command inside it.
//
// Paste this into Jenkins UI as a new Pipeline job named 'hello-k8s'.
//
// Scripted equivalent: see 01-hello-k8s-scripted.Jenkinsfile.

pipeline {
  agent {
    kubernetes {
      // Run in the 'jenkins-agents' namespace we configured in JCasC.
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
              resources:
                requests:
                  cpu: "100m"
                  memory: "128Mi"
                limits:
                  cpu: "500m"
                  memory: "256Mi"
      '''
    }
  }

  options {
    timeout(time: 10, unit: 'MINUTES')
    ansiColor('xterm')
  }

  stages {
    stage('Who am I') {
      steps {
        container('kubectl') {
          sh '''
            printf "\\033[36m▶ Identifying agent pod\\033[0m\\n"
            echo "Running in pod: $HOSTNAME"
            echo "Namespace: $(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
            printf "\\033[32m✓ Pod identified\\033[0m\\n"
          '''
        }
      }
    }
    stage('List cluster nodes') {
      steps {
        container('kubectl') {
          sh '''
            printf "\\033[36m▶ Listing cluster nodes\\033[0m\\n"
            kubectl get nodes -o wide
            count=$(kubectl get nodes --no-headers | wc -l | tr -d " ")
            printf "\\033[32m✓ %s nodes Ready\\033[0m\\n" "$count"
          '''
        }
      }
    }
    stage('Can I create namespaces?') {
      steps {
        container('kubectl') {
          // Should print 'yes' if RBAC is set up correctly.
          sh '''
            printf "\\033[36m▶ Checking RBAC: namespaces/create\\033[0m\\n"
            if kubectl auth can-i -n default create namespaces | grep -q yes; then
              printf "\\033[32m✓ Allowed: SA can create namespaces\\033[0m\\n"
            else
              printf "\\033[31m✗ Denied: SA cannot create namespaces — RBAC misconfigured\\033[0m\\n"
              exit 1
            fi
          '''
        }
      }
    }
  }
}
