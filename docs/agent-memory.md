# Agenten-Gedächtnis: Campus Köthen

Arbeitsnotizen für KI-gestützte Sessions, damit eine spätere Session nahtlos fortsetzen kann
(„continue“ → an der letzten offenen Stelle weitermachen). Verbindliche Regeln stehen
ausschließlich in `AGENTS.md`; diese Datei ergänzt sie nur um Fortschritt und To-dos.

## Projekt-Eckdaten

- Monorepo: `apps/backend` (NestJS, Prisma, Node 24), `apps/cms` (Strapi 5), `apps/mobile` (Flutter, Riverpod, go_router, dio, hive_ce), `packages/campus-map`, `packages/openapi`.
- Aktuelle App-Version: `2.0.3+13` (`apps/mobile/pubspec.yaml`). Vor jedem Release-Build Versionsnummer erhöhen.
- Smoke-Check je Änderung: Release-Build (Flutter) bzw. die Gates aus `README.md`.
- In Cloud-Sessions ist Flutter/Dart nicht installiert; Backend-Gates laufen nach `pnpm install --frozen-lockfile`.

## Verlauf

| Datum      | Arbeit                                                                                                                                            | Ergebnis                                                                                                              |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| 2026-10-07 | Rekursiver Mehragenten-Bughunt (4 Runden, 19 Agenten, nur Analyse)                                                                                | `docs/bughunt-audit-2026-10-07.md`: 94 validierte Bugs (9 hoch, 40 mittel, 45 niedrig)                                |
| 2026-10-10 | Mehragenten-Bugfix-Lauf (12 Arbeitspakete, je ein Worktree, TDD)                                                                                  | Branch `fix/bughunt-2026-10-07`: 85 von 94 Funden behoben, 9 offen als Maintainer-Entscheidung                        |
| 2026-10-11 | Doku-Drift aufgelöst, Folgefixes und Maintainer-Entscheidungen                                                                                    | Alle 94 Funde erledigt; Sicherheits-Patches, Folgefixes und G-08 umgesetzt (siehe unten)                              |
| 2026-10-11 | Zweiter Bughunt (`bughunt-audit-2026-10-10.md`) und Fix-Sprint aus einer anderen Session, validiert und nach `main` übernommen                    | 8 Fix-Branches über `claude/confident-meitner-m82y60`; siehe „Validierung 2026-10-11 (zweiter Sprint)“                |
| 2026-10-14 | Release 2.0.3 auf Basis von 2.0.2: NFC-Launch-Absturz (Android), beendete Events im Feed und in der Eventübersicht, „ältere anzeigen“, Sortierung | `main` und `feat/matrix` vorher gesichert (`backup/*-2026-10-14`), danach auf 2.0.3 gesetzt; siehe „Stand 2026-10-14“ |

## Stand nach dem Bugfix-Lauf (2026-10-10)

Behoben (alle mit vorher real rotem Test): alle 9 „hoch“, alle 40 „mittel“, 36 von 45 „niedrig“.
Zusätzlich behoben, nicht im Audit: `ical.js` verknüpfte Overrides UID-übergreifend (doppelter
`occurrenceKey`, Feed-Sync-Abbruch); `meta.truncated` im Kalender-Abgleich gemerkter Events;
48-dp-Ziel des Sterns in `meal_card.dart`; Race beim parallelen Schreiben von Antragsvorgängen.

Gates auf dem Endstand, CI-Jobs lokal nachgebildet (sauberer Worktree, gepinntes Node 24.21.0,
Flutter 3.44.7, Wegwerf-Container `postgres:16-alpine` mit `campus_app_test_<run-id>`):

- Backend: `prisma migrate deploy` (13 Migrationen, Schema aktuell), Unit- **und** Integrationstests
  58/58 Suites, 811/811; `lint`, `typecheck`, `build`, OpenAPI ohne Drift.
- CMS: `typecheck`, `test`, `build`, Slug-Schema-Prüfung grün. Karte: `test`, `validate`, `check` grün.
- Mobile: `gen-l10n`, `validate_release_api`, `dart format .`, `analyze --fatal-infos --fatal-warnings`,
  `flutter test` (TZ=Europe/Berlin) 3087/3087, Hardcoded-Text-Grep, Dart-Dependency-Audit grün.
- Repo: `pnpm format:check` grün (7 Docs, die schon auf `main` rot waren, formatiert), Gitleaks 8.30.1
  über die gesamte Historie ohne Fund, `image_url`-Guard grün, nginx `-t` für beide API-Edge-Confs ok.
- **Rot, aber nicht durch diesen Branch:** `pnpm audit --audit-level high` (identisch auf `main`, keine
  Abhängigkeit geändert): `proxy-addr` 2.0.7 → ≥2.0.8 und `compression` 1.8.1 → ≥1.8.2 (Backend-Laufzeit),
  `handlebars` 4.7.9 → ≥4.7.10, `sharp` 0.35.4 → ≥0.35.5 (CMS).

## Stand 2026-10-11

Umgesetzt (jeweils TDD, vorher real roter Test):

- Sicherheits-Patches: `proxy-addr` 2.0.8, `compression` 1.8.2, `handlebars` 4.7.10, `sharp` 0.35.5 —
  `pnpm audit --audit-level high` grün (nur die dokumentierte `brace-expansion`-Ausnahme).
- Mail: periodischer Sync und Live-Verbindung teilen die Sperre nach abgelehntem Passwort (Rest von C-01).
- Hochschulzugang: Ein Kontowechsel verbindet nur den prüfenden Dienst; alle anderen (HSA-GPT über seinen
  Zustimmungsbildschirm) erst nach `+`. Reine Passwortänderung erhält die Verknüpfungen.
- Noten: HISinOne ist Standard; Konten ohne Portalwahl wechseln einmalig (Cache wird dabei verworfen).
- About: Quellcode-Links auf Originalprojekt und Fork (G-08, Release-Gate geschlossen).
- Backend: Aufbewahrung vergangener Termine öffentlicher Kalender ein Jahr; „heute“ nach Berliner Tag
  auch in Posts, Kalendern und Mensa-Sync; `timetable_sync_runs.groupsUnconfirmed` (Migration
  `20261011120000_…`).
- Events: vor VF-N01 gemerkte Ganztags-Posts werden beim Lesen auf ihren Tag korrigiert.
- Tests: Mail-Tests mit fester Uhr (verifiziert mit Standarduhr 2030).

Gates (sauberer Worktree, Node 24.21.0, Wegwerf-`postgres:16-alpine`): Migrationen 14/14, Backend inkl.
Integration 59/59 Suites, 820/820; Lint, Typecheck, Build, OpenAPI ohne Drift; CMS und Karte grün;
`format:check` und `pnpm audit` grün; Flutter `dart format .`, `analyze`, `test` 3099/3099, Release-API,
Hardcoded-Text-Grep, Dart-Audit grün; Gitleaks (200 Commits) ohne Fund.

## Validierung 2026-10-11 (zweiter Sprint)

Integrationsstand `5db9dc7` (alle 8 `claude/fix-*`-Branches enthalten), vor dem Merge geprüft:

- CI nachgebildet: Migrationen 14/14, Backend inkl. Integration 60/60 Suites, 854/854; Lint, Typecheck,
  Build, OpenAPI ohne Drift; CMS, Karte, `format:check`, `pnpm audit`, Schema-Skript grün; Flutter
  3206/3206 inkl. `format`, `analyze`, Release-API, Text-Grep, Dart-Audit; Gitleaks ohne Fund.
- Regeländerung `AGENTS.md`: HAWKI `GET /profile` nur zwischen Login und Logout als CSRF-Quelle — Code
  entspricht dem.
- Images lokal gebaut und mit Trivy wie `images.yml` gescannt: Backend sauber (die gelöschten
  `.trivyignore`-Einträge sind wirklich aufgelöst). CMS: `perl-base` aus `node:24.21.0-slim` (3 kritisch,
  4 hoch, behoben in `deb12u4`) — schon vorher vorhanden, blockiert die CMS-Veröffentlichung in der CI.
- VPS-`compose.yaml` mit diesen Images gestartet: DB-Init mit `REVOKE CONNECT` ok (Rollen gegenseitig
  ausgesperrt), Migration aus root-eigenem Image ok, API/Worker/CMS healthy, Code nicht beschreibbar,
  nur `public/uploads` und `.tmp` beschreibbar, `rooms-sync --dry-run` ohne EACCES, Medien-404 mit `no-store`.

Erledigt daraus: `perl-base` wird in der CMS-Runtime-Stufe per `--only-upgrade` auf `deb12u4`
gehoben; Trivy auf dem neu gebauten CMS-Image ohne Funde.

Windows-Hinweis: Flutter-Gates scheitern in sehr langen Pfaden an MAX_PATH (`ios/Flutter/ephemeral`);
lokal Repo-Pfad kurz halten oder per `subst` mappen. Lokale Arbeitskopie hat teils CRLF
(`core.autocrlf=true`), Index ist LF — `format:check` im Arbeitsverzeichnis kann deshalb fälschlich rot sein.

## Stand 2026-10-14

Ausgangspunkt war Tag `2.0.2` (`a2dd81b`), identisch mit `main`. `feat/matrix` trug 9 Commits darüber
(Matrix-Chat in Arbeit). Beide wurden vor dem Überschreiben gesichert: `backup/main-2026-10-14`,
`backup/feat-matrix-2026-10-14`. Überschrieben wurde ohne Force-Push, per Commit, dessen Inhalt dem
Release-Stand entspricht; die Matrix-Arbeit lässt sich aus dem Backup-Branch zurückholen.

- Android-NFC: Der getypte `getParcelableExtra(name, Class)` wurde schon ab API 33 genutzt und kann dort
  beim Entpacken werfen (b/232589966); ein NFC-Launch-Intent beendete damit die App. Jetzt erst ab
  API 34, sonst der alte Aufruf, beides fehlertolerant. NFC-I/O nach `onDestroy` endet mit Fehler statt
  `RejectedExecutionException`. Nicht auf einem Gerät reproduziert — auf Android 13 gezielt testen.
- News-Feed und Kanalseiten blenden beendete Event-Beiträge aus (gleiche Regel wie die Eventübersicht),
  „Ältere Events anzeigen“, Sortierung „Neueste zuerst“/„Chronologisch“ im Filter.
- Eventübersicht: „Ältere anzeigen“ lädt die letzten 180 Tage (immer `from` und `to`), eigener Abschnitt
  „Vergangene Events“, Sortierung „Chronologisch“/„Neueste zuerst“ im Quellenfilter.

## Offene To-dos (Priorität absteigend)

- [x] 2026-10-11 Doku-Drift aufgelöst, Doku/AGENTS folgen dem Code: A-07 (Mensa-IDs als dokumentierte Ausnahme),
      A-08 (lokaler `STRAPI_BASE_URL`-Default), VA-N02 (`to` = from+14), B-11 (manueller `images.yml`-Start im
      README beschrieben), D-10 (`POST /api/ai-req`), D-11 (E2EE-Modul nicht angebunden), E-13 (Moodle stündlich
      im Vordergrund), G-07 (Store-Kennungen). PROD-Domains in AGENTS §10 und `mvp.md` als geklärt eingetragen.
- [x] 2026-10-11 Sicherheits-Patches, Folgefixes, G-08 und Maintainer-Entscheidungen umgesetzt (siehe „Stand
      2026-10-11“). Bestätigt: B-10 `.invalid`-Kalender bleiben aktiv; D-06 jetzt mit HISinOne als Standard.
- [ ] Optional: HIS-QIS ganz entfernen, falls HISinOne alle Konten abdeckt (heute nur noch über „Prüfungsportal
      wechseln“ erreichbar).
- [ ] Live/real zu verifizieren: F-06 (EWS-Ganztag), C-02 (Teilabruf ohne Anhänge, echtes Postfach), D-08 (Overlay-IDs
      HISinOne), E-12 (Moodle-`wsaccessuser*`-Codes), F-08 (Gerätematrix #20), B-05/B-08 (Strapi `channels.isActive`,
      `documentId` in Relationen), B-06 (nginx-Laufzeitverhalten auf dem VPS; Syntax geprüft), B-02/VB-N02
      (Google-ETag-Verhalten).
- [ ] Deployment (manuell, kein Auto-Deploy): Standard-Update laut `infrastructure/vps/README.md`
      (`--profile migrate run --rm migrate` vor `up -d api worker`) deckt die rein additiven Migrationen
      `20261009120000_…` und `20261011120000_…` ab; geänderte Edge-Confs (`proxy_ignore_headers`) separat auf dem
      VPS einspielen, `nginx -t`, reload.
- [ ] Release: signierte Android-Version braucht den Release-Keystore (`CAMPUS_ANDROID_KEYSTORE_*`); iOS nur
      unter macOS. HSA-GPT bleibt deaktiviert, bis HSA HAWKI aktualisiert.
