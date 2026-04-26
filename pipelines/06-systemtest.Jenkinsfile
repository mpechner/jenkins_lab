// Pipeline 06 — systemtest workload class.
// Heavy workload: larger agent + dynamic namespace for the stack.
// Combines the per-build namespace pattern (pipeline 02/03) with a larger
// resource class. This is the pattern for a "deploy 10 services + run
// integration tests" job.

pipeline {
  agent {
    kubernetes {
      cloud 'kubernetes-agents'
      yaml '''
        apiVersion: v1
        kind: Pod
        metadata:
          labels:
            workload-class: systemtest
        spec:
          serviceAccountName: jenkins-test-runner
          containers:
            - name: kubectl
              image: alpine/k8s:1.34.1
              command: ["sleep"]
              args: ["infinity"]
              resources:
                requests:
                  cpu: "500m"
                  memory: "512Mi"
                limits:
                  cpu: "2000m"
                  memory: "1Gi"
      '''
    }
  }

  options {
    ansiColor('xterm')
  }

  environment {
    TEST_NS = "systest-heavy-${env.BUILD_NUMBER}"
  }

  stages {
    stage('Provision namespace') {
      steps {
        container('kubectl') {
          sh '''
            printf "\\033[36m▶ Creating namespace %s\\033[0m\\n" "$TEST_NS"
            kubectl create namespace $TEST_NS
            kubectl label ns $TEST_NS ephemeral=true \
              jenkins-build=$BUILD_NUMBER \
              workload-class=systemtest
            printf "\\033[32m✓ Namespace ready\\033[0m\\n"
          '''
        }
      }
    }

    stage('Deploy minimal stack') {
      steps {
        container('kubectl') {
          sh '''
            printf "\\033[36m▶ Deploying web (3 replicas)\\033[0m\\n"
            kubectl create deployment web --image=nginx:1.27-alpine \
              --replicas=3 -n $TEST_NS
            kubectl set resources deploy/web -n $TEST_NS \
              --requests=cpu=100m,memory=64Mi \
              --limits=cpu=300m,memory=128Mi
            kubectl expose deployment web --port=80 -n $TEST_NS
            if kubectl wait --for=condition=available deploy/web \
                 -n $TEST_NS --timeout=120s; then
              printf "\\033[32m✓ web Deployment available (3/3)\\033[0m\\n"
            else
              printf "\\033[31m✗ web Deployment did not become available\\033[0m\\n"
              exit 1
            fi
          '''
        }
      }
    }

    stage('Run test suite') {
      steps {
        container('kubectl') {
          sh '''
            printf "\\033[36m▶ Hitting web 5 times\\033[0m\\n"
            if kubectl run tester --image=curlimages/curl:8.8.0 \
                 --restart=Never --rm -i -n $TEST_NS \
                 --command -- sh -c '
                   for i in 1 2 3 4 5; do
                     curl -sSf http://web > /dev/null && printf "\\033[32m✓ request %s ok\\033[0m\\n" "$i"
                     sleep 1
                   done
                 '; then
              printf "\\033[32m✓ Test suite passed\\033[0m\\n"
            else
              printf "\\033[31m✗ Test suite failed\\033[0m\\n"
              exit 1
            fi
          '''
        }
      }
    }
  }

  post {
    always {
      container('kubectl') {
        sh '''
          printf "\\033[33m! Tearing down %s\\033[0m\\n" "$TEST_NS"
          kubectl delete namespace $TEST_NS --wait=false || true
        '''
      }
    }
  }
}
