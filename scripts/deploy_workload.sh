#!/bin/sh

# deploy_workload.sh - Deploy sample nginx workload to k3s cluster
# This script deploys the nginx pod from official Kubernetes examples

set -e

# Colors for output (tput fallback)
if command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    NC=$(tput sgr0)
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

# Function to print colored output
print_status() {
    echo "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl > /dev/null 2>&1; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    print_success "kubectl found"
}

# Check cluster connectivity
check_cluster() {
    print_status "Checking cluster connectivity..."
    
    if ! kubectl cluster-info > /dev/null 2>&1; then
        print_error "Cannot connect to cluster. Please ensure:"
        print_error "1. Cluster is running"
        print_error "2. Kubeconfig is properly configured"
        print_error "3. You have access to the cluster"
        exit 1
    fi
    
    print_success "Cluster connectivity verified"
}

# Get cluster nodes
show_nodes() {
    print_status "Current cluster nodes:"
    kubectl get nodes
    echo
}

# Deploy nginx workload
deploy_nginx() {
    print_status "Deploying nginx workload from official Kubernetes examples..."
    
    # Download and apply the nginx pod manifest
    if kubectl apply -f https://k8s.io/examples/pods/simple-pod.yaml; then
        print_success "Nginx pod manifest applied successfully"
    else
        print_error "Failed to apply nginx pod manifest"
        exit 1
    fi
}

# Wait for pod to be ready
wait_for_pod() {
    print_status "Waiting for nginx pod to be ready..."
    
    max_attempts=30
    attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if kubectl get pods nginx | grep -q "Running"; then
            print_success "Nginx pod is running"
            return 0
        fi
        
        print_status "Attempt $attempt/$max_attempts - Pod not ready yet, waiting..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    print_error "Timeout waiting for nginx pod to be ready"
    return 1
}

# Show pod details
show_pod_details() {
    print_status "Nginx pod details:"
    kubectl get pods nginx -o wide
    echo
    
    print_status "Pod description:"
    kubectl describe pod nginx
    echo
}

# Show all resources
show_all_resources() {
    print_status "All resources in all namespaces:"
    kubectl get all --all-namespaces
    echo
}

# Test pod connectivity (if possible)
test_pod_connectivity() {
    print_status "Testing nginx pod connectivity..."
    
    # Try to get pod logs
    if kubectl logs nginx > /dev/null 2>&1; then
        print_success "Pod logs accessible"
        print_status "Recent pod logs:"
        kubectl logs nginx --tail=10
    else
        print_warning "Cannot access pod logs yet"
    fi
    
    echo
}

# Main execution
main() {
    echo "=========================================="
    echo "  K3s Workload Deployment Script"
    echo "=========================================="
    echo
    
    # Check prerequisites
    check_kubectl
    check_cluster
    
    # Show current state
    show_nodes
    
    # Deploy workload
    deploy_nginx
    
    # Wait for deployment
    if wait_for_pod; then
        # Show results
        show_pod_details
        show_all_resources
        test_pod_connectivity
        
        print_success "Workload deployment completed successfully!"
        print_status "You can now verify the nginx pod is running with:"
        echo "  kubectl get pods nginx"
        echo "  kubectl get all --all-namespaces"
    else
        print_error "Workload deployment failed"
        exit 1
    fi
}

# Run main function
main "$@" 