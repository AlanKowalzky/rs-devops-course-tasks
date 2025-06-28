#!/bin/bash
set -e

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Function to check if command succeeded
check_command() {
    if [ $? -eq 0 ]; then
        log_info "$1 - OK"
    else
        log_error "$1 - FAILED"
        exit 1
    fi
}

echo "=== Installing k3s on nodes ==="

# Check if SSH agent is running
if [ -z "$SSH_AUTH_SOCK" ]; then
    log_warn "SSH agent is not running. Starting..."
    eval $(ssh-agent -s)
    check_command "Starting SSH agent"
fi

# Check if key is added to agent
if ! ssh-add -l | grep -q "k8s-infra-key.pem"; then
    log_warn "Adding SSH key to agent..."
    ssh-add ~/.ssh/k8s-infra-key.pem
    check_command "Adding SSH key"
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    log_warn "jq is not installed. Using alternative JSON parsing method..."
    USE_JQ=false
else
    USE_JQ=true
fi

# Get node IPs from Terraform outputs
log_info "Getting node IPs..."
NODES_JSON=$(terraform output -json k3s_nodes_private_ips)

if [ "$USE_JQ" = true ]; then
    # Use jq if available
    MASTER_IP=$(echo "$NODES_JSON" | jq -r '.[0]')
    WORKER_IP=$(echo "$NODES_JSON" | jq -r '.[1]')
else
    # Alternative JSON parsing method without jq
    # Remove square brackets and quotes, split by commas
    CLEAN_JSON=$(echo "$NODES_JSON" | tr -d '[]"' | sed 's/,/ /g')
    
    # Check if awk is available
    if command -v awk &> /dev/null; then
        MASTER_IP=$(echo "$CLEAN_JSON" | awk '{print $1}')
        WORKER_IP=$(echo "$CLEAN_JSON" | awk '{print $2}')
    elif command -v cut &> /dev/null; then
        # Use cut as alternative
        MASTER_IP=$(echo "$CLEAN_JSON" | cut -d' ' -f1)
        WORKER_IP=$(echo "$CLEAN_JSON" | cut -d' ' -f2)
    else
        # Final method using read
        read MASTER_IP WORKER_IP <<< "$CLEAN_JSON"
    fi
fi

BASTION_IP=$(terraform output -raw bastion_public_ip)

# Check if IPs are correctly retrieved
if [ "$MASTER_IP" = "null" ] || [ "$WORKER_IP" = "null" ] || [ "$BASTION_IP" = "null" ]; then
    log_error "Failed to retrieve node IPs. Check if Terraform has been applied."
    exit 1
fi

log_info "Master IP: $MASTER_IP"
log_info "Worker IP: $WORKER_IP"
log_info "Bastion IP: $BASTION_IP"

# SSH key path
SSH_KEY=~/.ssh/k8s-infra-key.pem

# Function to test SSH connection
test_ssh_connection() {
    local host=$1
    local description=$2
    
    log_info "Testing SSH connection to $description ($host)..."
    timeout 30 ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$host "echo 'SSH connection successful'" > /dev/null 2>&1
    check_command "SSH connection to $description"
}

# Test connections
test_ssh_connection $MASTER_IP "master node"
test_ssh_connection $WORKER_IP "worker node"

# Function to install k3s on master with fixes
install_k3s_master() {
    log_info "=== Installing k3s on master ==="
    
    # Check if k3s is already running
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "
        if systemctl is-active --quiet k3s; then
            echo 'K3s is already running on master. Skipping installation.'
            exit 0
        fi
    " || true
    
    # Install k3s on master with corrected service file
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "
        # Download k3s binary
        curl -Lo k3s https://github.com/k3s-io/k3s/releases/download/v1.32.5+k3s1/k3s
        chmod +x k3s
        sudo mv k3s /usr/local/bin/
        
        # Create corrected systemd service file
        sudo tee /etc/systemd/system/k3s.service > /dev/null <<EOF
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
After=network-online.target

[Service]
Type=notify
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s server
KillMode=process
Delegate=yes
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        
        # Check service file syntax
        sudo systemd-analyze verify /etc/systemd/system/k3s.service
        
        # Start service
        sudo systemctl daemon-reload
        sudo systemctl enable k3s
        sudo systemctl start k3s
        
        # Wait for startup
        sleep 30
        
        # Check status
        sudo systemctl status k3s --no-pager
    "
    check_command "Installing k3s on master"
}

# Function to fix permissions on master
fix_master_permissions() {
    log_info "=== Fixing permissions on master ==="
    
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "
        # Fix kubeconfig file permissions
        sudo chmod 644 /etc/rancher/k3s/k3s.yaml
        sudo chown root:root /etc/rancher/k3s/k3s.yaml
        
        # Copy config file to user home directory
        mkdir -p ~/.kube
        sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
        sudo chown ec2-user:ec2-user ~/.kube/config
        chmod 600 ~/.kube/config
        
        # Set KUBECONFIG environment variable
        if ! grep -q 'export KUBECONFIG=' ~/.bashrc; then
            echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
        fi
        export KUBECONFIG=~/.kube/config
        
        # Create correct kubectl alias using full path
        if ! grep -q 'alias kubectl=' ~/.bashrc; then
            echo 'alias kubectl=\"/usr/local/bin/k3s kubectl\"' >> ~/.bashrc
        fi
        alias kubectl=\"/usr/local/bin/k3s kubectl\"
        
        # Check if kubectl works using full path
        if /usr/local/bin/k3s kubectl get nodes; then
            echo '✅ Kubectl is working correctly!'
        else
            echo '❌ Problem with kubectl. Check logs:'
            sudo journalctl -u k3s -n 20
        fi
    "
    check_command "Fixing permissions on master"
}

# Function to install k3s on worker with fixes
install_k3s_worker() {
    log_info "=== Installing k3s on worker ==="
    
    # Check if k3s-agent is already running
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$WORKER_IP "
        if systemctl is-active --quiet k3s-agent; then
            echo 'K3s-agent is already running on worker. Skipping installation.'
            exit 0
        fi
    " || true
    
    # Get token from master
    TOKEN=$(ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "sudo cat /var/lib/rancher/k3s/server/node-token")
    check_command "Getting k3s token"
    
    if [ -z "$TOKEN" ]; then
        log_error "K3s token is empty!"
        exit 1
    fi
    
    log_info "Token retrieved successfully"
    
    # Install k3s on worker with corrected service file
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$WORKER_IP "
        # Download k3s binary
        curl -Lo k3s https://github.com/k3s-io/k3s/releases/download/v1.32.5+k3s1/k3s
        chmod +x k3s
        sudo mv k3s /usr/local/bin/
        
        # Create corrected systemd service file for worker
        sudo tee /etc/systemd/system/k3s-agent.service > /dev/null <<EOF
[Unit]
Description=Lightweight Kubernetes Agent
Documentation=https://k3s.io
After=network-online.target

[Service]
Type=notify
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s agent --server https://$MASTER_IP:6443 --token $TOKEN
KillMode=process
Delegate=yes
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        
        # Check service file syntax
        sudo systemd-analyze verify /etc/systemd/system/k3s-agent.service
        
        # Start service
        sudo systemctl daemon-reload
        sudo systemctl enable k3s-agent
        sudo systemctl start k3s-agent
        
        # Wait for startup
        sleep 30
        
        # Check status
        sudo systemctl status k3s-agent --no-pager
    "
    check_command "Installing k3s on worker"
}

# Function to fix k3s-agent service file on worker
fix_worker_service() {
    log_info "=== Fixing k3s-agent service file on worker ==="
    
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$WORKER_IP "
        # Check if service file has syntax error
        if [ -f /etc/systemd/system/k3s-agent.service ]; then
            echo 'Checking k3s-agent service file...'
            
            # Check if file has syntax error
            if ! sudo systemd-analyze verify /etc/systemd/system/k3s-agent.service 2>/dev/null; then
                echo 'Found syntax error. Fixing service file...'
                
                # Create backup
                sudo cp /etc/systemd/system/k3s-agent.service /etc/systemd/system/k3s-agent.service.backup
                
                # Get token from master
                TOKEN=$(ssh -i ~/.ssh/k8s-infra-key.pem -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i ~/.ssh/k8s-infra-key.pem -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "sudo cat /var/lib/rancher/k3s/server/node-token")
                
                # Fix service file
                sudo tee /etc/systemd/system/k3s-agent.service > /dev/null <<EOF
[Unit]
Description=Lightweight Kubernetes Agent
Documentation=https://k3s.io
After=network-online.target

[Service]
Type=notify
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s agent --server https://$MASTER_IP:6443 --token $TOKEN
KillMode=process
Delegate=yes
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
                
                echo 'Service file fixed.'
                
                # Reload systemd
                sudo systemctl daemon-reload
                
                # Start service
                sudo systemctl enable k3s-agent
                sudo systemctl start k3s-agent
                
                echo 'Checking service status...'
                sudo systemctl status k3s-agent --no-pager -l
            else
                echo 'Service file looks correct.'
            fi
        else
            echo 'K3s-agent service file does not exist.'
        fi
    "
    check_command "Fixing k3s-agent service file"
}

# Execute installation
install_k3s_master
fix_master_permissions
install_k3s_worker
fix_worker_service

log_info "=== Waiting for cluster readiness ==="
# Wait for all nodes to be ready
for i in {1..30}; do
    log_info "Checking cluster readiness (attempt $i/30)..."
    READY_NODES=$(ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "/usr/local/bin/k3s kubectl get nodes --no-headers | grep -c 'Ready'")
    
    if [ "$READY_NODES" -eq 2 ]; then
        log_info "All nodes are ready!"
        break
    fi
    
    if [ $i -eq 30 ]; then
        log_error "Timeout - cluster is not ready after 30 attempts"
        exit 1
    fi
    
    sleep 10
done

log_info "=== Checking cluster status ==="
# Check cluster status
ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "/usr/local/bin/k3s kubectl get nodes"
ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "/usr/local/bin/k3s kubectl get pods --all-namespaces"

log_info "=== Copying kubeconfig ==="
# Copy kubeconfig to bastion and fix localhost to master IP
ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "sudo cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/$MASTER_IP/g" | ssh -i $SSH_KEY ec2-user@$BASTION_IP "cat > ~/k3s.yaml"
check_command "Copying kubeconfig to bastion"

log_info "=== Installation completed successfully! ==="
echo ""
log_info "To connect to cluster from bastion:"
echo "ssh -i ~/.ssh/k8s-infra-key.pem ec2-user@$BASTION_IP"
echo "export KUBECONFIG=~/k3s.yaml"
echo "kubectl get nodes"
echo ""
log_info "To connect to cluster locally (through bastion):"
echo "ssh -i ~/.ssh/k8s-infra-key.pem -L 6443:$MASTER_IP:6443 ec2-user@$BASTION_IP"
echo "export KUBECONFIG=~/k3s.yaml"
echo "kubectl get nodes" 