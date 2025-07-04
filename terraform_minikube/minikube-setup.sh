#!/bin/bash
set -e

sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y docker.io
sudo usermod -aG docker ubuntu
newgrp docker

curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

sudo -u ubuntu minikube start --driver=docker --cpus=2 --memory=2048

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash 