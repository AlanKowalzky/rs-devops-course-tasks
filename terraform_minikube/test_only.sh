#!/bin/bash

cd "$(dirname "$0")"

# =============================================================================
# SEGMENT 1: POBRANIE IP Z TERRAFORM
# =============================================================================
echo "=== SEGMENT 1: Pobieranie IP z Terraform ==="

# Pobierz IP z terraform output (bez destroy/apply)
IP=$(terraform output -raw public_ip 2>/dev/null)
if [ -z "$IP" ]; then
    echo "❌ Błąd: Nie można pobrać IP z terraform output!"
    echo "Upewnij się, że instancja jest uruchomiona: terraform apply"
    exit 1
fi

KEY="~/.ssh/id_rsa"
USER="ubuntu"

echo "✅ IP pobrane: $IP"

# =============================================================================
# SEGMENT 2: TESTY NA INSTANCJI
# =============================================================================
echo "=== SEGMENT 2: Testy na instancji ($IP) ==="

timeout 300 ssh -tt -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -i "$KEY" $USER@$IP <<'EOF' 2>&1 | tee test_report.log

# =============================================================================
# HEALTH CHECKS: Czekam na gotowość usług przed testami
# =============================================================================
echo "=== HEALTH CHECKS: Czekam na gotowość usług ==="

# 1. Czekam na gotowość Minikube (zwiększony timeout i lepsze sprawdzenia)
echo "🔍 Health Check 1: Minikube..."
timeout 600 bash -c 'until minikube status | grep -q "Running" && minikube kubectl get nodes > /dev/null 2>&1 && minikube kubectl get pods > /dev/null 2>&1; do 
  echo "⏳ Czekam na Minikube... (status: $(minikube status | grep -E "host:|kubelet:|apiserver:" || echo "nieznany"))"
  echo "⏳ Sprawdzam kubectl... (nodes: $(minikube kubectl get nodes 2>/dev/null | wc -l || echo "błąd"))"
  echo "⏳ Debug kubectl nodes:"
  minikube kubectl get nodes 2>&1 || echo "Błąd kubectl get nodes"
  echo "⏳ Debug kubectl pods (default namespace):"
  minikube kubectl get pods 2>&1 | head -5 || echo "Błąd kubectl get pods"
  sleep 15
done' || {
  echo "❌ Minikube nie jest gotowy po 10 minutach!"
  echo "Status minikube:"
  minikube status
  echo "Logi minikube:"
  minikube logs --file=/tmp/minikube_test.log
  tail -20 /tmp/minikube_test.log
  exit 1
}
echo "✅ Minikube gotowy!"

# Dodatkowe sprawdzenie kubectl
echo "🔍 Sprawdzam kubectl..."
timeout 60 bash -c 'until minikube kubectl get nodes | grep -q "Ready"; do 
  echo "⏳ Czekam na gotowe node... (status: $(minikube kubectl get nodes | grep -o "Ready\|NotReady" || echo "brak"))"
  sleep 10
done' || {
  echo "❌ Node nie jest Ready!"
  minikube kubectl get nodes
  exit 1
}
echo "✅ Node gotowy!"

# 2. Czekam na gotowość Jenkins pods (zwiększony timeout)
echo "🔍 Health Check 2: Jenkins pods..."
timeout 900 bash -c 'until kubectl get pods --namespace=jenkins | grep jenkins | grep -q "Running"; do 
  echo "⏳ Czekam na Jenkins pods... (status: $(kubectl get pods --namespace=jenkins | grep jenkins || echo "Brak podów"))"
  sleep 20
done' || {
  echo "❌ Jenkins pods nie są gotowe po 15 minutach!"
  kubectl get pods --namespace=jenkins
  exit 1
}
echo "✅ Jenkins pods gotowe!"

# 3. Czekam na gotowość Jenkins HTTP (zwiększony timeout)
echo "🔍 Health Check 3: Jenkins HTTP..."
timeout 600 bash -c 'until curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200\|302\|401"; do 
  echo "⏳ Czekam na Jenkins HTTP... (kod: $(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 || echo "Błąd"))"
  sleep 15
done' || {
  echo "❌ Jenkins HTTP nie odpowiada po 10 minutach!"
  curl -v http://localhost:8080 || echo "Błąd curl"
  exit 1
}
echo "✅ Jenkins HTTP gotowy!"

echo "🎉 WSZYSTKIE USŁUGI GOTOWE! Uruchamiam testy..."

# =============================================================================
# SEGMENT 2.1: TEST MINIKUBE
# =============================================================================
echo "=== SEGMENT 2.1: Test Minikube ==="
timeout 30 minikube status || echo "❌ Minikube NIE działa!"

# =============================================================================
# SEGMENT 2.2: TEST HELM
# =============================================================================
echo "=== SEGMENT 2.2: Test Helm ==="
timeout 30 helm version || echo "❌ Helm NIE działa!"

# =============================================================================
# SEGMENT 2.3: TEST STORAGECLASS
# =============================================================================
echo "=== SEGMENT 2.3: Test StorageClass ==="
timeout 30 minikube kubectl get storageclass || echo "❌ Brak StorageClass!"

# =============================================================================
# SEGMENT 2.4: TEST JENKINS PODS
# =============================================================================
echo "=== SEGMENT 2.4: Test Jenkins Pods ==="
timeout 30 kubectl get pods --namespace=jenkins | grep jenkins || echo "❌ Brak podów Jenkins!"

# =============================================================================
# SEGMENT 2.5: TEST JENKINS SERVICES
# =============================================================================
echo "=== SEGMENT 2.5: Test Jenkins Services ==="
timeout 30 kubectl get svc --namespace=jenkins | grep jenkins || echo "❌ Brak serwisu Jenkins!"

# =============================================================================
# SEGMENT 2.6: TEST JENKINS HTTP
# =============================================================================
echo "=== SEGMENT 2.6: Test Jenkins HTTP ==="
timeout 30 curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080

# =============================================================================
# SEGMENT 2.7: TEST JCASC W LOGACH
# =============================================================================
echo "=== SEGMENT 2.7: Test JCasC w logach ==="
JENKINS_POD=$(timeout 30 kubectl get pods --namespace=jenkins | grep jenkins | grep controller | awk '{print $1}')
if [ -n "$JENKINS_POD" ]; then
  echo "✅ Znaleziono pod Jenkins: $JENKINS_POD"
  timeout 30 kubectl logs $JENKINS_POD --namespace=jenkins | grep -i "Configuration as Code" || echo "❌ Brak śladów JCasC w logach!"
else
  echo "❌ Nie znaleziono podu Jenkins controller!"
fi

# =============================================================================
# SEGMENT 2.8: LOGI CLOUD-INIT CHECKPOINTY
# =============================================================================
echo "=== SEGMENT 2.8: Logi Cloud-init (checkpointy) ==="
timeout 30 sudo cat /var/log/cloud-init-output.log | grep -E '===|SETUP SUCCESS|✅|❌' || echo "❌ Brak logu cloud-init-output.log lub brak checkpointów"

# =============================================================================
# SEGMENT 2.9: PEŁNY LOG CLOUD-INIT
# =============================================================================
echo "=== SEGMENT 2.9: Pełny log Cloud-init ==="
timeout 30 sudo cat /var/log/cloud-init-output.log || echo "❌ Brak logu cloud-init-output.log lub brak uprawnień"

# =============================================================================
# SEGMENT 2.10: DIAGNOSTYKA NARZĘDZI
# =============================================================================
echo "=== SEGMENT 2.10: Diagnostyka narzędzi ==="
echo "Sprawdzam lokalizację minikube:"
which minikube || echo "❌ minikube NIE w PATH"
echo

echo "Sprawdzam lokalizację helm:"
which helm || echo "❌ helm NIE w PATH"
echo

echo "Sprawdzam lokalizację kubectl:"
which kubectl || echo "❌ kubectl NIE w PATH"
echo

echo "✅ KONIEC TESTÓW"
echo "Wylogowuję się z SSH..."

logout

EOF

# =============================================================================
# SEGMENT 3: WYNIKI TESTÓW
# =============================================================================
echo "=== SEGMENT 3: Wyniki testów ==="
echo "=== WYNIK TESTU (test_report.log) ==="
cat test_report.log

echo "✅ Test zakończony - sprawdź test_report.log"
echo "✅ SSH sesja zakończona" 