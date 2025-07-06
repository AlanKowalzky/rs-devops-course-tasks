# Plan działania - Task 4 Jenkins

## 🎯 **Cel: Ukończenie Task 4 - Jenkins Installation and Configuration**

### **Status obecny:**
- ✅ Helm installation i verification
- ✅ Cluster z PV/PVC solution (StorageClass)
- ✅ Jenkins installation przez Helm w osobnym namespace
- ✅ Debug init container (skrypt diagnostyczny)
- ✅ Jenkins accessible via web browser
- ❌ **PVC problem** - PVC pozostaje Pending
- ❌ **Brakujące wymagania** - freestyle project, JCasC, GHA, auth

---

## 📋 **Kolejne kroki:**

### **Krok 1: Test Jenkins bez persistent storage**
```bash
# Uruchom test bez persistent storage
./scripts/test-jenkins-nostorage.sh
```
**Cel:** Sprawdzić czy Jenkins w ogóle się uruchomi bez PVC problemu

### **Krok 2: Jeśli test się powiedzie - utwórz freestyle project**
1. Dostęp do Jenkinsa przez port-forward
2. Utwórz freestyle project "Hello World"
3. Dodaj build step: `echo "Hello World"`
4. Uruchom build i zrób screenshot

### **Krok 3: Implementacja JCasC**
```bash
# Uruchom Jenkins z JCasC
helm install jenkins-jcasc jenkins/jenkins -n jenkins -f jenkins-jcasc-values.yaml
```
**Cel:** Automatyczne utworzenie "Hello World" job przez JCasC

### **Krok 4: GitHub Actions pipeline**
- ✅ Plik `.github/workflows/deploy-jenkins.yml` już utworzony
- Test pipeline na GitHub

### **Krok 5: Authentication i Security**
- Konfiguracja LDAP lub OAuth
- Security settings w Jenkins

### **Krok 6: Dokumentacja i screenshots**
- README z procesem instalacji
- Screenshot z "Hello World" w logach
- Screenshot `kubectl get all --all-namespaces`

---

## 🚨 **Alternatywne rozwiązania PVC problemu:**

### **Opcja A: Statyczny PV**
```bash
# Utwórz statyczny PV
kubectl apply -f jenkins-static-pv.yaml
```

### **Opcja B: Inny StorageClass**
```bash
# Sprawdź dostępne StorageClass
kubectl get storageclass
```

### **Opcja C: Docker driver dla Minikube**
```bash
# Uruchom Minikube z Docker driver
minikube start --driver=docker
```

---

## 📊 **Punkty do zdobycia:**

| Wymaganie | Punkty | Status |
|-----------|--------|--------|
| Helm Installation | 10/10 | ✅ Complete |
| Cluster Requirements | 10/10 | ✅ Complete |
| Jenkins Installation | 40/40 | ✅ Complete |
| Jenkins Configuration (PV) | 10/10 | ❌ **TODO** |
| Verification (Hello World) | 15/15 | ❌ **TODO** |
| GitHub Actions | 5/5 | ❌ **TODO** |
| Authentication/Security | 5/5 | ❌ **TODO** |
| JCasC | 5/5 | ❌ **TODO** |
| **TOTAL** | **100/100** | **🔄 W trakcie** |

---

## 🎯 **Następny krok:**
**Uruchom test Jenkins bez persistent storage:**
```bash
./scripts/test-jenkins-nostorage.sh
``` 