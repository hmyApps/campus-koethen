<!-- Campus Köthen App · AGPL-3.0-only · Copyright © 2026 Leviora Studio and Jona Loreen Sommer -->

# Moodle-Integration & quellenübergreifender Kalender

Zwei zusammenhängende Funktionen der mobilen App:

- **Moodle** (unter „Mehr → Moodle") — native, **lesende** Ansicht von Kursen, Materialien,
  Aufgaben mit Abgabestatus und Ankündigungen.
- **Kalender** (eigenes Modul, ersetzt den bisherigen Stundenplan-Tab) — führt Stundenplan,
  öffentliche Kalender und Moodle-Deadlines **lokal auf dem Gerät** zu einer Ansicht zusammen
  (Tag, Woche **oder** Liste).

Beide sind bewusst restriktiv gebaut. Maßgeblich ist die Ausnahmeregel in
[`../AGENTS.md`](../AGENTS.md) §2.

## 1. Datenfluss — direkt und nur zum Gerät

```
Flutter-App  ──HTTPS──▶  https://moodle.hs-anhalt.de
     │
     └── verschlüsselter lokaler Cache · Token nur im Keychain/Keystore
```

**Nie** über ein Campus-Köthen-Backend: Es gibt **keine** Campus-API-Route, **keine**
Strapi-Collection, **keinen** Worker-Job, **keine** DB-Tabelle und **keinen** Proxy für persönliche
Moodle-Daten. Weder Moodle-Benutzername, Passwort, Web-Service-Token, Nutzer-ID, Kursnamen,
Mitgliedschaften, Materialien, Aufgaben, Abgabestatus, Noten, Ankündigungen noch Deadlines
verlassen das Gerät in Richtung eines Dienstes dieser App.

## 2. Authentifizierung

1. `POST https://moodle.hs-anhalt.de/login/token.php` (form-urlencoded: `username`, `password`,
   `service=moodle_mobile_app`) → Token.
2. **Vor** dem Speichern: `core_webservice_get_site_info` verifiziert das Token und liefert die
   Nutzer-ID. Erst danach wird das Token abgelegt; der Moodle-Dienststore speichert das Passwort
   **nie**. Wenn die Person den optionalen zentralen Hochschulzugang ausdrücklich aktiviert hat,
   kann dasselbe Passwort getrennt davon im gerätegebundenen Keychain/Keystore liegen. Das ist eine
   lokale Eingabehilfe und keine Moodle- oder SSO-Sitzung.
3. Alle weiteren Aufrufe: `POST .../webservice/rest/server.php` mit `wstoken`, `wsfunction`,
   `moodlewsrestformat=json`.

Nur eine feste, **rein lesende** Whitelist von `wsfunction`s wird angebunden (u. a.
`core_course_get_enrolled_courses_by_timeline_classification`, `core_course_get_contents`,
`mod_assign_get_assignments`,
`mod_assign_get_submission_status`, `mod_forum_*`, `core_calendar_get_action_events_by_timesort`).
Es gibt **keine** Schreibfunktion und **keine** generische „beliebige Funktion aufrufen"-Schnittstelle.

## 3. Zentrale, nicht umgehbare Host-/Token-Policy

Umgesetzt in [`../apps/mobile/lib/features/moodle/data/moodle_http_client.dart`](../apps/mobile/lib/features/moodle/data/moodle_http_client.dart)
und im Datei-Downloader:

- **Nur HTTPS**, **nur** Host `moodle.hs-anhalt.de` (`MoodleProfile.allows`), vor jedem Request geprüft.
- Kein Zertifikats-Ausnahme, keine deaktivierte Hostname-Prüfung.
- **Redirects werden nie mit Token verfolgt** — ein `3xx` wird abgelehnt (`tlsOrHostRejected`), das
  Token kann nicht an einen anderen Host weitergereicht werden.
- Token reist im **POST-Body**, nie im Query-String.
- Moodle liefert Fehler oft als HTTP 200 mit `exception`-Objekt — das wird erkannt und auf einen
  klassifizierten Fehler abgebildet.
- In Fehlern, Logs oder Crashreports landen **kein** Token, Passwort, keine vollständige URL und
  keine vollständige Moodle-Antwort — nur die Fehlerklasse (`MoodleFailureKind`).

**Externe Links** aus Moodle (z. B. `url`-Module) werden über `SafeLinkLauncher` geöffnet: nur
`https`, **ohne** Token, unbekannte Schemata werden abgelehnt.

## 4. Datei-Download (nur bei Bedarf)

- Dateien werden **erst beim Öffnen** geladen, nie vorgeladen.
- Nur wenn die finale URL HTTPS auf `moodle.hs-anhalt.de` ist, wird das Token (im POST-Body)
  angehängt.
- Zentrale In-Memory-Obergrenze `kMaxInMemoryPreviewBytes` (25 MB); die deklarierte Größe wird
  vorab respektiert, ein zu großer Stream bricht mit `fileTooLarge` ab.
- Abbruch/Fehler verwerfen den Teil-Download vollständig (nichts landet auf der Platte).
- Zu große oder nicht darstellbare Dateien erhalten eine sichere Alternative (Teilen/Öffnen) über
  den geteilten `DocumentViewerScreen`.

## 5. Verschlüsselter Cache & Sync-Policy

- Persönliche Moodle-Daten liegen nur **verschlüsselt** lokal (`EncryptedMoodleCache` über die
  geteilte `EncryptedBox`: 256-Bit-Schlüssel im Secure Storage — dieselbe Krypto-Infrastruktur wie
  bei den Noten, keine zweite Implementierung).
- **24-Stunden-Rolling-Sync:** lazy beim Öffnen, höchstens **ein** automatischer Versuch pro
  rollenden 24 h, **kein** Hintergrund-Timer/Polling. Gleichzeitige Aufrufe werden zu einem
  Netzaufruf zusammengeführt (Single-Flight). Ein fehlgeschlagener Auto-Versuch wird nicht bei jedem
  Rebuild wiederholt (`lastAttempt` wird vorab gesetzt). `lastAttempt` und `lastSuccess` werden
  getrennt geführt; nur ein **vollständig validierter** Erfolg ersetzt den Cache.
- Manuelles Aktualisieren (in Moodle **und** im Kalender sichtbar) umgeht die 24-h-Sperre, bleibt
  aber Single-Flight.
- Eine ungültige/unbekannte Antwort **löscht nie** den letzten guten Cache. Eine gültige leere
  `inprogress`-Kursliste ist dagegen maßgeblich und entfernt Kurse, die Moodle nicht mehr als
  aktuell einstuft; eine leere Deadline-Antwort behält weiterhin den letzten guten Bestand.

**„Moodle-Verbindung und lokale Daten löschen"** entfernt Token, Nutzer-ID, verschlüsselten Cache,
Cache-Schlüssel, Sync-Zeitstempel und alle zugehörigen Riverpod-Zustände. Ein optionaler zentraler
Hochschulzugang bleibt erhalten; seine Komplettlöschung ist eine separate, ausdrücklich bestätigte
Aktion in den Einstellungen.

## 6. Quellenübergreifender Kalender

- Der **Stundenplan** (über die Campus API) ist die **erste** Kalenderquelle, **Moodle-Deadlines**
  (direkt) die zweite. Zusammengeführt wird **ausschließlich lokal** in
  [`../apps/mobile/lib/features/calendar/application/calendar_merge.dart`](../apps/mobile/lib/features/calendar/application/calendar_merge.dart).
- **Isolierte Quellen:** Ein Moodle-Fehler beeinträchtigt die Stundenplan-Ansicht nicht; ein
  Campus-API-Fehler entfernt die lokal zwischengespeicherten Moodle-Deadlines nicht. Jede Quelle
  trägt unabhängig bei; Fehler werden pro Quelle als Banner angezeigt.
- **Erweiterbar:** Eine neue Quelle = ein Wert in `CalendarSource`, ein Mapper nach `CalendarEntry`
  und eine Verdrahtung im Aggregator.
- Explizite Umschaltung **Tag ↔ Woche ↔ Liste**. Moodle-`timestart` sind absolute Unixzeiten und
  werden ohne doppelte Zeitzonen-Konvertierung umgerechnet.
- Die Moodle-Quelle wird über das Quellen-Control „Moodle" ein- und ausgeblendet. Ohne Anmeldung
  erklärt dessen Sheet das und führt zum Moodle-Login; es werden **keine** Moodle-Daten an ein
  Campus-Köthen-Backend gesendet.

## 6a. Kurssuche und Kursansicht

Die Kursübersicht lädt ausschließlich Moodles Timeline-Klassifizierung **`inprogress`**. Das ist
dieselbe serverseitige Auswahl wie in der Kursübersicht von Moodle Web; vergangene, zukünftige und
vom Nutzer dort ausgeblendete Kurse erscheinen deshalb auch in der App nicht.

Die Kursübersicht hat einen **lokalen** Suchknopf. Er filtert ausschließlich die bereits
geladenen beziehungsweise im verschlüsselten Cache liegenden Kurse — **kein Tastendruck
erzeugt eine Anfrage**, weder an Moodle noch an ein Campus-Köthen-Backend, das Moodle-Daten
ohnehin nie sehen darf.

Durchsucht werden `fullName`, `shortName` und `summary`. Die Normalisierung
(`moodle_course_search.dart`) macht Groß-/Kleinschreibung, die deutschen Umlaute und die
gängigen lateinischen Diakritika gleichwertig: „Prüfung", „PRUEFUNG" und „prufung" finden
einander. Ein leeres Suchfeld ist kein Filter; Schließen der Suche leert den Begriff, damit
ein vergessener Filter nicht dauerhaft Kurse verbirgt. Ohne Treffer erscheint ein eigener
leerer Zustand mit dem Hinweis, dass nur geladene Kurse durchsucht werden.

Die Kursansicht behält die drei Tabs **Inhalte**, **Aufgaben** und **Ankündigungen**. Die
TabBar ist `isScrollable`, weil drei gleich breite Drittel eines 320 px breiten Telefons
„Ankündigungen" bei großer Schrift nicht fassen — und eine Abkürzung, die niemand entziffert,
ist schlechter als eine Wischgeste. Widgettests prüfen beides bei 320 px und doppelter
Schrift.

## 7. Fehlerklassen

`invalidCredentials`, `tokenRejected`, `tokenExpired`, `networkUnavailable`, `timeout`,
`tlsOrHostRejected`, `serviceUnavailable`, `permissionDenied`, `invalidResponse`,
`unsupportedModule`, `secureStorageUnavailable`, `cacheUnavailable`, `fileTooLarge`,
`downloadFailed`, `unknown` — jeweils mit vollständigen DE/EN-Texten, ohne sensible Details.

## 8. Tests

Alle Tests laufen gegen **synthetische Fixtures** mit fiktiven Kursen („Beispielkurs Informatik",
„Musterseminar", „Übungsblatt 1"). Es gibt **keine** echten Moodle-Aufrufe und **keine** echten
Zugangsdaten/Token/Kursdaten im Repository. Sicherheitskritische Pfade (Host-/Token-Policy,
Redirect-Ablehnung, Größenlimit, „leere Antwort löscht Cache nicht", 24-h-Policy, Kalender-Merge)
sind durch Unit-Tests abgesichert.
