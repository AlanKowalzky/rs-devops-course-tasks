#!/bin/bash
set -e

# Sprawdzenie dostępnej pamięci RAM (w MB)
MIN_RAM_MB=2048
RAM_TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)

if [ "$RAM_TOTAL_MB" -lt "$MIN_RAM_MB" ]; then
  echo "!!! UWAGA: Wykryto tylko ${RAM_TOTAL_MB}MB RAM. Jenkins zaleca co najmniej ${MIN_RAM_MB}MB."
  echo "!!! Jesteś na Free Tier AWS (t2.micro/t3.micro)? Jenkins MOŻE działać niestabilnie lub wcale."
  echo "!!! Kontynuuję instalację na własne ryzyko (Free Tier)!"
else
  echo "Wykryto ${RAM_TOTAL_MB}MB RAM - wystarczająco do uruchomienia Jenkinsa."
fi

sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y docker.io
sudo usermod -aG docker ubuntu
newgrp docker

curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Minimalne zasoby Minikube na Free Tier
echo "Uruchamiam Minikube na 1 CPU, 900MB RAM (Free Tier)"
sudo -u ubuntu minikube start --driver=docker --cpus=1 --memory=900mb

# Instalacja Helm
echo "Instaluję Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Ustawienie StorageClass hostPath jako domyślnej
echo "Konfiguruję StorageClass..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Kopiowanie pliku JCasC do /tmp (zakładamy, że plik jest w tym samym katalogu co skrypt)
cp $(dirname "$0")/jenkins-jcasc.yaml /tmp/jenkins-jcasc.yaml

# Instalacja Jenkinsa z minimalnymi zasobami i pełnym JCasC
echo "Instaluję Jenkinsa przez Helm (minimalne zasoby, JCasC)..."
helm repo add jenkins https://charts.jenkins.io
helm repo update
helm install jenkins jenkins/jenkins \
  --set controller.adminPassword=admin \
  --set persistence.enabled=true \
  --set persistence.size=5Gi \
  --set persistence.storageClass=local-path \
  --set controller.resources.requests.memory="512Mi" \
  --set controller.resources.limits.memory="900Mi" \
  --set controller.JCasC.enabled=true \
  --set-file controller.JCasC.configScripts.jcasc=/tmp/jenkins-jcasc.yaml \
  --wait

# Diagnostyka
echo "Status podów:"
kubectl get pods -A
echo "Status PVC:"
kubectl get pvc -A
echo "Logi Jenkinsa:"
kubectl logs -l app.kubernetes.io/component=jenkins-controller || true 