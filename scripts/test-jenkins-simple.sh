#!/bin/bash

echo "🚀 Simple Jenkins Test - No JCasC"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if minikube is running
echo -e "${YELLOW}1. Checking Minikube status...${NC}"
if ! minikube status >/dev/null 2>&1; then
    echo -e "${RED}❌ Minikube not running. Starting...${NC}"
    minikube start --driver=docker --cpus=2 --memory=4000
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to start Minikube${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Minikube is running${NC}"
fi

# Quick Jenkins test (without JCasC)
echo -e "${YELLOW}2. Testing Jenkins installation (simple, no JCasC)...${NC}"
kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -

# Create StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: minikube-hostpath
provisioner: k8s.io/minikube-hostpath
volumeBindingMode: Immediate
EOF

# Install Jenkins without JCasC
helm repo add jenkins https://charts.jenkins.io
helm repo update

helm install jenkins jenkins/jenkins \
  -n jenkins \
  -f jenkins-simple-values.yaml \
  --wait \
  --timeout=5m || {
    echo -e "${RED}❌ Jenkins installation failed${NC}"
    echo "=== DIAGNOSTICS ==="
    kubectl get pods -n jenkins -o wide
    kubectl get events -n jenkins --sort-by='.lastTimestamp' | tail -10
    exit 1
}

echo -e "${GREEN}✅ Jenkins installed successfully!${NC}"

# Quick verification
echo -e "${YELLOW}3. Quick verification...${NC}"
kubectl get pods -n jenkins
kubectl get svc -n jenkins

echo -e "${GREEN}🎉 Simple test completed!${NC}"
echo "Jenkins should be available at: minikube service jenkins -n jenkins"
echo "Admin password: kubectl exec -n jenkins -c jenkins deployment/jenkins -- cat /run/secrets/additional/chart-admin-password" 