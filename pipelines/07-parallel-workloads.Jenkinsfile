// Pipeline 07 — orchestrator that runs the three workload classes (04, 05, 06)
// in parallel. Demonstrates the original motivating point of the lab: the
// k8s scheduler spreads heterogeneous pods across worker nodes by resource
// request, which the legacy Docker plugin's count-based cap couldn't do.
//
// Prerequisite: child jobs 'tiny-bash', 'compile', and 'systemtest' must
// exist in Jenkins (created from pipelines 04/05/06 respectively). Adjust
// the job names below if you used different ones.
//
// While this runs, watch in another terminal:
//   watch -n1 'kubectl get pods -A -o wide | grep -E "NAMESPACE|jenkins-agents|systest-"'

pipeline {
  // No agent on the orchestrator itself — it just dispatches child builds.
  agent none

  options {
    timeout(time: 30, unit: 'MINUTES')
  }

  stages {
    stage('Fan out') {
      parallel {
        stage('tiny-bash')  { steps { build job: 'tiny-bash',  wait: true } }
        stage('compile')    { steps { build job: 'compile',    wait: true } }
        stage('systemtest') { steps { build job: 'systemtest', wait: true } }
      }
    }
  }
}
