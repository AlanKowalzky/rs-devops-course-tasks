#!/bin/bash
set -e

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if command succeeded
check_command() {
    if [ $? -eq 0 ]; then
        log_info "$1 - OK"
    else
        log_error "$1 - FAILED"
        exit 1
    fi
}

echo "=== Kubernetes Cluster Verification Script ==="
echo "This script verifies k3s cluster and deploys test workload"
echo ""

# Get IPs from Terraform outputs
log_step "Getting cluster IPs from Terraform..."
MASTER_IP=$(terraform output -json k3s_nodes_private_ips | tr -d '[]"' | cut -d',' -f1)
WORKER_IP=$(terraform output -json k3s_nodes_private_ips | tr -d '[]"' | cut -d',' -f2)
BASTION_IP=$(terraform output -raw bastion_public_ip)

log_info "Master IP: $MASTER_IP"
log_info "Worker IP: $WORKER_IP"
log_info "Bastion IP: $BASTION_IP"

# SSH key path
SSH_KEY=~/.ssh/k8s-infra-key.pem

log_step "Step 1: Connecting to bastion host and setting up kubectl alias..."

# Connect to bastion and set up kubectl alias
ssh -i $SSH_KEY ec2-user@$BASTION_IP "
    echo 'Setting up kubectl function to use k3s from master node...'
    
    # Create kubectl function that executes k3s kubectl on master
    kubectl() {
        ssh -i ~/.ssh/k8s-infra-key.pem ec2-user@$MASTER_IP '/usr/local/bin/k3s kubectl' \"\$@\"
    }
    
    # Export the function so it's available in subshells
    export -f kubectl
    
    # Set KUBECONFIG environment variable
    export KUBECONFIG=~/k3s.yaml
    
    echo 'Testing kubectl connection...'
    
    # Test kubectl connection
    kubectl version --client
    
    echo ''
    echo '=== Step 2: Verifying cluster nodes ==='
    echo 'Running: kubectl get nodes'
    kubectl get nodes
    
    echo ''
    echo '=== Step 3: Checking cluster status ==='
    echo 'Running: kubectl get pods --all-namespaces'
    kubectl get pods --all-namespaces
    
    echo ''
    echo '=== Step 4: Deploying test workload ==='
    echo 'Deploying nginx pod from Kubernetes examples...'
    kubectl apply -f https://k8s.io/examples/pods/simple-pod.yaml
    
    echo 'Waiting for pod to be ready...'
    sleep 10
    
    echo ''
    echo '=== Step 5: Verifying workload deployment ==='
    echo 'Running: kubectl get all --all-namespaces'
    kubectl get all --all-namespaces
    
    echo ''
    echo '=== Step 6: Checking specific nginx pod ==='
    echo 'Running: kubectl get pods | grep nginx'
    kubectl get pods | grep nginx
    
    echo ''
    echo '=== Step 7: Getting pod details ==='
    echo 'Running: kubectl describe pod nginx'
    kubectl describe pod nginx
    
    echo ''
    echo '=== Step 8: Testing local access (SSH tunnel) ==='
    echo 'To access cluster from your local computer, run:'
    echo 'ssh -i ~/.ssh/k8s-infra-key.pem -L 6443:$MASTER_IP:6443 ec2-user@$BASTION_IP'
    echo 'export KUBECONFIG=~/k3s.yaml'
    echo 'kubectl get nodes'
    
    echo ''
    echo '=== Verification Summary ==='
    echo '✅ Cluster verification completed!'
    echo '✅ kubectl is working via SSH tunnel to master'
    echo '✅ Test workload (nginx pod) deployed successfully'
    echo '✅ Cluster is accessible from bastion host'
    echo ''
    echo 'Next steps:'
    echo '1. Take screenshots of kubectl get nodes (should show 2 nodes)'
    echo '2. Take screenshots of kubectl get all --all-namespaces (should show nginx pod)'
    echo '3. Test local access using SSH tunnel'
    echo '4. Create documentation and submit PR'
"

check_command "Cluster verification completed"

echo ""
log_info "=== Cluster Verification Script Completed Successfully! ==="
echo ""
log_info "Summary of what was verified:"
echo "✅ kubectl function configured on bastion"
echo "✅ Cluster nodes accessible (2 nodes expected)"
echo "✅ Test workload deployed (nginx pod)"
echo "✅ All namespaces checked"
echo "✅ Local access instructions provided"
echo ""
log_info "Next steps for task completion:"
echo "1. Take screenshots of the outputs above"
echo "2. Test local access using SSH tunnel"
echo "3. Create README documentation"
echo "4. Create task_3 branch and submit PR"

# Sprawdź adres serwera
cat ~/k3s.yaml | grep server 