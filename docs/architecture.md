# Architektur

Campus Köthen App · `AGPL-3.0-only` · Copyright © 2026 Leviora Studio and Jona Loreen Sommer

---

## 1. Überblick

Die App nutzt **zwei streng getrennte Datenpfade**. Welcher Pfad gilt, entscheidet allein die
Sensibilität der Daten.

### 1.1 Pfad 1 — öffentliche und redaktionelle Daten über das Backend

```text
      Redaktion / Herausgeber
                │ HTTPS (Admin-Panel)
                ▼
        ┌───────────────────┐        ┌──────────────────────┐
        │  Strapi 5 (CMS)   │───────►│  campus_cms_<env>    │
        │  apps/cms         │        │  Rolle: campus_cms   │
        └───────────────────┘        └──────────────────────┘
                │
                │ REST /api/*  ·  serverseitiges Read-only-Token
                │ (nur Backend → Strapi, nie App → Strapi)
                ▼
        ┌───────────────────┐        ┌──────────────────────┐
   ┌───►│  Campus API       │───────►│  campus_app_<env>    │
   │    │  apps/backend     │        │  Rolle: campus_app   │
   │    │  NestJS + Prisma  │        └──────────────────────┘
   │    └───────────────────┘                   ▲
   │ HTTPS /v1                                  │ Prisma
   │                                 ┌──────────────────────┐
┌──┴─────────────┐                   │  Campus Worker       │
│ Flutter        │                   │  apps/backend        │
│ apps/mobile    │                   │  dist/worker.js      │
│ iOS / Android  │                   └──────────────────────┘
└────────────────┘                              │ HTTPS
                                                ├──► meine-mensa.de/api/food_plans
                                                │      alle 2 h
                                                ├──► hsa.webuntis.com  (öffentliche View-API)
                                                │      WEBUNTIS_ENABLED, Default false
                                                └──► calendar.google.com  (öffentlicher ICS-Feed)
                                                       PUBLIC_CALENDAR_ENABLED, Default false
```

### 1.2 Pfad 2 — persönliche Dienste direkt vom Gerät

```text
┌────────────────┐
│ Flutter        │──HTTPS/IMAPS/SMTP──► mail.hs-anhalt.de           E-Mail (IMAP 993, SMTP 587)
│ apps/mobile    │──HTTPS─────────────► service.ssc.hs-anhalt.de    HIS-QIS-Notenspiegel
│                │──HTTPS─────────────► sscportal.ssc.hs-anhalt.de  HISinOne-Notenspiegel
│                │──HTTPS─────────────► moodle.hs-anhalt.de         Moodle-Webservice (lesend)
│                │──HTTPS─────────────► REQUESTS_BASE_URL           Gremiensystem (Anträge/Feedback)
└────────────────┘
        │
        └── Zugangsdaten/Token: Keychain / Keystore · Inhalte: verschlüsselter lokaler Cache
```

Diese vier Dienste laufen **bewusst am Backend vorbei**, damit weder Campus API noch Strapi noch
Worker jemals Zugangsdaten oder persönliche Inhalte erhalten. Es sind **genau vier** ausdrücklich
beschlossene Ausnahmen — jede weitere muss in [`../AGENTS.md`](../AGENTS.md) §2 ergänzt werden.

Zwei Besonderheiten, die aus dem Diagramm allein nicht hervorgehen:

- Der **Notenspiegel** spricht mit genau **einem** von zwei parallel betriebenen Prüfungsportalen.
  Jedes hat seine **eigene, getrennte** Host-Allowlist — es gibt keinen gemeinsamen Pool. Welches
  Portal ein Konto nutzt, wird bei der Einrichtung einmalig ermittelt und lokal gespeichert
  ([grades.md](grades.md), „Portalwahl").
- Die **Antragstellung** ist als einzige der vier **nicht nutzerauthentifiziert**. Ausschlaggebend
  ist hier der Inhalt statt der Anmeldung: eine Einreichung trägt den Namen der antragstellenden
  Person und eine **Kopie des Studierendenausweises**. Der zurückgegebene **Statuslink ist ein
  Geheimnis** und der einzige Zugang zum Vorgang ([requests.md](requests.md)).

Die optionale `UniversityIdentity` verbindet diese Netze **nicht** zu einer technischen SSO-
Sitzung. Sie ist eine lokale Eingabehilfe mit genau **einer** Kennung (Hochschul-Benutzername
oder -Mailadresse, je nachdem was eingegeben wurde) und einem Passwort — das spiegelt, dass die
Hochschule dieselbe Kennung und dasselbe Passwort für alle drei Dienste akzeptiert. Der öffentliche
Controller-State enthält nur diese Kennung; das Passwort wird für
eine ausdrücklich ausgelöste `+`-Aktion just in time aus dem gerätegebundenen Keychain/Keystore
gelesen. Moodle und Noten erhalten sie unverändert im Benutzername-Feld. Der Mail-Adapter ergänzt
nur eine Kennung ohne `@` zu `<Kennung>@hs-anhalt.de`; eine bereits vollständige Mailadresse bleibt
unverändert. Das frühere Drei-Feld-Schema wird vollständig gelöscht und nicht geraten migriert.
Danach erzeugt
der jeweilige Adapter ausschließlich seinen eigenen Zustand: Mail-Credentials, Moodle-Token oder
Noten-Credentials samt Portalwahl. Es gibt weder ein Campus-Köthen-Konto noch einen
Identity-Endpunkt im Backend.

Die Zusammenführung von Stundenplan (Pfad 1), öffentlichen Kalendern (Pfad 1) und Moodle-Deadlines
(Pfad 2) im Kalender-Tab geschieht **ausschließlich lokal auf dem Gerät**. Kein Server sieht die
kombinierte Ansicht.

## 2. Harte Systemgrenzen

Verstöße gegen diese Regeln sind Blocker, keine Stilfragen.

| #   | Grenze                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| G1  | Für öffentliche und redaktionelle Daten spricht Flutter **ausschließlich** mit der Campus API unter `/v1`. Kein direkter Zugriff auf Strapi, `meine-mensa.de`, WebUntis oder den ICS-Feed.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| G2  | Das Backend liest Strapi **ausschließlich** über dessen REST-API mit einem serverseitigen Read-only-Token. Kein Zugriff auf Strapi-Tabellen.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| G3  | Redaktionelle Inhalte liegen in Strapi. Importierte Mensa-, Stundenplan- und Kalenderdaten sowie Sync-Zustände liegen in `campus_app_<env>`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| G4  | CMS und operative Daten nutzen **getrennte Datenbanken und getrennte Rollen**. Keine Rolle hat Zugriff auf beide.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| G5  | Strapi stellt **keine** unauthentifizierte Content-API bereit. Das Plugin `users-permissions` ist **nicht installiert**: es gibt damit weder eine Public Role noch eine Berechtigungstabelle, in der jemand versehentlich ein Leserecht aktivieren könnte. Jede `/api/*`-Route antwortet ohne gültigen API-Token mit `401`. Die Campus API nutzt ein eigenes minimales Read-only-Token; API-Tokens liefert Strapi-Core, nicht dieses Plugin. Wird das Plugin je wieder aufgenommen, entsteht erneut eine Public Role, deren Rechte in der Datenbank liegen und für CI unsichtbar sind — dann braucht G5 wieder eine Laufzeitprüfung. `apps/cms/test/no-public-role-plugin.test.ts` schlägt genau in diesem Moment fehl. |
| G6  | Die Strapi-Adresse ist nie eine Quellcode-Konstante — ausschließlich `STRAPI_BASE_URL`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| G7  | Umgebungsunterschiede entstehen **nur** durch Environment/Secrets, nie durch Quellcode oder Branches.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| G8  | Öffentliche DTOs leaken keine Strapi-Internas (`data`, `attributes`, `documentId`, `meta.pagination` der Quelle) und keine Fremd-IDs (WebUntis-IDs, `location_id`, Google-Kalender-ID).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| G9  | PostgreSQL wird nie öffentlich gebunden.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| G10 | Persönliche Dienste laufen **direkt** vom Gerät zum offiziellen Anbieter: Mail, Notenspiegel (HIS-QIS **und** HISinOne), Moodle, Anträge/Feedback. **Kein** Backend-Proxy, **keine** serverseitige Speicherung, **kein** Logging-Umweg.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| G11 | Für die Direktdienste gilt: nur HTTPS bzw. implizites TLS, feste Host-Allowlist **je Dienst und je Prüfungsportal** (kein gemeinsamer Pool), Redirects auf fremde Hosts werden abgelehnt, Zertifikatsprüfung nie deaktiviert, kein Certificate-Pinning. Die Origin-Prüfung umfasst Schema, Host, Port und schließt `userInfo` aus.                                                                                                                                                                                                                                                                                                                                                                                      |
| G12 | Zugangsdaten, Token und der Statuslink der Anträge liegen **ausschließlich** im Keychain/Keystore beziehungsweise verschlüsselt lokal; persönliche Inhalte einschließlich hochgeladener Nachweise nur **verschlüsselt** lokal. Nie in `SharedPreferences` oder einer unverschlüsselten Box.                                                                                                                                                                                                                                                                                                                                                                                                                             |
| G13 | Quellenübergreifende Zusammenführung im Kalender geschieht **ausschließlich lokal** in Flutter. Kein Server sieht die kombinierte Ansicht.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |

## 3. Komponenten

### 3.1 `apps/cms` — Strapi 5 Community

- TypeScript, Draft & Publish für Posts, offizielle i18n-Plugin-Funktionen für `de`/`en`.
- Content-Types: `channel`, `tag`, `post`, `contact-area`, `contact-person`,
  `public-calendar`, `room`.
- `room` ist technische Referenzdatenhaltung: katalogverwaltete Felder gehören
  `packages/campus-map` und sind serverseitig gegen normale Bearbeitungswege geschützt,
  redaktionelle Felder und Kontaktrelationen bleiben editierbar
  ([campus-map.md](campus-map.md)).
- Slugs sind **nicht** lokalisiert und unique — das ist ein eigenes CI-Gate, damit der stabile
  Bezeichner nicht pro Locale auseinanderläuft.
- Uploads im persistenten Volume unter `/opt/app/public/uploads`. Ausgeliefert werden sie **nicht**
  direkt an die App, sondern über `GET /v1/media/uploads/:filename` der Campus API — die App spricht
  nie mit Strapi (G2), und der lokale Provider veröffentlicht ohnehin nur relative URLs. Der
  Endpunkt lässt ausschließlich Bilder aus genau diesem Verzeichnis durch.
- Upload-Grenzen (`apps/cms/config/plugins.ts`): `sizeLimit` ist **explizit** gesetzt
  (`UPLOAD_SIZE_LIMIT_BYTES`, Default 25 MB) — ohne den Wert gilt der Plugin-Default von 1 GB pro
  Datei gegen ein Volume ohne Quota. `plugin.upload.security.allowedTypes`/`deniedTypes` wird
  serverseitig durchgesetzt (Inhaltsprüfung über die ersten 4100 Bytes); das ist gegen die
  installierte Strapi-Version durch `apps/cms/test/upload-security.test.ts` belegt, nicht nur
  angenommen. `image/svg+xml` steht **explizit** auf der Deny-Liste: `image/*` würde es sonst
  matchen, und Uploads werden von derselben Origin wie das Admin-Panel ausgeliefert.
  Bekannte Grenze: die Inhaltsprüfung erkennt Textformate nicht, eine SVG-Datei mit `.png`-Namen
  wird daher als `image/png` angenommen und auch so ausgeliefert — als Bild, nicht als Dokument.
- Rollen: Redaktion (ohne Publish), Herausgeber (mit Publish), Super-Admin separat.
  Für den Start genügt ein manuell angelegter Super-Admin; SMTP folgt später.
- Health: `GET /_health`.

### 3.2 `apps/backend` — Campus API + Worker

Eine Codebasis, zwei Einstiegspunkte:

| Einstiegspunkt | Start                 | Aufgabe                                                       |
| -------------- | --------------------- | ------------------------------------------------------------- |
| API            | `node dist/main.js`   | HTTP-Server auf `0.0.0.0:3000`                                |
| Worker         | `node dist/worker.js` | Zeitgesteuerte Synchronisierung: Mensa, Stundenplan, Kalender |

Module:

```text
src/
  config/            typisierte, validierte Konfiguration (Zod), einmalig beim Boot geprüft
  common/            Locale-Auflösung, Fehlerfilter, JSON-Logging, Pagination,
                     Query-Validierung, Content-Block-Sanitizer
  modules/
    health/          /health/live, /health/ready
    strapi/          gekapselter StrapiClient (Timeout, Retry, typisierte Fehler)
    posts/           /v1/posts/*
    contacts/        /v1/contact-areas/*
    canteen/         /v1/canteens/*, Sync-Service, meine-mensa-Client + Zod-Schema
    timetable/       /v1/timetable/*, Sync-Service, WebUntis-Client + Zod-Schema
    public-calendar/ /v1/calendars/*, Katalog- und Event-Sync, ICS-Client + RFC-5545-Parser,
                     Google-Freigabelink-Validierung
    rooms/           /v1/rooms/*, Raumkatalog aus Strapi, RoomReference für Kontakte
  cli/               administrative Kommandos: OpenAPI erzeugen, Mensen seeden,
                     Mensa- und Stundenplan-Sync manuell auslösen
  main.ts            API-Bootstrap
  worker.ts          Worker-Bootstrap
```

Der Worker läuft als **eigener Container** aus demselben Image. Er teilt sich die Datenbank mit der
API, aber nicht den Prozess — ein Sync-Fehler kann die API nicht blockieren. Jeder Job hat einen
eigenen Overlap-Guard; Mensa, Stundenplan und Kalender sind unabhängig voneinander schaltbar.

### 3.3 `apps/mobile` — Flutter

Feature-first, Riverpod für State, go_router für Navigation, dio als HTTP-Client:

```text
lib/
  core/
    theme/           typisierte Design-Tokens, Light- und Dark-Theme, Kontrastprüfung
    network/         Dio-Client, API-Konfiguration via --dart-define, typisierte Fehler
    cache/           hive_ce-Repositories, Stale-Metadaten, verschlüsselte Box
    prefs/           SharedPreferences für kleine Skalare
    documents/       geteilter Dokument-Viewer (Bild, PDF, Text) + OS-Teilen
    links/           SafeLinkLauncher (nur https/mailto/tel)
    locale/          Locale-Modus und Formatierung
  l10n/              ARB-Dateien de/en (gen_l10n)
  features/
    news/  canteen/  contacts/  settings/  about/  legal/    Pfad 1, über die Campus API
    timetable/                                               Pfad 1, serverseitig schaltbar
    campusmap/                                               Pfad 1 (Namen) + lokales Asset (Geometrie)
    calendar/                                                lokale Zusammenführung + öffentliche Kalender
    mail/  grades/  moodle/                                  Pfad 2, direkt vom Gerät
    todos/                                                   rein lokal, ohne Netz
    notifications/                                           lokale Benachrichtigungsplanung,
                                                             ohne Netz und ohne Push-Dienst
                                                             ([adr/0001](adr/0001-push-benachrichtigungen.md))
    requests/                                                Pfad 2, direkt an das Gremiensystem
                                                             (Anträge, Feedback, Statusabruf —
                                                             [requests.md](requests.md))
    more/                                                    Hub für alles, was nicht angeheftet ist
```

Navigation: **vier frei wählbare Module plus ein festes „Mehr"**, jedes mit eigenem
Navigationsstack. Voreingestellt sind **News · Kalender · Mensa · E-Mail · Mehr**; die ersten vier
sind in den Einstellungen austauschbar und per Drag-and-drop sortierbar.

Woraus diese Navigation besteht, entscheidet **ein** typisierter Modulkatalog
(`lib/app/app_modules.dart`): Storage-ID, Route, voller und kurzer Titel, Icons, Kategorie,
Sortierung und ob ein Modul anheftbar ist. Bottom Navigation, Navigationseinstellungen,
Onboarding, die Mehr-Ansicht und die Reparatur ungültiger gespeicherter Konfigurationen lesen
alle denselben Katalog — getrennt gepflegte Listen würden genau so lange übereinstimmen, bis
jemand eine davon vergisst.

Die Mehr-Ansicht wird daraus abgeleitet: Was angeheftet ist, erscheint dort **nicht** zusätzlich;
alles andere steht unter seiner kanonischen Kategorie (**Studium**, **Campus**, **App**).
Einstellungen und „Über die App" sind nicht anheftbar und stehen immer unter **App**. Gespeichert
werden ausschließlich die vier stabilen Modul-IDs in ihrer Reihenfolge; unbekannte IDs, Duplikate
oder eine falsche Anzahl werden beim Lesen repariert, sodass keine Konfiguration ein Modul
unerreichbar machen kann.

`API_BASE_URL` wird über `--dart-define` als exakte HTTPS-Origin ohne Pfad, Query oder Fragment
gesetzt. Jede Loopback-Adresse, einschließlich lokalem HTTP, erfordert zusätzlich das
ausdrückliche `ALLOW_LOCAL_API=true`; Release- und Profile-Builds verweigern sie immer. Die Strapi-URL gelangt
**nie** in die App.

Die Direktdienste sind jeweils hinter einem Port gekapselt (`MailGateway`, `GradesGateway`,
`MoodleRepository`). UI und Riverpod-Controller kennen **keine** `enough_mail`-, Dio-, Cookie-
oder HTML-Typen — das hält die Fremdbibliothek austauschbar und die Tests frei von echten
Netzaufrufen.

Beim Mailcache ist `MailCacheStore` der Port. `EncryptedMailCache` serialisiert Kopfzeilen,
Inhalte, Adressindex und optionale Anhangbytes über den gemeinsamen Kryptobaustein in eine
eigene verschlüsselte Box. `MailCacheManager` verantwortet Aktivierung,
Memory-only-Degradation, Altcache-Entfernung, Write-Fence und verifizierten Wipe.
`MailLocalDataCoordinator` koordiniert Cache, Credentials und den persistenten Lösch-Intent vor
Kontowiederherstellung und Account-Entfernung. Damit bleiben Mailtransport, Cache-Lebenszyklus und
Sitzungs-State getrennte Verantwortlichkeiten.

Die **lokale Benachrichtigungsplanung** (`features/notifications`) folgt demselben Port-Muster.
`NotificationPlanner` ist eine reine Funktion: Sie bekommt die Kandidaten der Kategorien, die
Einstellungen, den Berechtigungsstatus, „jetzt" und die Gerätezeitzone und liefert den
**vollständigen Sollzustand** — nie ein Delta. `NotificationScheduler` überträgt diesen Zustand
serialisiert (`cancelAll()`, dann neu einplanen) an den einzigen Ort, der
`flutter_local_notifications` kennt: `data/local_notification_gateway.dart`. Aktualisieren,
Ersetzen und Stornieren haben deshalb keinen eigenen Codepfad — ein abgesagter Termin wird beim
nächsten Lauf schlicht nicht mehr erzeugt.

Wann neu geplant wird, steht in **keiner** Auslöserliste: `notificationCandidatesProvider` liest
die Quellen und Einstellungen als Provider, sodass Riverpod nach jedem erfolgreichen Abruf und
jeder Präferenzänderung von selbst neu plant. Nur was kein App-Zustand ist — Rückkehr in den
Vordergrund, Zeitzonenwechsel, Tageswechsel, Sprachwechsel — behandelt `NotificationHost`.
Kein Netzaufruf, kein Hintergrundcode, kein Gerätetoken und kein serverseitiger Datensatz sind
beteiligt. Details und Gerätematrix: [notifications.md](notifications.md).

### 3.4 `packages/campus-map`

Kanonischer Kartenkatalog, SVG-Validator und Generator der gebündelten Flutter-Kartenassets.
Dependency-frei wie `packages/openapi`. Die Ausgabe ist deterministisch und wird committet; ein
CI-Gate erkennt Drift zwischen Quelle und generiertem Asset. Details:
[campus-map.md](campus-map.md).

### 3.5 `packages/openapi`

Der aus den NestJS-DTOs erzeugte, versionierte OpenAPI-Vertrag. Er ist das gemeinsame Artefakt
zwischen Backend und Flutter und wird in CI gegen den Code geprüft.

### 3.6 Direktintegrationen (Pfad 2)

Vier geräteseitige Integrationen ohne jede Backend-Beteiligung. Jede hat ein eigenes Dokument mit
Bedrohungsmodell, Sicherheitszusagen und manueller Testcheckliste.

| Dienst           | Ziel                                                                                                                                                                                                                          | Transport                                       | Umfang                                                                                                                                                                                                                                                                                      | Doku                               |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| Studenten-Mail   | `mail.hs-anhalt.de`                                                                                                                                                                                                           | IMAPS 993, SMTP 587 mit Pflicht-STARTTLS        | lesen, suchen, antworten, senden; Ordner wechseln; Anhänge anzeigen                                                                                                                                                                                                                         | [student-mail.md](student-mail.md) |
| Notenspiegel     | `service.ssc.hs-anhalt.de` **oder** `sscportal.ssc.hs-anhalt.de` — nie beide, getrennte Allowlists; für einen erzeugten HISinOne-Nachweis zusätzlich nur `sscportal.ssc.hs-anhalt.de/qisserver/rds?state=docdownload` (enge Pfad-/Parameter-Prüfung, kein eigener Host) | HTTPS, HTML-/JSF-Parsing (keine offizielle API) | Notenspiegel lesen; 24-Stunden-Regel; Portalwahl bei der Einrichtung. Auf HISinOne zusätzlich **nur lesend**, eine Seite „Studienservice" mit mehreren Tabs: Bescheinigungsübersicht/-abruf, Personendaten/Kontaktdaten, Studiengangsübersicht — dieselben Zugangsdaten, kein zweiter Login | [grades.md](grades.md)             |
| Moodle           | `moodle.hs-anhalt.de`                                                                                                                                                                                                         | HTTPS, Moodle-Webservice (REST)                 | Kurse, Materialien, Aufgaben, Ankündigungen, Deadlines — **nur lesend**                                                                                                                                                                                                                     | [moodle.md](moodle.md)             |
| Anträge/Feedback | `REQUESTS_BASE_URL` (Build-Environment, **nie** Quellcode-Konstante, **muss** HTTPS sein)                                                                                                                                     | HTTPS, öffentliche JSON-API, Multipart-Upload   | Finanzanträge und Rückmeldungen einreichen; Vorgangsstatus per `POST` abfragen; Entwürfe, Nachweise und Statuslink bleiben auf dem Gerät                                                                                                                                                    | [requests.md](requests.md)         |

Der Antragsdienst ist **nicht nutzerauthentifiziert**. Er steht hier trotzdem, weil die Begründung
dieselbe ist wie bei den übrigen drei: die Einreichung trägt den Namen der antragstellenden Person
und eine Kopie des Studierendenausweises, und genau solche Daten sollen kein Campus-Köthen-Backend
erreichen. Es gibt hier keine Sitzung zum Beenden — der entsprechende Weg heißt daher „lokale Daten
löschen" und nicht „abmelden".

Der **Mensa-€-Check per NFC** ist keine fünfte Netzwerkintegration: Der Lesevorgang bleibt vollständig
zwischen Gerät und vorgehaltener Mensakarte. Ein schmales natives Bridge-Modul stellt Android
`IsoDep` und iOS Core NFC bereit; die gemeinsame Dart-Schicht sendet ausschließlich die zwei
festgelegten Read-Kommandos, validiert Statuswort, Länge und Wertebereich und hält das Ergebnis nur
flüchtig im Widget-State. Die App wertet keine Kartenkennung aus und speichert, protokolliert oder
überträgt weder Kartenkennung, Rohantwort noch Saldo. Es gibt keinen Hintergrundscan. Android darf
einen bereits per `TECH_DISCOVERED` erkannten Tag nach der systemseitigen Öffnen-Aktion unmittelbar
verarbeiten; iOS startet ausschließlich eine manuelle In-App-Session.

Gemeinsame, nicht verhandelbare Zusagen (G10–G12):

- Feste Host-Allowlist, vor **jedem** Request geprüft. Ein Redirect auf einen anderen Host oder auf
  Klartext wird abgebrochen — ein Token oder Cookie kann so nie an einen fremden Host gelangen.
- Zertifikats- und Hostname-Prüfung sind immer aktiv; es gibt nirgends ein „accept all certificates“.
- Zugangsdaten und Token wandern nie in Logs, Exceptions, `toString()` oder Fehlermeldungen.
  Fehler sind klassifizierte Aufzählungswerte mit lokalisierten Texten, ohne Rohdaten der Quelle.
- Kein Hintergrund-Polling. Solange die App aktiv ist, synchronisieren News alle 5 Minuten,
  Kalenderdaten alle 10 Minuten, Mail alle 10 Minuten, Moodle und Stundenplan stündlich sowie
  Kontakte täglich. Beim App-Start laufen diese Quellen ebenfalls an; News aktualisiert zusätzlich
  bei jedem Vordergrundwechsel, Kalender frühestens 10 Minuten nach dem letzten Versuch. Noten
  folgen weiterhin einer 24-Stunden-Regel. Moodle und Noten behalten Single-Flight und manuelle
  Übersteuerung.
- Das dienstbezogene `−` beziehungsweise „Verbindung und lokale Daten löschen“ entfernt die
  Credential-Kopie beziehungsweise den Token dieses Diensts, Cache, Cache-Schlüssel, Zeitstempel
  und den zugehörigen State logisch. Ein optionaler zentraler Hochschulzugang bleibt erhalten. Beim Mailkonto wird
  Erfolg erst nach bestätigter Abwesenheit der persistenten Artefakte gemeldet. Ein Teilfehler
  hält die Sitzung gesperrt und wird beim Retry oder nächsten Start fortgesetzt.
- „Hochschulzugang vollständig löschen“ ruft für alle verbundenen Dienste genau diese kanonischen
  Wipes auf. Erst wenn jeder erfolgreich war, wird die zentrale Identität zuletzt verifiziert
  gelöscht. Bei Teilfehlern bleiben erfolgreiche Dienst-Wipes bestehen, fehlgeschlagene Dienste
  werden benannt, und die zentrale Identität bleibt für den Retry erhalten. Bei einem
  Passwortwechsel wird die Identität über „Zugangsdaten aktualisieren“ erneut an einem bewusst
  gewählten Dienst geprüft; erst danach ersetzt sie den bisherigen sicheren Wert.
- Die
  Anträge haben stattdessen ihre eigene Aktion **„Lokale Antragsdaten und Nachweise löschen“**
  (Einstellungen → Daten): sie entfernt Entwürfe, eingereichte Vorgänge, Anhänge und beide
  Verschlüsselungsschlüssel und meldet einen unvollständigen Lauf als solchen. Mit dem Statuslink
  geht dabei der **einzige** Zugang zu einem bereits eingereichten Vorgang verloren; die Aktion
  sagt das vor der Bestätigung.
- Der logische Wipe nimmt den App-Zugriff und verwirft den Cache-Schlüssel; er verspricht kein
  forensisches Secure Erase von Flash-Zellen, Betriebssystem-Snapshots oder Backups.

Die HIS-QIS-Integration ist **inhärent fragil**, weil das Portal keine JSON-API anbietet und über
Spaltenüberschriften geparst wird. Eine Portaländerung ist deshalb zuerst als Quelländerung zu
behandeln, nicht als eigener Bug; sie führt zu `portalStructureChanged` und **überschreibt den
Cache nicht**. Dasselbe gilt für die WebUntis-View-API in Pfad 1.

## 4. Datenhaltung

### 4.1 Trennung

| Datenbank          | Rolle        | Inhalt                                                            | Zugriff durch           |
| ------------------ | ------------ | ----------------------------------------------------------------- | ----------------------- |
| `campus_cms_<env>` | `campus_cms` | Strapi-Tabellen, redaktionelle Inhalte                            | nur Strapi              |
| `campus_app_<env>` | `campus_app` | importierte Mensa-, Stundenplan- und Kalenderdaten, Sync-Zustände | nur Campus API + Worker |

Redaktionelle Inhalte werden **nicht** in die operative Datenbank gespiegelt. Die API liest sie bei
Bedarf über Strapi. Die **einzige** Ausnahme ist der Katalog der öffentlichen Kalender: Er wird als
minimales operatives Read-Model gespiegelt, damit ein Kalender erst nach Validierung **und** erstem
erfolgreichen ICS-Sync erscheint und ein Strapi-Ausfall die öffentliche API nicht lahmlegt.

**Persönliche Daten aus Pfad 2 liegen in keiner dieser Datenbanken.** Es gibt weder Tabelle noch
Spalte für E-Mails, Noten, Moodle-Inhalte, Antragsentwürfe, hochgeladene Nachweise oder
Statuslinks — sie existieren ausschließlich auf dem Gerät.

### 4.2 Operatives Schema (Prisma)

13 Modelle in drei fachlichen Gruppen. Vollständig: [`../apps/backend/prisma/schema.prisma`](../apps/backend/prisma/schema.prisma).

**Mensa**

```text
Canteen                 slug (unique), sourceLocationId (unique), displayName, campusLabel, active
Meal                    sourcePlanId (unique) ← Upsert-Schlüssel, canteenId, date, counterId,
                        isSprint, name, subtitle, extras[], ingredientCodes[],
                        sourceUpdatedAt, importedAt
MealPrice               mealId + group (unique), amount (Decimal) — jede Preisgruppe eine Zeile,
                        eine fehlende Gruppe ist eine fehlende Zeile, nie ein geschätzter Wert
IngredientDefinition    code (PK), labelDe, labelEn?, kind (ingredient | marker)
SyncRun                 source, canteenId?, startedAt, finishedAt, status, recordsReceived,
                        recordsUpserted, recordsRejected, errorMessage
```

**Stundenplan (WebUntis, öffentliche Ansicht)**

```text
TimetableContext        source + externalId (unique), Schuljahr, validFrom/validTo — die ID ist
                        dynamisch und wird zur Laufzeit gelesen, nie hartkodiert
TimetableGroup          source + externalId (unique), shortName, longName, department, active,
                        lastSeenAt — Deaktivierung erst nach vollständigem Erfolgslauf
TimetableEntry          source + externalKey (unique) ← Upsert-Schlüssel, startsAt/endsAt (UTC),
                        date, title, subjectCode, type, status, sourceStatus, teachers, rooms
TimetableEntryGroup     explizite n:m — ohne sie würde ein Gruppensync eine Stunde löschen,
                        die andere Gruppen noch besuchen
TimetableSyncRun        kind (context | groups | entries), status, bestätigtes Fenster, Zähler,
                        klassifizierter Fehlercode
```

**Öffentliche Kalender (öffentlicher Google-ICS-Feed)**

```text
PublicCalendar          slug (unique), googleCalendarId (nur serverseitig), Anzeigefelder,
                        operationalStatus, lastEtag/lastModified/lastContentHash,
                        lastSuccessfulSyncAt
PublicCalendarEvent     calendarId + occurrenceKey (unique), uid, recurrenceId, title,
                        description?, location?, startsAt/endsAt, allDay, status
PublicCalendarSyncRun   kind (catalog | events), status, Fenster, Zähler, redigierter Fehler
```

Durchgehende Regeln:

- Geldwerte sind `Decimal`, niemals `float`.
- `Meal.imageUrl` existiert **nicht** — die Bild-URL der Quelle wird bewusst nicht persistiert.
- Externe IDs werden gespeichert, damit Upserts stabil bleiben, aber **nie** ausgeliefert. Clients
  sehen ausschließlich Campus-UUIDs und Slugs.
- Roh-ICS wird **nie** gespeichert; `ATTENDEE`/`ORGANIZER` werden nicht einmal gelesen.
- Jede `*SyncRun`-Tabelle speichert nur Zähler und einen klassifizierten Fehler — nie Header, URLs,
  Rohdaten oder Personennamen.

### 4.3 Gerätelokale Speicher (Pfad 2 und lokale Funktionen)

| Daten                                                                      | Speicher                                                                                             |
| -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Zugangsdaten Mail, Notenspiegel · Moodle-Token                             | `flutter_secure_storage` (Keychain/Keystore)                                                         |
| Gewähltes Prüfungsportal des Notenkontos                                   | `flutter_secure_storage`                                                                             |
| Schlüssel der verschlüsselten Boxen (256 Bit, CSPRNG)                      | `flutter_secure_storage`                                                                             |
| Noten, Moodle-Inhalte                                                      | verschlüsselte `hive_ce`-Box                                                                         |
| E-Mail-Kopfzeilen, begrenzte Inhalte, Adress-/Suchindex, optionale Anhänge | verschlüsselte `hive_ce`-Box (Retention: 500 Header, 200 Bodies, 100 MiB)                            |
| Antragsentwürfe, eingereichte Vorgänge, **Statuslinks**                    | verschlüsselte `hive_ce`-Box `campus_requests_secure_v1` (Schlüssel `campus_requests_secure_key_v1`) |
| Hochgeladene Nachweise inkl. **Kopie des Studierendenausweises**           | verschlüsselte `hive_ce`-Box `campus_request_files_v1` (Schlüssel `campus_request_files_key_v1`)     |
| Aufgabenliste                                                              | `hive_ce`, rein lokal, ohne Netz                                                                     |
| News, Kanäle, Kontakte, Mensadaten, Kalender-/Stundenplanfenster           | `hive_ce` (Inhaltscache; 128 Einträge/20 MiB, Namespace-LRU, 90-Tage-Fenster-Retention)              |
| Kanal-Abos, Kalenderauswahl, Sprache, Theme, Mensa                         | `SharedPreferences` (kleine Skalare)                                                                 |
| Benachrichtigungs-Opt-in und Kategorieschalter                             | `SharedPreferences` (vier kleine Skalare)                                                            |
| NFC-Mensaguthaben und Kartenantwort                                        | **keine Persistenz**; nur flüchtig im Arbeitsspeicher der geöffneten Anzeige                         |

Alle Einträge — Zugangsdaten wie Box-Schlüssel — werden mit derselben, an genau einer
Stelle definierten Konfiguration abgelegt (`apps/mobile/lib/core/security/app_secure_storage.dart`).
Sie ist **gerätegebunden** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`): nichts davon
gelangt in ein Gerätebackup oder den iCloud-Schlüsselbund und lässt sich auf einem anderen
Gerät wiederherstellen. Der Preis ist bewusst gewählt — beim Gerätewechsel werden die Konten
erneut angemeldet. Ein Test verhindert, dass eine einzelne Stelle wieder eigene Optionen setzt.

Der Mailcache nutzt `campus_mail_cache_secure_v2`; sein gerätegebundener Schlüssel
`mail.cache.key.v2` liegt im Keychain/Keystore. Beim Upgrade wird der unverschlüsselte
Testcache `campus_mail_cache_v1` ungeöffnet und idempotent entfernt, nicht inhaltlich migriert.
Kann der Altcache nicht sicher entfernt oder der sichere Speicher nicht genutzt werden, degradiert
Mail auf Memory-only und erzeugt niemals eine unverschlüsselte Persistenz.

Der allgemeine Inhaltscache führt pro Dokument Namespace, Erstell- und Zugriffszeit. Beim Öffnen
der Box und nach erfolgreichen Schreibvorgängen werden ungültige Einträge, alte Bereichsfenster
und anschließend die am längsten nicht verwendeten Dokumente entfernt. Je
Stundenplan-/Kalender-Scope bleibt das jüngste erfolgreiche Fenster bei der Altersbereinigung
erhalten; eine einzelne Antwort, die das gesamte Bytebudget überschreitet, ersetzt keinen zuvor
nutzbaren Cacheeintrag.

Ein gewöhnlicher Cachefehler darf **nie** zum Absturz führen — er degradiert auf Memory-only oder
einen Netzabruf. Umgekehrt **löscht** eine leere, ungültige oder fehlgeschlagene Antwort **nie** den
letzten guten Stand.

## 5. Locale-Vertrag der Campus API

Priorität der Auflösung:

1. Query-Parameter `locale` (`de` | `en`) — höchste Priorität.
2. Header `Accept-Language`, sofern kein `locale`-Parameter gesetzt ist.
3. Standard `de`.

Ein **nicht unterstützter expliziter** `locale`-Parameter wird mit `400` abgelehnt. Ein nicht
unterstützter `Accept-Language`-Wert fällt still auf `de` zurück.

Jede inhaltliche Antwort trägt:

```json
{
  "meta": {
    "requestedLocale": "en",
    "resolvedLocale": "en",
    "translationFallback": false
  }
}
```

`translationFallback` ist `true`, sobald mindestens ein ausgeliefertes Feld aus der Fallback-Locale
stammt. Externe Mensa-Gerichtsnamen werden **nie** übersetzt; sie sind bei `locale=en` immer
Fallback und werden entsprechend markiert.

## 6. Resilienz der Synchronisierung

Alle drei Worker-Jobs folgen demselben Grundsatz: **eine leere, ungültige oder fehlgeschlagene
Fremdantwort löscht niemals den letzten erfolgreichen Datenbestand.** Aufgeräumt wird nur innerhalb
eines bestätigten Zeitfensters und nur nach einer erfolgreichen, nicht-leeren Antwort. Dieser Punkt
ist für jeden Job durch Integrationstests gegen eine echte Datenbank abgesichert.

### 6.1 Mensa

```text
Worker-Tick (CANTEEN_SYNC_CRON, Standard "0 */2 * * *")
   │
   ├─ SyncRun anlegen (status = running)
   ├─ HTTP GET mit Timeout und Retry mit exponentiellem Backoff
   │     └─ Fehler ⇒ SyncRun(failed) · KEIN Löschen bestehender Daten · Abbruch
   ├─ Antwort gegen Zod-Schema validieren
   │     └─ ungültig ⇒ SyncRun(failed) · KEIN Löschen · Abbruch
   ├─ location_id jedes Eintrags gegen die angefragte Mensa prüfen
   │     └─ Mismatch ⇒ Eintrag verwerfen und zählen
   ├─ leere data-Liste ⇒ SyncRun(empty) · KEIN Löschen · Abbruch
   └─ Upsert über sourcePlanId
         └─ Aufräumen NUR innerhalb des erfolgreich synchronisierten Zeitraums
            und NUR nach erfolgreicher, nicht-leerer Antwort
```

`lastSuccessfulSyncAt` ist der jüngste `SyncRun` mit `status = success`. `dataStale` ist `true`,
wenn dieser Zeitpunkt älter als `CANTEEN_STALE_AFTER_MINUTES` ist.

Davon getrennt läuft die optionale lokale NFC-Guthabenprüfung ohne Campus API und ohne Worker. Nach
der Auswahl von DESFire-Anwendung `5F8415` wird nur bei erfolgreichem Statuswort der Wert gelesen;
vier Nutzdatenbytes werden als vorzeichenbehafteter 32-Bit-Wert in Little Endian interpretiert und
in Tausendstel Euro dargestellt. Ein Protokoll-, Längen- oder Plausibilitätsfehler beendet den
Vorgang mit einem Fehlerzustand und erzeugt keinen scheinbaren Nullsaldo.

### 6.2 Stundenplan

Zwei getrennte Jobs, beide über `WEBUNTIS_ENABLED` schaltbar (Default `false`):

- **Gruppenkatalog** (`WEBUNTIS_GROUP_SYNC_CRON`, Default `0 2 * * *`) — eine Gruppe wird erst
  nach einem **vollständig** erfolgreichen Katalogimport deaktiviert, nie aufgrund eines Teillaufs.
- **Einträge** (`WEBUNTIS_ENTRY_SYNC_CRON`, Default `15 2 * * *`) — die öffentliche Ansicht
  verlangt inzwischen genau eine Klasse pro Request. Der Worker lädt die Klassen aller Schuljahre,
  die das Zeitfenster schneiden, und übernimmt die Ergebnisse erst nach einem vollständigen Lauf.
  Wegen der höheren Abrufzahl laufen Katalog und Einträge standardmäßig einmal täglich.

Die Schuljahres-IDs werden dynamisch aus `/schoolyears` gelesen, einschließlich kommender Semester.
Zeiten kommen als zonenlose
Wandzeit und werden beim Import nach UTC gerechnet — würde man sie roh speichern, verschöbe sich
jede Stunde. Unbekannte Vokabeln in `type`/`status` werden auf `unknown` abgebildet und brechen den
Import **nicht**.

### 6.3 Öffentliche Kalender

Zwei getrennte Jobs, beide über `PUBLIC_CALENDAR_ENABLED` schaltbar (Default `false`):

- **Katalog** — spiegelt validierte Strapi-Definitionen ins operative Read-Model. Eine fehlerhafte
  oder unvollständige Strapi-Antwort löscht den letzten gültigen Katalog nie.
- **Events** — pro Kalender: ICS laden (bytebegrenzt) → validieren → parsen → im Zielfenster
  expandieren → **eine Transaktion** aus Upsert und Löschen ausschließlich im bestätigten Fenster.
  Der Job nutzt einen Worker-Pool mit höchstens vier parallelen Feeds, behält die deterministische
  Katalogreihenfolge bei und isoliert auch unerwartete Einzelfehler.

Bemerkenswerte Zustände:

| Fall                                | Verhalten                                                              |
| ----------------------------------- | ---------------------------------------------------------------------- |
| Gültiger leerer Feed                | erfolgreicher leerer Snapshot, **kein** Fehler                         |
| Unveränderter Hash / HTTP 304       | teure Parse-/Persistenzphase überspringen, Zeitstempel trotzdem setzen |
| Timeout, Netzfehler, 5xx, 429       | letzten Stand behalten, Kalender `stale`, weiter ausliefern            |
| Beschädigt, zu groß, Limit gerissen | keine destruktive Übernahme; `stale` bzw. `invalid` ohne Vorstand      |
| Freigabe entzogen (403, 404, 410)   | Status `revoked`/`unavailable`, Termine gelöscht, aus dem Katalog raus |

Der ICS-Client folgt **keinen** Redirects (3xx wird abgelehnt), konstruiert Scheme, Host und Pfad
selbst und nimmt **keine** Basis-URL aus Strapi oder dem Environment entgegen. Wiederholungsregeln
werden nur im Zielfenster expandiert, mit harten Obergrenzen pro Event und pro Lauf gegen
„recurrence bombs“. Details: [public-calendars.md](public-calendars.md).

Für jeden Feed entstehen strukturierte Betriebsmetriken zu Status, Gesamtlaufzeit, tatsächlich
empfangenen UTF-8-Bytes, Fehlerklasse und Datensatzanzahlen. Sie enthalten weder URL noch
Google-Kalender-ID, Slug oder Termininhalte; die interne Feed-Zuordnung verbleibt im Sync-Run.

## 7. Betrieb

### 7.1 Container

| Image                                           | Port           | Health                                  | User     |
| ----------------------------------------------- | -------------- | --------------------------------------- | -------- |
| `ghcr.io/leviora-studio/campus-koethen/cms`     | `0.0.0.0:1337` | `GET /_health`                          | non-root |
| `ghcr.io/leviora-studio/campus-koethen/backend` | `0.0.0.0:3000` | `GET /health/live`, `GET /health/ready` | non-root |
| `postgres:16-alpine` (offiziell, gepinnt)       | intern         | `pg_isready`                            | —        |

Der Worker nutzt dasselbe Backend-Image mit abweichendem Startkommando. Zielplattform der
veröffentlichten Images: **ausschließlich `linux/amd64`**.

**Wie diese Images entstehen:** `.github/workflows/ci.yml` ruft
`.github/workflows/images.yml` erst auf, nachdem Backend, CMS, Flutter, Kartenpaket und
Security-Gates erfolgreich waren. Das Image wird zunächst nur in den Runner geladen und mit Trivy
auf alle nicht begründet ausgenommenen, behebbaren HIGH/CRITICAL-CVEs geprüft. Erst ein sauberer
Build wird mit SBOM und maximaler Build-Provenance nach GHCR veröffentlicht.

`main` erhält die Tags `main` und `sha-<voller Commit SHA>`. Ein Git-Tag erhält zusätzlich seinen
eigenen Namen, für diesen Release also `1.2.4`. Deployments verwenden ausschließlich den
unveränderlichen `sha-`-Tag; CI verbindet sich nie mit einem Server und deployt nichts.

### 7.2 Health-Semantik

- `/health/live` prüft **nur** den Prozess. Es darf nie durch eine Abhängigkeit fehlschlagen,
  sonst würde ein Datenbankausfall unnötige Container-Neustarts auslösen.
- `/health/ready` prüft kontrolliert und **mit Timeout** die Datenbank und die erreichbare
  Strapi-Instanz.

### 7.3 Umgebungswechsel

```dotenv
# DEV
STRAPI_BASE_URL=https://cms-dev.<domain>
DATABASE_URL=postgresql://campus_app:<secret>@postgres:5432/campus_app_dev

# PROD
STRAPI_BASE_URL=https://cms.<domain>
DATABASE_URL=postgresql://campus_app:<secret>@postgres:5432/campus_app_prod
```

Kein manueller URL-Austausch in mehreren Dateien, kein umgebungsspezifischer Code.

### 7.4 Kante (Reverse Proxy)

Die Campus API ist öffentlich und unauthentifiziert. Ihre **Eingabegrenzen** sind eng
(`pageSize` ≤ 50, ≤ 25 Filterwerte, begrenzte Datumsbereiche, gedeckelte Ergebnismengen), aber
die _Kosten pro Anfrage_ waren unbegrenzt oft abrufbar — insbesondere
`GET /v1/media/uploads/:filename` (bis 12 MB je Anfrage durch den API-Prozess) und
`GET /v1/calendars/events` (bis 2000 Termine über 50 Kalender). Ein Rate Limit im Node-Prozess
griffe erst, nachdem die Anfrage ihn bereits beschäftigt.

Der Vertrag über die Kante liegt deshalb versioniert im Repository:
[`infrastructure/vps/edge/`](../infrastructure/vps/edge/README.md). Verbindlich sind dort
Default-Deny auf Pfadebene (nur `/v1/`, `/health/live`, `/health/ready` und das bewusst
oeffentliche `/docs`), getrennte sehr großzügige Shared-NAT- und globale Schutzlimits,
Verbindungsgrenzen, `client_max_body_size` (die API ist read-only), Upstream-Keepalive,
Timeouts, ein auf öffentliche redaktionelle Bilder begrenzter Edge-Cache und die erlaubten
Methoden. Die Dimensionierungsannahme sind 3.000 Studierende, von denen viele dieselbe
öffentliche Campus-IP teilen können; garantierter Durchsatz bleibt bis zu einem Lasttest offen.

Für die erikspace.eu-Testumgebung liegen dort ein HTTP-only-ACME-Bootstrap und zwei direkt
installierbare finale VHosts für API und CMS. Sie enthalten die konkreten Testdomains,
Loopback-Ports und TLS-Pfade. Das Deployment bleibt trotzdem ausdrücklich manuell
(AGENTS.md §3, kein SSH aus CI): Änderungen an der Kante werden versioniert und anschließend
bewusst auf dem VPS installiert, geprüft und neu geladen.

## 8. Bewusste Nicht-Entscheidungen

| Thema                                           | Status                                                                                                                                                                                                                                                               |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Redis                                           | nicht im MVP — Datenmengen sind klein; nur öffentliche redaktionelle Bilder werden an der Nginx-Kante gecacht                                                                                                                                                        |
| SMTP                                            | später — Strapi-Admins werden zunächst manuell angelegt                                                                                                                                                                                                              |
| Sentry / Analytics                              | dauerhaft ausgeschlossen im MVP                                                                                                                                                                                                                                      |
| Automatisches Deployment                        | ausgeschlossen — Images werden gebaut, Deployment bleibt manuell                                                                                                                                                                                                     |
| Offsite-Backups                                 | offenes Release-Gate, **nicht** eingerichtet                                                                                                                                                                                                                         |
| WebUntis-Stundenplan                            | vollständig umgesetzt, aber `WEBUNTIS_ENABLED=false` bis zur organisatorischen Freigabe                                                                                                                                                                              |
| Öffentliche Kalender                            | vollständig umgesetzt, aber `PUBLIC_CALENDAR_ENABLED=false` bis Kalender in Strapi gepflegt sind                                                                                                                                                                     |
| Google API Key / OAuth / SDK                    | dauerhaft ausgeschlossen — der Worker liest ausschließlich den öffentlichen ICS-Feed                                                                                                                                                                                 |
| Backend-Proxy für Mail, Noten, Moodle           | dauerhaft ausgeschlossen — genau deshalb laufen diese Dienste direkt vom Gerät                                                                                                                                                                                       |
| Hintergrund-Sync bei geschlossener App          | ausgeschlossen — bräuchte WorkManager/BGTaskScheduler; Sync läuft, solange die App läuft, plus beim Start. Die lokale Benachrichtigungsplanung berührt das **nicht**: Sie meldet die Termine im Voraus beim Betriebssystem an, es läuft kein App-Code im Hintergrund |
| Push über einen externen Dienst (FCM/APNs)      | ausgeschlossen — Benachrichtigungen werden lokal aus vorhandenen Gerätedaten geplant, siehe [adr/0001](adr/0001-push-benachrichtigungen.md). Die Grundlage (Planer, Scheduler, Berechtigung, Einstellungen) ist umgesetzt; die fachlichen Kategorien folgen getrennt |
| Schreibzugriffe auf Moodle                      | ausgeschlossen — nur eine feste, rein lesende Whitelist von `wsfunction`s                                                                                                                                                                                            |
| Persönlicher WebUntis-Login                     | außerhalb des MVP; genutzt wird ausschließlich die öffentliche Gruppenansicht                                                                                                                                                                                        |
| Raumpläne, Raumverfügbarkeit, Indoor-Navigation | außerhalb des MVP; Architektur bleibt erweiterbar                                                                                                                                                                                                                    |
