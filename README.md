# fastapi-devops-infra

Infrastruktura (IaC) dla pracy dyplomowej DevOps: Terraform + Ansible dla
aplikacji z forka [`fastapi-realworld-example-app`](https://github.com/TurboBee77/fastapi-realworld-example-app)
(FastAPI + PostgreSQL). Docelowo: 3 instancje EC2 (Jenkins, aplikacja,
monitoring), stawiane od zera niewielką liczbą komend.

**Stan repo: Etap 0–3 zamknięte.** Terraform stawia infrastrukturę, Ansible
konfiguruje bazę (Docker + firewall) na wszystkich hostach i wdraża aplikację
(backend + PostgreSQL w Docker Compose) na VM2. Jenkins i monitoring to
kolejne etapy — patrz [Co jeszcze nie działa](#co-jeszcze-nie-działa).

## Architektura

3 instancje EC2 (Ubuntu 24.04, `t3.micro`), tworzone jednym reużywalnym
modułem Terraform (`terraform/modules/ec2-instance`), wywołanym trzykrotnie:

| VM | Rola | Docelowo | Elastic IP | Security group |
|---|---|---|---|---|
| VM1 | `ci` | Jenkins | tak | `ci-sg` |
| VM2 | `app` | Backend + PostgreSQL (Docker Compose) | tak | `app-sg` |
| VM3 | `monitoring` | Prometheus + Grafana (Docker Compose) | tak | `monitoring-sg` |

Sieć: domyślne VPC konta AWS, region `eu-central-1`. Każda instancja ma
własny Elastic IP (adres przetrwa `terraform destroy`→`apply`) i własny
security group. Każdy zaczyna z portem 22 (SSH); `app-sg` ma dodatkowo
otwarty port 8000 (API aplikacji, przez zmienną `extra_ingress_ports`
modułu `ec2-instance`) — patrz [`docs/network-architecture.md`](docs/network-architecture.md)
po diagram i plan dalszych rozszerzeń portów.

Na poziomie systemu operacyjnego druga warstwa firewalla to `ufw` (rola
Ansible), konfigurowana z domyślną polityką `deny incoming` / `allow
outgoing` + jawna reguła SSH.

## Wymagania wstępne

Zanim cokolwiek uruchomisz — **z control node na Linuksie** (Ansible nie
działa natywnie na Windows jako control node):

- **Terraform** `>= 1.5`
- **AWS CLI**, skonfigurowane (`aws configure`) z uprawnieniami do EC2/VPC
  w docelowym koncie
- **Istniejąca para kluczy EC2** w AWS o nazwie zgodnej z `key_name` w
  `terraform.tfvars` — Terraform jej nie tworzy, musi już istnieć
  (`aws ec2 create-key-pair` albo `aws ec2 import-key-pair`, jeśli masz już
  klucz SSH wygenerowany lokalnie)
- **Ansible** (`ansible-core`) + kolekcje spoza `ansible-core` (moduł `ufw`
  i moduł `docker_compose_v2` nie są w nim zawarte), zdeklarowane w
  `ansible/requirements.yml`:
  ```bash
  cd ansible
  ansible-galaxy collection install community.general
  ansible-galaxy collection install -r requirements.yml
  ```
- **Hasło do Ansible Vault** — sekrety appki (hasło do Postgresa,
  `SECRET_KEY`) są zaszyfrowane w `ansible/roles/deploy-app/vars/main.yml`.
  Playbook poprosi o to hasło interaktywnie (`--ask-vault-pass`) — nie jest
  ono nigdzie w repo, musisz je znać/mieć zapisane osobno (menedżer haseł).

  **Zakładasz repo od zera (świeży klon, nowy Vault)?** Zaszyfrowany
  `vars/main.yml` jest wprawdzie w repo, ale bez znajomości hasła Vaulta
  nikt poza autorem go nie odszyfruje. Żeby założyć własny, użyj wzorca
  `vars/main.yml.example` (jawny, pokazuje tylko oczekiwane nazwy zmiennych):
  ```bash
  cp ansible/roles/deploy-app/vars/main.yml.example \
     ansible/roles/deploy-app/vars/main.yml
  # wpisz prawdziwe wartości zamiast "changeme", potem zaszyfruj:
  ansible-vault encrypt ansible/roles/deploy-app/vars/main.yml
  ```
  Ansible zapyta o nowe hasło do Vaulta — to hasło (nie jego zawartość)
  musisz zapamiętać/zapisać osobno, będzie potrzebne przy każdym
  `--ask-vault-pass`. Edycja już zaszyfrowanego pliku później:
  `ansible-vault edit ansible/roles/deploy-app/vars/main.yml` (poprosi
  o hasło, otworzy odszyfrowaną treść w `$EDITOR`, zaszyfruje z powrotem
  przy zapisie).
- **Python 3 + PyYAML** na control node — potrzebne do
  `ansible/scripts/generate_inventory.py` (PyYAML jest i tak zależnością
  samego Ansible, zwykle nic dodatkowego nie trzeba instalować)
- Klucz SSH (ten sam co dla EC2) dodany do `ssh-agent`:
  ```bash
  ssh-add ~/.ssh/<twój-klucz>
  ```
  Ansible łączy się przez agenta — żadna ścieżka do klucza prywatnego nie
  jest zapisana w configu ani w repo.

## Konfiguracja przed pierwszym uruchomieniem

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edytuj `terraform.tfvars`: ustaw `key_name` na nazwę swojej pary kluczy w
AWS. Domyślnie `ssh_allowed_cidr = "0.0.0.0/0"` (SSH dostępny z dowolnego
IP) — zawęź do własnego adresu, jeśli chcesz ograniczyć dostęp.
`terraform.tfvars` jest w `.gitignore` — nie trafia do repo.

## Pełna sekwencja komend od zera

```bash
# 1. Infrastruktura (z katalogu terraform/)
cd terraform
terraform init
terraform apply

# 2. Wygenerowanie inventory Ansible z outputu Terraform (z katalogu ansible/)
cd ../ansible
python3 scripts/generate_inventory.py

# 3. Kolekcje Ansible spoza ansible-core (jednorazowo per control node)
ansible-galaxy collection install community.general
ansible-galaxy collection install -r requirements.yml

# 4. Konfiguracja bazowa hostów (Docker + ufw) i deploy aplikacji na VM2
ansible-playbook --syntax-check site.yml   # opcjonalny szybki filtr
ansible-playbook site.yml --ask-vault-pass
```

Playbook jest idempotentny — powtórne uruchomienie na już skonfigurowanych
hostach nie zgłasza zmian (`changed=0`), łącznie z rolą `deploy-app`.

Weryfikacja ad-hoc (opcjonalnie):
```bash
ansible all -m ansible.builtin.command -a "docker ps"
ansible all -m ansible.builtin.command -a "ufw status verbose"

# appka odpowiada z zewnątrz? (adres z: terraform output app_public_ip)
curl http://<Elastic-IP-app>:8000/docs
```

## Sprzątanie (Free Tier)

Konto AWS jest na Free Tier: 750h/miesiąc łącznie, a 3 równoległe instancje
zużywają ten limit ok. 3× szybciej niż jedna (~10 dni ciągłej pracy).
**Po każdej sesji pracy:**

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
│   ├── requirements.yml        (kolekcje spoza ansible-core, np. community.docker)
│   ├── group_vars/{all,app}.yml
│   ├── inventory/hosts.yml     (generowany skryptem, gitignored)
│   ├── scripts/generate_inventory.py
│   ├── roles/
│   │   ├── docker/, ufw/       (wspólne, wszystkie VM)
│   │   └── deploy-app/         (specyficzna dla VM2: backend + PostgreSQL)
│   │       ├── defaults/, vars/main.yml (zaszyfrowany Vault)
│   │       └── templates/docker-compose.yml.j2
│   └── site.yml
├── docs/network-architecture.md
├── .gitattributes, .gitignore, CONTRIBUTING.md
└── README.md
```

Konwencje branchy i commitów (Conventional Commits) — patrz
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Co jeszcze nie działa

Poniższe jest w harmonogramie, ale nie ma jeszcze pokrycia w tym repo —
nie próbuj tego uruchamiać na obecnym stanie kodu:

- Role Ansible `deploy-jenkins` (VM1) i `deploy-monitoring` (VM3) — Etap 4, 7
- Obraz appki buduje się **lokalnie na VM2** z klonowanego repo (`build: ./src`
  w compose) — Docker Hub (publikacja i `docker compose pull` zamiast
  lokalnego builda) to dopiero Etap 5, wykona to Jenkins
- Jenkinsfile / pipeline CI-CD — Etap 4–6 (znajdzie się w forku aplikacji,
  nie w tym repo)
- Prometheus/Grafana — Etap 7
- Terraform state w S3 — backlog, poza rdzeniem obowiązkowym

## Znane ograniczenia

- `ssh_allowed_cidr` domyślnie `0.0.0.0/0` — zawęź w `terraform.tfvars` do
  własnego IP, jeśli nie chcesz zostawiać SSH otwartego dla całego internetu
- Security groups nie mają jeszcze reguł komunikacji między instancjami
  (np. `ci` → `app` po SSH do celów deployu) — planowane przy Etapie 6/7
  przez `source_security_group_id`, nie szeroki CIDR
- Hasło do Ansible Vault jest podawane ręcznie (`--ask-vault-pass`) przy
  każdym uruchomieniu — automatyzacja (`--vault-password-file` z pliku poza
  repo, albo credential w Jenkinsie) to temat Etapu 4/6, nie teraz
- `/opt/app/docker-compose.yml` na VM2 ma `mode: 0600` (zawiera jawne hasło
  i `SECRET_KEY` po odszyfrowaniu Vaulta) — ręczne komendy `docker compose`
  na tej maszynie wymagają `sudo`, zwykły użytkownik `ubuntu` nie odczyta
  pliku bezpośrednio
