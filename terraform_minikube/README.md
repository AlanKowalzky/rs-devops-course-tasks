# Automatyczne uruchomienie Minikube + Jenkins na AWS (Terraform, Free Tier)

## Krok 1: Przygotowanie
- Upewnij się, że masz skonfigurowane AWS CLI oraz klucz SSH (`~/.ssh/id_rsa.pub`).
- Free Tier AWS: t2.micro/t3.micro (1GB RAM, 20GB EBS, region eu-central-1).
- Zmień region/AMI w pliku `main.tf` jeśli używasz innego regionu.

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

## Krok 5: Sprawdź status klastra i Jenkinsa
```sh
kubectl get nodes
kubectl get pods -A
kubectl get pvc -A
kubectl logs -l app.kubernetes.io/component=jenkins-controller
```

## Krok 6: Dostęp do Jenkinsa
- Jenkins uruchomiony jest na NodePort (sprawdź port przez `kubectl get svc jenkins`).
- Domyślny login: admin/admin
- Otwórz w przeglądarce: `http://<public_ip>:<nodeport>`

## Ostrzeżenia Free Tier
- Free Tier = 1GB RAM. Jenkins MOŻE działać niestabilnie lub bardzo wolno.
- Skrypt automatycznie ostrzega, jeśli RAM <2GB, ale kontynuuje instalację.
- Zalecane: do testów, nie do produkcji.

## Usuwanie środowiska
```sh
terraform destroy
```

## Troubleshooting
- Jeśli Jenkins nie startuje: sprawdź logi, RAM, miejsce na dysku.
- Jeśli Jenkins jest niestabilny: rozważ większą instancję (np. t3.small).
- Sprawdź status PVC, podów, logi Jenkinsa.

## Dalsze kroki
- Możesz rozbudować pipeline, dodać aplikacje, testy, backup do S3.
- Wszystkie polecenia wykonuj w terminalu z dostępem do kubectl i helm.

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

## Checklist zgodności z wymaganiami zadania
- [x] Automatyczny provisioning EC2 (Free Tier, t2.micro)
- [x] Persistent storage dla Jenkinsa (local-path-provisioner na EBS)
- [x] Jenkins Configuration as Code (JCasC, admin user, pipeline seed job)
- [x] Pipeline (przykładowy pipeline hello-aws)
- [x] Diagnostyka (RAM, status podów, PVC, logi Jenkinsa)
- [x] Security group – tylko niezbędne porty
- [x] Dokumentacja, troubleshooting, ostrzeżenia Free Tier
- [x] Diagram architektury (Mermaid)

## Backup konfiguracji Jenkins do S3 (Free Tier)
Możesz wykonać backup katalogu Jenkinsa do S3 (do 15GB w Free Tier):
```sh
aws s3 cp /var/jenkins_home s3://twoj-bucket-jenkins-backup/ --recursive
```

## Automatyczna konfiguracja JCasC i pipeline
- Plik `jenkins-jcasc.yaml` automatycznie konfiguruje admina, systemMessage i seed job pipeline (hello-aws).
- Po uruchomieniu Jenkins od razu ma gotowy pipeline do testów. 