#!/bin/bash

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

echo "=== Local Kubernetes Cluster Access Script ==="
echo "This script helps you connect to k3s cluster from your local machine"
echo ""

# Get IPs from Terraform outputs
log_step "Getting cluster IPs from Terraform..."
MASTER_IP=$(terraform output -json k3s_nodes_private_ips | tr -d '[]"' | cut -d',' -f1)
BASTION_IP=$(terraform output -raw bastion_public_ip)

log_info "Master IP: $MASTER_IP"
log_info "Bastion IP: $BASTION_IP"

# SSH key path
SSH_KEY=~/.ssh/k8s-infra-key.pem

# Check if SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    log_error "SSH key not found: $SSH_KEY"
    exit 1
fi

# Check SSH key permissions
KEY_PERMS=$(stat -c %a "$SSH_KEY")
if [ "$KEY_PERMS" != "600" ]; then
    log_warn "SSH key has wrong permissions: $KEY_PERMS (should be 600)"
    log_info "Fixing permissions..."
    chmod 600 "$SSH_KEY"
fi

log_step "Step 1: Testing basic SSH connection to bastion..."
if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY" ec2-user@$BASTION_IP "echo 'SSH connection successful'"; then
    log_info "SSH connection to bastion works"
else
    log_error "SSH connection to bastion failed"
    log_info "Possible issues:"
    echo "  - Check if bastion is running"
    echo "  - Check security groups (SSH port 22)"
    echo "  - Check your IP is allowed in bastion security group"
    echo "  - Check SSH key is correct"
    exit 1
fi

log_step "Step 2: Testing connection to master through bastion..."
if timeout 15 ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "echo 'Connection to master successful'"; then
    log_info "Connection to master through bastion works"
else
    log_error "Connection to master through bastion failed"
    log_info "Possible issues:"
    echo "  - Check if master node is running"
    echo "  - Check security groups between bastion and master"
    echo "  - Check k3s is running on master"
    exit 1
fi

log_step "Step 3: Setting up SSH tunnel for local access..."

echo ""
log_info "Creating SSH tunnel with improved options:"
echo "Local port: 6443"
echo "Remote: $MASTER_IP:6443"
echo "Bastion: $BASTION_IP"
echo ""

# Improved SSH tunnel command with debugging options
log_info "Starting SSH tunnel (press Ctrl+C to stop)..."
echo "Command: ssh -o ConnectTimeout=10 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -i $SSH_KEY -L 6443:$MASTER_IP:6443 ec2-user@$BASTION_IP"
echo ""

ssh -o ConnectTimeout=10 \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -L 6443:$MASTER_IP:6443 \
    ec2-user@$BASTION_IP

echo ""
log_info "SSH tunnel closed"
log_info "To test cluster access, open another terminal and run:"
echo "export KUBECONFIG=~/k3s.yaml"
echo "kubectl get nodes" 