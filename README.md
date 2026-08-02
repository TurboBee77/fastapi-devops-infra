# fastapi-devops-infra

Infrastruktura (IaC) dla pracy dyplomowej DevOps: Terraform + Ansible dla
aplikacji z forka [`fastapi-realworld-example-app`](https://github.com/TurboBee77/fastapi-realworld-example-app)
(FastAPI + PostgreSQL). Docelowo: 3 instancje EC2 (Jenkins, aplikacja,
monitoring), stawiane od zera niewielką liczbą komend.

**Stan repo: Etap 0–5 zamknięte, Etap 6 w toku.** Terraform stawia
infrastrukturę, Ansible konfiguruje bazę (Docker + firewall) na wszystkich
hostach, wdraża aplikację (backend + PostgreSQL w Docker Compose) na VM2 i
stawia Jenkinsa na VM1 w pełni skonfigurowanego przez **Jenkins
Configuration as Code** (JCasC, `ansible/roles/deploy-jenkins/files/jenkins.yml`):
setup wizard pominięty, konto admina, wszystkie credentiale (SSH do VM2,
GitHub PAT ×2, Docker Hub), GitHub Server config i sam Multibranch Pipeline
job (`fastapi-app-ci`) tworzone automatycznie przy starcie kontenera —
sekrety czytane z plików dostarczanych przez Ansible Vault (`/run/secrets/`),
nie z surowych zmiennych środowiskowych. Jenkinsfile w forku appki
automatycznie buduje obraz, uruchamia testy pytest na efemerycznej bazie i
publikuje obraz na Docker Hub przy każdym pushu.
**Wyjątek, świadomy i udokumentowany:** klucz SSH do VM2 jest na razie
placeholderem (`vault_jenkins_ssh_cd_key`) — prawdziwy klucz i sam stage
`deploy` w Jenkinsfile to dopiero domykany Etap 6, patrz
[Co jeszcze nie działa](#co-jeszcze-nie-działa). Monitoring to Etap 7.

## Architektura

3 instancje EC2 (Ubuntu 24.04, `t3.small`), tworzone jednym reużywalnym
modułem Terraform (`terraform/modules/ec2-instance`), wywołanym trzykrotnie:
`t3.micro` (1GB RAM) okazał się za mały dla `ci` pod obciążeniem pipeline'u
CI (JVM Jenkinsa + demon Dockera + kontenery testowe + build obrazu
jednocześnie — instancja stawała się nieresponsywna, prawdopodobnie OOM,
patrz `etap-5-podsumowanie.md`); podbite do `t3.small` dla **wszystkich
trzech** VM przez wspólną zmienną `var.instance_type` (nie tylko `ci`,
świadomie, dla prostoty). `t3.small` pokazuje się w konsoli AWS jako "Free
tier eligible" dla tego konta — zweryfikuj to jednak samodzielnie przez
**Billing → Free Tier**, bo to inny/szerszy model niż klasyczny
"750h/mies. tylko t2/t3.micro".

| VM | Rola | Co tam działa | Elastic IP | Security group |
|---|---|---|---|---|
| VM1 | `ci` | Jenkins (kontener, port 8080) | tak | `ci-sg` |
| VM2 | `app` | Backend + PostgreSQL (Docker Compose) | tak | `app-sg` |
| VM3 | `monitoring` | Prometheus + Grafana (Docker Compose) — Etap 7 | tak | `monitoring-sg` |

Sieć: domyślne VPC konta AWS, region `eu-central-1`. Każda instancja ma
własny Elastic IP (adres przetrwa `terraform destroy`→`apply`) i własny
security group. Każdy zaczyna z portem 22 (SSH); `app-sg` ma dodatkowo
otwarty port 8000 (API aplikacji), `ci-sg` port 8080 (UI Jenkinsa) — oba
przez zmienną `extra_ingress_ports` modułu `ec2-instance`, sterowaną
zmiennymi root modułu `app_extra_ingress_ports`/`ci_extra_ingress_ports`
w `terraform.tfvars` — patrz [`docs/network-architecture.md`](docs/network-architecture.md)
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

  Ten sam mechanizm (i to samo hasło do Vaulta) dotyczy drugiego pliku:
  `ansible/roles/deploy-jenkins/vars/main.yml` — załóż go analogicznie z
  `vars/main.yml.example` w tym samym katalogu. Niesie cztery zmienne,
  wszystkie wstrzykiwane do JCasC jako pliki w `/run/secrets/` (nie env
  vars): `vault_jenkins_admin_password`, `vault_jenkins_git_token`
  (GitHub PAT), `vault_jenkins_dockerhub_token` (Docker Hub Access Token),
  `vault_jenkins_ssh_cd_key` (klucz SSH do VM2 — **na dziś placeholder**,
  patrz [Co jeszcze nie działa](#co-jeszcze-nie-działa)).
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

# 4. Konfiguracja bazowa hostów (Docker + ufw), deploy aplikacji na VM2
#    i Jenkinsa na VM1
ansible-playbook --syntax-check --ask-vault-pass site.yml   # opcjonalny szybki filtr
ansible-playbook site.yml --ask-vault-pass
```

Playbook jest idempotentny — powtórne uruchomienie na już skonfigurowanych
hostach nie zgłasza zmian (`changed=0`), łącznie z rolami `deploy-app` i
`deploy-jenkins`. Uwaga: `--syntax-check` też wymaga `--ask-vault-pass` —
Ansible ładuje (i próbuje odszyfrować) `vars` ról już przy budowaniu
struktury playbooka, zanim cokolwiek faktycznie wykona.

Weryfikacja ad-hoc (opcjonalnie):
```bash
ansible all -m ansible.builtin.command -a "docker ps"
ansible all -m ansible.builtin.command -a "ufw status verbose"

# appka odpowiada z zewnątrz? (adres z: terraform output app_public_ip)
curl http://<Elastic-IP-app>:8000/docs

# Jenkins wstał? (adres z: terraform output ci_public_ip)
curl -I http://<Elastic-IP-ci>:8080
```

Pierwsze logowanie do Jenkinsa: `http://<Elastic-IP-ci>:8080`, loginem i
hasłem z `ansible/roles/deploy-jenkins/vars/main.yml` (setup wizard jest
pominięty, konto administratora i pluginy tworzą/instalują się automatycznie
przy starcie kontenera — patrz `etap-4-podsumowanie.md`, `etap-5-podsumowanie.md`).

## Konfiguracja Jenkinsa po każdym pełnym recreate

**Od Etapu 6 w większości zautomatyzowane przez JCasC**
(`ansible/roles/deploy-jenkins/files/jenkins.yml`, plugin
`configuration-as-code`). Przy starcie kontenera, bez ręcznego klikania,
powstają: konto admina, wszystkie credentiale (GitHub PAT jako *Secret
text* i jako *Username/password*, Docker Hub, SSH do VM2), GitHub Server
config (**Manage hooks** włączone) i sam Multibranch Pipeline job
(`fastapi-app-ci`, Script Path `Jenkinsfile`) — zdefiniowany przez skrypt
Job DSL osadzony w `jenkins.yml` (sekcja `jobs:`, wymaga pluginu `job-dsl`).

Żeby to faktycznie zadziałało, musisz wcześniej założyć/wypełnić
`ansible/roles/deploy-jenkins/vars/main.yml` (patrz
[Wymagania wstępne](#wymagania-wstępne)) prawdziwymi wartościami GitHub PAT
i Docker Hub Access Tokena — bez nich Jenkins i tak wstanie, ale
credentiale będą puste/nieużyteczne.

**Nadal ręczne:**
- Klucz SSH do VM2 (`vault_jenkins_ssh_cd_key`) — dziś placeholder, nie
  prawdziwy klucz (Etap 6, patrz [Co jeszcze nie działa](#co-jeszcze-nie-działa))
- Jeśli zmieniasz coś w sekcji `jobs:`/`traits` w `jenkins.yml` na
  **już istniejącym** środowisku (nie świeżym `terraform apply`) — Job DSL
  nie odświeża listy `traits` na już istniejącym jobie. Usuń ręcznie job
  `fastapi-app-ci` w UI przed ponownym uruchomieniem playbooka/restartem
  kontenera, inaczej stara konfiguracja (np. brak "Discover branches")
  zostanie. Na świeżej instancji (job jeszcze nie istnieje) problem nie
  występuje — JCasC tworzy go poprawnie za pierwszym razem.

Szczegóły uzasadnienia (dlaczego GitHub Server wymaga akurat *Secret
text*, historia debugowania JCasC) — `etap-5-podsumowanie.md`,
`etap-6-podsumowanie.md`.

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
│   │   ├── deploy-app/         (specyficzna dla VM2: backend + PostgreSQL)
│   │   │   ├── defaults/, vars/main.yml (zaszyfrowany Vault)
│   │   │   └── templates/docker-compose.yml.j2
│   │   └── deploy-jenkins/     (specyficzna dla VM1: Jenkins w kontenerze)
│   │       ├── defaults/, vars/main.yml (zaszyfrowany Vault)
│   │       └── files/Dockerfile, jenkins.yml (JCasC), plugins.txt
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

- Rola Ansible `deploy-monitoring` (VM3) — Etap 7
- **SSH do VM2 w Jenkinsie** — credential istnieje (JCasC, `ssh_cd_key`),
  ale niesie tylko placeholder zamiast prawdziwego klucza prywatnego;
  decyzja czy reużyć istniejący klucz projektu, czy wygenerować dedykowany
  tylko do CD, jeszcze niepodjęta
- Obraz appki na VM2 nadal buduje się **lokalnie z klonowanego repo**
  (`build: ./src` w compose roli `deploy-app`) — nie pobiera jeszcze
  gotowego obrazu z Docker Huba, mimo że Jenkins (Etap 5) już go tam
  publikuje. Przełączenie `deploy-app` na `image: turbobee/...` + `docker
  compose pull` zamiast lokalnego builda to dopiero Etap 6 (CD)
- Warunkowy stage `deploy` w Jenkinsfile (`when { branch 'master' }`) +
  powiadomienia (webhook) — Etap 6
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
- Kontener Jenkinsa na VM1 ma zamontowany `/var/run/docker.sock` (potrzebne
  do budowania obrazów appki z poziomu pipeline'u w Etapie 5/6) — to
  świadomy kompromis bezpieczeństwa: kto ma dostęp do tego socketu, ma
  efektywnie uprawnienia roota na VM1 (Docker-outside-of-Docker, nie
  izolowany demon zagnieżdżony). Szczegóły uzasadnienia w
  `etap-4-podsumowanie.md`
- Obraz Jenkinsa (z doinstalowanym `docker-ce-cli`/`docker-compose-plugin`)
  buduje się **lokalnie na VM1** przy każdym `ansible-playbook`, analogicznie
  do appki na VM2 — koszt: kilka minut przy każdym `terraform destroy`→`apply`,
  bo nic nie jest publikowane na Docker Hub (świadoma decyzja, patrz
  `etap-4-podsumowanie.md`)
- Kontener Jenkinsa działa jako `root` (nie `USER jenkins`) — świadomy,
  zaakceptowany kompromis: przełączenie na non-root złamało zapis do
  istniejącego wolumenu `jenkins_home` (zapisywany po raz pierwszy jako
  root), naprawa wymagałaby jednorazowego przechownerowania wolumenu, co
  uznano za niewarte nakładu przy braku wymogu dodatkowego hardeningu w tym
  projekcie — patrz `etap-5-podsumowanie.md`
- Anonimowy odczyt UI Jenkinsa był domyślnie włączony
  (`FullControlOnceLoggedInAuthorizationStrategy` ma `allowAnonymousRead =
  true` domyślnie) mimo publicznego Elastic IP — zablokowany jawnym
  `allowAnonymousRead: false` w `jenkins.yml` (JCasC, Etap 6; wcześniej
  w Etapie 5 przez Groovy `init-admin.groovy`, od migracji do JCasC ten
  plik już nie istnieje)
- Wersje pluginów w `plugins.txt` **nie są przypięte** (same nazwy, bez
  `:wersja`) — `jenkins-plugin-cli` przy każdym budowaniu obrazu instaluje
  "najnowszą kompatybilną" wersję, nie zawsze tę samą co poprzednio.
  W praktyce uderzyło to przy pracy nad Etapem 6: nowsza wersja
  `github-branch-source` zmieniła wymagane pola konstruktora
  `GitHubSCMSource` (Job DSL) między dwoma kolejnymi przebudowami obrazu
  w tej samej sesji — build nie jest w pełni reprodukowalny w czasie
- Job DSL (sekcja `jobs:` w `jenkins.yml`) nie odświeża `traits`/
  `branchSources` na **już istniejącym** Multibranch jobie przy ponownym
  zastosowaniu JCasC — wymaga ręcznego usunięcia joba przed reapply.
  Nie występuje przy świeżym `terraform destroy`→`apply` (job jeszcze nie
  istnieje), tylko przy iteracji nad `jenkins.yml` na już działającym
  środowisku — patrz [Konfiguracja Jenkinsa po każdym pełnym recreate](#konfiguracja-jenkinsa-po-każdym-pełnym-recreate)
- Status commitów na GitHubie nie aktualizuje się (`403 Resource not
  accessible by personal access token`) — GitHub PAT używany przez Jenkinsa
  nie ma scope'u `Commit statuses`/`Checks`; kosmetyczne, nie blokuje
  pipeline'u, nienaprawione
- Żaden stage w `Jenkinsfile` nie ma `timeout()` — jednorazowy "zombie"
  build (proces `sh` zawieszony po wymuszonym restarcie VM w trakcie
  działania) wymagał ręcznego Abort/Hard kill; zabezpieczenie zaprojektowane,
  niewdrożone — `etap-5-podsumowanie.md`
