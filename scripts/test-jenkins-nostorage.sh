#!/bin/bash
set -e

NAMESPACE=jenkins-test
RELEASE=jenkins-test

# Kolory do czytelnych komunikatów
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfigurowalny czas oczekiwania między krokami
SLEEP_TIME=${SLEEP_TIME:-15}

# Parametry dla aktywnego sprawdzania statusu
POLL_TIMEOUT=${POLL_TIMEOUT:-600}   # 10 minut
POLL_INTERVAL=${POLL_INTERVAL:-10}  # 10 sekund

# Parametry dla zasobów i probe
JENKINS_CPU_LIMIT=${JENKINS_CPU_LIMIT:-2}
JENKINS_CPU_REQUEST=${JENKINS_CPU_REQUEST:-1}
JENKINS_MEM_LIMIT=${JENKINS_MEM_LIMIT:-2Gi}
JENKINS_MEM_REQUEST=${JENKINS_MEM_REQUEST:-1Gi}
PROBE_INITIAL_DELAY=${PROBE_INITIAL_DELAY:-120}
PROBE_TIMEOUT=${PROBE_TIMEOUT:-10}
PROBE_PERIOD=${PROBE_PERIOD:-20}
PROBE_FAILURE=${PROBE_FAILURE:-15}
DISABLE_PROBES=${DISABLE_PROBES:-false}

# Sprawdzenie dostępnej pamięci RAM (w MB)
MIN_RAM_MB=2048
RAM_TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)

if [ "$RAM_TOTAL_MB" -lt "$MIN_RAM_MB" ]; then
  echo "!!! UWAGA: Wykryto tylko ${RAM_TOTAL_MB}MB RAM. Jenkins wymaga co najmniej ${MIN_RAM_MB}MB."
  echo "!!! Zwiększ ilość pamięci RAM lub uruchom Minikube z większym limitem (--memory)."
  echo "!!! Skrypt NIE będzie kontynuowany."
  exit 1
else
  echo "Wykryto ${RAM_TOTAL_MB}MB RAM - wystarczająco do uruchomienia Jenkinsa."
fi

function info() { echo -e "${YELLOW}[INFO] $1${NC}"; }
function ok() { echo -e "${GREEN}[OK] $1${NC}"; }
function err() { echo -e "${RED}[ERROR] $1${NC}"; }
function debug() { echo -e "${BLUE}[DEBUG] $1${NC}"; }

function sleep_step() {
  info "Czekam ${SLEEP_TIME}s na stabilizację środowiska..."
  sleep $SLEEP_TIME
}

function wait_for_status() {
  local resource_type=$1
  local label=$2
  local namespace=$3
  local desired_status=$4
  local what=$5
  local elapsed=0
  info "Czekam aż $what osiągnie status: $desired_status (timeout: $POLL_TIMEOUT s)"
  while (( elapsed < POLL_TIMEOUT )); do
    status=$(kubectl get $resource_type -l $label -n $namespace -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    echo -e "[STATUS] $what: $status (po $elapsed s)"
    if [[ "$status" == "$desired_status" ]]; then
      ok "$what osiągnął status $desired_status po $elapsed s."
      return 0
    fi
    sleep $POLL_INTERVAL
    ((elapsed+=POLL_INTERVAL))
  done
  err "$what nie osiągnął statusu $desired_status w czasie $POLL_TIMEOUT s!"
  return 1
}

function check_cluster_connection() {
  if ! kubectl get nodes >/dev/null 2>&1; then
    err "Brak połączenia z klastrem Kubernetes!"
    echo -e "${RED}Nie można połączyć się z API serwera Kubernetes (np. TLS handshake timeout, connection refused).${NC}"
    echo "Możliwe przyczyny:"
    echo "- Minikube nie działa, VM zatrzymana lub zamrożona (VirtualBox/WSL2/Windows)"
    echo "- Brak zasobów RAM/CPU na hoście, system zabił VM"
    echo "- Sieć VM nie działa lub została zresetowana"
    echo "- Kubeconfig nie wskazuje na aktywny klaster"
    echo "Zalecenia:"
    echo "1. Sprawdź status Minikube: minikube status"
    echo "2. Jeśli nie działa: minikube stop && minikube start"
    echo "3. Sprawdź, czy VM Minikube jest aktywna w VirtualBox"
    echo "4. Upewnij się, że masz wystarczająco RAM/CPU/miejsca na dysku"
    echo "5. Po restarcie sprawdź: kubectl get nodes"
    exit 2
  fi
}

info "=== TEST JENKINS BEZ PERSISTENT STORAGE ==="
echo ""

# Sprawdź czy Minikube działa, jeśli nie - spróbuj uruchomić
info "Sprawdzam status Minikube..."
MINIKUBE_STATUS=$(minikube status --format '{{.Host}}' 2>/dev/null || echo "Stopped")
if [[ "$MINIKUBE_STATUS" != "Running" ]]; then
    info "Minikube nie jest uruchomiony. Próbuję uruchomić Minikube..."
    if minikube start; then
        ok "Minikube został uruchomiony."
    else
        err "Nie udało się uruchomić Minikube! Przerwano test."
        exit 1
    fi
else
    ok "Minikube jest już uruchomiony."
fi

# Sprawdź czy istnieje StorageClass minikube-hostpath, jeśli nie - spróbuj ją utworzyć
info "Sprawdzam, czy istnieje StorageClass minikube-hostpath..."
if ! kubectl get storageclass minikube-hostpath >/dev/null 2>&1; then
    info "StorageClass minikube-hostpath nie istnieje. Próbuję utworzyć z pliku minikube-hostpath-sc.yaml..."
    if kubectl apply -f minikube-hostpath-sc.yaml 2>sc_err.log; then
        ok "StorageClass minikube-hostpath została utworzona."
    else
        err "Nie udało się utworzyć StorageClass minikube-hostpath!"
        echo -e "${RED}Szczegóły błędu:${NC}"
        cat sc_err.log
        rm -f sc_err.log
        exit 1
    fi
else
    ok "StorageClass minikube-hostpath już istnieje."
fi

# Po utworzeniu StorageClass
sleep_step

# 1. Sprawdź Helm repo
info "Sprawdzam repozytoria Helm:"
if ! helm repo list | grep -q jenkins; then
    info "Dodaję repozytorium Jenkins..."
    helm repo add jenkins https://charts.jenkins.io
    helm repo update
    ok "Repozytorium Jenkins dodane"
else
    ok "Repozytorium Jenkins już istnieje"
fi
echo ""

# 2. Utwórz namespace testowy
info "Tworzę namespace testowy: $NAMESPACE"
if ! kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f - 2>err.log; then
    err "Nie udało się utworzyć namespace $NAMESPACE!"
    echo -e "${RED}Szczegóły błędu:${NC}"
    cat err.log
    echo ""
    info "Diagnostyka środowiska:"
    echo -e "${YELLOW}minikube status:${NC}"
    minikube status || echo "Brak Minikube lub nie działa"
    echo -e "${YELLOW}kubectl cluster-info:${NC}"
    kubectl cluster-info || echo "Brak połączenia z klastrem Kubernetes"
    echo ""
    err "Możliwe przyczyny: Minikube nie działa, kubeconfig nieprawidłowy, kube-apiserver nie odpowiada, port 8080 zajęty lub nie działa."
    rm -f err.log
    exit 1
else
    ok "Namespace $NAMESPACE utworzony"
fi

# Po utworzeniu namespace
sleep_step

# 3. Usuń stary release jeśli istnieje
info "Usuwam stary release testowy jeśli istnieje..."
helm uninstall $RELEASE -n $NAMESPACE || info "Release nie istniał"
echo ""

# Po usunięciu starego release
sleep_step

# 4. Instaluj Jenkins bez persistent storage
info "Aktualne ustawienia zasobów i probe:"
echo "CPU: $JENKINS_CPU_REQUEST/$JENKINS_CPU_LIMIT, MEM: $JENKINS_MEM_REQUEST/$JENKINS_MEM_LIMIT"
echo "Probe: initialDelay=$PROBE_INITIAL_DELAY, timeout=$PROBE_TIMEOUT, period=$PROBE_PERIOD, failureThreshold=$PROBE_FAILURE, disable=$DISABLE_PROBES"

HELM_PROBE_ARGS="--set controller.resources.requests.cpu=$JENKINS_CPU_REQUEST --set controller.resources.limits.cpu=$JENKINS_CPU_LIMIT --set controller.resources.requests.memory=$JENKINS_MEM_REQUEST --set controller.resources.limits.memory=$JENKINS_MEM_LIMIT --set controller.startupProbe.initialDelaySeconds=$PROBE_INITIAL_DELAY --set controller.startupProbe.timeoutSeconds=$PROBE_TIMEOUT --set controller.startupProbe.periodSeconds=$PROBE_PERIOD --set controller.startupProbe.failureThreshold=$PROBE_FAILURE --set controller.readinessProbe.initialDelaySeconds=$PROBE_INITIAL_DELAY --set controller.readinessProbe.timeoutSeconds=$PROBE_TIMEOUT --set controller.readinessProbe.periodSeconds=$PROBE_PERIOD --set controller.readinessProbe.failureThreshold=$PROBE_FAILURE --set controller.livenessProbe.initialDelaySeconds=$PROBE_INITIAL_DELAY --set controller.livenessProbe.timeoutSeconds=$PROBE_TIMEOUT --set controller.livenessProbe.periodSeconds=$PROBE_PERIOD --set controller.livenessProbe.failureThreshold=$PROBE_FAILURE"
if [[ "$DISABLE_PROBES" == "true" ]]; then
  HELM_PROBE_ARGS="$HELM_PROBE_ARGS --set controller.startupProbe.enabled=false --set controller.readinessProbe.enabled=false --set controller.livenessProbe.enabled=false"
fi

# Sprawdź połączenie z klastrem na początku
check_cluster_connection

info "Instaluję Jenkinsa bez persistent storage..."
if helm install $RELEASE jenkins/jenkins -n $NAMESPACE -f jenkins-nostorage-values.yaml $HELM_PROBE_ARGS --wait --timeout=10m --atomic; then
    ok "Jenkins zainstalowany bez persistent storage"
    # Aktywne czekanie na PVC Bound
    wait_for_status pvc "app.kubernetes.io/instance=$RELEASE" $NAMESPACE Bound "PVC Jenkins"
    # Aktywne czekanie na pod Running
    wait_for_status pod "app.kubernetes.io/name=jenkins" $NAMESPACE Running "Pod Jenkins"
else
    err "Instalacja Jenkinsa bez persistent storage nie powiodła się!"
    echo ""
    check_cluster_connection
    info "[Diagnostyka] Status podów w namespace $NAMESPACE:"
    kubectl get pods -n $NAMESPACE -o wide || true
    echo ""
    info "[Diagnostyka] Status PVC i PV w namespace $NAMESPACE:"
    kubectl get pvc,pv -n $NAMESPACE || true
    echo ""
    info "[Diagnostyka] Eventy w namespace $NAMESPACE:"
    kubectl get events -n $NAMESPACE --sort-by=.metadata.creationTimestamp | tail -n 40 || true
    echo ""
    info "[Diagnostyka] Logi storage-provisionera:"
    kubectl logs -n kube-system -l app=storage-provisioner --tail=40 || true
    echo ""
    info "[Diagnostyka] Logi i szczegóły wszystkich podów Jenkins (w tym init-containerów):"
    for POD in $(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=jenkins -o jsonpath='{.items[*].metadata.name}'); do
      echo -e "\n==== Pod: $POD ===="
      kubectl describe pod $POD -n $NAMESPACE || echo "Brak opisu poda."
      for CONTAINER in $(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}'); do
        echo -e "\n-- Logi kontenera: $CONTAINER --"
        kubectl logs -n $NAMESPACE $POD -c $CONTAINER --tail=100 || echo "Brak logów kontenera $CONTAINER."
        echo -e "\n-- Logi kontenera: $CONTAINER (poprzednia instancja) --"
        kubectl logs -n $NAMESPACE $POD -c $CONTAINER --previous --tail=100 || echo "Brak logów poprzedniej instancji kontenera $CONTAINER."
      done
      for INIT in $(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.spec.initContainers[*].name}'); do
        echo -e "\n-- Logi init-containera: $INIT --"
        kubectl logs -n $NAMESPACE $POD -c $INIT --tail=100 || echo "Brak logów init-containera $INIT."
        echo -e "\n-- Logi init-containera: $INIT (poprzednia instancja) --"
        kubectl logs -n $NAMESPACE $POD -c $INIT --previous --tail=100 || echo "Brak logów poprzedniej instancji init-containera $INIT."
      done
      # Sprawdzenie CrashLoopBackOff
      PHASE=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null)
      REASON=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
      echo -e "\n[INFO] Pod $POD: phase=$PHASE, reason=$REASON"
      if [[ "$REASON" == "CrashLoopBackOff" ]]; then
        err "Pod $POD jest w CrashLoopBackOff!"
      fi
      # Resource usage (jeśli dostępne)
      if command -v kubectl-top &>/dev/null || kubectl top pod $POD -n $NAMESPACE &>/dev/null; then
        echo -e "\n-- Resource usage (kubectl top): --"
        kubectl top pod $POD -n $NAMESPACE || echo "Brak danych o zużyciu zasobów."
      fi
    done
    echo ""
    info "[Diagnostyka] Wolne miejsce na dysku w Minikube (df -h):"
    minikube ssh -- df -h || echo "Nie można pobrać informacji o dysku z Minikube."
    echo ""
    err "PODSUMOWANIE: Jenkins nie startuje, bo kontener nie jest w stanie podnieść się na czas (startup probe failed: connection refused/HTTP 503/context deadline exceeded)."
    echo "Najczęstsze przyczyny:" 
    echo "- Za mało RAM/CPU (Jenkins na Minikube/VirtualBox potrzebuje dużo zasobów)"
    echo "- Za wolny storage (hostPath/VirtualBox jest bardzo wolny, Jenkins nie zdąża się uruchomić)"
    echo "- Brak miejsca na dysku w Minikube"
    echo "- Błąd w obrazie lub konfiguracji (np. pluginy, JCasC)"
    echo "- Zbyt krótki timeout probe (nawet wydłużone mogą być za krótkie na bardzo wolnym storage)"
    echo ""
    echo "Co możesz zrobić:" 
    echo "1. Sprawdź logi kontenera Jenkins powyżej."
    echo "2. Sprawdź wolne miejsce na dysku powyżej."
    echo "3. Spróbuj uruchomić Jenkins bez persistent storage (wyłącz persistence w values.yaml) – jeśli wtedy wystartuje, problem to storage."
    echo "4. Zmniejsz liczbę pluginów, wyłącz JCasC, uruchom najprostszy możliwy Jenkins."
    echo "5. Zwiększ limity zasobów, jeśli masz RAM/CPU na hoście."
    echo "6. Jeśli możesz, uruchom Minikube na Dockerze – storage będzie dużo szybszy."
    echo ""
    echo "To typowy problem Jenkins + Minikube/VirtualBox: za wolny storage, za mało zasobów lub błąd w konfiguracji. Najpierw sprawdź logi kontenera Jenkins i miejsce na dysku – to da ostateczną odpowiedź."
    exit 1
fi
echo ""

# 5. Sprawdź status
info "Sprawdzam status poda:"
kubectl get pods -n $NAMESPACE

info "Sprawdzam status serwisów:"
kubectl get svc -n $NAMESPACE

# 6. Sprawdź czy Jenkins się uruchomił
POD_STATUS=$(kubectl get pod -l app.kubernetes.io/name=jenkins -n $NAMESPACE -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
if [[ "$POD_STATUS" == "Running" ]]; then
    ok "Jenkins pod jest Running!"
    
    # 7. Pobierz hasło administratora
    info "Pobieram hasło administratora Jenkinsa:"
    kubectl exec -n $NAMESPACE -c jenkins deployment/$RELEASE -- cat /run/secrets/additional/chart-admin-password 2>/dev/null || \
    kubectl exec -n $NAMESPACE -c jenkins deployment/$RELEASE -- cat /run/secrets/chart-admin-password 2>/dev/null || \
    echo "Nie można pobrać hasła - sprawdź logi poda"
    
    # 8. Port forward dla dostępu
    info "Uruchamiam port-forward dla dostępu do Jenkinsa:"
    info "Jenkins będzie dostępny pod adresem: http://localhost:8080"
    info "Użyj hasła z powyższego outputu"
    echo ""
    info "Aby uruchomić port-forward, wykonaj:"
    echo "kubectl port-forward -n $NAMESPACE svc/$RELEASE 8080:8080"
    echo ""
    info "Aby sprawdzić logi Jenkinsa:"
    echo "kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=jenkins -f"
    
else
    err "Jenkins pod nie jest Running! Status: $POD_STATUS"
    info "Sprawdzam szczegóły poda:"
    kubectl describe pod -l app.kubernetes.io/name=jenkins -n $NAMESPACE
    info "Sprawdzam logi poda:"
    kubectl logs -l app.kubernetes.io/name=jenkins -n $NAMESPACE --tail=50
fi

echo ""
info "=== TEST ZAKOŃCZONY ===" 