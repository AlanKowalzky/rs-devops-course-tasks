#!/bin/bash

IP="34.247.190.19"
KEY="~/.ssh/id_rsa"
USER="ubuntu"

ssh -i $KEY $USER@$IP <<'EOF'
echo "=== TEST: Minikube status ==="
minikube status || echo "Minikube NIE działa!"

echo
echo "=== TEST: Helm ==="
helm version || echo "Helm NIE działa!"

echo
echo "=== TEST: StorageClass ==="
kubectl get storageclass || echo "Brak StorageClass!"

echo
echo "=== TEST: Jenkins pod ==="
kubectl get pods -A | grep jenkins || echo "Brak podów Jenkins!"

echo
echo "=== TEST: Jenkins service ==="
kubectl get svc -A | grep jenkins || echo "Brak serwisu Jenkins!"

echo
echo "=== TEST: Jenkins HTTP (localhost:8080) ==="
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080

echo
echo "=== TEST: JCasC w logach Jenkinsa ==="
JENKINS_POD=$(kubectl get pods -A | grep jenkins | grep controller | awk '{print $2}')
if [ -n "$JENKINS_POD" ]; then
  kubectl logs -n default $JENKINS_POD | grep -i "Configuration as Code" || echo "Brak śladów JCasC w logach!"
else
  echo "Nie znaleziono podu Jenkins controller!"
fi
EOF
