#!/bin/bash
set -e

# Kolory dla lepszej czytelności
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funkcja do logowania
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Funkcja do sprawdzania czy komenda się udała
check_command() {
    if [ $? -eq 0 ]; then
        log_info "$1 - OK"
    else
        log_error "$1 - FAILED"
        exit 1
    fi
}

echo "=== Instalacja k3s na nodach ==="

# Sprawdź czy SSH agent działa
if [ -z "$SSH_AUTH_SOCK" ]; then
    log_warn "SSH agent nie jest uruchomiony. Uruchamiam..."
    eval $(ssh-agent -s)
    check_command "Uruchomienie SSH agent"
fi

# Sprawdź czy klucz jest dodany do agenta
if ! ssh-add -l | grep -q "k8s-infra-key.pem"; then
    log_warn "Dodaję klucz SSH do agenta..."
    ssh-add ~/.ssh/k8s-infra-key.pem
    check_command "Dodanie klucza SSH"
fi

# Sprawdź czy jq jest dostępne
if ! command -v jq &> /dev/null; then
    log_error "jq nie jest zainstalowane. Zainstaluj jq aby kontynuować."
    exit 1
fi

# Pobierz IP nodów z outputów Terraform
log_info "Pobieranie IP nodów..."
NODES_JSON=$(terraform output -json k3s_nodes_private_ips)
MASTER_IP=$(echo "$NODES_JSON" | jq -r '.[0]')
WORKER_IP=$(echo "$NODES_JSON" | jq -r '.[1]')
BASTION_IP=$(terraform output -raw bastion_public_ip)

# Sprawdź czy IP są poprawnie pobrane
if [ "$MASTER_IP" = "null" ] || [ "$WORKER_IP" = "null" ] || [ "$BASTION_IP" = "null" ]; then
    log_error "Nie udało się pobrać IP nodów. Sprawdź czy Terraform został zastosowany."
    exit 1
fi

log_info "Master IP: $MASTER_IP"
log_info "Worker IP: $WORKER_IP"
log_info "Bastion IP: $BASTION_IP"

# Ścieżka do klucza SSH
SSH_KEY=~/.ssh/k8s-infra-key.pem

# Funkcja do testowania połączenia SSH
test_ssh_connection() {
    local host=$1
    local description=$2
    
    log_info "Testowanie połączenia SSH do $description ($host)..."
    timeout 30 ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$host "echo 'SSH connection successful'" > /dev/null 2>&1
    check_command "Połączenie SSH do $description"
}

# Testuj połączenia
test_ssh_connection $MASTER_IP "master node"
test_ssh_connection $WORKER_IP "worker node"

# Funkcja do instalacji k3s na masterze z poprawkami
install_k3s_master() {
    log_info "=== Instalacja k3s na masterze ==="
    
    # Sprawdź czy k3s już działa
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "
        if systemctl is-active --quiet k3s; then
            echo 'K3s już działa na masterze. Pomijam instalację.'
            exit 0
        fi
    " || true
    
    # Instalacja k3s na masterze z poprawionym plikiem serwisu
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "
        # Pobierz binarny k3s
        curl -Lo k3s https://github.com/k3s-io/k3s/releases/download/v1.32.5+k3s1/k3s
        chmod +x k3s
        sudo mv k3s /usr/local/bin/
        
        # Utwórz poprawiony plik serwisu systemd
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
        
        # Sprawdź składnię pliku serwisu
        sudo systemd-analyze verify /etc/systemd/system/k3s.service
        
        # Uruchom serwis
        sudo systemctl daemon-reload
        sudo systemctl enable k3s
        sudo systemctl start k3s
        
        # Czekaj na uruchomienie
        sleep 30
        
        # Sprawdź status
        sudo systemctl status k3s --no-pager
    "
    check_command "Instalacja k3s na masterze"
}

# Funkcja do naprawy uprawnień na masterze
fix_master_permissions() {
    log_info "=== Naprawa uprawnień na masterze ==="
    
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "
        # Popraw uprawnienia do pliku kubeconfig
        sudo chmod 644 /etc/rancher/k3s/k3s.yaml
        sudo chown root:root /etc/rancher/k3s/k3s.yaml
        
        # Skopiuj plik konfiguracyjny do katalogu domowego użytkownika
        mkdir -p ~/.kube
        sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
        sudo chown ec2-user:ec2-user ~/.kube/config
        chmod 600 ~/.kube/config
        
        # Ustaw zmienną środowiskową KUBECONFIG
        if ! grep -q 'export KUBECONFIG=' ~/.bashrc; then
            echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
        fi
        export KUBECONFIG=~/.kube/config
        
        # Utwórz poprawny alias kubectl
        if ! grep -q 'alias kubectl=' ~/.bashrc; then
            echo 'alias kubectl=\"sudo k3s kubectl\"' >> ~/.bashrc
        fi
        alias kubectl=\"sudo k3s kubectl\"
        
        # Sprawdź czy kubectl działa
        if sudo k3s kubectl get nodes; then
            echo '✅ Kubectl działa poprawnie!'
        else
            echo '❌ Problem z kubectl. Sprawdź logi:'
            sudo journalctl -u k3s -n 20
        fi
    "
    check_command "Naprawa uprawnień na masterze"
}

# Funkcja do instalacji k3s na workerze z poprawkami
install_k3s_worker() {
    log_info "=== Instalacja k3s na workerze ==="
    
    # Sprawdź czy k3s-agent już działa
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$WORKER_IP "
        if systemctl is-active --quiet k3s-agent; then
            echo 'K3s-agent już działa na workerze. Pomijam instalację.'
            exit 0
        fi
    " || true
    
    # Pobierz token z mastera
    TOKEN=$(ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "sudo cat /var/lib/rancher/k3s/server/node-token")
    check_command "Pobranie tokenu k3s"
    
    if [ -z "$TOKEN" ]; then
        log_error "Token k3s jest pusty!"
        exit 1
    fi
    
    log_info "Token pobrany pomyślnie"
    
    # Instalacja k3s na workerze z poprawionym plikiem serwisu
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$WORKER_IP "
        # Pobierz binarny k3s
        curl -Lo k3s https://github.com/k3s-io/k3s/releases/download/v1.32.5+k3s1/k3s
        chmod +x k3s
        sudo mv k3s /usr/local/bin/
        
        # Utwórz poprawiony plik serwisu systemd dla workera
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
        
        # Sprawdź składnię pliku serwisu
        sudo systemd-analyze verify /etc/systemd/system/k3s-agent.service
        
        # Uruchom serwis
        sudo systemctl daemon-reload
        sudo systemctl enable k3s-agent
        sudo systemctl start k3s-agent
        
        # Czekaj na uruchomienie
        sleep 30
        
        # Sprawdź status
        sudo systemctl status k3s-agent --no-pager
    "
    check_command "Instalacja k3s na workerze"
}

# Wykonaj instalację
install_k3s_master
fix_master_permissions
install_k3s_worker

log_info "=== Czekam na gotowość klastra ==="
# Czekaj na gotowość wszystkich nodów
for i in {1..30}; do
    log_info "Sprawdzanie gotowości klastra (próba $i/30)..."
    READY_NODES=$(ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "sudo k3s kubectl get nodes --no-headers | grep -c 'Ready'")
    
    if [ "$READY_NODES" -eq 2 ]; then
        log_info "Wszystkie nody są gotowe!"
        break
    fi
    
    if [ $i -eq 30 ]; then
        log_error "Timeout - klaster nie jest gotowy po 30 próbach"
        exit 1
    fi
    
    sleep 10
done

log_info "=== Sprawdzanie statusu klastra ==="
# Sprawdź status klastra
ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "sudo k3s kubectl get nodes"
ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "sudo k3s kubectl get pods --all-namespaces"

log_info "=== Kopiowanie kubeconfig ==="
# Skopiuj kubeconfig na bastiona i popraw localhost na master IP
ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "sudo cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/$MASTER_IP/g" | ssh -i $SSH_KEY ec2-user@$BASTION_IP "cat > ~/k3s.yaml"
check_command "Kopiowanie kubeconfig na bastion"

log_info "=== Instalacja zakończona pomyślnie! ==="
echo ""
log_info "Aby połączyć się z klastrem z bastiona:"
echo "ssh -i ~/.ssh/k8s-infra-key.pem ec2-user@$BASTION_IP"
echo "export KUBECONFIG=~/k3s.yaml"
echo "kubectl get nodes"
echo ""
log_info "Aby połączyć się z klastrem lokalnie (przez bastion):"
echo "ssh -i ~/.ssh/k8s-infra-key.pem -L 6443:$MASTER_IP:6443 ec2-user@$BASTION_IP"
echo "export KUBECONFIG=~/k3s.yaml"
echo "kubectl get nodes" 