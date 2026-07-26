# fastapi-devops-infra

Infrastruktura (IaC) dla pracy dyplomowej DevOps: Terraform + Ansible dla
aplikacji z forka [`fastapi-realworld-example-app`](https://github.com/TurboBee77/fastapi-realworld-example-app)
(FastAPI + PostgreSQL). Docelowo: 3 instancje EC2 (Jenkins, aplikacja,
monitoring), stawiane od zera niewielką liczbą komend.

**Stan repo: Etap 0–2 zamknięte.** Terraform stawia infrastrukturę, Ansible
konfiguruje bazę (Docker + firewall) na wszystkich hostach. Deploy aplikacji,
Jenkins i monitoring to kolejne etapy — patrz [Co jeszcze nie działa](#co-jeszcze-nie-działa).

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
security group, obecnie otwierający wyłącznie port 22 (SSH) — patrz
[`docs/network-architecture.md`](docs/network-architecture.md) po diagram i
plan rozszerzeń portów w kolejnych etapach.

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
- **Ansible** (`ansible-core`) + kolekcja `community.general` (moduł `ufw`
  nie jest częścią `ansible-core`):
  ```bash
  ansible-galaxy collection install community.general
  ```
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

# 3. Konfiguracja bazowa hostów (Docker + ufw)
ansible-playbook --syntax-check site.yml   # opcjonalny szybki filtr
ansible-playbook site.yml
```

Playbook jest idempotentny — powtórne uruchomienie na już skonfigurowanych
hostach nie zgłasza zmian (`changed=0`).

Weryfikacja ad-hoc (opcjonalnie):
```bash
ansible all -m ansible.builtin.command -a "docker ps"
ansible all -m ansible.builtin.command -a "ufw status verbose"
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
│   ├── group_vars/all.yml
│   ├── inventory/hosts.yml     (generowany skryptem, gitignored)
│   ├── scripts/generate_inventory.py
│   ├── roles/{docker,ufw}/
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

- Rola Ansible `deploy` (docker-compose dla `app`/`monitoring`, Jenkins na
  `ci`) — Etap 3+
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
