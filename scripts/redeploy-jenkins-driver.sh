#!/bin/bash
set -e

# === KOLORY I FUNKCJE LOGUJĄCE ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }
ok() { echo -e "${GREEN}[OK] $1${NC}"; }
err() { echo -e "${RED}[ERROR] $1${NC}"; }
debug() { echo -e "${BLUE}[DEBUG] $1${NC}"; }

# === DOMYŚLNE PARAMETRY ===
NAMESPACE="jenkins"
RELEASE="jenkins"
VALUES="jenkins-values.yaml"
DRY_RUN=false
LOG_TO_FILE=false

# === POMOC ===
show_help() {
    echo "Użycie: $0 [NAMESPACE] [RELEASE] [VALUES_FILE] [opcje]"
    echo ""
    echo "Parametry:"
    echo "  NAMESPACE     - Namespace dla Jenkinsa (domyślnie: jenkins)"
    echo "  RELEASE       - Nazwa release Helm (domyślnie: jenkins)"
    echo "  VALUES_FILE   - Plik values.yaml (domyślnie: jenkins-values.yaml)"
    echo ""
    echo "Opcje:"
    echo "  --dry-run     - Test bez zmian"
    echo "  --log-to-file - Logi do pliku jenkins-install.log"
    echo "  --help, -h    - Pomoc"
}

# === PARSOWANIE ARGUMENTÓW ===
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --log-to-file) LOG_TO_FILE=true; shift ;;
        --help|-h) show_help; exit 0 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]}"
NAMESPACE=${1:-$NAMESPACE}
RELEASE=${2:-$RELEASE}
VALUES=${3:-$VALUES}

# === LOGOWANIE DO PLIKU ===
if [[ "$LOG_TO_FILE" == "true" ]]; then
    exec > >(tee jenkins-install.log) 2>&1
    info "Logi będą zapisywane do pliku jenkins-install.log"
fi

# === PYTANIE O ZMIANĘ STEROWNIKA MINIKUBE ===
read -rp "$(echo -e "${BLUE}Czy chcesz użyć sterownika Docker dla Minikube zamiast domyślnego? (y/n): ${NC}")" USE_DOCKER
if [[ "$USE_DOCKER" =~ ^[Yy]$ ]]; then
    info "Przełączam Minikube na sterownik Docker..."
    minikube delete || true
    minikube start --driver=docker || { err "Nie udało się uruchomić Minikube z Dockerem!"; exit 1; }
    ok "Minikube działa z Dockerem"
else
    info "Używam obecnej konfiguracji Minikube"
fi

# === FUNKCJE SPRAWDZAJĄCE ===
check_helm_repo() {
    info "Sprawdzam repozytoria Helm..."
    if ! helm repo list | grep -q jenkins; then
        helm repo add jenkins https://charts.jenkins.io
        helm repo update
        ok "Dodano repozytorium Jenkins"
    else
        ok "Repozytorium Jenkins już istnieje"
    fi
    echo ""
}

check_namespace() {
    info "Sprawdzam namespace $NAMESPACE"
    if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
        [[ "$DRY_RUN" == "true" ]] && info "[DRY RUN] Utworzyłbym namespace $NAMESPACE" && return
        kubectl create namespace "$NAMESPACE"
        ok "Utworzono namespace $NAMESPACE"
    else
        ok "Namespace $NAMESPACE już istnieje"
    fi
    echo ""
}

check_storage_and_pv() {
    info "StorageClass:"
    kubectl get storageclass || err "Brak StorageClass"
    echo ""

    info "PersistentVolume:"
    kubectl get pv || err "Brak PersistentVolume"
    echo ""
}

check_values_file() {
    info "Sprawdzam plik $VALUES"
    if [[ ! -f "$VALUES" ]]; then
        err "Plik $VALUES nie istnieje!"
        exit 1
    fi

    if grep -q "storageClass:" "$VALUES"; then
        ok "StorageClass jest ustawione w $VALUES"
    else
        err "Brak StorageClass w pliku $VALUES"
    fi
    echo ""
}

clean_old_install() {
    [[ "$DRY_RUN" == "true" ]] && {
        info "[DRY RUN] Usunąłbym release $RELEASE oraz PVC/PV"
        return
    }

    info "Usuwam stary release Helm: $RELEASE"
    helm uninstall "$RELEASE" -n "$NAMESPACE" || info "Brak release"

    info "Usuwam PVC jenkins"
    kubectl delete pvc jenkins -n "$NAMESPACE" || info "Brak PVC"

    info "Usuwam PV jenkins-pv"
    kubectl delete pv jenkins-pv || info "Brak PV"
}

install_jenkins() {
    [[ "$DRY_RUN" == "true" ]] && {
        info "[DRY RUN] Zainstalowałbym Jenkinsa z $VALUES"
        return
    }

    info "Instaluję Jenkinsa z $VALUES"
    if ! helm install "$RELEASE" jenkins/jenkins -n "$NAMESPACE" -f "$VALUES" --wait --timeout=5m --atomic; then
        err "Instalacja nieudana. Próba alternatywna ze storageClass=minikube-hostpath"
        helm install "$RELEASE" jenkins/jenkins -n "$NAMESPACE" -f "$VALUES" \
            --set controller.persistence.storageClass=minikube-hostpath \
            --wait --timeout=5m --atomic || {
                err "Również nieudana!"
                return 1
            }
    fi
    ok "Jenkins zainstalowany"
}

diagnose() {
    info "Status PVC:"
    kubectl get pvc -n "$NAMESPACE"

    info "Status poda Jenkins:"
    kubectl get pods -n "$NAMESPACE"

    kubectl describe pvc jenkins -n "$NAMESPACE" || info "Brak PVC"
    kubectl describe pod jenkins-0 -n "$NAMESPACE" || info "Brak poda"

    PVC_STATE=$(kubectl get pvc jenkins -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    POD_STATE=$(kubectl get pod jenkins-0 -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

    [[ "$PVC_STATE" == "Bound" ]] && ok "PVC jest Bound" || err "PVC NIE jest Bound"
    [[ "$POD_STATE" == "Running" ]] && ok "Pod działa poprawnie" || err "Pod NIE jest w stanie Running"
}

# === GŁÓWNA LOGIKA ===
info "=== DIAGNOSTYKA JENKINS ==="
info "Namespace: $NAMESPACE, Release: $RELEASE, Plik: $VALUES"
[[ "$DRY_RUN" == "true" ]] && info "Tryb DRY RUN aktywny"

check_helm_repo
check_namespace
check_storage_and_pv
check_values_file
clean_old_install
install_jenkins || exit 1
diagnose

info "=== KONIEC ==="
