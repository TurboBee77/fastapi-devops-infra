# TODO / do przemyślenia — backlog drobnych usprawnień

> Rzeczy zauważone w trakcie pracy, nie na tyle pilne żeby blokować bieżący
> etap, ale warte zapamiętania. Nieformalny brudnopis — nie mylić z
> `DevOpsProj.md` / `Wymagania Projektu Dyplomowego.md` (te wygrywają, jeśli
> jest sprzeczność).

## Infrastruktura / VM1 (`ci`)

- **Sprzątanie Docker build cache** — `docker compose down -v --rmi local`
  czyści tylko finalny obraz i wolumeny danego projektu testowego, **nie**
  build cache (warstwy `poetry install` itp.). Ten cache rośnie z każdym
  pipeline'em appki i nic go automatycznie nie czyści — to główny winowajca
  powtarzających się `no space left on device`, obok samego rozmiaru dysku.
  Propozycja: cron raz dziennie (`ansible.builtin.cron` w roli
  `deploy-jenkins`, `docker system prune -af`) — zachowuje cache w ciągu
  dnia (buildy nadal szybkie), czyści bez ręcznej interwencji. **Nie** robić
  tego jako `post { always }` w Jenkinsfile — zabijałoby cache po każdym
  pojedynczym buildzie, nie tylko starym.
- Root EBS `ci` był za mały (6.8GB) — stąd powtarzające się `no space left
  on device` przy budowaniu obrazu testowego appki. Resize
  (`root_block_device.volume_size` w module Terraform) + rebuild w toku.

## GitHub webhooks (repo appki)

- Repo ma nagromadzone **stare webhooki** (Settings → Webhooks) — z
  poprzednich Elastic IP `ci` sprzed pełnego `destroy`→`apply`, ze statusem
  "failed to connect to host". `manageHooks: true` w JCasC tworzy nowy
  webhook przy starcie kontenera, jeśli URL się zmienił, ale **nie usuwa**
  starych — do ręcznego sprzątania w UI, albo do adresowania później w
  JCasC/Job DSL.
- Po rebuildzie Jenkinsa (z poprawką `JENKINS_PUBLIC_URL`) zweryfikować w
  "Recent Deliveries", czy webhook faktycznie łapie **push**, a nie tylko
  ping przy tworzeniu.

## Branch `feature/ci-pipeline` (repo appki)

- Ma **stary Jenkinsfile**, sprzed dodania stage `Deploy` i `post` notify —
  build na tym branchu nigdy nie wyśle powiadomienia na Discord ani nie
  zdeployuje, niezależnie od wyniku. Zmergować/zrebase'ować z `master`, albo
  usunąć branch, jeśli nieużywany.

## Monitoring (VM3)

- `fastapi-app` job w `prometheus.yml.j2` scrape'uje po `ansible_host`
  (publiczny IP) — działa, ale niespójne z node_exporterami, które
  przełączone na `private_ip`. Kosmetyka, do wyrównania przy okazji.
- Dashboard `devops-overview.json` nie ma panelu latencji — appka wystawia
  histogram `http_request_duration_seconds`, nieużywany. Naturalne
  rozszerzenie, gdy będzie czas.

## Drobne

- Workspace joba (`/var/jenkins_home/jobs/.../workspace`) nie jest
  czyszczony automatycznie między buildami — rozważyć `cleanWs()` w
  `post { always }`, jeśli miejsce znowu zacznie być problemem po resize.
