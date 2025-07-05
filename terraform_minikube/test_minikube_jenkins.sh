#!/bin/bash

cd "$(dirname "$0")"

echo "=== DESTROY ==="
terraform destroy -auto-approve || { echo "Błąd podczas destroy!"; exit 1; }

echo "=== APPLY ==="
terraform apply -auto-approve || { echo "Błąd podczas apply!"; exit 1; }

IP=$(terraform output -raw public_ip)
KEY="~/.ssh/id_rsa"
USER="ubuntu"

echo "=== CZEKAM NA CLOUD-INIT (max 10 minut) ==="
for i in {1..60}; do
  echo "Próba $i/60: Sprawdzam połączenie SSH..."
  if timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "echo 'SSH OK'" 2>/dev/null; then
    echo "✅ SSH działa! Sprawdzam cloud-init..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "sudo cloud-init status --wait" 2>/dev/null; then
      echo "✅ Cloud-init zakończony! Sprawdzam czy narzędzia są zainstalowane..."
      
      # Sprawdź czy minikube jest zainstalowany
      if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" $USER@$IP "which minikube" 2>/dev/null; then
        echo "✅ Minikube zainstalowany! Przechodzę do testów."
        break
      else
        echo "⏳ Minikube jeszcze nie zainstalowany... (próba $i/60)"
      fi
    else
      echo "⏳ Cloud-init jeszcze trwa... (próba $i/60)"
    fi
  else
    echo "⏳ SSH jeszcze nie działa... (próba $i/60)"
  fi
  sleep 10
done

echo "=== TESTY NA INSTANCJI ==="
timeout 300 ssh -tt -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -i "$KEY" $USER@$IP <<'EOF' > test_report.log 2>&1

# Test: Minikube status
timeout 30 minikube status || echo "Minikube NIE działa!"

echo
# Test: Helm
timeout 30 helm version || echo "Helm NIE działa!"

echo
# Test: StorageClass
timeout 30 minikube kubectl get storageclass || echo "Brak StorageClass!"

echo
# Test: Jenkins pod (bez flagi --all-namespaces)
timeout 30 minikube kubectl get pods | grep jenkins || echo "Brak podów Jenkins!"

echo
# Test: Jenkins service (bez flagi --all-namespaces)
timeout 30 minikube kubectl get svc | grep jenkins || echo "Brak serwisu Jenkins!"

echo
# Test: Jenkins HTTP (localhost:8080)
timeout 30 curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080

echo
# Test: JCasC w logach Jenkinsa (bez flagi --all-namespaces)
JENKINS_POD=$(timeout 30 minikube kubectl get pods | grep jenkins | grep controller | awk '{print $1}')
if [ -n "$JENKINS_POD" ]; then
  timeout 30 minikube kubectl logs $JENKINS_POD | grep -i "Configuration as Code" || echo "Brak śladów JCasC w logach!"
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
