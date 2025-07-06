#!/bin/bash

echo "🚀 Local Jenkins Test - Development Environment"

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

# Check kubectl
echo -e "${YELLOW}2. Checking kubectl...${NC}"
if ! kubectl version --client >/dev/null 2>&1; then
    echo -e "${RED}❌ kubectl not found${NC}"
    exit 1
else
    echo -e "${GREEN}✅ kubectl is available${NC}"
fi

# Check Helm
echo -e "${YELLOW}3. Checking Helm...${NC}"
if ! helm version >/dev/null 2>&1; then
    echo -e "${RED}❌ Helm not found${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Helm is available${NC}"
fi

# Quick Helm test
echo -e "${YELLOW}4. Testing Helm with Nginx (quick)...${NC}"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install test-nginx bitnami/nginx --set service.type=ClusterIP --wait --timeout=2m
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Helm test passed${NC}"
    helm uninstall test-nginx
else
    echo -e "${RED}❌ Helm test failed${NC}"
    exit 1
fi

# Check Jenkins configuration files
echo -e "${YELLOW}5. Checking Jenkins configuration files...${NC}"
if [ -f "jenkins-jcasc-values.yaml" ]; then
    echo -e "${GREEN}✅ jenkins-jcasc-values.yaml exists${NC}"
else
    echo -e "${RED}❌ jenkins-jcasc-values.yaml not found${NC}"
    exit 1
fi

# Quick Jenkins test (without waiting for full startup)
echo -e "${YELLOW}6. Testing Jenkins installation (quick)...${NC}"
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

# Install Jenkins with shorter timeout
helm repo add jenkins https://charts.jenkins.io
helm repo update

helm install jenkins jenkins/jenkins \
  -n jenkins \
  -f jenkins-jcasc-values.yaml \
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
echo -e "${YELLOW}7. Quick verification...${NC}"
kubectl get pods -n jenkins
kubectl get svc -n jenkins

echo -e "${GREEN}🎉 Local test completed!${NC}"
echo "Jenkins should be available at: minikube service jenkins -n jenkins"
echo "Admin password: kubectl exec -n jenkins -c jenkins deployment/jenkins -- cat /run/secrets/additional/chart-admin-password" 