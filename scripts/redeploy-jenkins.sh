#!/bin/bash
set -e

# Parametry CLI z wartościami domyślnymi
NAMESPACE=${1:-jenkins}
RELEASE=${2:-jenkins}
VALUES=${3:-jenkins-values.yaml}
DRY_RUN=false
LOG_TO_FILE=false

# Parsowanie argumentów
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --log-to-file)
            LOG_TO_FILE=true
            shift
            ;;
        --help|-h)
            echo "Użycie: $0 [NAMESPACE] [RELEASE] [VALUES_FILE] [OPCJE]"
            echo ""
            echo "Parametry:"
            echo "  NAMESPACE     - namespace Jenkins (domyślnie: jenkins)"
            echo "  RELEASE       - nazwa release Helm (domyślnie: jenkins)"
            echo "  VALUES_FILE   - plik values.yaml (domyślnie: jenkins-values.yaml)"
            echo ""
            echo "Opcje:"
            echo "  --dry-run     - test bez faktycznych zmian"
            echo "  --log-to-file - zapisz logi do pliku jenkins-install.log"
            echo "  --help, -h    - wyświetl tę pomoc"
            echo ""
            echo "Przykłady:"
            echo "  $0                           # użyj wartości domyślnych"
            echo "  $0 my-jenkins my-release    # niestandardowe nazwy"
            echo "  $0 --dry-run                # test bez zmian"
            echo "  $0 --log-to-file            # zapisz logi do pliku"
            exit 0
            ;;
        *)
            # Przesuń argumenty jeśli nie są opcjami
            if [[ "$1" != "--"* ]]; then
                shift
            else
                shift
            fi
            ;;
    esac
done

# Logowanie do pliku jeśli włączone
if [[ "$LOG_TO_FILE" == "true" ]]; then
    exec > >(tee jenkins-install.log) 2>&1
    info "Logi będą zapisywane do pliku jenkins-install.log"
fi

# Kolory do czytelnych komunikatów
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function info() { echo -e "${YELLOW}[INFO] $1${NC}"; }
function ok() { echo -e "${GREEN}[OK] $1${NC}"; }
function err() { echo -e "${RED}[ERROR] $1${NC}"; }
function debug() { echo -e "${BLUE}[DEBUG] $1${NC}"; }

# Funkcja do sprawdzania i dodawania Helm repo
check_helm_repo() {
    info "Sprawdzam repozytoria Helm:"
    if ! helm repo list | grep -q jenkins; then
        info "Dodaję repozytorium Jenkins..."
        helm repo add jenkins https://charts.jenkins.io
        helm repo update
        ok "Repozytorium Jenkins dodane i zaktualizowane"
    else
        ok "Repozytorium Jenkins już istnieje"
    fi
    echo ""
}

# Funkcja do sprawdzania i tworzenia namespace
check_namespace() {
    info "Sprawdzam namespace: $NAMESPACE"
    if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Utworzyłbym namespace: $NAMESPACE"
        else
            info "Tworzę namespace: $NAMESPACE"
            kubectl create namespace "$NAMESPACE"
            ok "Namespace $NAMESPACE utworzony"
        fi
    else
        ok "Namespace $NAMESPACE istnieje"
    fi
    echo ""
}

# Funkcja do sprawdzania StorageClass
check_storageclass() {
    info "Sprawdzam dostępne StorageClass:"
    kubectl get storageclass
    echo ""
    
    info "Sprawdzam szczegóły StorageClass minikube-hostpath:"
    kubectl get storageclass minikube-hostpath -o yaml || err "StorageClass minikube-hostpath nie istnieje!"
    echo ""
}

# Funkcja do sprawdzania PersistentVolume
check_persistentvolumes() {
    info "Sprawdzam dostępne PersistentVolume:"
    kubectl get pv
    echo ""
}

# Funkcja do sprawdzania zasobów noda
check_node_resources() {
    info "Sprawdzam zasoby noda:"
    kubectl describe node minikube
    echo ""
}

# Funkcja do sprawdzania konfiguracji values.yaml
check_values_yaml() {
    info "Sprawdzam konfigurację $VALUES:"
    if [[ -f "$VALUES" ]]; then
        cat "$VALUES"
        echo ""
        
        # Sprawdź czy storageClass jest ustawiona
        if grep -q "storageClass:" "$VALUES"; then
            ok "StorageClass jest ustawiona w $VALUES"
        else
            err "StorageClass NIE jest ustawiona w $VALUES!"
        fi
    else
        err "Plik $VALUES nie istnieje!"
    fi
    echo ""
}

# Funkcja do szczegółowej diagnostyki PVC
diagnose_pvc() {
    info "Szczegółowa diagnostyka PVC:"
    if kubectl get pvc jenkins -n $NAMESPACE >/dev/null 2>&1; then
        kubectl describe pvc jenkins -n $NAMESPACE
    else
        info "PVC jenkins nie istnieje."
    fi
    echo ""
    
    # Sprawdź czy PVC ma StorageClass
    PVC_SC=$(kubectl get pvc jenkins -n $NAMESPACE -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
    if [[ -z "$PVC_SC" ]]; then
        err "PVC nie ma ustawionej StorageClass!"
    else
        ok "PVC ma StorageClass: $PVC_SC"
    fi
}

# Funkcja do szczegółowej diagnostyki poda
diagnose_pod() {
    info "Szczegółowa diagnostyka poda:"
    if kubectl get pod jenkins-0 -n $NAMESPACE >/dev/null 2>&1; then
        kubectl describe pod jenkins-0 -n $NAMESPACE
    else
        info "Pod jenkins-0 nie istnieje."
    fi
    echo ""
    
    # Sprawdź czy pod ma wystarczające zasoby
    POD_STATUS=$(kubectl get pod jenkins-0 -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$POD_STATUS" == "Pending" ]]; then
        err "Pod jest w stanie Pending - sprawdź szczegóły powyżej"
    fi
}

# Główna logika
info "=== DIAGNOSTYKA PROBLEMU Z JENKINS ==="
info "Parametry: NAMESPACE=$NAMESPACE, RELEASE=$RELEASE, VALUES=$VALUES"
if [[ "$DRY_RUN" == "true" ]]; then
    info "TRYB DRY RUN - zasoby nie będą modyfikowane"
fi
echo ""

# 1. Sprawdź Helm repo
check_helm_repo

# 2. Sprawdź i utwórz namespace
check_namespace

# 3. Sprawdź StorageClass
check_storageclass

# 4. Sprawdź PersistentVolume
check_persistentvolumes

# 5. Sprawdź zasoby noda
check_node_resources

# 6. Sprawdź konfigurację values.yaml
check_values_yaml

# 7. Usuń stary release, PVC i PV
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Usunąłbym stary release Helm: $RELEASE w namespace: $NAMESPACE"
    info "[DRY RUN] Usunąłbym PVC: jenkins w namespace: $NAMESPACE"
    info "[DRY RUN] Usunąłbym stary PV: jenkins-pv (jeśli istnieje)"
else
    info "Usuwam stary release Helm: $RELEASE w namespace: $NAMESPACE"
    helm uninstall $RELEASE -n $NAMESPACE || info "Release nie istniał."

    info "Usuwam PVC: jenkins w namespace: $NAMESPACE"
    kubectl delete pvc jenkins -n $NAMESPACE || info "PVC nie istniał."

    info "Usuwam stary PV: jenkins-pv (jeśli istnieje)"
    kubectl delete pv jenkins-pv || info "PV nie istniał."
fi

# 8. Upewnij się, że nie ma już PV i PVC
info "Sprawdzam, czy nie ma już PV i PVC:"
kubectl get pv
kubectl get pvc -n $NAMESPACE

# 9. Instaluj ponownie (domyślnie z values.yaml)
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Zainstalowałbym Jenkinsa z $VALUES"
    info "[DRY RUN] Alternatywnie z --set controller.persistence.storageClass=minikube-hostpath"
else
    info "Instaluję ponownie Jenkinsa z $VALUES (może to potrwać nawet kilka minut, jeśli storage działa wolno lub są problemy z PVC)"
    if ! helm install $RELEASE jenkins/jenkins -n $NAMESPACE -f $VALUES --wait --timeout=5m --atomic; then
        err "Helm install nie powiodło się! Spróbuję alternatywnej instalacji z --set controller.persistence.storageClass=minikube-hostpath"
        info "Alternatywna instalacja: wymuszam StorageClass przez --set"
        if ! helm install $RELEASE jenkins/jenkins -n $NAMESPACE -f $VALUES --set controller.persistence.storageClass=minikube-hostpath --wait --timeout=5m --atomic; then
            err "Alternatywna instalacja również nie powiodła się!"
            diagnose_pvc
            diagnose_pod
            exit 1
        else
            ok "Alternatywna instalacja z --set zakończona sukcesem."
        fi
    else
        ok "Helm install zakończony sukcesem."
    fi
fi

# 10. Sprawdź wyniki
info "Sprawdzam status PVC:"
kubectl get pvc -n $NAMESPACE

diagnose_pvc

info "Sprawdzam status poda Jenkinsa:"
kubectl get pods -n $NAMESPACE

diagnose_pod

PVC_STATUS=$(kubectl get pvc jenkins -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
if [[ "$PVC_STATUS" != "Bound" ]]; then
    err "PVC nie jest Bound! Sprawdź szczegóły powyżej."
else
    ok "PVC jest Bound."
fi

POD_STATUS=$(kubectl get pod jenkins-0 -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
if [[ "$POD_STATUS" != "Running" ]]; then
    err "Pod Jenkinsa nie jest Running! Sprawdź szczegóły powyżej."
else
    ok "Pod Jenkinsa działa poprawnie."
fi

# 11. Alternatywny test: sprawdzenie dynamicznego provisionera na Bitnami Nginx
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Testowałbym dynamiczny provisioner na Bitnami Nginx"
else
    info "[ALTERNATYWA] Testuję dynamiczny provisioner na Bitnami Nginx z PVC i StorageClass..."
    helm uninstall test-nginx || info "test-nginx nie istniał."

    helm install test-nginx bitnami/nginx --set persistence.enabled=true --set persistence.storageClass=minikube-hostpath --set persistence.size=1Gi --wait --timeout=3m --atomic || err "Testowa instalacja Nginx nie powiodła się!"

    info "Status PVC dla test-nginx:"
    kubectl get pvc

    info "Szczegóły PVC test-nginx:"
    kubectl describe pvc test-nginx

    info "Status poda test-nginx:"
    kubectl get pods

    info "Szczegóły poda test-nginx:"
    kubectl describe pod $(kubectl get pods -l app.kubernetes.io/name=nginx -o jsonpath='{.items[0].metadata.name}')

    info "[ALTERNATYWA] Jeśli PVC test-nginx jest Bound, dynamiczny provisioner działa poprawnie. Jeśli nie, problem leży w klastrze Minikube lub StorageClass."
fi

echo ""
info "=== DIAGNOSTYKA ZAKOŃCZONA ===" 