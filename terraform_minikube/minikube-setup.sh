#!/bin/bash
set -euxo pipefail

echo "=== START SETUP ==="

# =============================================================================
# SEGMENT 1: SPRAWDZENIE ZASOBÓW SYSTEMU
# =============================================================================
echo "=== SEGMENT 1: Sprawdzanie zasobów systemu ==="

# Sprawdzenie dostępnej pamięci RAM (w MB)
MIN_RAM_MB=2048
RAM_TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)

echo "RAM: ${RAM_TOTAL_MB}MB"

if [ "$RAM_TOTAL_MB" -lt "$MIN_RAM_MB" ]; then
  echo "!!! UWAGA: Wykryto tylko ${RAM_TOTAL_MB}MB RAM. Jenkins zaleca co najmniej ${MIN_RAM_MB}MB."
  echo "!!! Jesteś na Free Tier AWS (t2.micro/t3.micro)? Jenkins MOŻE działać niestabilnie lub wcale."
  echo "!!! Kontynuuję instalację na własne ryzyko (Free Tier)!"
else
  echo "✅ Wykryto ${RAM_TOTAL_MB}MB RAM - wystarczająco do uruchomienia Jenkinsa."
fi

# =============================================================================
# SEGMENT 2: AKTUALIZACJA SYSTEMU I INSTALACJA DOCKER
# =============================================================================
echo "=== SEGMENT 2: Aktualizacja systemu i instalacja Docker ==="

echo "Aktualizuję system..."
sudo apt-get update && sudo apt-get upgrade -y
echo "✅ System zaktualizowany"

echo "Instaluję Docker..."
sudo apt-get install -y docker.io
echo "✅ Docker zainstalowany"

# DODANA ZMIANA: Dodanie użytkownika ubuntu do grupy docker
echo "Dodaję użytkownika 'ubuntu' do grupy 'docker'..."
sudo usermod -aG docker ubuntu
echo "✅ Użytkownik 'ubuntu' dodany do grupy 'docker'"

# WAŻNE: Po zakończeniu działania cloud-init, będziesz musiał zrestartować instancję
# lub zalogować się ponownie jako użytkownik 'ubuntu', aby zmiany grupy były aktywne.

# =============================================================================
# SEGMENT 3: INSTALACJA KUBECTL
# =============================================================================
echo "=== SEGMENT 3: Instalacja kubectl ==="

echo "Aktualizuję certyfikaty CA..."
sudo apt-get update
sudo apt-get install -y ca-certificates
sudo update-ca-certificates

echo "Aktualny czas systemowy:"
date

echo "Pobieram kubectl z oficjalnej strony (z retry)..."
curl -LO --retry 5 --retry-delay 5 "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" || { echo "❌ Błąd pobierania kubectl!"; exit 1; }

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

echo "✅ kubectl zainstalowany jako binarka w /usr/local/bin/kubectl"

# =============================================================================
# SEGMENT 4: INSTALACJA MINIKUBE
# =============================================================================
echo "=== SEGMENT 4: Instalacja Minikube ==="

echo "Pobieram Minikube (z timeout)..."
timeout 60 curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 || {
  echo "❌ Błąd pobierania Minikube - używam alternatywnego źródła"
  timeout 60 curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64 || {
    echo "❌ Błąd pobierania Minikube - kończę"
    exit 1
  }
}
sudo install minikube-linux-amd64 /usr/local/bin/minikube
sudo ln -sf /usr/local/bin/minikube /usr/bin/minikube
echo "✅ Minikube zainstalowany"

# =============================================================================
# SEGMENT 5: URUCHOMIENIE MINIKUBE
# =============================================================================
echo "=== SEGMENT 5: Uruchomienie Minikube ==="

echo "Uruchamiam Minikube na 2 CPU, 2000MB RAM (jako użytkownik ubuntu)..."
# Uruchamiam jako użytkownik ubuntu (bez sudo) - sudo powoduje problemy z certyfikatami
# Najpierw upewniam się, że użytkownik ubuntu jest w grupie docker
sudo usermod -aG docker ubuntu

# Uruchamiam minikube jako użytkownik ubuntu (bez sudo)
sudo -u ubuntu minikube start --driver=docker --cpus=2 --memory=2000mb --force || {
  echo "❌ Błąd uruchamiania Minikube! Sprawdzam logi..."
  sudo -u ubuntu minikube logs --file=/tmp/minikube_error.log
  echo "Ostatnie logi minikube:"
  sudo -u ubuntu tail -20 /tmp/minikube_error.log
  exit 1
}

echo "✅ Minikube uruchomiony! Sprawdzam status..."

# Czekam na pełne uruchomienie Minikube z timeoutem (jako użytkownik ubuntu)
echo "Czekam na pełne uruchomienie Minikube (max 5 minut)..."
timeout 300 bash -c 'until sudo -u ubuntu minikube status | grep -q "host: Running" && sudo -u ubuntu minikube kubectl get nodes > /dev/null 2>&1; do 
  echo "⏳ Czekam na Minikube... (status: $(sudo -u ubuntu minikube status | head -1))"
  sleep 10
done' || {
  echo "❌ Minikube nie uruchomił się poprawnie w oczekiwanym czasie!"
  echo "Status minikube:"
  sudo -u ubuntu minikube status
  echo "Logi minikube:"
  sudo -u ubuntu minikube logs --file=/tmp/minikube_timeout.log
  sudo -u ubuntu tail -20 /tmp/minikube_timeout.log
  exit 1
}

echo "✅ Minikube gotowy i API dostępne!"

# Sprawdź czy kubectl działa (jako użytkownik ubuntu)
echo "Sprawdzam czy kubectl działa..."
sudo -u ubuntu minikube kubectl get nodes || {
  echo "❌ Problem z kubectl! Sprawdzam konfigurację..."
  sudo -u ubuntu minikube kubectl config view
  exit 1
}

echo "✅ Kubectl działa poprawnie!"

# Konfiguruj kubectl do pracy z Minikube
echo "Konfiguruję kubectl do pracy z Minikube..."
sudo -u ubuntu minikube kubectl config view --minify --flatten > /tmp/kubeconfig
sudo cp /tmp/kubeconfig /root/.kube/config
sudo chown root:root /root/.kube/config
sudo chmod 600 /root/.kube/config
echo "✅ Kubectl skonfigurowane do pracy z Minikube!"

# =============================================================================
# SEGMENT 6: INSTALACJA HELM
# =============================================================================
echo "=== SEGMENT 6: Instalacja Helm ==="

echo "Instaluję Helm z oficjalnego repozytorium..."
# Dodaj klucz GPG Helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null

# Dodaj repozytorium Helm
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

# Aktualizuj listę pakietów
sudo apt-get update

# Zainstaluj Helm
sudo apt-get install -y helm || {
  echo "❌ Błąd instalacji Helm! Sprawdzam alternatywne źródło..."
  # Alternatywna instalacja Helm
  curl https://get.helm.sh/helm-v3.15.0-linux-amd64.tar.gz | tar xz
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64
  echo "✅ Helm zainstalowany z alternatywnego źródła"
}

# Sprawdź czy Helm działa
echo "Sprawdzam czy Helm działa..."
helm version || {
  echo "❌ Helm nie działa! Sprawdzam instalację..."
  which helm
  ls -la /usr/local/bin/helm
  exit 1
}

echo "✅ Helm zainstalowany z oficjalnego repozytorium"

# =============================================================================
# SEGMENT 7: KONFIGURACJA STORAGECLASS
# =============================================================================
echo "=== SEGMENT 7: Konfiguracja StorageClass ==="

# --- ZMIANA: Usuwam ręczne generowanie pliku local-path-storage.yaml ---
# echo "Tworzę StorageClass local-path lokalnie..."
# cat > /tmp/local-path-storage.yaml << 'EOF'
# ... stary manifest ...
# EOF

# --- NOWE: Pobieram oficjalny manifest local-path-provisioner i instaluję ---
echo "Pobieram oficjalny manifest local-path-provisioner..."
curl -sSL -o /tmp/local-path-storage.yaml https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml || { echo "❌ Błąd pobierania manifestu local-path-provisioner!"; exit 1; }

# Instaluję StorageClass local-path z oficjalnego manifestu
# Czekam na dostępność Minikube przed próbą użycia kubectl

echo "Instaluję StorageClass local-path z oficjalnego manifestu..."
timeout 120 bash -c 'until sudo -u ubuntu minikube kubectl apply -- -f /tmp/local-path-storage.yaml; do echo "Czekam na Minikube API do apply StorageClass..."; sleep 10; done' || { echo "❌ Nie udało się zainstalować StorageClass!"; exit 1; }
echo "✅ StorageClass local-path zainstalowany"

# Patchuję StorageClass local-path na domyślny

echo "Ustawiam StorageClass local-path jako domyślny..."
timeout 60 bash -c 'until sudo -u ubuntu minikube kubectl patch storageclass local-path -- -p '"'"'{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'"'"'; do echo "Czekam na StorageClass..."; sleep 5; done' || { echo "❌ Nie udało się ustawić StorageClass jako domyślnego!"; exit 1; }
echo "✅ StorageClass ustawiony jako domyślny"

# --- NOWE: Czekam na Running pod local-path-provisioner ---
echo "Czekam na Running pod local-path-provisioner..."
timeout 120 bash -c 'until sudo -u ubuntu minikube kubectl -- get pods --namespace=local-path-storage | grep local-path-provisioner | grep -q "1/1 *Running"; do echo "⏳ Czekam na pod local-path-provisioner..."; sleep 5; done' || { echo "❌ Pod local-path-provisioner nie jest Running!"; sudo -u ubuntu minikube kubectl -- get pods --namespace=local-path-storage; exit 1; }
echo "✅ Pod local-path-provisioner jest Running!"

# =============================================================================
# SEGMENT 8: PRZYGOTOWANIE JCASC
# =============================================================================
echo "=== SEGMENT 8: Przygotowanie JCasC ==="

echo "Kopiuję plik JCasC..."
cp $(dirname "$0")/jenkins-jcasc.yaml /tmp/jenkins-jcasc.yaml
echo "✅ Plik JCasC skopiowany do /tmp/jenkins-jcasc.yaml"

# =============================================================================
# SEGMENT 9: INSTALACJA JENKINSA
# =============================================================================
echo "=== SEGMENT 9: Instalacja Jenkinsa ==="

echo "Tworzę namespace jenkins (jeśli nie istnieje)..."
sudo -u ubuntu minikube kubectl create namespace jenkins || echo "Namespace jenkins już istnieje"
echo "✅ Namespace jenkins gotowy"

echo "Dodaję repozytorium Jenkins Helm..."
helm repo add jenkins https://charts.jenkins.io
helm repo update
echo "✅ Repozytorium Jenkins dodane"

echo "Instaluję Jenkinsa z JCasC w namespace jenkins..."
timeout 600 sudo -u ubuntu helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  --set controller.adminPassword=admin \
  --set persistence.enabled=true \
  --set persistence.size=5Gi \
  --set persistence.storageClass=local-path \
  --set controller.resources.requests.memory=\"512Mi\" \
  --set controller.resources.requests.cpu=\"250m\" \
  --set controller.resources.limits.memory=\"1Gi\" \
  --set controller.resources.limits.cpu=\"500m\" \
  --set controller.serviceType=NodePort \
  --set controller.serviceNodePort=8080 \
  --set-file controller.JCasC.configScripts.jcasc=/tmp/jenkins-jcasc.yaml \
  --wait || { echo "❌ Błąd instalacji Jenkinsa Helm!"; exit 1; }
echo "✅ Jenkins zainstalowany z JCasC w namespace jenkins!"

# =============================================================================
# SEGMENT 10: KOŃCOWE SPRAWDZENIE
# =============================================================================
echo "=== SEGMENT 10: Końcowe sprawdzenie ==="

echo "Sprawdzam czy wszystkie narzędzia działają..."
echo "1. Minikube:"
sudo -u ubuntu minikube status | head -1 || echo "❌ Problem z minikube"

echo "2. Kubectl:"
sudo -u ubuntu minikube kubectl get nodes || echo "❌ Problem z kubectl"

echo "3. Helm:"
helm version || echo "❌ Problem z helm"

echo "4. Jenkins pods:"
kubectl get pods --namespace=jenkins | grep jenkins || echo "❌ Brak podów Jenkins w namespace jenkins"

echo "✅ SETUP ZAKOŃCZONY SUKCESEM!"
echo "=== SETUP SUCCESS ==="