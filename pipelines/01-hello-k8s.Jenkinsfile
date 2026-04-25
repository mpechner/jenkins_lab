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
  }

  stages {
    stage('Who am I') {
      steps {
        container('kubectl') {
          sh '''
            echo "Running in pod: $HOSTNAME"
            echo "Namespace:"
            cat /var/run/secrets/kubernetes.io/serviceaccount/namespace
            echo ""
          '''
        }
      }
    }
    stage('List cluster nodes') {
      steps {
        container('kubectl') {
          sh 'kubectl get nodes -o wide'
        }
      }
    }
    stage('Can I create namespaces?') {
      steps {
        container('kubectl') {
          // Should print 'yes' if RBAC is set up correctly.
          sh 'kubectl auth can-i -n default create namespaces'
        }
      }
    }
  }
}
