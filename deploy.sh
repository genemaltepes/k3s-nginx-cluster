#!/bin/bash
#
# K3S HA Cluster Deployment Script
# Version 2.0 - Without External Storage
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to print banner
print_banner() {
    echo -e "${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     K3S HA Cluster Deployment                            ║
║     Version 2.0 - Simplified Architecture                ║
║                                                           ║
║     Components:                                           ║
║       • 1 Load Balancer (Nginx + Keepalived)            ║
║       • 3 Master Nodes (K3S + etcd + storage)           ║
║       • 3 Worker Nodes (K3S + storage)                  ║
║                                                           ║
║     Total VMs: 7                                         ║
║     Storage: Local Path Provisioner                      ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing=0
    
    # Check for Ansible
    if ! command -v ansible &> /dev/null; then
        print_error "Ansible is not installed"
        missing=1
    else
        print_success "Ansible found: $(ansible --version | head -n1)"
    fi
    
    # Check for Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed"
        missing=1
    else
        print_success "Terraform found: $(terraform version -json | grep -o '"version":"[^"]*' | cut -d'"' -f4)"
    fi
    
    # Check for SSH key
    if [ ! -f ~/.ssh/id_ed25519 ]; then
        print_warning "SSH key not found at ~/.ssh/id_ed25519"
        print_info "Generate it with: ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ''"
        missing=1
    else
        print_success "SSH key found"
    fi
    
    # Check for kubectl (optional)
    if command -v kubectl &> /dev/null; then
        print_success "kubectl found: $(kubectl version --client --short 2>/dev/null | head -n1)"
    else
        print_warning "kubectl not found (optional, but recommended)"
    fi
    
    if [ $missing -eq 1 ]; then
        print_error "Missing prerequisites. Please install required tools."
        exit 1
    fi
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    print_info "Deploying infrastructure with Terraform..."
    
    cd terraform
    
    if [ ! -f terraform.tfvars ]; then
        print_error "terraform.tfvars not found!"
        print_info "Create it with your Proxmox credentials:"
        cat << 'EOF'
cat > terraform.tfvars << 'TFVARS'
proxmox_api_url = "https://192.168.1.192:8006/api2/json"
proxmox_token_id = "root@pam!terraform"
proxmox_token_secret = "your-token-secret-here"
TFVARS
EOF
        exit 1
    fi
    
    terraform init
    terraform plan -out=tfplan
    terraform apply tfplan
    
    cd ..
    print_success "Infrastructure deployed successfully"
}

# Test Ansible connectivity
test_connectivity() {
    print_info "Testing Ansible connectivity..."
    
    cd ansible
    
    if ansible all -i inventory.yml -m ping; then
        print_success "All nodes are reachable"
    else
        print_error "Some nodes are not reachable"
        exit 1
    fi
    
    cd ..
}

# Deploy K3S cluster
deploy_cluster() {
    print_info "Deploying K3S cluster..."
    
    cd ansible
    
    print_info "Phase 1: Installing prerequisites..."
    ansible-playbook -i inventory.yml playbooks/prerequisites.yml
    
    print_info "Phase 2: Setting up load balancer..."
    ansible-playbook -i inventory.yml playbooks/loadbalancer.yml
    
    print_info "Phase 3: Deploying K3S masters..."
    ansible-playbook -i inventory.yml playbooks/k3s-masters.yml
    
    print_info "Phase 4: Verifying and restarting..."
    ansible-playbook -i inventory.yml playbooks/verify-nginx-k3s.yml
    
    print_info "Phase 5: Deploying K3S workers..."
    ansible-playbook -i inventory.yml playbooks/k3s-workers.yml
    
    print_info "Phase 6: Running validation..."
    ansible-playbook -i inventory.yml playbooks/validate.yml
    
    cd ..
    print_success "K3S cluster deployed successfully"
}

# Get kubeconfig
get_kubeconfig() {
    print_info "Retrieving kubeconfig..."
    
    mkdir -p ~/.kube
    
    # Get kubeconfig from first master
    if ssh ansible@192.168.1.211 "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/k3s-ha-config 2>/dev/null; then
        # Replace localhost with VIP
        sed -i 's/127.0.0.1/192.168.1.200/g' ~/.kube/k3s-ha-config
        
        export KUBECONFIG=~/.kube/k3s-ha-config
        
        print_success "Kubeconfig saved to ~/.kube/k3s-ha-config"
        print_info "To use: export KUBECONFIG=~/.kube/k3s-ha-config"
    else
        print_warning "Could not retrieve kubeconfig automatically"
        print_info "Retrieve manually: ssh ansible@192.168.1.211 'sudo cat /etc/rancher/k3s/k3s.yaml'"
    fi
}

# Verify deployment
verify_deployment() {
    print_info "Verifying deployment..."
    
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl not found, skipping verification"
        return
    fi
    
    export KUBECONFIG=~/.kube/k3s-ha-config
    
    print_info "Cluster nodes:"
    kubectl get nodes -o wide || print_warning "Could not get nodes"
    
    print_info "Cluster pods:"
    kubectl get pods -A || print_warning "Could not get pods"
    
    print_info "Storage classes:"
    kubectl get storageclass || print_warning "Could not get storage classes"
    
    print_success "Deployment verification complete"
}

# Print summary
print_summary() {
    echo -e "\n${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     Deployment Complete!                                  ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo -e "${BLUE}Cluster Information:${NC}"
    echo "  • API Endpoint: https://192.168.1.200:6443"
    echo "  • Load Balancer: 192.168.1.210"
    echo "  • Masters: 192.168.1.211-213"
    echo "  • Workers: 192.168.1.221-223"
    echo ""
    echo -e "${BLUE}Storage:${NC}"
    echo "  • Storage Class: local-path (default)"
    echo "  • Location: /var/lib/rancher/k3s/storage (on each node)"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Export kubeconfig:"
    echo "     export KUBECONFIG=~/.kube/k3s-ha-config"
    echo ""
    echo "  2. Verify cluster:"
    echo "     kubectl get nodes"
    echo "     kubectl get pods -A"
    echo ""
    echo "  3. Check storage:"
    echo "     kubectl get storageclass"
    echo ""
    echo "  4. Test VIP:"
    echo "     curl -k https://192.168.1.200:6443/ping"
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "  • Architecture: docs/ARCHITECTURE.md"
    echo "  • Deployment Checklist: docs/DEPLOYMENT-CHECKLIST.md"
    echo "  • kubectl Guide: docs/KUBECTL-GUIDE.md"
    echo "  • Change History: docs/CHANGES.md"
    echo ""
}

# Main deployment function
main() {
    print_banner
    
    case "${1:-all}" in
        check)
            check_prerequisites
            ;;
        infrastructure|infra)
            check_prerequisites
            deploy_infrastructure
            ;;
        test)
            test_connectivity
            ;;
        cluster)
            deploy_cluster
            get_kubeconfig
            verify_deployment
            ;;
        verify)
            verify_deployment
            ;;
        all)
            check_prerequisites
            deploy_infrastructure
            test_connectivity
            deploy_cluster
            get_kubeconfig
            verify_deployment
            print_summary
            ;;
        *)
            echo "Usage: $0 {check|infrastructure|test|cluster|verify|all}"
            echo ""
            echo "Commands:"
            echo "  check          - Check prerequisites"
            echo "  infrastructure - Deploy infrastructure with Terraform"
            echo "  test          - Test Ansible connectivity"
            echo "  cluster       - Deploy K3S cluster"
            echo "  verify        - Verify deployment"
            echo "  all           - Run complete deployment (default)"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
