# AGENTS.md — Verbindliche Regeln für die Arbeit an diesem Repository

Projekt: **Campus Köthen App** · Lizenz: **AGPL-3.0-only** · `Copyright © 2026 Leviora Studio and Jona Loreen Sommer`

Diese Datei ist für automatisierte und menschliche Beiträge gleichermaßen verbindlich.

---

## 1. Projektidentität — nicht verhandelbar

- Sichtbarer App-Name: **Campus Köthen**. Technische Kennungen: Android-`applicationId`
  `erikengler.campuskoethen` (Kotlin-Namespace `dev.erikengler.campuskoethen`), iOS-Bundle-ID
  `campus-koethen` (Widget `campus-koethen.CampusCalendarWidget`). Diese Store-Kennungen werden
  nicht geändert — eine neue Kennung wäre im Store eine neue App ohne Update-Pfad.
- Das Projekt ist **unabhängig und inoffiziell**. Es darf an keiner Stelle den Eindruck einer
  offiziellen Anwendung der Hochschule Anhalt erwecken.
- **Verboten:** Logos, Wappen, geschützte Markenassets, kopierte Designsysteme der Hochschule;
  Formulierungen wie „offizielle App“, „HSA-App“ oder „von der Hochschule“.
- **Erlaubt:** sachliche Nennung von Hochschul- und Einrichtungsnamen zur Quellen- oder
  Bereichszuordnung.
- Der Unabhängigkeitshinweis muss in Deutsch **und** Englisch in README, `docs/product/mvp.md`,
  dem About-Screen und den rechtlichen Seiten stehen. Kanonische Fassung:
  `apps/mobile/lib/l10n/app_de.arb` / `app_en.arb`, Schlüssel `aboutIndependenceNotice`.
- Die App wird von Erik Engler, handelnd unter „Leviora Studio“, entwickelt und über die App
  Stores bereitgestellt. Betreiberin des Campus-Backends und Herausgeberin der redaktionellen
  Inhalte ist die **Studierendenschaft der Hochschule Anhalt**, Körperschaft des öffentlichen
  Rechts, vertreten durch den Sprecherrat des Studierendenrates. Die Hochschule Anhalt selbst
  bleibt von beiden Rollen getrennt; Campus Köthen ist keine offizielle Hochschul-App.

## 2. Systemgrenzen — Architekturverstöße sind Blocker

1. Öffentliche, redaktionelle und allgemeine Campusdaten laufen **ausschließlich** über die
   Campus API unter `/v1`. Kein direkter Zugriff auf Strapi oder `meine-mensa.de` aus der App.

   **Eng begrenzte, ausdrücklich beschlossene Ausnahme (nur diese):** Persönliche, besonders
   sensible Dienste dürfen aus Datenschutzgründen **direkt** vom Gerät an den jeweiligen
   offiziellen Anbieter angebunden werden, damit weder Campus-Backend noch Strapi Zugangsdaten
   oder personenbezogene Inhalte erhalten. Aktuell sind das **genau sechs**:
   - der **Studenten-Mailclient** → direkt zu `mail.hs-anhalt.de` (IMAPS/SMTP; ausschließlich für
     die authentifizierte Empfängersuche EWS `ResolveNames` am festen HTTPS-Endpunkt
     `https://mail.hs-anhalt.de/EWS/Exchange.asmx`, kein Autodiscover und keine beliebigen
     EWS-Operationen; sowie ausschließlich nach ausdrücklichem Opt-in lesender
     Exchange-Kalenderzugriff über exakt denselben Endpunkt). Der EWS-Kalender darf nur Betreff,
     Beginn, Ende, Ganztags-/Absagestatus und Ort des eigenen Standardkalenders abfragen; keine
     Bodies, Teilnehmerlisten, Schreiboperationen oder Redirects. Termine bleiben im regulären
     Betrieb flüchtig im Arbeitsspeicher und werden ausschließlich lokal mit den anderen
     Kalenderquellen vereinigt. Sie dürfen weder in den persistenten Homescreen-Widget-Payload
     noch in geplante Betriebssystem-Benachrichtigungen gelangen. Nur ein vom Nutzer bewusst
     ausgelöster ICS-Export darf die aktuell geladenen Termine an ein vom Nutzer gewähltes Ziel
     übergeben;
   - der **Notenspiegel** → direkt und **nur** zu genau dem Host des Portals, auf dem das
     jeweilige Konto eingerichtet wurde. Die Hochschule Anhalt betreibt zwei Prüfungsportale
     parallel; jedes hat seine EIGENE, getrennte Host-Allowlist (kein gemeinsamer Pool):
     `https://service.ssc.hs-anhalt.de` (HIS-QIS, Bestandsportal) und
     `https://sscportal.ssc.hs-anhalt.de` (HISinOne, neueres Portal und Standard). Welches Portal
     ein Konto nutzt, wird bei der Einrichtung einmalig ermittelt (`docs/grades.md`
     „Portalwahl", HISinOne zuerst) und lokal gespeichert; ein Konto ohne gespeicherte Wahl
     wechselt einmalig auf HISinOne.
     Dieselbe HISinOne-Verbindung (für Login, Seiten und Formularaktionen **ausschließlich**
     `https://sscportal.ssc.hs-anhalt.de`, **nicht** das HIS-QIS-Bestandsportal) erweitert um
     konkret benannte, ausschließlich
     **lesende** Funktionen auf der Seite „Studienservice" (ein Formular, Tab-Wechsel per
     Voll-POST): Bescheinigungsübersicht, Personendaten und Kontaktdaten, Studiengangsübersicht
     sowie die nur über die Zahlungsübersicht ableitbaren Status-Hinweise (Hörerstatus unter
     Personendaten; ein Rückmeldestatus existiert nicht als eigenes Feld, nur indirekt über
     offene/keine offenen Zahlungen); zusätzlich um den Abruf der auf der Notenübersichtsseite
     selbst angebotenen drei festen Bescheinigungen (Leistungsübersicht bestandener Leistungen
     auf Deutsch und Englisch, Übersicht fehlender Leistungen) über deren eigene Druck-Buttons —
     eine normale volle Formularabgabe, kein AJAX-Auftrag, kein Polling. Diese Funktionen nutzen
     dieselben, bereits für den Notenspiegel hinterlegten Zugangsdaten wieder — kein zweiter
     Login, kein separater `+`/`−`-Dienst. Der erzeugte Bescheinigungsabruf — ob aus dem
     Studienservice-Auftrag oder aus einem Notenübersicht-Druck-Button — ist zweistufig: zuerst
     ausschließlich per `GET` an `https://sscportal.ssc.hs-anhalt.de/qisserver/rds` mit exakt
     `state=docdownload`, danach folgt ein serverseitiger Redirect auf denselben Pfad und
     Zustand, aber auf die **separate** Origin `https://untrust-sscportal.ssc.hs-anhalt.de`
     (bestätigt 2026-10-04 durch einen echten `Location`-Header eines abgeschlossenen Auftrags,
     zusätzlich durch den `Content-Security-Policy`-Header des Portals selbst belegt, der genau
     diesen Host unter `child-src` listet). Ziel und Einweg-Token für beide Stufen müssen aus der
     jeweils aktuellen AJAX-Antwort beziehungsweise dem Formular-Redirect stammen, und diese enge
     Pfad-/Parameter-Prüfung auf genau diesen zwei Hosts ist **keine** gemeinsame oder allgemeine
     Allowlist.
     Erlaubte Formularaktionen sind nur Login, Studienservice-Tabwechsel, Start und Polling der
     vom Nutzer gewählten Studienservice-Bescheinigung, sowie das Absenden genau eines der drei
     festen Bescheinigungs-Buttons auf der Notenübersichtsseite. **Ausdrücklich ausgeschlossen**
     bleibt jede Änderung
     des Hochschul-Datensatzes: keine Prüfungsanmeldung, keine Adressänderung und kein Antrag.
     Eine unbekannte oder unerwartete Seitenstruktur erhält einen klassifizierten Fehler und wird
     **nie** geraten geparst;
   - die **Moodle-Integration** (Kurse, Materialien, Aufgaben, Ankündigungen, Deadlines) →
     direkt und **nur** zu `https://moodle.hs-anhalt.de`. Kein Moodle-Token, keine Kurs-,
     Aufgaben-, Abgabe-, Ankündigungs- oder Deadline-Daten dürfen ein Campus-Köthen-Backend
     erreichen. Der quellenübergreifende Kalender führt Stundenplan (Campus API),
     Moodle-Deadlines und optional Exchange-Termine **ausschließlich lokal auf dem Gerät**
     zusammen.
   - der **Nextcloud-Dateiexplorer** → direkt und **nur** zur exakten Origin
     `https://cloud.hs-anhalt.de`. Die Anmeldung erfolgt ausschließlich über Nextcloud Login Flow
     v2 im Systembrowser; Campus Köthen erhält und übermittelt dabei nie das zentrale
     Hochschulpasswort. Das ausgegebene App-Passwort, `loginName` und die für WebDAV ermittelte
     Nutzer-ID liegen ausschließlich im gerätegebundenen Keychain/Keystore. Verzeichnislisten und
     geladene Dateien bleiben flüchtig im Arbeitsspeicher und werden nicht in Hive,
     SharedPreferences oder einem Campus-Backend gespeichert. Erlaubt sind nur Login Flow v2,
     die OCS-Abfrage des eigenen Benutzerprofils, der Widerruf des eigenen App-Passworts sowie
     WebDAV-Aufrufe unter `/remote.php/dav/files/{eigene Nutzer-ID}`. Schreibzugriffe sind eng
     begrenzt auf bewusst ausgelöste Uploads ohne stilles Überschreiben und bestätigtes Löschen;
     ein Ordner-DELETE muss ausdrücklich auf die rekursive Wirkung hinweisen. Nach separater
     Bestätigung darf die OCS-Share-API einen nur lesbaren öffentlichen Link (`shareType=3`,
     `permissions=1`) erzeugen. Der Link bleibt flüchtig, wird nie geloggt oder persistiert und
     darf nur an das OS-Share-Sheet übergeben werden. Keine Umbenennungen, Verschiebungen,
     Hintergrundmutationen oder frei konfigurierbaren Nextcloud-Server. `−` versucht den
     serverseitigen Widerruf und löscht die lokale Berechtigung auch dann verifiziert, wenn der
     Server nicht erreichbar ist. Details: [`docs/nextcloud.md`](docs/nextcloud.md).
   - die **Antragstellung und das Feedback** (Finanzanträge und Rückmeldungen an das Gremiensystem
     des Studierendenrats) → direkt an dessen öffentliche API. Anders als die vier anderen ist
     dieser Dienst **nicht** nutzerauthentifiziert; ausschlaggebend ist der Inhalt: Eine
     Einreichung trägt den Namen der antragstellenden Person und eine **Kopie des
     Studierendenausweises**. Genau solche Daten sollen kein Campus-Köthen-Backend erreichen,
     weshalb hier dieselbe Begründung greift wie bei den übrigen vier. Die Adresse ist **nie**
     eine Quellcode-Konstante, sondern kommt als `REQUESTS_BASE_URL` aus dem Build-Environment
     und muss **HTTPS** sein; daraus entsteht eine exakte Origin-Allowlist. Der zurückgegebene
     **Statuslink ist ein Geheimnis** — er ist der einzige Zugang zum Vorgang, wird verschlüsselt
     lokal gespeichert und **niemals** geloggt, gemeldet, kopiert, allgemein geteilt oder in eine
     App-Route aufgenommen. Ausschließlich nach der bewussten Aktion „Zum Antrag“ darf der zuvor
     gegen die exakte `REQUESTS_BASE_URL`-Origin validierte Statuslink an den externen Browser
     übergeben werden; fremde Origins werden abgewiesen. Dasselbe Geheimhaltungsniveau gilt für
     die Quittungs- und Dokument-Links, die denselben Token tragen. Der native Statusabruf erfolgt
     **ausschließlich** per `POST` mit dem Link im JSON-Body, nie über einen Query-Parameter.
     Entwürfe, Anhänge und Ergebnis bleiben auf dem Gerät.
     Details: [`docs/requests.md`](docs/requests.md).
   - der **HSA-GPT-Chat** (HAWKI, der KI-Dienst der Hochschule Anhalt) → direkt und **nur** zu
     `https://ki.hs-anhalt.de`. Anmeldung erfolgt mit denselben, bereits hinterlegten
     Hochschulzugangsdaten über HAWKIs Web-Login (`GET /login`, `POST /req/login`, danach
     `/logout`); das Passwort wird dabei einmalig verwendet, um über HAWKIs eigene
     Profilfunktion (`POST /req/profile/create-token`) ein persönliches, jederzeit über
     `POST /req/profile/revoke-token` widerrufbares Sanctum-API-Token zu erzeugen. Gespeichert wird
     ausschließlich dieses Token, **niemals** das Passwort. Jede weitere Aktion — Modell-Liste
     (`GET /api/hawki/v1/ai-models`) und Chat-Anfrage (`POST /api/ai-req`; HAWKI registriert diese
     Route ohne `/hawki/v1`-Präfix, am 2026-10-06 gegen die Live-Instanz bestätigt) — läuft
     ausschließlich mit diesem Bearer-Token gegen HAWKIs eigene, zustandslose externe API; der
     Chatverlauf besteht nur im Arbeitsspeicher der App, solange die Ansicht offen ist, und wird
     nie an ein Campus-Köthen-Backend gesendet oder dort gespeichert. Kein Zugriff auf HAWKIs
     interne SSE-Streaming-Route, kein E2EE-/Passkey-Schema dieses Diensts, keine Prompt- oder
     Antwortinhalte in Logs. Das im Quellbaum liegende Modul
     `apps/mobile/lib/features/hsa_ki/crypto/` (HAWKIs E2EE-Schema, mit Tests) ist von keinem
     Produktionscode importiert und wird nicht angebunden, solange diese Regel gilt. HSA-GPT ist
     derzeit in „Mehr“ vorübergehend deaktiviert, weil `ki.hs-anhalt.de` noch HAWKI 2.4.0 ohne die
     benötigte Modell-API betreibt. HSA-GPT bekommt einen eigenen, expliziten Zustimmungsbildschirm
     statt einer Checkbox im allgemeinen Ersteinrichtungs-Assistenten, da die Verbindung direkt vom Gerät
     erfolgt und die Antworten HAWKIs eigene sind, nicht die von Campus Köthen.

   Für diese Ausnahmen gilt: **kein** Backend-Proxy, **keine** serverseitige Speicherung, **kein**
   Analytics-/Logging-Umweg. Zugangsdaten nur im Keychain/Keystore, sensible Inhalte nur
   verschlüsselt lokal. Dies ist **keine** allgemeine Erlaubnis für beliebige direkte
   Drittanbieterzugriffe — jede weitere Ausnahme muss hier ausdrücklich ergänzt werden.

   Die optionale zentrale `UniversityIdentity` ist ausschließlich eine **lokale Eingabehilfe** für
   Mail, Moodle, Noten und HSA-GPT — **keine** gemeinsame SSO-Sitzung und kein App-/Backend-Konto.
   Nextcloud verwendet unabhängig davon ausschließlich den Browser-basierten Login Flow v2. Die
   Identität enthält genau **eine Kennung** (Benutzername oder vollständige Mailadresse) und ein
   Passwort, wird erst nach ausdrücklicher Bestätigung und erfolgreicher Prüfung durch mindestens
   einen Dienst gespeichert und liegt nur im gerätegebundenen Keychain/Keystore. Ein reiner
   Benutzername wird ausschließlich für Mail zu `<Kennung>@hs-anhalt.de` ergänzt; eine eingegebene
   Mailadresse bleibt unverändert, Moodle, Noten und HSA-GPT erhalten die Kennung unverändert. Das
   frühere Drei-Feld-Schema wird
   beim Erkennen vollständig verworfen, nie still migriert. `+` erzeugt nach bewusster Nutzeraktion
   ausschließlich die dienstbezogene Session beziehungsweise Credential-Kopie; `−` wischt nur
   diesen Dienst und seinen
   Cache, nicht die zentrale Identität. Ein Kontowechsel (andere Kennung) verbindet ausschließlich
   den Dienst, mit dem das neue Konto geprüft wurde; jeder zuvor verknüpfte Dienst wird getrennt
   und erst nach erneutem `+` des Nutzers mit dem neuen Konto verbunden, HSA-GPT nur über seinen
   Zustimmungsbildschirm. Eine reine Passwortänderung derselben Kennung erhält die bestehenden
   Verknüpfungen und verbindet sie mit dem neuen Passwort neu. „Hochschulzugang vollständig löschen“ trennt alle Dienste
   über deren kanonische Wipes und löscht die zentrale Identität **zuletzt**; bei einem Teilfehler
   bleibt sie für den sichtbaren, wiederholbaren Retry erhalten. Kein Wert daraus darf in
   `SharedPreferences`, Hive, öffentlichen Riverpod-State, Campus API, Logs oder Telemetrie gelangen.

   **Öffentliche Google-Kalender** sind dagegen **öffentliche** Campusdaten und laufen bewusst über
   den **öffentlichen** Backend-Pfad: Der Campus-Worker liest die in Strapi gepflegte öffentliche
   Freigabe, konstruiert daraus **selbst** den festen öffentlichen ICS-Feed
   (`https://calendar.google.com/calendar/ical/{ID}/public/basic.ics`), lädt und normalisiert ihn
   und speichert die Termine in PostgreSQL; die App liest sie über die Campus API. **Kein** Google
   API Key, **kein** Google-OAuth, **kein** Google-SDK, **keine** Anbindung persönlicher
   Google-Konten. Die App ruft den ICS-Feed **nie** direkt ab. Feed-URL, ETag, `lastContentHash`
   und `ownerContact` bleiben backendintern. Die öffentliche Google-Kalender-ID ist kein
   eigenständiges DTO-Feld; sie darf ausschließlich innerhalb serverseitig erzeugter
   `googleOpenUrl`- beziehungsweise `src`-Parameter an die App gelangen, weil die Links zum Öffnen
   in Google ohne sie nicht funktionieren. Die Zusammenführung mit dem Stundenplan (Campus API)
   den Moodle-Deadlines sowie optionalen Exchange-Terminen (direkt) geschieht weiterhin
   **ausschließlich lokal** in Flutter. Details:
   [`docs/public-calendars.md`](docs/public-calendars.md).

   **Selbst erstellte, versionierte Assets** sind von dieser Regel nicht berührt: Kartengeometrie
   und der daraus generierte Raumkatalog (`packages/campus-map` → `apps/mobile/assets/maps`) liegen
   als geprüfte Dateien **im Repository** und werden mit der App gebündelt. Sie werden zur Laufzeit
   **nie** über das Netz geladen, nie aus Strapi bezogen und nie aus einer fremden Quelle
   nachgeladen. Das ist **keine** Erlaubnis, öffentliche Drittanbieterdaten direkt in die App zu
   holen — solche Daten laufen weiterhin ausnahmslos über die Campus API. Raumbezeichnungen und
   redaktionelle Raumtexte sind genau solche Daten und kommen daher über `/v1/rooms`.
   Reale Gebäudepläne dürfen erst nach geklärter Herkunft, Bearbeitungs- und
   Veröffentlichungsberechtigung aufgenommen werden. Details: [`docs/campus-map.md`](docs/campus-map.md).

2. Das Backend liest Strapi **ausschließlich** über dessen REST-API mit einem serverseitigen
   Read-only-Token. Kein direkter Zugriff auf Strapi-Tabellen, keine gemeinsame Prisma-Verbindung.
3. Redaktionelle Inhalte leben in Strapi. Importierte Mensadaten und Sync-Zustände leben in der
   operativen PostgreSQL-Datenbank. Getrennte Datenbanken, getrennte Rollen.
4. Die Strapi-Adresse kommt aus `STRAPI_BASE_URL`. Einzige Ausnahme im Quellcode: Fehlt die
   Variable ganz, setzt das Env-Schema des Backends den lokalen Entwicklungswert
   `http://127.0.0.1:1337`. Alle Compose-Umgebungen (lokal, Test, Produktion) setzen
   `STRAPI_BASE_URL` beziehungsweise `BACKEND_STRAPI_BASE_URL` explizit.
5. DEV und PROD unterscheiden sich **nur** durch Environment/Secrets, nie durch Quellcode.
6. Strapi stellt **keine** unauthentifizierte Content-API bereit. Das Plugin `users-permissions`
   ist bewusst nicht installiert; dadurch existiert keine versehentlich freischaltbare Public
   Role. Die Campus API nutzt ein eigenes minimales Read-only-Token. Wird das Plugin wieder
   aufgenommen, muss erneut eine Laufzeitprüfung der Public Role eingeführt werden; der Test
   `apps/cms/test/no-public-role-plugin.test.ts` schützt diese Grenze.

## 3. Sicherheit

- **Niemals** reale Tokens, Passwörter, SSH-Schlüssel oder private Kontaktdaten in Code, Tests,
  Fixtures, Images, Commits, CI-Logs oder Dokumentation.
- `.env` ist ignoriert; gepflegt wird ausschließlich `.env.example` mit Platzhaltern.
- Strukturierte JSON-Logs ohne Secrets und ohne personenbezogene Debug-Dumps.
- CORS kommt aus dem Environment. Keine Wildcard in Produktionskonfiguration.
- PostgreSQL wird nie öffentlich gebunden.
- Container laufen als **non-root**.
- Drittanbieter-Actions in GitHub Actions werden auf vollständige Commit-SHAs gepinnt.
- Kein automatisches Deployment, kein SSH aus CI, keine Server-Secrets im Repository.

## 4. Datenintegrität

- Externe Antworten werden **immer** explizit validiert, bevor sie verarbeitet werden: in den
  TypeScript-Diensten gegen Zod-Schemas, in Flutter über die typisierten Parser und Validatoren
  der jeweiligen Integration.
- Eine leere, ungültige oder fehlgeschlagene Drittantwort **löscht niemals** den letzten
  erfolgreichen Datenbestand. Dieser Punkt ist durch Tests abgesichert.
- Geldwerte sind `Decimal`, niemals `float`.
- Upserts laufen über stabile Quell-IDs (`sourcePlanId`), nicht über zusammengesetzte Heuristiken.
- `food.image_url` wird **weder gespeichert noch ausgeliefert**. Es werden keine Mensabilder verwendet.

## 5. Inhalte und Urheberrecht

- Die Redaktion schreibt eigene Beiträge oder eigene Zusammenfassungen **mit Quellenlink**.
  Keine vollständige Übernahme fremder Texte.
- Nur eigene oder nachweislich freigegebene Bilder.
- Keine erfundenen Personen, Telefonnummern, E-Mail-Adressen oder offiziellen Aussagen — auch
  nicht in Seeds, Fixtures oder Tests. Demo-Daten werden **eindeutig als Demo markiert**.
- Fixtures aus Drittquellen werden anonymisiert.

## 6. Internationalisierung

- Unterstützte Locales: `de`, `en`. Standard und Fallback: `de`.
- Flutter: `gen_l10n` mit ARB-Dateien. **Keine sichtbaren UI-Texte im Dart-Code hardcodieren.**
- Strapi: offizielle i18n-Funktionen. Stabile Slugs/IDs laufen nicht pro Locale auseinander.
- Campus API: `locale=de|en`, optional `Accept-Language`. Antwort-Metadaten enthalten
  `requestedLocale`, `resolvedLocale` und `translationFallback`.
- **Externe Mensa-Gerichtsnamen werden niemals maschinell übersetzt.** Liefert die Quelle nur
  Deutsch, bleibt der Quelltext erhalten und wird transparent als Fallback markiert.
  API-eigene Labels (Mensanamen, Preisgruppen, Marker, Fehlertexte) sind zweisprachig.

## 7. Technische Standards

- TypeScript **strict**. Kein `any` ohne begründeten, kommentierten Ausnahmefall.
- Node.js 24.x, repositoryweit exakt über `.node-version` und `.nvmrc` gepinnt. pnpm-Workspace
  mit Lockfile; `--frozen-lockfile` in CI.
- Öffentliche DTOs leaken **keine** Strapi-Internas (`data`, `attributes`, `documentId`,
  `populate`-Metadaten) und keine internen Fremd-IDs wie WebUntis-IDs, `location_id` oder eine
  Google-Kalender-ID als eigenständiges Feld. Bewusste, in `docs/api.md` dokumentierte Ausnahme:
  Mensa-Gerichte tragen als `id` die Gericht-ID und als `counterId` die Ausgabestellen-ID von
  meine-mensa. Die App behandelt `id` als undurchsichtige Zeichenkette und nutzt `counterId` nicht.
- Query-Parameter werden validiert und begrenzt (insbesondere `pageSize` und Datumsbereiche).
- Flutter: Riverpod, go_router, dio, `hive_ce` für den Inhaltscache.
  `SharedPreferences` **nur** für kleine skalare Einstellungen — kein JSON-Großspeicher.
- Design-Tokens sind zentral und typisiert. **Keine verstreuten Hexwerte in Screens.**

## 8. Arbeitsweise

- **TDD für fachlichen Code:** fehlschlagenden Test schreiben → Fehler real bestätigen →
  minimal implementieren → grün machen → refaktorieren.
- Integrationstests, Benchmarks und destruktive Prisma-Operationen laufen **ausschließlich** gegen
  eine ausdrücklich konfigurierte, isolierte temporäre PostgreSQL-Datenbank — niemals gegen die
  lokale Entwicklungsdatenbank. Temporäre Testdatenbanken werden nach der Prüfung entfernt.
- Kleine, verständliche Commits pro abgeschlossenem Arbeitsschritt.
- Keine Force-Pushes, kein Rebase veröffentlichter Historie.
- Nichts als erledigt melden, was nicht real ausgeführt und verifiziert wurde.
- Vor einem Push müssen alle lokal ausführbaren Gates aus dem README grün sein.

## 9. Barrierefreiheit

- Ausreichende Kontraste in Light **und** Dark Theme.
- Dynamische Schriftgrößen, Screenreader-Semantics, große Touch-Ziele (>= 48dp).
- Zustände werden **nie** ausschließlich über Farbe unterschieden.

## 10. Bekannte offene technische Entscheidungen

Diese Platzhalter dürfen nicht durch erfundene Werte ersetzt werden. Die vollständige und
aktuelle Liste aller organisatorischen, rechtlichen, datenquellenbezogenen und technischen
Release-Gates steht in `README.md` und `docs/product/mvp.md`:

- SMTP · Offsite-Backups

Geklärt sind die PROD-Domains: Campus API `https://campus-koethen-api.sturahsa.de`, Strapi
`https://koethen-cms.sturahsa.de`, Antragsportal (`REQUESTS_BASE_URL`) `https://antrag.sturahsa.de`.
Sie bleiben Build- beziehungsweise Deployment-Environment und werden nicht als Konstanten in den
Quellcode übernommen.
