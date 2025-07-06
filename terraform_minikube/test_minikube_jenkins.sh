#!/bin/bash

cd "$(dirname "$0")"

echo "=== DESTROY ==="
terraform destroy -auto-approve || { echo "Błąd podczas destroy!"; exit 1; }

echo "=== APPLY ==="
terraform apply -auto-approve || { echo "Błąd podczas apply!"; exit 1; }

IP=$(terraform output -raw public_ip)
KEY="~/.ssh/id_rsa"
USER="ubuntu"

echo "=== ASYNCHRONICZNE SPRAWDZANIE SYSTEMU (max 2 minuty) ==="

# Funkcje do asynchronicznego sprawdzania
check_ssh() {
  local result
  result=$(timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "echo 'SSH OK'" 2>/dev/null && echo "OK" || echo "FAIL")
  echo "SSH:$result" > /tmp/ssh_status
}

check_network() {
  local result
  result=$(timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "sudo systemctl is-active --quiet systemd-networkd && echo 'OK' || echo 'FAIL'" 2>/dev/null)
  echo "NETWORK:$result" > /tmp/network_status
}

check_disk() {
  local result
  result=$(timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "df -h / | grep -q '^/dev' && echo 'OK' || echo 'FAIL'" 2>/dev/null)
  echo "DISK:$result" > /tmp/disk_status
}

check_memory() {
  local result
  result=$(timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "free -h | grep -q 'Mem:' && echo 'OK' || echo 'FAIL'" 2>/dev/null)
  echo "MEMORY:$result" > /tmp/memory_status
}

check_cloud_init() {
  local result
  result=$(timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "sudo cloud-init status --wait" 2>/dev/null && echo "OK" || echo "FAIL")
  echo "CLOUD_INIT:$result" > /tmp/cloud_init_status
}

check_tools() {
  local minikube_result kubectl_result helm_result
  minikube_result=$(timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "which minikube" 2>/dev/null && echo "OK" || echo "FAIL")
  kubectl_result=$(timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "which kubectl" 2>/dev/null && echo "OK" || echo "FAIL")
  helm_result=$(timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "which helm" 2>/dev/null && echo "OK" || echo "FAIL")
  echo "MINIKUBE:$minikube_result" > /tmp/minikube_status
  echo "KUBECTL:$kubectl_result" > /tmp/kubectl_status
  echo "HELM:$helm_result" > /tmp/helm_status
}

# Wyświetl status wszystkich komponentów
show_status() {
  echo "=== STATUS SYSTEMU (próba $1/24) ==="
  
  # SSH
  if [ -f /tmp/ssh_status ]; then
    ssh_status=$(cat /tmp/ssh_status | cut -d: -f2)
    if [ "$ssh_status" = "OK" ]; then
      echo "✅ SSH: Działa"
    else
      echo "❌ SSH: Nie działa"
    fi
  else
    echo "⏳ SSH: Sprawdzanie..."
  fi
  
  # Sieć
  if [ -f /tmp/network_status ]; then
    network_status=$(cat /tmp/network_status | cut -d: -f2)
    if [ "$network_status" = "OK" ]; then
      echo "✅ Sieć: Działa"
    else
      echo "❌ Sieć: Problem"
    fi
  else
    echo "⏳ Sieć: Sprawdzanie..."
  fi
  
  # Dysk
  if [ -f /tmp/disk_status ]; then
    disk_status=$(cat /tmp/disk_status | cut -d: -f2)
    if [ "$disk_status" = "OK" ]; then
      echo "✅ Dysk: OK"
    else
      echo "❌ Dysk: Problem"
    fi
  else
    echo "⏳ Dysk: Sprawdzanie..."
  fi
  
  # Pamięć
  if [ -f /tmp/memory_status ]; then
    memory_status=$(cat /tmp/memory_status | cut -d: -f2)
    if [ "$memory_status" = "OK" ]; then
      echo "✅ Pamięć: OK"
    else
      echo "❌ Pamięć: Problem"
    fi
  else
    echo "⏳ Pamięć: Sprawdzanie..."
  fi
  
  # Cloud-init
  if [ -f /tmp/cloud_init_status ]; then
    cloud_init_status=$(cat /tmp/cloud_init_status | cut -d: -f2)
    if [ "$cloud_init_status" = "OK" ]; then
      echo "✅ Cloud-init: Zakończony"
    else
      echo "⏳ Cloud-init: W trakcie"
    fi
  else
    echo "⏳ Cloud-init: Sprawdzanie..."
  fi
  
  # Narzędzia
  if [ -f /tmp/minikube_status ] && [ -f /tmp/kubectl_status ] && [ -f /tmp/helm_status ]; then
    minikube_status=$(cat /tmp/minikube_status | cut -d: -f2)
    kubectl_status=$(cat /tmp/kubectl_status | cut -d: -f2)
    helm_status=$(cat /tmp/helm_status | cut -d: -f2)
    echo "🔧 Narzędzia: Minikube($minikube_status) Kubectl($kubectl_status) Helm($helm_status)"
  else
    echo "⏳ Narzędzia: Sprawdzanie..."
  fi
  
  echo "----------------------------------------"
}

# Główna pętla asynchronicznego sprawdzania
for i in {1..24}; do
  echo "🔄 Uruchamiam asynchroniczne sprawdzanie (próba $i/24)..."
  
  # Uruchom wszystkie sprawdzenia w tle
  check_ssh &
  check_network &
  check_disk &
  check_memory &
  check_cloud_init &
  check_tools &
  
  # Czekaj na zakończenie wszystkich sprawdzeń
  wait
  
  # Wyświetl status
  show_status $i
  
  # Sprawdź czy wszystko gotowe
  if [ -f /tmp/ssh_status ] && [ -f /tmp/cloud_init_status ] && [ -f /tmp/minikube_status ]; then
    ssh_ok=$(cat /tmp/ssh_status | cut -d: -f2)
    cloud_init_ok=$(cat /tmp/cloud_init_status | cut -d: -f2)
    minikube_ok=$(cat /tmp/minikube_status | cut -d: -f2)
    
    if [ "$ssh_ok" = "OK" ] && [ "$cloud_init_ok" = "OK" ] && [ "$minikube_ok" = "OK" ]; then
      echo "🎉 WSZYSTKO GOTOWE! Przechodzę do testów."
      break
    fi
  fi
  
  echo "⏳ Czekam 5 sekund przed następnym sprawdzeniem..."
  sleep 5
done

# Wyczyść pliki tymczasowe
rm -f /tmp/*_status

# DODATKOWE SPRAWDZENIE: Czekaj na pełne zakończenie cloud-init
echo "=== DODATKOWE SPRAWDZENIE: Czekam na pełne zakończenie cloud-init ==="
timeout 300 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "sudo cloud-init status --wait" || {
  echo "❌ Cloud-init nie zakończył się w ciągu 5 minut!"
  echo "Sprawdzam logi cloud-init..."
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "sudo tail -20 /var/log/cloud-init-output.log"
  exit 1
}

echo "✅ Cloud-init zakończony! Sprawdzam czy narzędzia są zainstalowane..."

# Sprawdź czy narzędzia są rzeczywiście zainstalowane
echo "=== SPRAWDZENIE NARZĘDZI ==="
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "which minikube && echo '✅ Minikube OK' || echo '❌ Minikube brak'" || echo "❌ Problem z SSH"
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "which kubectl && echo '✅ Kubectl OK' || echo '❌ Kubectl brak'" || echo "❌ Problem z SSH"
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "which helm && echo '✅ Helm OK' || echo '❌ Helm brak'" || echo "❌ Problem z SSH"

echo "✅ Wszystko gotowe! Przechodzę do testów."

# DODATKOWE HEALTH CHECKS: Czekam na gotowość usług
echo "=== HEALTH CHECKS: Czekam na gotowość usług ==="

# 1. Czekam na gotowość Minikube
echo "🔍 Health Check 1: Minikube..."
timeout 300 bash -c 'until sudo -u ubuntu minikube status | grep -q "host: Running" && sudo -u ubuntu minikube kubectl get nodes > /dev/null 2>&1; do 
  echo "⏳ Czekam na Minikube... (status: $(sudo -u ubuntu minikube status | head -1))"
  sleep 10
done' || {
  echo "❌ Minikube nie jest gotowy po 5 minutach!"
  sudo -u ubuntu minikube status
  exit 1
}
echo "✅ Minikube gotowy!"

# 2. Czekam na gotowość Jenkins pods
echo "🔍 Health Check 2: Jenkins pods..."
timeout 600 bash -c 'until sudo -u ubuntu minikube kubectl get pods | grep jenkins | grep -q "Running"; do 
  echo "⏳ Czekam na Jenkins pods... (status: $(sudo -u ubuntu minikube kubectl get pods | grep jenkins || echo "Brak podów"))"
  sleep 15
done' || {
  echo "❌ Jenkins pods nie są gotowe po 10 minutach!"
  sudo -u ubuntu minikube kubectl get pods
  exit 1
}
echo "✅ Jenkins pods gotowe!"

# 3. Czekam na gotowość Jenkins service
echo "🔍 Health Check 3: Jenkins service..."
timeout 300 bash -c 'until sudo -u ubuntu minikube kubectl get svc | grep jenkins | grep -q "ClusterIP"; do 
  echo "⏳ Czekam na Jenkins service..."
  sleep 10
done' || {
  echo "❌ Jenkins service nie jest gotowy po 5 minutach!"
  sudo -u ubuntu minikube kubectl get svc
  exit 1
}
echo "✅ Jenkins service gotowy!"

# 4. Czekam na gotowość Jenkins HTTP
echo "🔍 Health Check 4: Jenkins HTTP..."
timeout 300 bash -c 'until curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200\|302\|401"; do 
  echo "⏳ Czekam na Jenkins HTTP... (kod: $(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 || echo "Błąd"))"
  sleep 10
done' || {
  echo "❌ Jenkins HTTP nie odpowiada po 5 minutach!"
  curl -v http://localhost:8080 || echo "Błąd curl"
  exit 1
}
echo "✅ Jenkins HTTP gotowy!"

echo "🎉 WSZYSTKIE USŁUGI GOTOWE! Uruchamiam testy..."

echo "=== TESTY NA INSTANCJI ==="
timeout 300 ssh -tt -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -i "$KEY" $USER@$IP <<'EOF' > test_report.log 2>&1

# Test: Minikube status
timeout 30 sudo -u ubuntu minikube status || echo "Minikube NIE działa!"

echo
# Test: Helm
timeout 30 helm version || echo "Helm NIE działa!"

echo
# Test: StorageClass
timeout 30 sudo -u ubuntu minikube kubectl get storageclass || echo "Brak StorageClass!"

echo
# Test: Jenkins pod (bez flagi --all-namespaces)
timeout 30 sudo -u ubuntu minikube kubectl get pods | grep jenkins || echo "Brak podów Jenkins!"

echo
# Test: Jenkins service (bez flagi --all-namespaces)
timeout 30 sudo -u ubuntu minikube kubectl get svc | grep jenkins || echo "Brak serwisu Jenkins!"

echo
# Test: Jenkins HTTP (localhost:8080)
timeout 30 curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080

echo
# Test: JCasC w logach Jenkinsa (bez flagi --all-namespaces)
JENKINS_POD=$(timeout 30 sudo -u ubuntu minikube kubectl get pods | grep jenkins | grep controller | awk '{print $1}')
if [ -n "$JENKINS_POD" ]; then
  timeout 30 sudo -u ubuntu minikube kubectl logs $JENKINS_POD | grep -i "Configuration as Code" || echo "Brak śladów JCasC w logach!"
else
  echo "Nie znaleziono podu Jenkins controller!"
fi

echo
# LOGI CLOUD-INIT (checkpointy)
echo "=== LOGI CLOUD-INIT (/var/log/cloud-init-output.log) - CHECKPOINTY ==="
timeout 30 sudo cat /var/log/cloud-init-output.log | grep -E '===|SETUP SUCCESS' || echo "Brak logu cloud-init-output.log lub brak checkpointów"

echo
# Pełny log cloud-init
echo "=== PELNY LOG CLOUD-INIT (/var/log/cloud-init-output.log) ==="
timeout 30 sudo cat /var/log/cloud-init-output.log || echo "Brak logu cloud-init-output.log lub brak uprawnień"

echo "KONIEC TESTÓW"
echo "Wylogowuję się z SSH..."

exit

EOF

echo "=== WYNIK TESTU (test_report.log) ==="
cat test_report.log
