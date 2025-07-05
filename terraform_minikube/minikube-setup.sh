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

# =============================================================================
# SEGMENT 3: INSTALACJA KUBECTL
# =============================================================================
echo "=== SEGMENT 3: Instalacja kubectl ==="

echo "Instaluję kubectl z pakietów systemowych..."
sudo apt-get install -y kubectl
echo "✅ kubectl zainstalowany"

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

echo "Uruchamiam Minikube na 2 CPU, 2000MB RAM..."
sudo minikube start --driver=docker --cpus=2 --memory=2000mb --force
echo "✅ Minikube uruchomiony"

# =============================================================================
# SEGMENT 6: INSTALACJA HELM
# =============================================================================
echo "=== SEGMENT 6: Instalacja Helm ==="

echo "Instaluję Helm z pakietów systemowych..."
sudo apt-get install -y helm
echo "✅ Helm zainstalowany"

# =============================================================================
# SEGMENT 7: KONFIGURACJA STORAGECLASS
# =============================================================================
echo "=== SEGMENT 7: Konfiguracja StorageClass ==="

echo "Tworzę StorageClass local-path lokalnie..."
cat > /tmp/local-path-storage.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: local-path-storage
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: local-path-provisioner-service-account
  namespace: local-path-storage
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: local-path-provisioner-role
rules:
- apiGroups: [""]
  resources: ["nodes", "persistentvolumeclaims"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["persistentvolumes"]
  verbs: ["get", "list", "watch", "create", "delete"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "patch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: local-path-provisioner-bind
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: local-path-provisioner-role
subjects:
- kind: ServiceAccount
  name: local-path-provisioner-service-account
  namespace: local-path-storage
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: local-path-provisioner
  namespace: local-path-storage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: local-path-provisioner
  template:
    metadata:
      labels:
        app: local-path-provisioner
    spec:
      serviceAccountName: local-path-provisioner-service-account
      containers:
      - name: local-path-provisioner
        image: rancher/local-path-provisioner:v0.0.24
        imagePullPolicy: IfNotPresent
        command:
        - local-path-provisioner
        - --debug
        - start
        - --config
        - /etc/config/config.json
        volumeMounts:
        - name: config-volume
          mountPath: /etc/config/
        env:
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
      volumes:
      - name: config-volume
        configMap:
          name: local-path-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-path-config
  namespace: local-path-storage
data:
  config.json: |-
        {
                "nodePathMap":[
                {
                        "node":"DEFAULT_PATH_FOR_NON_LISTED_NODES",
                        "paths":["/var/lib/rancher/k3s/storage"]
                }
                ],
                "setupScripts":{},
                "teardownScripts":{},
                "hostPath": "/var/lib/rancher/k3s/storage"
        }
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF

echo "Instaluję StorageClass local-path..."
minikube kubectl apply -f /tmp/local-path-storage.yaml
echo "✅ StorageClass local-path zainstalowany"

echo "Ustawiam StorageClass jako domyślny..."
minikube kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
echo "✅ StorageClass ustawiony jako domyślny"

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

echo "Dodaję repozytorium Jenkins Helm..."
helm repo add jenkins https://charts.jenkins.io
helm repo update
echo "✅ Repozytorium Jenkins dodane"

echo "Instaluję Jenkinsa z JCasC..."
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
echo "✅ Jenkins zainstalowany"

# =============================================================================
# SEGMENT 10: DIAGNOSTYKA
# =============================================================================
echo "=== SEGMENT 10: Diagnostyka ==="

echo "Sprawdzam status podów:"
minikube kubectl get pods
echo

echo "Sprawdzam status PVC:"
minikube kubectl get pvc
echo

echo "Sprawdzam logi Jenkinsa:"
minikube kubectl logs -l app.kubernetes.io/component=jenkins-controller || echo "Brak logów Jenkinsa"
echo

# =============================================================================
# SEGMENT 11: WERYFIKACJA NARZĘDZI
# =============================================================================
echo "=== SEGMENT 11: Weryfikacja narzędzi ==="

echo "Sprawdzam PATH: $PATH"
echo

echo "Sprawdzam lokalizację minikube:"
which minikube || echo "❌ minikube NIE w PATH"
ls -l /usr/local/bin/minikube /usr/bin/minikube 2>/dev/null || echo "❌ minikube nie znaleziony w /usr/local/bin ani /usr/bin"
echo

echo "Sprawdzam lokalizację helm:"
which helm || echo "❌ helm NIE w PATH"
ls -l /usr/local/bin/helm /usr/bin/helm 2>/dev/null || echo "❌ helm nie znaleziony w /usr/local/bin ani /usr/bin"
echo

echo "Sprawdzam lokalizację kubectl:"
which kubectl || echo "❌ kubectl NIE w PATH"
ls -l /usr/local/bin/kubectl /usr/bin/kubectl 2>/dev/null || echo "❌ kubectl nie znaleziony w /usr/local/bin ani /usr/bin"
echo

# =============================================================================
# KONIEC SETUPU
# =============================================================================
echo "=== SETUP ZAKOŃCZONY POMYŚLNIE ==="
echo "✅ Wszystkie komponenty zainstalowane i skonfigurowane"
echo "✅ Minikube uruchomiony"
echo "✅ Jenkins z JCasC zainstalowany"
echo "✅ StorageClass skonfigurowany" 