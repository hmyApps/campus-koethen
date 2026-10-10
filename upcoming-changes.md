# Anstehende Backend-Änderungen

Stand: 11. Oktober 2026 · App-Version 2.0.1+11 · Repository `hmyApps/campus-koethen` (`main`)

Die App 2.0.1 ist **ohne** dieses Backend-Update voll nutzbar: Der API-Vertrag ist unverändert
(OpenAPI ohne Abweichung). Auch die ältere App 2.0.0 läuft mit dem neuen Backend. Das Update ist
trotzdem zeitnah nötig, weil die folgenden Datenschutz-, Sicherheits- und Datenkorrekturen erst mit
dem Deployment live sind.

## 1. Was sich auf Backend, CMS und Edge ändert

| Bereich                | Änderung                                                                                                                                                                                                                    |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Öffentliche Kalender   | Abgeschaltete Beschreibungen/Orte verschwinden sofort (bisher blieben sie öffentlich). Erholung nach 404, Kalender-ID-Wechsel, Serien am Fensterende, Zeitumstellung, UID-fremde Ausnahmen, Nutzertest-Kalender korrigiert. |
| Aufbewahrung           | Vergangene Kalendertermine werden ein Jahr nach ihrem Ende automatisch gelöscht (beim ersten Lauf ggf. viele auf einmal).                                                                                                   |
| Beiträge               | Beiträge mit Embargo (`validFrom`) oder nach `validUntil` sowie aus inaktiven Kanälen sind nicht mehr abrufbar.                                                                                                             |
| Kontakte               | Englische Personenlisten stimmen mit der deutschen Liste überein.                                                                                                                                                           |
| Medien                 | Fehlerantworten tragen `Cache-Control: no-store`; die Edge cacht Fehler nicht mehr bis zu 24 h.                                                                                                                             |
| Stundenplan            | Klassen, die eine Stunde verlassen, verlieren sie; eine WebUntis-Fehlerantwort löscht keinen Plan mehr; neue Spalte `groupsUnconfirmed` für das Monitoring.                                                                 |
| „Heute“                | Standardzeiträume von Mensa, Stundenplan, Beiträgen und Kalendern beginnen am Berliner Kalendertag (bisher zwischen 0 und 2 Uhr am Vortag).                                                                                 |
| Strapi-Anbindung, Logs | Nur noch vorübergehende Fehler werden wiederholt; in Produktion landen keine Fehlertexte oder Stacktraces mehr im Log.                                                                                                      |
| Sicherheit             | `proxy-addr` 2.0.8 (kritisch) und `compression` 1.8.2 im Backend, `sharp` 0.35.5 im CMS.                                                                                                                                    |

## 2. Datenbank

Zwei neue, rein additive Migrationen. Ein älteres Image läuft auch mit dem neuen Schema, ein neues
Image braucht die Migrationen. Deshalb: **erst migrieren, dann API und Worker starten.**

- `20261009120000_add_public_calendar_source_and_expansion`: `public_calendars.source` (Standard
  `strapi`) und `lastExpandedTo`; markiert vorhandene Nutzertest-Kalender.
- `20261011120000_add_timetable_sync_run_unconfirmed_groups`: `timetable_sync_runs.groupsUnconfirmed`
  (Standard `0`).

Beide sind gegen PostgreSQL 16 getestet. Es gibt **keine neuen Environment-Variablen**.

## 3. Woher die Images kommen

Der VPS zieht `ghcr.io/leviora-studio/campus-koethen/{backend,cms}`. Diese Images baut ausschließlich
die CI des Originalprojekts. Die Änderungen dieses Forks sind dort noch nicht enthalten. Zwei Wege:

- **A (empfohlen): über das Originalprojekt.** Pull Request von `hmyApps/campus-koethen` nach
  `Leviora-Studio/campus-koethen`. Nach dem Merge baut, scannt und veröffentlicht die dortige CI die
  Images mit einem unveränderlichen Tag `sha-<commit>`.
- **B: eigene Images aus dem Fork.** Auf einem Rechner mit Docker im Repository-Root:

  ```bash
  TAG=sha-$(git rev-parse HEAD)
  docker build --platform linux/amd64 -f apps/backend/Dockerfile -t <registry>/campus-koethen/backend:$TAG .
  docker build --platform linux/amd64 -f apps/cms/Dockerfile -t <registry>/campus-koethen/cms:$TAG .
  docker push <registry>/campus-koethen/backend:$TAG
  docker push <registry>/campus-koethen/cms:$TAG
  ```

  Auf dem VPS in der `.env` zusätzlich `BACKEND_IMAGE_REPOSITORY=<registry>/campus-koethen/backend`
  und `CMS_IMAGE_REPOSITORY=<registry>/campus-koethen/cms` setzen. Die Images vorher mit Trivy prüfen,
  so wie es die CI des Originalprojekts tut.

## 4. Kurzanleitung auf dem VPS

Im Verzeichnis mit `compose.yaml` und `.env` (siehe `infrastructure/vps/README.md`):

1. **Backup** beider Datenbanken und der Strapi-Uploads anlegen.
2. In der `.env` `CAMPUS_IMAGE_TAG=sha-<commit>` setzen (bei Weg B auch die beiden `*_IMAGE_REPOSITORY`).
3. Aktualisieren:

   ```bash
   docker compose config --quiet
   docker compose pull cms api worker migrate
   docker compose stop api worker
   docker compose --profile migrate run --rm migrate
   docker compose up -d cms
   # warten, bis das CMS healthy ist (der Raumkatalog ist unverändert, rooms-sync ist nicht nötig)
   docker compose up -d api worker
   docker compose ps --all
   ```

4. **Edge (nginx)**: Die API-VHost-Datei hat `proxy_ignore_headers Cache-Control Expires;` für
   `/v1/media/` erhalten. Aus `infrastructure/vps/edge/`:

   ```bash
   sudo install -o root -g root -m 0644 campus-koethen-api.sturahsa.de.conf \
     /etc/nginx/conf.d/campus-koethen-api.sturahsa.de.conf
   sudo nginx -t && sudo systemctl reload nginx
   # optional: bereits gecachte Fehlerantworten verwerfen
   sudo find /var/cache/nginx/campus-media -type f -delete
   ```

## 5. Nach dem Update prüfen

```bash
API=https://campus-koethen-api.sturahsa.de
curl -fsS $API/health/ready
curl -sI "$API/v1/media/uploads/gibt-es-nicht.png" | grep -i cache-control   # erwartet: no-store
curl -fsS $API/v1/timetable/status                                        # dataStale: false nach dem nächsten Lauf
curl -fsS "$API/v1/calendars?locale=de" | grep -o '"from":"[0-9-]*"'       # heutiger Berliner Tag
```

- Worker-Log: beim ersten Event-Lauf ggf. `Public-calendar retention: removed …`.
- Monitoring auf dauerhaft unbestätigte Stundenplan-Klassen:

  ```sql
  SELECT "startedAt", "groupsRequested", "groupsUnconfirmed"
  FROM timetable_sync_runs
  WHERE kind = 'entries'
  ORDER BY "startedAt" DESC
  LIMIT 10;
  ```

## 6. Rückweg

`CAMPUS_IMAGE_TAG` auf den vorherigen `sha-`-Tag zurücksetzen und `docker compose up -d cms api worker`
ausführen. Die Migrationen bleiben bestehen; sie sind additiv, der ältere Code ignoriert die neuen
Spalten. Die nginx-Änderung kann bleiben.

## 7. Danach live zu prüfen

- Strapi: Filter der Beitrags-Detailroute auf aktive Kanäle und `documentId` in befüllten
  Kontakt-Relationen (bisher nur gegen Fakes getestet).
- Google-Kalender: ETag-Verhalten bei der Neu-Expansion von Serien und nach einer Wiederfreigabe.
- nginx: Laufzeitverhalten des Medien-Caches (Syntax ist geprüft).

Unabhängige, inoffizielle App — keine offizielle Anwendung der Hochschule Anhalt.
