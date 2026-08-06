# fastapi-devops-infra

Infrastruktura (IaC) dla pracy dyplomowej DevOps: Terraform + Ansible dla
aplikacji z forka [`fastapi-realworld-example-app`](https://github.com/TurboBee77/fastapi-realworld-example-app)
(FastAPI + PostgreSQL). Trzy instancje EC2 (Jenkins, aplikacja, monitoring),
stawiane od zera niewielką liczbą komend, z w pełni zautomatyzowanym
pipeline'em CI/CD (build → test → publikacja obrazu → deploy → powiadomienie)
i stackiem Prometheus + Grafana.

Terraform stawia infrastrukturę, Ansible konfiguruje bazę (Docker +
firewall) na wszystkich hostach, wdraża aplikację (backend + PostgreSQL w
Docker Compose) na VM aplikacyjnej i stawia Jenkinsa w pełni
skonfigurowanego przez **Jenkins Configuration as Code** (JCasC): setup
wizard pominięty, konto admina, wszystkie credentiale (SSH do VM
aplikacyjnej, GitHub, Docker Hub, hasło Ansible Vault, webhook Discorda),
konfiguracja GitHub Servera i sam Multibranch Pipeline job tworzone
automatycznie przy starcie kontenera — sekrety czytane z plików
dostarczanych przez Ansible Vault, nie z surowych zmiennych środowiskowych.
Pipeline w forku aplikacji: `Test` (pytest na efemerycznej bazie) →
`Build & Push` (Docker Hub) → `Deploy` (tylko na głównej gałęzi — Ansible/SSH
aktualizuje aplikację) → powiadomienie o wyniku na Discord. Na VM
monitoringowej stoi Prometheus + Grafana — aplikacja wystawia `/metrics`,
Prometheus scrape'uje aplikację i node_exportery na wszystkich trzech VM po
prywatnym IP, Grafana ma dashboard "DevOps Overview" auto-provisionowany
jako kod (zero klikania po `destroy`→`apply`). Wszystkie credentiale
Jenkinsa żyją w Vault na control-node (nie w AWS) — pełny cykl
`terraform destroy` → `apply` → `ansible-playbook` nie wymaga ręcznej
konfiguracji w UI Jenkinsa.

## Architektura

Trzy instancje EC2 (Ubuntu 24.04, `t3.small`), tworzone jednym reużywalnym
modułem Terraform (`terraform/modules/ec2-instance`), wywołanym trzykrotnie
z różnymi parametrami. `t3.micro` (1GB RAM) okazał się za mały pod
obciążeniem pipeline'u CI (JVM Jenkinsa + demon Dockera + kontenery testowe
+ build obrazu jednocześnie — instancja stawała się nieresponsywna,
prawdopodobnie z powodu OOM); podbite do `t3.small` dla wszystkich trzech VM
wspólną zmienną `var.instance_type`. `t3.small` pokazuje się w konsoli AWS
jako "Free tier eligible" — zweryfikuj to jednak samodzielnie przez
**Billing → Free Tier** na swoim koncie, bo to inny/szerszy model niż
klasyczny "750h/mies. tylko t2/t3.micro".

| VM | Rola | Co tam działa | Elastic IP | Security group |
|---|---|---|---|---|
| VM1 | `ci` | Jenkins (kontener, port 8080) | tak | `ci-sg` |
| VM2 | `app` | Backend + PostgreSQL (Docker Compose) | tak | `app-sg` |
| VM3 | `monitoring` | Prometheus + Grafana (Docker Compose) | tak | `monitoring-sg` |

Sieć: domyślne VPC konta AWS, region `eu-central-1`. Każda instancja ma
własny Elastic IP (adres przetrwa `terraform destroy`→`apply`) i własny
security group. Każdy zaczyna z portem 22 (SSH); `app-sg` ma dodatkowo
otwarty port 8000 (API aplikacji) i 9100 (node_exporter), `ci-sg` port 8080
(UI Jenkinsa) i 9100, `monitoring-sg` port 3000 (Grafana), 9090 (Prometheus
UI) i 9100. Dwie **osobne** pule portów per moduł: publiczna
(`extra_ingress_ports`, `0.0.0.0/0` albo zawężony `ssh_allowed_cidr`) dla
tego, co musi być dostępne z zewnątrz (8000, 8080, 3000), i wewnętrzna
(`internal_ingress_ports`, CIDR domyślnego VPC — `data "aws_vpc" "default"`)
dla portów bez auth, które nie powinny być widoczne z internetu (9100,
9090) — patrz [`docs/network-architecture.md`](docs/network-architecture.md)
po diagram.

Na poziomie systemu operacyjnego druga warstwa firewalla to `ufw` (rola
Ansible), konfigurowana z domyślną polityką `deny incoming` / `allow
outgoing` + jawna reguła SSH — obie warstwy (security group AWS i `ufw`)
muszą przepuścić ruch, żeby cokolwiek doszło do usługi.

## Wymagania wstępne

Wszystko poniżej uruchamiasz **z control node na Linuksie** — Ansible nie
działa natywnie na Windows jako control node.

### Narzędzia

- **Terraform** `>= 1.5` — stawia infrastrukturę AWS.
- **AWS CLI**, uwierzytelniony do konta z uprawnieniami EC2/VPC:
  ```bash
  aws configure
  ```
- **Para kluczy EC2 w AWS** — Terraform jej nie tworzy, musi już istnieć,
  nazwa musi zgadzać się z `key_name` w `terraform.tfvars`:
  ```bash
  aws ec2 import-key-pair --key-name <nazwa> --public-key-material fileb://~/.ssh/<klucz>.pub
  ```
- **Ansible** (`ansible-core`) + kolekcje spoza rdzenia — moduły `ufw`,
  `docker_compose_v2`, `authorized_key` w nim nie siedzą:
  ```bash
  cd ansible
  ansible-galaxy collection install -r requirements.yml
  ```
- **ssh-agent z załadowanym kluczem** — Ansible łączy się przez agenta,
  bez ścieżki do klucza w configu:
  ```bash
  ssh-add ~/.ssh/<twój-klucz>
  ```
- **Python 3 + PyYAML** — potrzebne do `scripts/generate_inventory.py`
  (zwykle nic dodatkowego, to i tak zależność samego Ansible)

### Konfiguracja specyficzna dla projektu

Cztery pliki do założenia przed pierwszym uruchomieniem — jeden jawny
(Terraform), trzy zaszyfrowane Ansible Vault (niosą sekrety). Każdy ma
wzorzec `*.example` w repo.

#### `terraform/terraform.tfvars`

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

```hcl
aws_region       = "eu-central-1"
key_name         = "fastapi-devops-key"
ssh_allowed_cidr = "0.0.0.0/0"
instance_type    = "t3.small"

app_extra_ingress_ports        = [8000]
ci_extra_ingress_ports         = [8080]
monitoring_extra_ingress_ports = [3000]

ci_internal_ingress_ports         = [9100]
app_internal_ingress_ports        = [9100]
monitoring_internal_ingress_ports = [9100, 9090]

ci_root_volume_size  = 16
app_root_volume_size = 12
```

| Zmienna | Co to jest |
|---|---|
| `key_name` | nazwa pary kluczy EC2 w AWS (patrz wyżej) |
| `ssh_allowed_cidr` | źródło dopuszczone do SSH i portów publicznych — zawęź do własnego IP zamiast `0.0.0.0/0` |
| `*_extra_ingress_ports` | porty publiczne per rola (Jenkins UI, API appki, Grafana) |
| `*_internal_ingress_ports` | porty widoczne tylko z CIDR VPC (node_exporter, Prometheus UI) |
| `ci_root_volume_size` / `app_root_volume_size` | root EBS w GB — domyślne 8 GB za mało pod Docker + build cache (`ci`) / Docker + PostgreSQL (`app`) |

#### `ansible/roles/deploy-app/vars/main.yml`

```bash
cp ansible/roles/deploy-app/vars/main.yml.example \
   ansible/roles/deploy-app/vars/main.yml
ansible-vault encrypt ansible/roles/deploy-app/vars/main.yml
```

```yaml
vault_postgres_password: "changeme"
vault_secret_key: "changeme-generuj-losowy-string"
```

| Zmienna | Co to jest |
|---|---|
| `vault_postgres_password` | hasło do bazy PostgreSQL appki |
| `vault_secret_key` | `SECRET_KEY` appki (podpisywanie JWT) |

#### `ansible/roles/deploy-jenkins/vars/main.yml`

```bash
cp ansible/roles/deploy-jenkins/vars/main.yml.example \
   ansible/roles/deploy-jenkins/vars/main.yml
ansible-vault encrypt ansible/roles/deploy-jenkins/vars/main.yml
```

```yaml
vault_jenkins_admin_password: "wpisz-swoje-haslo"
vault_jenkins_git_token: "token git"
vault_jenkins_dockerhub_token: "dockerhub token"
vault_jenkins_ssh_cd_key: "klucz ssh do obslugi node"
vault_ansible_vault_password: "to samo haslo, ktorym szyfrujesz ten plik (ansible-vault)"
vault_discord_webhook_url: "https://discord.com/api/webhooks/..."
```

| Zmienna | Co to jest |
|---|---|
| `vault_jenkins_admin_password` | hasło konta admina Jenkinsa |
| `vault_jenkins_git_token` | GitHub PAT (webhook + Multibranch Pipeline) |
| `vault_jenkins_dockerhub_token` | Docker Hub Access Token |
| `vault_jenkins_ssh_cd_key` | prywatny klucz SSH dedykowany do CD na VM `app` (`ssh-keygen -t ed25519 -N ""`; publiczną część dopisuje automatycznie rola `deploy-app`) |
| `vault_ansible_vault_password` | to samo hasło Vaulta — Jenkins potrzebuje go do nieinteraktywnego `--vault-password-file` w stage'u `Deploy` |
| `vault_discord_webhook_url` | Server Settings → Integrations → Webhooks na Discordzie |

#### `ansible/roles/deploy-monitoring/vars/main.yml`

```bash
cp ansible/roles/deploy-monitoring/vars/main.yml.example \
   ansible/roles/deploy-monitoring/vars/main.yml
ansible-vault encrypt ansible/roles/deploy-monitoring/vars/main.yml
```

```yaml
vault_grafana_admin_password: changeme
```

| Zmienna | Co to jest |
|---|---|
| `vault_grafana_admin_password` | hasło konta admina Grafany |

**Jedno hasło Vaulta dla wszystkich trzech plików** — Ansible poprosi o nie
interaktywnie (`--ask-vault-pass`) przy każdym uruchomieniu playbooka.
Edycja później:
```bash
ansible-vault edit ansible/roles/<rola>/vars/main.yml
```

## Uruchomienie od zera

1. **Infrastruktura** (katalog `terraform/`):
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

2. **Inventory Ansible**, generowane z outputu Terraform (katalog `ansible/`) —
   Elastic IP dostaje nową alokację przy każdym `apply`, więc inventory nie
   jest edytowane ręcznie:
   ```bash
   cd ../ansible
   python3 scripts/generate_inventory.py
   ```

3. **Konfiguracja hostów + deploy** (Docker, `ufw`, aplikacja, Jenkins,
   monitoring — wszystko w jednym playbooku):
   ```bash
   ansible-playbook --syntax-check --ask-vault-pass site.yml   # opcjonalny szybki filtr
   ansible-playbook site.yml --ask-vault-pass
   ```
   Playbook jest idempotentny — drugi przebieg na już skonfigurowanych
   hostach kończy się `changed=0`. `--syntax-check` też wymaga
   `--ask-vault-pass` (Ansible odszyfrowuje `vars` ról już przy budowaniu
   struktury playbooka).

## Weryfikacja

Adresy IP z `terraform output` (`app_public_ip`, `ci_public_ip`,
`monitoring_public_ip`):

```bash
curl http://<IP-app>:8000/docs        # appka odpowiada
curl http://<IP-app>:8000/metrics     # appka wystawia metryki
curl -I http://<IP-ci>:8080           # Jenkins wstał
curl -I http://<IP-monitoring>:3000   # Grafana wstała
```

Prometheus (`:9090`) i node_exporter (`:9100`) są celowo niewidoczne z
internetu (patrz [Architektura](#architektura)) — sprawdź po SSH na
dowolną VM:

```bash
curl -s localhost:9090/api/v1/targets | python3 -m json.tool   # na monitoring
curl -s http://<dowolny-private-ip>:9100/metrics                # z dowolnej VM
```

Pierwsze logowanie do Jenkinsa: `http://<IP-ci>:8080`, loginem/hasłem z
`ansible/roles/deploy-jenkins/vars/main.yml` — setup wizard jest pominięty,
konto i wszystkie pluginy tworzą się automatycznie przy starcie kontenera.

## Pipeline CI/CD

Multibranch Pipeline w Jenkinsie (`fastapi-app-ci`, auto-discovery gałęzi z
`Jenkinsfile` w forku aplikacji, wyzwalacz: webhook GitHub):

- **Dowolna gałąź** → `Test` (pytest na efemerycznej bazie PostgreSQL w
  Docker Compose) → `Build & Push` (obraz `<gałąź>-<sha>` na Docker Hub).
- **Gałąź `master`** dodatkowo → `Deploy`: Ansible/SSH aktualizuje kontener
  aplikacji na VM `app` nowym tagiem obrazu. Ograniczone do buildów
  wywołanych realnym pushem/webhookiem — automatyczne buildy ze skanu
  gałęzi (np. przy każdym świeżym starcie Jenkinsa) nie wyzwalają deployu.
- **Zawsze na koniec** → powiadomienie na Discord (sukces albo porażka),
  niezależnie od tego, na którym etapie pipeline się zatrzymał.

`Deploy` woła ten sam playbook `site.yml` co pełne uruchomienie z control
node, ale z `--limit app` — aktualizuje wyłącznie kontener aplikacji.
Wszystko, co wymaga widoczności VM `ci` (autoryzacja klucza SSH używanego
do CD, przekazanie aktualnego IP aplikacji do Jenkinsa), ustawia tylko
pełny przebieg z control node.

## Sprzątanie (Free Tier)

Konto AWS jest na Free Tier: 750h/miesiąc łącznie, a 3 równoległe instancje
zużywają ten limit ok. 3× szybciej niż jedna (~10 dni ciągłej pracy). Po
każdej sesji pracy:

```bash
cd terraform
terraform destroy
```

Elastic IP dostanie nową alokację przy kolejnym `apply` — dlatego inventory
Ansible jest generowane skryptem z aktualnego `terraform output`, nie
edytowane ręcznie.

## Struktura repo

```
fastapi-devops-infra/
├── terraform/
│   ├── main.tf, variables.tf, outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/ec2-instance/   (reużywalny moduł, wywołany 3×: ci/app/monitoring)
├── ansible/
│   ├── ansible.cfg
│   ├── requirements.yml        (kolekcje spoza ansible-core)
│   ├── group_vars/{all,app,ci,monitoring}.yml
│   ├── inventory/hosts.yml     (generowany skryptem, gitignored)
│   ├── scripts/generate_inventory.py
│   ├── roles/
│   │   ├── docker/, ufw/, node-exporter/   (wspólne, wszystkie VM)
│   │   ├── deploy-app/                     (VM app: backend + PostgreSQL)
│   │   │   ├── defaults/, vars/main.yml (Vault)
│   │   │   ├── tasks/main.yml, tasks/provisioning_ci_link.yml
│   │   │   └── templates/docker-compose.yml.j2
│   │   ├── deploy-jenkins/                 (VM ci: Jenkins w kontenerze)
│   │   │   ├── defaults/, vars/main.yml (Vault)
│   │   │   └── files/Dockerfile, jenkins.yml (JCasC), plugins.txt
│   │   └── deploy-monitoring/              (VM monitoring: Prometheus + Grafana)
│   │       ├── defaults/, vars/main.yml (Vault), handlers/
│   │       ├── templates/docker-compose.yml.j2, prometheus.yml.j2
│   │       └── files/grafana/{provisioning,dashboards}/
│   └── site.yml
├── docs/network-architecture.md
├── .gitattributes, .gitignore, CONTRIBUTING.md
├── TODO.md
└── README.md
```

## Known limitations

- `ssh_allowed_cidr` domyślnie `0.0.0.0/0` — zawęź w `terraform.tfvars` do
  własnego IP, jeśli nie chcesz zostawiać SSH i portów publicznych
  otwartych dla całego internetu.
- `/metrics` aplikacji jest publicznie dostępny (ten sam port 8000 co
  reszta API, security group filtruje po IP+porcie, nie po ścieżce) —
  docelowo reverse proxy (nginx) razem z ewentualnym SSL, świadomie poza
  obecnym zakresem.
- `/opt/app/docker-compose.yml` na VM `app` ma `mode: 0600` (zawiera jawne
  hasło i `SECRET_KEY` po odszyfrowaniu Vaulta) — odczyt wymaga `sudo`.
- Kontener Jenkinsa ma zamontowany `/var/run/docker.sock`
  (Docker-outside-of-Docker, potrzebne do budowania obrazów appki z
  poziomu pipeline'u) i działa jako `root` — świadomy kompromis
  bezpieczeństwa, nie pełna izolacja.
- Obraz Jenkinsa buduje się lokalnie na VM `ci` przy każdym
  `ansible-playbook` (kilka minut) — nic nie jest publikowane na Docker
  Hub, w odróżnieniu od obrazu aplikacji.
- Wersje pluginów w `plugins.txt` nie są przypięte — build obrazu
  Jenkinsa nie jest w pełni reprodukowalny w czasie.
- Sekcja `jobs:` w `jenkins.yml` (Job DSL) nie odświeża konfiguracji
  (`traits`/`branchSources`) na **już istniejącym** Multibranch jobie —
  zmiana wymaga ręcznego usunięcia joba w UI przed ponownym uruchomieniem
  playbooka. Na świeżym `terraform destroy`→`apply` nie występuje.
- Status commitów na GitHubie się nie aktualizuje (GitHub PAT używany
  przez Jenkinsa nie ma scope'u `Commit statuses`) — kosmetyczne, nie
  blokuje pipeline'u.
- Martwe webhooki GitHub akumulują się w repo aplikacji przy kolejnych
  cyklach `destroy`→`apply` (nowy Elastic IP `ci` → nowy webhook, stary
  zostaje) — do ręcznego sprzątania w GitHub → Settings → Webhooks.
- Zmiana `root_volume_size` w Terraform na **już istniejącej** instancji
  (in-place modify, nie świeży `destroy`→`apply`) nie rozciąga
  automatycznie systemu plików — wymaga ręcznego `growpart`+`resize2fs`.
- Dashboard Grafany nie ma jeszcze panelu latencji (aplikacja wystawia
  histogram `http_request_duration_seconds`, obecnie niewykorzystany).
