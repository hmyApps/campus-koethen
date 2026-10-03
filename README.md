# Campus Köthen App

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)

Monorepo für die **Campus Köthen** App — News, Kalender, Mensapläne, Kontakte sowie direkt
angebundene persönliche Dienste (Studenten-E-Mail, Notenspiegel, Moodle) für den Campus Köthen.

---

## ⚠️ Unabhängigkeitshinweis / Independence notice

> **Deutsch**
>
> Campus Köthen ist keine offizielle App der Hochschule Anhalt. Die App wird unabhängig von Erik Engler, handelnd unter „Leviora Studio“, entwickelt und über die App Stores bereitgestellt. Das Campus-Backend und die redaktionellen Inhalte werden von der rechtlich selbstständigen Studierendenschaft der Hochschule Anhalt betrieben. Die Hochschule Anhalt selbst ist weder Entwicklerin noch Betreiberin der App.

> **English**
>
> Campus Köthen is not an official Hochschule Anhalt app. The app is independently developed and distributed through app stores by Erik Engler, trading as “Leviora Studio”. The Campus backend and editorial content are operated by the legally independent student body of Hochschule Anhalt. Hochschule Anhalt itself neither develops nor operates the app.

Dieses Projekt verwendet **keine** Logos, Wappen, Markenassets oder Designsysteme der Hochschule Anhalt.

---

## Status

**MVP in Entwicklung.** Es gibt noch kein öffentliches Deployment.

## Umfang des MVP

| Enthalten                                                                                                                                                    | Nicht enthalten                                 |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------- |
| News als endloser Inline-Feed, Kanäle frei wählbar                                                                                                           | Nutzerkonten für die App selbst                 |
| Quellenübergreifender Kalender (Tag/Woche/Liste)                                                                                                             | Push-Nachrichten von einem Server               |
| Gruppenstundenplan (WebUntis, serverseitig schaltbar)                                                                                                        | Persönlicher WebUntis-Login                     |
| Öffentliche Google-Kalender (öffentlicher ICS-Feed)                                                                                                          | Nicht freigegebene reale Gebäudepläne           |
| Mensapläne und lokaler NFC-Guthabencheck (Android/iOS)                                                                                                       | Analytics, Tracking, Crash-Reporting            |
| Kontakte und Kontaktbereiche                                                                                                                                 | Redis, SMTP                                     |
| Studenten-E-Mail (IMAP/SMTP, direkt vom Gerät)                                                                                                               | Automatisches Deployment                        |
| Notenspiegel HIS-QIS **und** HISinOne, auf HISinOne zusätzlich nur lesend: Bescheinigungen, Personen-/Kontaktdaten, Studiengangsübersicht (direkt vom Gerät) | Globale Volltextsuche                           |
| Moodle: Kurse, Materialien, Aufgaben, Ankündigungen                                                                                                          | Schreibzugriffe auf Moodle                      |
| Optionaler zentraler Hochschulzugang, nur lokal                                                                                                              | Gemeinsame SSO-Sitzung oder App-Konto           |
| Lokale Aufgabenliste (rein auf dem Gerät)                                                                                                                    | Serverseitige Synchronisierung der Aufgaben     |
| Anträge & Feedback (direkt an das Gremiensystem)                                                                                                             | Serverseitige Ablage von Anträgen               |
| Lageplan: Demo- und schematische Pläne, Raumsuche                                                                                                            | Indoor-Navigation, Wegberechnung, Live-Position |
| Räume mit Kontaktbezug und Deep-Link in den Plan                                                                                                             | Raumbelegung und Buchung                        |
| Lokale Einstellungen (Sprache, Theme, Abos)                                                                                                                  | Mehrere Mail- oder Moodle-Konten                |
| Lokale Erinnerungen, rein auf dem Gerät geplant                                                                                                              |                                                 |
| Offline-/Cache-Verhalten                                                                                                                                     |                                                 |
| About, vollständiges Impressum und Datenschutz                                                                                                               |                                                 |
| Deutsch und Englisch                                                                                                                                         |                                                 |

Details: [docs/product/mvp.md](docs/product/mvp.md)

## Architektur

Die App hat **zwei streng getrennte Datenpfade**. Welcher Pfad gilt, entscheidet allein die
Sensibilität der Daten — nicht die Bequemlichkeit.

**Pfad 1 — öffentliche und redaktionelle Daten: immer über das Backend**

```text
Redaktion ──► Strapi 5 (CMS) ──► campus_cms_* (PostgreSQL 16)
                   │
                   │ REST, serverseitiges Read-only-Token
                   ▼
Flutter ──/v1──► Campus API (NestJS) ──► campus_app_* (PostgreSQL 16)
                                              ▲
                   Campus Worker ─────────────┘
                        │
                        ├──► meine-mensa.de (alle 2 Stunden)
                        ├──► WebUntis, öffentliche Ansicht (WEBUNTIS_ENABLED)
                        └──► calendar.google.com, öffentlicher ICS-Feed
                             (PUBLIC_CALENDAR_ENABLED)
```

**Pfad 2 — persönliche oder besonders sensible Dienste: direkt vom Gerät, bewusst am Backend vorbei**

```text
                 ┌──► mail.hs-anhalt.de           IMAPS 993 / SMTP 587 + STARTTLS
                 ├──► service.ssc.hs-anhalt.de    HIS-QIS-Notenspiegel (Bestandsportal)
Flutter ─────────┼──► sscportal.ssc.hs-anhalt.de  HISinOne-Notenspiegel (neueres Portal)
                 │    └► untrust-sscportal.ssc.hs-anhalt.de
                 │       einmaliger Bescheinigungs-GET (`/qisserver/rds?state=docdownload`)
                 ├──► moodle.hs-anhalt.de         Moodle-Webservice (nur lesend)
                 └──► REQUESTS_BASE_URL           Anträge und Feedback (HTTPS)
```

Ein Konto spricht **immer nur eines** der beiden Notenportale — welches, wird einmalig bei der
Einrichtung ermittelt (`docs/grades.md`).

Damit erhalten weder Campus API, Strapi noch Worker jemals Zugangsdaten oder persönliche Inhalte.
Zugangsdaten liegen ausschließlich im Keychain/Keystore, zwischengespeicherte Inhalte nur
verschlüsselt auf dem Gerät. Dies sind **genau vier** ausdrücklich beschlossene Ausnahmen — keine
allgemeine Erlaubnis für beliebige Direktzugriffe (siehe [AGENTS.md](AGENTS.md) §2).

Der optionale zentrale Hochschulzugang speichert genau eine Kennung (Benutzername oder vollständige
Mailadresse) und ein Passwort erst nach ausdrücklicher Bestätigung und erfolgreicher Prüfung eines
der Dienste ausschließlich im gerätegebundenen Keychain/Keystore. Er ist eine lokale Eingabehilfe,
**kein** Projektkonto und keine
gemeinsame SSO-Sitzung: `+` verbindet Mail, Moodle oder Noten jeweils separat; `−` löscht nur die
gewählte Dienstverbindung. Für Mail wird ein reiner Benutzername lokal um `@hs-anhalt.de` ergänzt;
eine vollständige Mailadresse sowie die Kennung für Moodle und Noten bleiben unverändert. Ein
vorhandenes altes Drei-Feld-Schema wird beim Upgrade vollständig verworfen. Die Komplettlöschung
trennt alle Dienste und entfernt die zentrale
Identität zuletzt. Bei einem Teilfehler bleibt sie für einen sichtbaren Retry erhalten.

Der verschlüsselte Mailcache umfasst Kopfzeilen, Inhalte, den Adressindex und optional
Anhangbytes; sein gerätegebundener Schlüssel liegt im Keychain/Keystore. Ein vorhandener
unverschlüsselter Testcache wird beim Upgrade entfernt und nicht inhaltlich migriert. Nach
erfolgreichem „E-Mail-Verbindung und lokale Daten löschen“ sind die dienstbezogenen Credentials,
alter und neuer Cache, Cache-Schlüssel und
Mail-State logisch entfernt; die Servermails bleiben unverändert. Dies ist keine Zusage eines
forensischen Secure Erase von Flash-Zellen oder Backups.

Harte Systemgrenzen:

- Flutter spricht für alle öffentlichen und redaktionellen Daten **ausschließlich** mit der versionierten Campus API unter `/v1` — niemals direkt mit Strapi, meine-mensa.de, WebUntis oder dem Google-ICS-Feed.
- Das Backend liest Strapi **ausschließlich** über dessen REST-API mit einem serverseitigen Read-only-Token — niemals direkt aus Strapi-Tabellen.
- Für Mail, Noten, Moodle sowie Anträge und Feedback gibt es **keinen** Backend-Proxy, **keine** serverseitige Speicherung und **keinen** Analytics-/Logging-Umweg. Das gilt auch für den optionalen zentralen Hochschulzugang.
- Der Kalender führt Stundenplan, öffentliche Kalender und Moodle-Deadlines **ausschließlich lokal auf dem Gerät** zusammen.
- CMS und operative Daten nutzen **getrennte Datenbanken und Rollen**.
- Umgebungsunterschiede entstehen ausschließlich durch Environment/Secrets, nicht durch Quellcode.

Details: [docs/architecture.md](docs/architecture.md)

## Repository-Struktur

```text
apps/
  cms/                         Strapi 5 Community (TypeScript)
  backend/                     NestJS Campus API + Prisma + Worker
  mobile/                      Flutter (iOS/Android)
packages/
  openapi/                     Veröffentlichter API-Vertrag (OpenAPI 3.1)
  campus-map/                  Kanonischer Kartenkatalog, Validator, Asset-Generator
infrastructure/
  local/                       Lokaler Compose-Stack
  myaioffice-dev/              Dokumentierter DEV-Deployment-Vertrag (kein Deployment)
  vps/                         Manueller VPS-Betrieb und Edge-Konfiguration
docs/                          Produkt-, Architektur- und Betriebsdokumentation
.github/workflows/             CI, GHCR-Images und Uptime-Check
```

## Dokumentation

| Dokument                                                          | Inhalt                                                     |
| ----------------------------------------------------------------- | ---------------------------------------------------------- |
| [product/mvp.md](docs/product/mvp.md)                             | Umfang, fachliche Anforderungen, Akzeptanzkriterien        |
| [architecture.md](docs/architecture.md)                           | Komponenten, Systemgrenzen, Datenhaltung, Betrieb          |
| [api.md](docs/api.md)                                             | Verbindlicher Vertrag der Campus API                       |
| [data-sources.md](docs/data-sources.md)                           | Alle Fremdquellen mit verifizierten Eigenheiten            |
| [public-calendars.md](docs/public-calendars.md)                   | Öffentliche Google-Kalender über den öffentlichen ICS-Feed |
| [student-mail.md](docs/student-mail.md)                           | Studenten-E-Mail-Client (IMAP/SMTP, direkt vom Gerät)      |
| [grades.md](docs/grades.md)                                       | Notenspiegel HIS-QIS **und** HISinOne (direkt vom Gerät)   |
| [moodle.md](docs/moodle.md)                                       | Moodle-Integration und quellenübergreifender Kalender      |
| [requests.md](docs/requests.md)                                   | Anträge und Feedback ans Gremiensystem (direkt vom Gerät)  |
| [local-development.md](docs/local-development.md)                 | Lokaler Stack, Schritt für Schritt                         |
| [content-editor-guide.md](docs/content-editor-guide.md)           | Handbuch für die Redaktion in Strapi                       |
| [legal/dependency-licenses.md](docs/legal/dependency-licenses.md) | Lizenzbewertung der Abhängigkeiten                         |
| [adr/](docs/adr/)                                                 | Langlebige Architekturentscheidungen                       |

## Voraussetzungen

| Werkzeug         | Version                                             |
| ---------------- | --------------------------------------------------- |
| Node.js          | 24.21.0 LTS (Strapi 5.52.1 unterstützt `>=20 <=26`) |
| pnpm             | >= 10 (hier: 11.15.1, via Corepack)                 |
| Docker + Compose | Docker 29.x, Compose v5                             |
| Flutter          | stable channel                                      |
| PostgreSQL       | 16 (über Compose)                                   |

## Schnellstart (lokal)

```bash
corepack enable
pnpm install --frozen-lockfile

# Lokale Datenbanken starten (CMS-DB + App-DB, getrennte Rollen)
cp infrastructure/local/.env.example infrastructure/local/.env
pnpm compose:local:up

# Backend
cp apps/backend/.env.example apps/backend/.env
pnpm --filter @campus/backend prisma:migrate:dev
pnpm --filter @campus/backend start:dev      # http://localhost:3000/docs

# CMS
cp apps/cms/.env.example apps/cms/.env
pnpm --filter @campus/cms develop            # http://localhost:1337/admin

# Flutter
cd apps/mobile
flutter pub get
flutter gen-l10n
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

Vollständige Anleitung: [docs/local-development.md](docs/local-development.md)

## Qualitätsgates

Die Backend-Integrationstests enthalten absichtlich destruktive Tabellenresets.
Sie starten nur, wenn `DATABASE_URL` und `TEST_DATABASE_URL` exakt dieselbe,
eigens angelegte Datenbank `campus_app_test` beziehungsweise
`campus_app_test_<run-id>` bezeichnen. Die normale lokale Datenbank
`campus_app_local` wird geschlossen abgewiesen. Der sichere temporäre Ablauf
steht in [docs/local-development.md](docs/local-development.md#31-isolierte-backend-testdatenbank).

```bash
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
pnpm --filter @campus/backend build
pnpm --filter @campus/cms build
pnpm --filter @campus/map check

cd apps/mobile
flutter gen-l10n && dart format --output=none --set-exit-if-changed . \
  && flutter analyze --fatal-infos --fatal-warnings && flutter test

# Prüft die gesperrten Dart-Abhängigkeiten gegen die OSV-Datenbank.
# Braucht Netz und scheitert bewusst, wenn die Prüfung selbst nicht laufen
# kann — ein nicht ausgeführtes Audit darf nicht wie ein sauberes aussehen.
dart run tool/audit_dependencies.dart
```

Die CI führt zusätzlich aus: Prisma-Migrationen gegen ein echtes PostgreSQL, den Abgleich von
[`packages/openapi/openapi.json`](packages/openapi/openapi.json) gegen den Code, einen Secret-Scan,
ein Dependency-Audit für Node **und** Dart sowie Greps gegen hartkodierte UI-Texte und gegen jede
Verwendung von `food.image_url`. Nach einem vollständig grünen Lauf auf `main` oder einem
Version-Tag baut [`.github/workflows/images.yml`](.github/workflows/images.yml) die Backend- und
CMS-Images für `linux/amd64`, prüft sie vor der Veröffentlichung mit Trivy und veröffentlicht sie
mit SBOM und Provenance unter `ghcr.io/leviora-studio/campus-koethen/{backend,cms}`. Es findet kein
automatisches Deployment statt.

## Lizenz

**AGPL-3.0-only** — siehe [LICENSE](LICENSE).

`Copyright © 2026 Leviora Studio and Jona Loreen Sommer`

Drittanbieter-Abhängigkeiten und separat lizenzierte Assets (u. a. die gebündelte Schrift
Albert Sans unter SIL OFL 1.1 und Tabler Icons unter MIT) sind in
[NOTICE.md](NOTICE.md) dokumentiert.

## Beitragen

Siehe [AGENTS.md](AGENTS.md) für die verbindlichen Entwicklungsregeln
(TypeScript strict, TDD, keine Secrets, keine Hochschulassets).
