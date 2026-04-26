// Pipeline 05 — compile workload class.
// Represents a build job: 1Gi RAM, 500m CPU (trimmed for laptop).
// Uses maven image as a realistic compile-ish workload.

pipeline {
  agent {
    kubernetes {
      cloud 'kubernetes-agents'
      yaml '''
        apiVersion: v1
        kind: Pod
        metadata:
          labels:
            workload-class: compile
        spec:
          serviceAccountName: jenkins-test-runner
          containers:
            - name: maven
              image: maven:3.9-eclipse-temurin-17
              command: ["sleep"]
              args: ["infinity"]
              resources:
                requests:
                  cpu: "500m"
                  memory: "1Gi"
                limits:
                  cpu: "1500m"
                  memory: "2Gi"
      '''
    }
  }

  options {
    ansiColor('xterm')
  }

  stages {
    stage('Compile simulation') {
      steps {
        container('maven') {
          sh '''
            printf "\\033[36m▶ Compile job on %s\\033[0m\\n" "$(hostname)"
            mvn --version
            # Simulate a build by generating a throwaway project.
            mkdir -p /tmp/demo && cd /tmp/demo
            if mvn -B -q archetype:generate \
                 -DgroupId=com.example -DartifactId=demo \
                 -DarchetypeArtifactId=maven-archetype-quickstart \
                 -DarchetypeVersion=1.4 -DinteractiveMode=false \
               && cd demo && mvn -B -q package; then
              printf "\\033[32m✓ Build succeeded — artifact:\\033[0m\\n"
              ls -la target/*.jar
            else
              printf "\\033[31m✗ Build failed\\033[0m\\n"
              exit 1
            fi
          '''
        }
      }
    }
  }
}
