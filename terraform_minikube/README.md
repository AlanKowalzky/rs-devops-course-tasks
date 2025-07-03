# Minikube – lokalny klaster Kubernetes

## Instalacja Minikube

1. Pobierz i zainstaluj Minikube zgodnie z oficjalną dokumentacją:
   https://minikube.sigs.k8s.io/docs/start/

2. Uruchom klaster:
   ```sh
   minikube start
   ```

3. Sprawdź status klastra:
   ```sh
   kubectl get nodes
   ```

## Dalsze kroki
- Po uruchomieniu Minikube możesz instalować Helm, Jenkins, aplikacje, itp.
- Wszystkie polecenia wykonuj w terminalu z dostępem do kubectl i helm. 