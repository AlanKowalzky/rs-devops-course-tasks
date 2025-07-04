# Automatyczne uruchomienie Minikube na AWS (Terraform)

## Krok 1: Przygotowanie
- Upewnij się, że masz skonfigurowane AWS CLI oraz klucz SSH (`~/.ssh/id_rsa.pub`).
- Zmień region i AMI w pliku `main.tf` jeśli używasz innego regionu.

## Krok 2: Inicjalizacja Terraform
```sh
cd terraform_minikube
terraform init
```

## Krok 3: Uruchomienie infrastruktury
```sh
terraform apply
```
- Po zakończeniu zobaczysz publiczny adres IP instancji EC2.

## Krok 4: Połącz się przez SSH
```sh
ssh -i ~/.ssh/id_rsa ubuntu@<public_ip>
```

## Krok 5: Sprawdź status klastra
```sh
kubectl get nodes
```

## Krok 6: Dalsze kroki
- Możesz instalować Helm chart Jenkinsa, aplikacje, itp.
- Dostęp do aplikacji przez NodePort lub port-forward.

## Usuwanie środowiska
```sh
terraform destroy
```

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