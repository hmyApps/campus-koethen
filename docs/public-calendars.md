<!-- Campus Köthen App · AGPL-3.0-only · Copyright © 2026 Leviora Studio and Jona Loreen Sommer -->

# Öffentliche Google-Kalender (ICS)

Redakteur:innen legen in Strapi **öffentliche** Google-Kalender an. Der Campus-Worker
synchronisiert sie über den **öffentlichen ICS-Feed**, die Campus API liefert Katalog und Termine,
und die App führt sie – lokal – mit Stundenplan und Moodle-Deadlines im Kalender-Tab zusammen. Nach
der einmaligen Implementierung braucht ein weiterer Kalender **weder App- noch Backend-Änderung**.

## 1. Erlaubter Datenfluss

```
Strapi (public-calendar)  ──▶  Campus-Worker  ──ICS──▶  calendar.google.com (public/basic.ics)
   Definitionen                 │  validiert, parst, normalisiert
                                ▼
                          PostgreSQL (operatives Read-Model)  ──▶  Campus API  ──▶  Flutter
```

- **Kein** Google API Key, **kein** Google-Cloud-Projekt, **kein** Google-OAuth, **kein** SDK.
- Die **App ruft den ICS-Feed nie direkt ab**. Nur der Worker lädt ihn.
- Die **Feed-URL** bleibt backendintern (nie ein DTO-Feld, nie geloggt); dasselbe gilt für ETag
  und `lastContentHash`.
- Die **Google-Kalender-ID** ist kein DTO-Feld, steckt aber base64-kodiert im `cid` von
  `googleOpenUrl` und im Klartext in den `src`-Parametern von `/v1/calendars/google-view-url` —
  ohne sie funktionieren diese Links nicht. Das ist unkritisch: Es geht ausschließlich um Kalender,
  die die Redaktion öffentlich geteilt hat, und die ID ergibt sich ohnehin aus dem öffentlichen
  Freigabelink. Sie ist damit **kein** Geheimnis.
- Zusammenführung mit Stundenplan/Moodle passiert **ausschließlich lokal** in Flutter.

## 2. Von der Freigabe zur Feed-URL

Redakteur:innen tragen einen **öffentlichen Freigabelink** ein, z. B.
`https://calendar.google.com/calendar/u/0?cid=<base64url>`. Aus dem `cid` wird die Kalender-ID
extrahiert und daraus **serverseitig** die feste Feed-URL konstruiert:

```
https://calendar.google.com/calendar/ical/{URL-kodierte-ID}/public/basic.ics
```

Validierung (`google-calendar-url.ts`, 36 Tests): HTTPS-only · Host **exakt** `calendar.google.com`
· kein Userinfo/Port · Pfad-Allowlist (`render`, `u/N`, `u/N/r`) · genau **ein** `cid` · Base64/-URL
mit kanonischem Roundtrip · striktes UTF-8 · Längenlimits · keine Steuerzeichen/Whitespace. Abgelehnt
werden u. a. `http`, `webcal`, `calendar.google.com.attacker.example`, `user@…`, Ports, IPs sowie
direkt eingefügte `basic.ics`-/`private-…`-Links. Dieselbe Validierung läuft **erneut** an der
Backend-Vertrauensgrenze (`validateCatalog`).

## 3. SSRF-Schutz & ICS-Client

`GooglePublicIcsClient` (12 Tests): fester Scheme+Host+Pfad · Kalender-ID als **einziges**
`encodeURIComponent`-Pfadsegment · **keine** Basis-URL aus Strapi/ENV · Redirects werden **nicht**
verfolgt (3xx → abgelehnt) · harte Timeouts, begrenzte Retries (nur 5xx/429/Transport),
Request-Abstand · `Content-Length`-Vorabprüfung **und** Streaming-Byte-Limit (Abbruch bei
Überschreitung) · `Content-Type: text/calendar` (tolerant nur bei gültigem VCALENDAR-Body) ·
ETag/Last-Modified + `If-None-Match`/`If-Modified-Since` + **304** · Feed-URL/ID nie in Fehlern.

## 4. RFC-5545-Parser

`ics-parser.ts` nutzt **`ical.js`** (Mozilla, MPL-2.0, **null** Laufzeit-Abhängigkeiten) – **keine**
naive Zeilentrennung. Unterstützt (17 Tests): Zeilenfaltung, Escaping, Parameter, `VTIMEZONE`, UTC,
TZID, floating (mit kontrollierter Fallback-Zeitzone), `VALUE=DATE` mit **exklusivem** `DTEND`,
`DTSTART`+`DURATION`, `RRULE`/`RDATE`/`EXDATE`, `RECURRENCE-ID` (verschoben/abgesagt), abgesagte
Events, `SEQUENCE`/`LAST-MODIFIED`, DST-Wechsel. **Netzwerkfunktionen des Parsers werden nicht
verwendet** – ihm wird nur der bereits geladene, größenbegrenzte Text übergeben.

- **Wiederholungen** werden **nur** im Zielzeitfenster expandiert. Eine Serie ist an ihrem `DTSTART`
  verankert und lässt sich nicht vorspulen, also muss der Iterator bis zum Fenster laufen. Deshalb
  greifen **zwei** getrennte Obergrenzen:
  - `PUBLIC_CALENDAR_MAX_OCCURRENCES_PER_EVENT` zählt nur Vorkommen **eines** Events, die das
    Fenster tatsächlich erreichen. Eine seit Jahren laufende Wochenserie wird dadurch normal
    expandiert, eine „recurrence bomb“ im Fenster (`FREQ=MINUTELY`) läuft weiterhin dagegen.
  - `PUBLIC_CALENDAR_MAX_SCANNED_OCCURRENCES` begrenzt die **Iterationsschritte des gesamten Laufs**
    inklusive der vor dem Fenster übersprungenen und stoppt damit eine Hochfrequenzserie, die lange
    **vor** dem Fenster beginnt.

  Beide Verletzungen enden in `recurrenceLimitExceeded` und sind nie destruktiv.

- **Ganztägig:** lokales Kalenderdatum, exklusives Enddatum, keine UTC-/Gerätezeitzonen-Verschiebung.
- **Datenminimierung:** `ATTENDEE`/`ORGANIZER`/`CONTACT`/`ATTACH`/Konferenz/Alarme/`X-*` werden
  **nie gelesen** → keine E-Mail-Adressen. `DESCRIPTION`/`LOCATION` nur bei entsprechendem
  Strapi-Flag, immer als **Plain Text** (nie HTML).

## 5. Strapi = Quelle, PostgreSQL = resilientes Read-Model

Strapi ist die kanonische redaktionelle Quelle. Der Worker spiegelt **validierte** Definitionen in
ein minimales operatives Read-Model (`PublicCalendar`), damit ein Kalender erst nach Validierung
**und** erstem erfolgreichen ICS-Sync erscheint und ein Strapi-Ausfall die öffentliche API nicht
lahmlegt. Eine fehlerhafte/leere/unvollständige Strapi-Antwort **löscht den letzten gültigen Katalog
nie**; erst ein vollständig erfolgreicher Abruf fügt hinzu/aktualisiert/deaktiviert. Roh-ICS wird
**nie** gespeichert.

## 6. Worker-Sync & Reconciliation (10 Integrationstests, echte DB)

- Getrennte Jobs `catalog` und `events`, per `PUBLIC_CALENDAR_ENABLED` schaltbar, eigener
  Overlap-Guard, unabhängig von Canteen/Timetable.
- Der Event-Job verarbeitet höchstens **vier Feeds gleichzeitig**. Die Katalogreihenfolge bleibt
  in den Ergebnissen erhalten; ein unerwarteter Fehler vor oder außerhalb eines normalen
  Feed-Laufs wird als isoliertes Fehlerergebnis erfasst und stoppt die übrigen Feeds nicht.
- Pro Kalender: SyncRun `running` → ICS laden (bytebegrenzt) → validieren → parsen → im Zielfenster
  expandieren → **Transaktion**: upsert + Löschen **nur** im bestätigten Fenster für nicht mehr
  gesehene `occurrenceKey` → Status/`lastSuccessfulSyncAt` setzen.
- **Gültiger leerer** Feed = erfolgreicher leerer Snapshot (kein Fehler).
- **Unveränderter Hash/304** = teure Parse-/Persistenzphase überspringen, Status/Zeitstempel trotzdem
  aktualisieren.
- **Temporärer Fehler** (Timeout/Netz/5xx/429): letzten Stand behalten, Kalender `stale`, weiter
  ausliefern.
- **Beschädigt/zu groß/Recurrence-Limit:** keine destruktive Übernahme; `stale` (mit Vorstand) bzw.
  `invalid` (ohne) — bei erstem Sync nicht öffentlich.
- **Freigabe entzogen** (404/410/403): Status `revoked`/`unavailable`, Termine gelöscht, aus dem
  öffentlichen Katalog entfernt.
- Jeder Feed-Lauf schreibt genau eine strukturierte Betriebsmetrik mit `status`, `durationMs`,
  UTF-8-genauen `responseBytes`, `errorClass` und Ergebniszählern. URL, Google-Kalender-ID,
  Kalender-Slug und Feed-Inhalte erscheinen nicht in diesen Logs. Die interne Zuordnung bleibt
  ausschließlich im geschützten `PublicCalendarSyncRun` der operativen Datenbank.

## 7. Campus API

- `GET /v1/calendars` — Katalog (nur aktive, valide, mind. einmal erfolgreich synchronisierte).
  DTO: `id, slug, channelSlug, name, colorHex, sortOrder, defaultSubscribed, dataState,
lastSuccessfulSyncAt, dataStale, googleOpenUrl`. `channelSlug` verknüpft einen Kalender
  1:1 mit einem redaktionellen Kanal (oder `null`). **Nie** Google-ID, Feed-URL,
  ETag oder interne Fehler.
- `GET /v1/calendars/:slug/events?from&to` — Termine eines Kalenders (Zeitraum begrenzt).
  Das Abfrageintervall ist als **Überlappung** definiert (`startsAt <= to AND endsAt >= from`).
- `GET /v1/calendars/events?calendar=…&calendar=…&from&to` — aggregiert; Slugs dedupliziert,
  begrenzt; **leere Auswahl ⇒ leere Liste** (nie „alle“); Überlappungsabfrage; pro Termin `calendarId`+`calendarSlug`;
  deterministisch sortiert; keine Live-/N+1-Abfrage.
- `GET /v1/calendars/google-view-url?calendar=…` — serverseitig konstruierte
  `calendar.google.com/embed`-URL (ein `src` je Kalender, `ctz`), nur aktive/öffentliche Kalender.

## 8. App

- **Kalender-Tab:** dynamische Quelle neben Stundenplan und Moodle. Öffentliche Termine erhalten
  einen Farbpunkt **plus** Kalendername/Icon (Farbe nie alleiniges Merkmal). Ein Fehler der
  öffentlichen Quelle blendet Stundenplan/Moodle **nicht** aus.
- **„Kalender verwalten“:** Y-aus-X-Auswahl lokal (SharedPreferences). `defaultSubscribed` greift
  **genau einmal** pro Slug (seen-Ledger); bewusst deaktivierte bleiben aus; verschwundene Slugs
  werden tolerant bereinigt; ein Backend-Update überschreibt die Auswahl nie; keine Auswahl ⇒ keine
  öffentlichen Termine.
- **Tageszuordnung:** Ein ganztägiger Termin nennt ein **Datum** und wird vom Worker als
  UTC-Mitternacht abgelegt; die App liest ihn genau so zurück, damit ihn keine Gerätezone
  verschiebt. Ein zeitgebundener Termin ist ein **Zeitpunkt** und wird vor der Tageszuordnung nach
  Ortszeit konvertiert. `DTEND` ist exklusiv: ein Termin, der um Mitternacht endet, erreicht den
  Folgetag nicht. Mehrtägige Termine — Prüfungszeitraum, vorlesungsfreie Zeit — erscheinen an
  **jedem** Tag, den sie berühren, in Tagesagenda, Wochenstreifen und Monatsraster. Im Zeitraster
  der Wochenansicht bleibt ein _zeitgebundener_ Termin in seiner Startspalte, weil ein Raster keine
  Box über zwei Spalten zeichnen kann; ganztägige Termine stehen dort im Band über dem Raster und
  spannen mit.
- **Google-Buttons:** „In Google Kalender öffnen“ (einzeln, `googleOpenUrl`) und „Ausgewählte in
  Google Kalender öffnen“ (kombinierte Embed-URL vom Backend), extern via `url_launcher`
  (HTTPS, Browser-Fallback). Kein automatisches Hinzufügen zum persönlichen Google-Konto; Stundenplan
  und Moodle sind keine Google-Quellen und nicht Teil der kombinierten Ansicht.

## 9. Strapi-Redaktionshandbuch

1. Strapi öffnen → **Public Calendar → Create an entry**.
2. **Name** (lokalisiert) und **Slug** (nur `a-z0-9-`, stabil, nach Veröffentlichung nicht mehr
   ändern) eintragen.
3. **googleShareUrl**: den **öffentlichen** Google-Freigabelink mit `cid` einfügen
   (`https://calendar.google.com/calendar/u/0?cid=…`). **Keine** geheime/private „iCal-Adresse“ und
   **keine** `basic.ics`-URL.
4. **colorHex** (`#RRGGBB`) und **sortOrder** wählen.
5. **defaultSubscribed** bewusst setzen (true = beim ersten Erscheinen automatisch aktiv).
6. **includeEventDescription** und **includeEventLocation** datensparsam entscheiden. Die Felder
   steuern ausdrücklich, ob Beschreibungen bzw. Orte importierter Termine in API und App erscheinen.
7. **Speichern und Veröffentlichen** (Draft & Publish).
8. Auf den **ersten erfolgreichen ICS-Sync** warten; danach erscheint der Kalender in `GET
/v1/calendars` und der App.
9. Bei Entzug der Freigabe: Eintrag deaktivieren (`isActive=false`) oder Freigabe klären.

Der serverseitige read-only Strapi-Token braucht **Leserechte** für veröffentlichte
`public-calendar`-Einträge. **Keine** öffentliche anonyme Strapi-Berechtigung aktivieren.

## 10. Veröffentlichungsrechte

Technisch öffentlich lesbar ≠ rechtlich frei weiterveröffentlichbar. Vor dem produktiven Eintrag
organisatorisch klären: Zustimmung des Inhabers, zulässiger Quellenhinweis, ob Beschreibung/Ort
gezeigt werden dürfen, Ansprechpartner, Verhalten bei Entzug. Teilnehmer-/Organizer-E-Mail-Adressen
werden **nie** übernommen oder veröffentlicht.

## 11. Konfiguration & Abhängigkeit

ENV (siehe `apps/backend/src/config/env.schema.ts`): `PUBLIC_CALENDAR_ENABLED` und der `PUBLIC_CALENDAR_*`-Block.
Standardparameter: Lookahead 400 Tage, API Max Range 400 Tage, Max Occurrences per Event 2000, Max Occurrences 25000.
Für DEV muss `PUBLIC_CALENDAR_ENABLED=true` gesetzt und der Strapi-Token mit Leserechten versehen
werden. Neue Abhängigkeit: **`ical.js@2.2.1` (MPL-2.0, keine transitiven Laufzeit-Deps)** — Bewertung
in [`legal/dependency-licenses.md`](legal/dependency-licenses.md).
