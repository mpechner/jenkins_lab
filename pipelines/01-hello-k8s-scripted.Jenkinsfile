// Pipeline 01 (scripted) — smoke test for the kubernetes plugin.
//
// Same goal as 01-hello-k8s.Jenkinsfile (declarative), implemented in
// scripted syntax using podTemplate + node(POD_LABEL). Useful as a reference
// for the scripted form, and as a fallback if the declarative agent block
// hits a plugin bug.
//
// Paste this into Jenkins UI as a new Pipeline job named 'hello-k8s-scripted'.

podTemplate(
  cloud: 'kubernetes-agents',
  yaml: '''
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
) {
  node(POD_LABEL) {
    timeout(time: 10, unit: 'MINUTES') {
      stage('Who am I') {
        container('kubectl') {
          sh '''
            echo "Running in pod: $HOSTNAME"
            echo "Namespace:"
            cat /var/run/secrets/kubernetes.io/serviceaccount/namespace
            echo ""
          '''
        }
      }
      stage('List cluster nodes') {
        container('kubectl') {
          sh 'kubectl get nodes -o wide'
        }
      }
      stage('Can I create namespaces?') {
        container('kubectl') {
          sh 'kubectl auth can-i -n default create namespaces'
        }
      }
    }
  }
}
