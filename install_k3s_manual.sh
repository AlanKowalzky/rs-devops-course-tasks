#!/bin/bash
set -e

echo "=== Ręczna instalacja k3s na Amazon Linux 2 (bez k3s-selinux) ==="

# Pobierz IP nodów z outputów Terraform
echo "Pobieranie IP nodów..."
NODES_JSON=$(terraform output -json k3s_nodes_private_ips)
MASTER_IP=$(echo "$NODES_JSON" | tr -d '[]"' | cut -d',' -f1)
WORKER_IP=$(echo "$NODES_JSON" | tr -d '[]"' | cut -d',' -f2)
BASTION_IP=$(terraform output -raw bastion_public_ip)

echo "Master IP: $MASTER_IP"
echo "Worker IP: $WORKER_IP"
echo "Bastion IP: $BASTION_IP"

# Ścieżka do klucza SSH
SSH_KEY=~/.ssh/k8s-infra-key.pem

# Funkcja do instalacji k3s na masterze
install_k3s_master() {
    echo "=== Instalacja k3s na masterze ==="
    
    # Sprawdź czy k3s już działa
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "
        if systemctl is-active --quiet k3s; then
            echo 'K3s już działa na masterze. Pomijam instalację.'
            # Dodaj alias kubectl jeśli nie istnieje
            if ! grep -q 'alias kubectl=' ~/.bashrc; then
                printf 'alias kubectl=\"sudo k3s kubectl\"\n' >> ~/.bashrc
                source ~/.bashrc
            fi
            exit 0
        fi
    "
    
    # Pobierz i zainstaluj k3s
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "
        # Pobierz binarny k3s
        curl -Lo k3s https://github.com/k3s-io/k3s/releases/download/v1.32.5+k3s1/k3s
        chmod +x k3s
        sudo mv k3s /usr/local/bin/
        
        # Utwórz plik serwisu systemd
        sudo tee /etc/systemd/system/k3s.service > /dev/null <<EOF
[Unit]
Description=Lightweight Kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/k3s server
Restart=always
RestartSec=5s
KillMode=process
Delegate=yes
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
        
        # Uruchom serwis
        sudo systemctl daemon-reload
        sudo systemctl enable k3s
        sudo systemctl start k3s
        
        # Czekaj na uruchomienie
        sleep 30
        
        # Sprawdź status
        sudo systemctl status k3s --no-pager
        
        # Dodaj alias kubectl
        if ! grep -q 'alias kubectl=' ~/.bashrc; then
            printf 'alias kubectl=\"sudo k3s kubectl\"\n' >> ~/.bashrc
            source ~/.bashrc
        fi
    "
}

# Funkcja do instalacji k3s na workerze
install_k3s_worker() {
    echo "=== Instalacja k3s na workerze ==="
    
    # Sprawdź czy k3s-agent już działa
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$WORKER_IP "
        if systemctl is-active --quiet k3s-agent; then
            echo 'K3s-agent już działa na workerze. Pomijam instalację.'
            # Dodaj alias kubectl jeśli nie istnieje
            if ! grep -q 'alias kubectl=' ~/.bashrc; then
                printf 'alias kubectl=\"sudo k3s kubectl\"\n' >> ~/.bashrc
                source ~/.bashrc
            fi
            exit 0
        fi
    "
    
    # Pobierz token z mastera (bez aliasu)
    TOKEN=$(ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "unalias kubectl 2>/dev/null || true; sudo cat /var/lib/rancher/k3s/server/node-token")
    echo "Token: $TOKEN"
    
    # Pobierz i zainstaluj k3s na workerze
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$WORKER_IP "
        # Pobierz binarny k3s
        curl -Lo k3s https://github.com/k3s-io/k3s/releases/download/v1.32.5+k3s1/k3s
        chmod +x k3s
        sudo mv k3s /usr/local/bin/
        
        # Utwórz plik serwisu systemd dla workera
        sudo tee /etc/systemd/system/k3s-agent.service > /dev/null <<EOF
[Unit]
Description=Lightweight Kubernetes Agent
After=network.target

[Service]
ExecStart=/usr/local/bin/k3s agent --server https://$MASTER_IP:6443 --token $TOKEN
Restart=always
RestartSec=5s
KillMode=process
Delegate=yes
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0

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
        
        # Dodaj alias kubectl
        if ! grep -q 'alias kubectl=' ~/.bashrc; then
            printf 'alias kubectl=\"sudo k3s kubectl\"\n' >> ~/.bashrc
            source ~/.bashrc
        fi
    "
}

# Funkcja do sprawdzenia statusu klastra
check_cluster_status() {
    echo "=== Sprawdzanie statusu klastra ==="
    
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "
        echo '=== Nodes ==='
        sudo kubectl get nodes
        echo '=== Pods ==='
        sudo kubectl get pods --all-namespaces
    "
}

# Funkcja do kopiowania kubeconfig
copy_kubeconfig() {
    echo "=== Kopiowanie kubeconfig ==="
    
    ssh -i $SSH_KEY -T -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p ec2-user@$BASTION_IP" ec2-user@$MASTER_IP "sudo cat /etc/rancher/k3s/k3s.yaml" | ssh -i $SSH_KEY ec2-user@$BASTION_IP "cat > ~/k3s.yaml"
    
    echo "Kubeconfig skopiowany na bastion: ~/k3s.yaml"
    echo "Aby używać kubectl z bastiona:"
    echo "export KUBECONFIG=~/k3s.yaml"
}

# Wykonaj instalację
install_k3s_master
install_k3s_worker
check_cluster_status
copy_kubeconfig

echo "=== Instalacja zakończona! ==="
echo "Klastr k3s jest gotowy do użycia." 