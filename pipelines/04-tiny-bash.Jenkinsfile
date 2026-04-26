// Pipeline 04 — tiny-bash workload class.
// Represents a simple bash cron-style job: 128Mi RAM, 100m CPU.
// Run this concurrently with 05 and 06 to see the k8s scheduler spread
// pods across your 3 worker nodes by resource request.

pipeline {
  agent {
    kubernetes {
      cloud 'kubernetes-agents'
      yaml '''
        apiVersion: v1
        kind: Pod
        metadata:
          labels:
            workload-class: tiny-bash
        spec:
          serviceAccountName: jenkins-test-runner
          containers:
            - name: bash
              image: bash:5.2
              command: ["sleep"]
              args: ["infinity"]
              resources:
                requests:
                  cpu: "100m"
                  memory: "128Mi"
                limits:
                  cpu: "200m"
                  memory: "256Mi"
      '''
    }
  }

  options {
    ansiColor('xterm')
  }

  stages {
    stage('Tiny job') {
      steps {
        container('bash') {
          sh '''
            printf "\\033[36m▶ Tiny bash job on %s\\033[0m\\n" "$(hostname)"
            for i in 1 2 3 4 5; do
              echo "tick $i"
              sleep 2
            done
            printf "\\033[32m✓ Tiny job complete\\033[0m\\n"
          '''
        }
      }
    }
  }
}
