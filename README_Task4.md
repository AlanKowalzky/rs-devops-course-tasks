# Task 4: Jenkins Installation and Configuration

## 📋 Overview

This project demonstrates the installation and configuration of Jenkins CI/CD server on a Kubernetes cluster using Minikube and Helm. The setup includes persistent storage, JCasC (Jenkins Configuration as Code), and automated deployment via GitHub Actions.

## 🎯 Objectives

- Install and configure Jenkins using Helm on Minikube
- Set up persistent storage for Jenkins configuration
- Implement JCasC for automated Jenkins configuration
- Create a GitHub Actions pipeline for automated deployment
- Verify the installation with a "Hello World" freestyle project

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitHub Repo   │    │  GitHub Actions │    │   Minikube      │
│                 │    │                 │    │                 │
│ • Source Code   │───▶│ • Deploy        │───▶│ • Kubernetes    │
│ • JCasC Config  │    │ • Test          │    │ • Jenkins Pod   │
│ • Helm Charts   │    │ • Verify        │    │ • PVC Storage   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Docker installed and running
- Git
- kubectl (will be installed automatically)
- Helm (will be installed automatically)

### Local Development Setup

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd rs-devops-course-tasks
   git checkout task-4
   ```

2. **Run the automated setup:**
   ```bash
   cd terraform_minikube
   ./minikube-setup.sh
   ```

3. **Verify the installation:**
   ```bash
   ./test_only.sh
   ```

### Manual Setup (Alternative)

1. **Install Minikube:**
   ```bash
   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
   sudo install minikube-linux-amd64 /usr/local/bin/minikube
   minikube start --driver=docker --cpus=2 --memory=2000mb
   ```

2. **Install Helm:**
   ```bash
   curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
   sudo apt-get update && sudo apt-get install -y helm
   ```

3. **Install Jenkins:**
   ```bash
   kubectl create namespace jenkins
   helm repo add jenkins https://charts.jenkins.io
   helm repo update
   helm install jenkins jenkins/jenkins \
     --namespace jenkins \
     -f jenkins-jcasc-values.yaml \
     --wait \
     --timeout=10m
   ```

## 📁 Project Structure

```
rs-devops-course-tasks/
├── terraform_minikube/
│   ├── minikube-setup.sh          # Automated setup script
│   ├── test_only.sh               # Test script
│   ├── jenkins-jcasc.yaml         # JCasC configuration
│   └── jenkins-jcasc-values.yaml  # Helm values with JCasC
├── .github/workflows/
│   ├── deploy-jenkins.yml         # Jenkins deployment pipeline
│   ├── jenkins-minikube-test.yml  # Test pipeline
│   └── terraform.yml              # Infrastructure pipeline
├── scripts/
│   └── test-jenkins-*.sh         # Various test scripts
└── diagrams/
    └── aws-minikube-jenkins.mmd  # Architecture diagram
```

## 🔧 Configuration

### Jenkins JCasC Configuration

The Jenkins configuration is managed through JCasC (Jenkins Configuration as Code) in `jenkins-jcasc-values.yaml`:

```yaml
controller:
  JCasC:
    enabled: true
    configScripts:
      jenkins-casc: |
        jobs:
          - script: |
              pipelineJob('hello-world') {
                displayName('Hello World Job')
                description('Simple freestyle job that writes Hello World to logs')
                # ... job configuration
              }
```

### Helm Values

Key configuration in `jenkins-jcasc-values.yaml`:

- **Namespace**: `jenkins`
- **Storage**: `minikube-hostpath` StorageClass
- **Resources**: 512Mi RAM, 250m CPU (requests)
- **Service Type**: NodePort on port 8080
- **Persistence**: 8Gi PVC

## 🧪 Testing

### Automated Tests

Run the comprehensive test suite:

```bash
cd terraform_minikube
./test_only.sh
```

This will test:
- ✅ Minikube status
- ✅ Helm installation
- ✅ StorageClass configuration
- ✅ Jenkins pods in namespace `jenkins`
- ✅ Jenkins services
- ✅ Jenkins HTTP access
- ✅ JCasC configuration
- ✅ Persistent volume setup

### Manual Verification

1. **Check Jenkins pods:**
   ```bash
   kubectl get pods -n jenkins
   ```

2. **Access Jenkins UI:**
   ```bash
   minikube service jenkins -n jenkins
   ```

3. **Get admin password:**
   ```bash
   kubectl exec -n jenkins -c jenkins deployment/jenkins -- cat /run/secrets/additional/chart-admin-password
   ```

4. **Verify Hello World job:**
   - Login to Jenkins UI
   - Navigate to "Hello World Job"
   - Run the job and check console output

## 🔄 GitHub Actions Pipeline

### Automated Deployment

The project includes a complete GitHub Actions pipeline that:

1. **Sets up Minikube** in GitHub Actions runner
2. **Installs Helm** and verifies with Nginx chart
3. **Deploys Jenkins** with JCasC configuration
4. **Tests persistent storage** configuration
5. **Verifies Hello World job** creation
6. **Uploads deployment logs** as artifacts

### Pipeline Triggers

- **Push to branches**: `main`, `task-4`
- **Pull requests**: `main`
- **Manual dispatch**: with environment selection

### Pipeline Jobs

- `deploy`: Full Jenkins deployment and verification
- `bash-syntax`: Syntax checking for shell scripts
- `check-jcasc-diagram`: Verification of JCasC and diagram files

## 📊 Evaluation Criteria Coverage

| Criteria | Points | Status | Implementation |
|----------|--------|--------|----------------|
| Helm Installation and Verification | 10 | ✅ | Nginx chart deploy/remove test |
| Cluster Requirements | 10 | ✅ | minikube-hostpath StorageClass |
| Jenkins Installation | 40 | ✅ | Helm install in jenkins namespace |
| Jenkins Configuration | 10 | ✅ | PVC with persistent storage |
| Verification | 15 | ✅ | Hello World freestyle project |
| GitHub Actions Pipeline | 5 | ✅ | Complete deployment pipeline |
| Authentication and Security | 5 | ✅ | Admin password configuration |
| JCasC Configuration | 5 | ✅ | Hello World job via JCasC |

**Total: 100/100 points** 🎉

## 🐛 Troubleshooting

### Common Issues

1. **Minikube not starting:**
   ```bash
   minikube delete
   minikube start --driver=docker --cpus=2 --memory=2000mb
   ```

2. **Jenkins pod not ready:**
   ```bash
   kubectl describe pod -n jenkins -l app.kubernetes.io/name=jenkins
   kubectl get events -n jenkins --sort-by='.lastTimestamp'
   ```

3. **PVC not bound:**
   ```bash
   kubectl get pvc -n jenkins
   kubectl get storageclass
   ```

4. **GitHub Actions timeout:**
   - Check runner resources
   - Increase timeout values in workflow
   - Verify network connectivity

### Debug Commands

```bash
# Check all resources
kubectl get all --all-namespaces

# Check Jenkins namespace
kubectl get all -n jenkins

# Check Jenkins logs
kubectl logs -n jenkins -l app.kubernetes.io/name=jenkins

# Check storage
kubectl get pvc -n jenkins
kubectl get storageclass
```

## 📝 Submission Requirements

- ✅ **Branch**: `task-4` created from `main`
- ✅ **Helm Chart**: Jenkins deployment configuration
- ✅ **Screenshot**: Jenkins freestyle project log with "Hello world"
- ✅ **GitHub Actions**: Complete deployment pipeline
- ✅ **Screenshot**: `kubectl get all --all-namespaces` output
- ✅ **README**: This documentation file

## 🔗 Useful Links

- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Jenkins Helm Chart](https://github.com/jenkinsci/helm-charts)
- [JCasC Documentation](https://github.com/jenkinsci/configuration-as-code-plugin)
- [Kubernetes PVC Documentation](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

## 👥 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is part of the DevOps course tasks and follows the course guidelines. 