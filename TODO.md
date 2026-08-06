# TODO / do przemyślenia — backlog drobnych usprawnień

> Rzeczy zauważone w trakcie pracy, nie na tyle pilne żeby blokować bieżący
> etap, ale warte zapamiętania. Nieformalny brudnopis — nie mylić z
> `DevOpsProj.md` / `Wymagania Projektu Dyplomowego.md` (te wygrywają, jeśli
> jest sprzeczność).

## Infrastruktura / VM1 (`ci`)

- **Sprzątanie Docker build cache** — `docker compose down -v --rmi local`
  czyści tylko finalny obraz i wolumeny danego projektu testowego, **nie**
  build cache (warstwy `poetry install` itp.). Zaimplementowane: cron
  (`ansible.builtin.cron` w roli `deploy-jenkins`, `docker system prune -af`
  codziennie) — dodany w `tasks/main.yml`, jeszcze niecommitowany/niepotwierdzony
  na żywym VM (sprawdzić drugi przebieg playbooka i `crontab -l`).

## Monitoring (VM3)

- Dashboard `devops-overview.json` nie ma panelu latencji — appka wystawia
  histogram `http_request_duration_seconds`, nieużywany. Naturalne
  rozszerzenie, gdy będzie czas.

## Reverse proxy przed appką (VM2) — na potem, razem z SSL

- `/metrics` jest publicznie dostępny (ten sam port 8000 co reszta API,
  Security Group filtruje tylko po IP+port, nie po ścieżce). Docelowe
  rozwiązanie: nginx jako reverse proxy przed appką w `deploy-app`
  (`location /metrics { allow <private_ip monitoringu>; deny all; }`),
  appka przestaje publikować port na hosta, tylko nginx. Świadomie
  odłożone — zrobić razem z SSL/domeną (nginx i tak potrzebny do
  terminacji TLS, sensowniej ogarnąć oba na raz niż budować proxy dwa
  razy).
  **Uwaga:** `DevOpsProj.md` sekcja 4 ma obecnie "SSL / domena" w kolumnie
  **Poza zakresem**, nie backlog — jeśli to się faktycznie zacznie robić,
  wymaga jawnej aktualizacji tabeli zakresu (i wpisu w `prompting-guide.md`,
  Log zmian założeń) przed implementacją, nie tylko dopisania tutaj.

## Drobne

- Workspace joba (`/var/jenkins_home/jobs/.../workspace`) nie jest
  czyszczony automatycznie między buildami — rozważyć `cleanWs()` w
  `post { always }`, jeśli miejsce znowu zacznie być problemem po resize.
