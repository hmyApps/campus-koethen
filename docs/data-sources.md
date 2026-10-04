# Datenquellen

Campus Köthen App · `AGPL-3.0-only`

---

## 1. Übersicht

### 1.1 Serverseitige Quellen (Pfad 1)

Diese Quellen werden **ausschließlich** vom Backend abgerufen. Der Flutter-Client greift auf keine
von ihnen direkt zu (siehe [architecture.md](architecture.md), Grenze G1).

| Quelle                           | Art                                 | Verbraucher   | Status                                                 |
| -------------------------------- | ----------------------------------- | ------------- | ------------------------------------------------------ |
| Strapi 5 (eigene Instanz)        | REST + Mediathek, Read-only-Token   | Campus API    | aktiv                                                  |
| `meine-mensa.de/api/food_plans`  | öffentliche REST-Schnittstelle      | Campus Worker | aktiv                                                  |
| `hsa.webuntis.com` (View-API)    | interne API der öffentlichen Web-UI | Campus Worker | umgesetzt; Default `false`, PROD-Abweichung siehe §4.4 |
| `calendar.google.com` (ICS-Feed) | öffentlicher ICS-Feed (RFC 5545)    | Campus Worker | umgesetzt, `PUBLIC_CALENDAR_ENABLED=false`             |

**Redaktionelle Bilder** kommen ebenfalls aus Strapi, erreichen die App aber nie direkt: Die Campus
API liefert sie unter `GET /v1/media/uploads/:filename` aus und veröffentlicht in allen DTOs
ausschließlich diesen API-relativen Pfad. Strapis lokaler Provider gibt nur relative URLs zurück,
die auf einem Telefon ohnehin nicht auflösbar wären — und die Adresse des CMS bleibt Konfiguration
statt Nutzdatum ([api.md](api.md) §11).

Die beiden geflaggten Quellen sind **vollständig implementiert und getestet**, aber serverseitig
abgeschaltet, bis die Nutzung organisatorisch entschieden ist. Details in §4 und §5.

### 1.2 Geräteseitige Quellen (Pfad 2)

Diese fünf Dienste spricht die App **direkt** an — ausdrücklich beschlossene, eng begrenzte
Ausnahmen von G1, damit weder Campus API noch Strapi noch Worker Zugangsdaten oder persönliche
Inhalte erhalten (siehe [`../AGENTS.md`](../AGENTS.md) §2).

| Quelle                     | Art                                 | Verbraucher | Status |
| -------------------------- | ----------------------------------- | ----------- | ------ |
| `mail.hs-anhalt.de`        | IMAP/SMTP                           | Flutter     | aktiv  |
| `service.ssc.hs-anhalt.de` | HIS-QIS, HTML (keine JSON-API)      | Flutter     | aktiv  |
| `sscportal.ssc.hs-anhalt.de` | HISinOne, HTML/JSF (keine JSON-API) | Flutter   | aktiv  |
| `moodle.hs-anhalt.de`      | Moodle-Webservice, nur lesend       | Flutter     | aktiv  |
| `cloud.hs-anhalt.de`       | Nextcloud Login Flow v2 / WebDAV, nur lesend | Flutter | umgesetzt; reale Geräteabnahme offen |
| `REQUESTS_BASE_URL`        | Gremiensystem, Finanzanträge (POST) | Flutter     | aktiv  |

Mail, Prüfungsportale, Moodle und Nextcloud sind nutzerauthentifiziert. Der Antragsdienst ist es
**nicht** — ausschlaggebend ist der
Inhalt: Eine Einreichung trägt den Namen der antragstellenden Person und eine Kopie des
Studierendenausweises. Genau solche Daten sollen kein Campus-Köthen-Backend erreichen.

Details in §6. Für sie gilt umgekehrt: **kein** Backend darf sie jemals abrufen.

### 1.3 Keine Quelle: der Lageplan

Die Kartengeometrie ist **keine** Fremdquelle. Sie ist ein selbst erstelltes, vollständig fiktives
Asset im Repository (`packages/campus-map`), wird validiert, deterministisch in App-Assets
übersetzt und mit der App gebündelt. Zur Laufzeit wird dafür **nichts** geladen — weder von einem
Drittanbieter noch aus Strapi. Nur die Raum*bezeichnungen* und redaktionellen Raumtexte sind
Campusdaten und laufen deshalb über die Campus API (`/v1/rooms`).
Details: [campus-map.md](campus-map.md).

---

## 2. Strapi

Basis-URL ausschließlich über `STRAPI_BASE_URL`. Authentifizierung über `STRAPI_API_TOKEN` als
Bearer-Token mit **Read-only-Scope**.

Genutzte Endpunkte:

```http
GET /api/news-channels?locale=<de|en>&populate=...
GET /api/news-articles?locale=<de|en>&populate=...
GET /api/contact-areas?locale=<de|en>&populate=...
```

Regeln:

- Es werden nur **veröffentlichte** Einträge gelesen (Strapi 5 Standard ohne `status=draft`).
- Es gibt keine Public Role: das Plugin `users-permissions` ist nicht installiert. Ohne gültigen
  Token liefert Strapi `401 Missing or invalid credentials` — verifiziert gegen eine laufende
  Instanz für `/api/posts`, `/api/channels`, `/api/tags`, `/api/rooms`, `/api/contact-areas` und
  `/api/public-calendars`. Siehe G5 in [architecture.md](architecture.md).
- Strapi-Antwortstrukturen (`data`, `attributes`, `documentId`, `meta.pagination`) werden im
  Backend gemappt und **nie** nach außen durchgereicht.

---

## 3. meine-mensa.de

### 3.1 Endpunkt

```http
GET https://meine-mensa.de/api/food_plans?location_id=<id>&date_from=<YYYY-MM-DD>&date_to=<YYYY-MM-DD>
```

Betreiber: Studentenwerk Halle. Kein Token erforderlich. Antwort ist `application/json`.

### 3.2 Verifizierte Standorte

| `location_id` | Slug                     | Anzeigename         | Campus-Label   |
| ------------- | ------------------------ | ------------------- | -------------- |
| `7`           | `koethen-fasanerieallee` | Mensa Köthen        | Fasanerieallee |
| `22`          | `koethen-lohmannstrasse` | Mensa Lohmannstraße | Lohmannstraße  |

Diese Zuordnung ist **Backend-Konfiguration** (`apps/backend/src/modules/canteen/canteens.config.ts`).
Flutter kennt keine Location-IDs. Eine weitere Mensa erfordert kein App-Release.

### 3.3 Verifizierte Antwortstruktur

Am 22.07.2026 real gegen beide Standorte geprüft (HTTP 200):

```jsonc
{
  "data": [
    {
      "id": 58033, // stabile Plan-ID → Upsert-Schlüssel (sourcePlanId)
      "date": "2026-07-20", // YYYY-MM-DD
      "counter_id": 44, // Ausgabetheke
      "location_id": 7, // MUSS gegen die angefragte Mensa geprüft werden
      "is_sprint": true,
      "food": {
        "id": 1892, // sourceFoodId
        "name": "Bulgur-Pfanne",
        "name_2": "mit Kichererbsen, Wirsing und Kräuterdip",
        "ingredients": ["2", "52", "53", "A1", "A3", "G2"],
        "price_1": 1.95, // Studierende
        "price_2": 4.95, // Bedienstete
        "price_3": 7, // Gäste  ← kann Integer sein, nicht nur Dezimal
        "extra_1": "",
        "extra_2": "",
        "extra_3": "",
        "extra_4": "",
        "image_url": "https://…", // WIRD NICHT GESPEICHERT UND NICHT AUSGELIEFERT
      },
    },
  ],
  "meta": {
    "ingredients": { "2": "Konservierungsstoffe", "52": "vegan", "A1": "enthält Weizengluten" },
    "markers": { "53": "Sprint-Menü", "54": "Mensa Vital", "55": "Bio", "9901": "Klima-Teller" },
  },
}
```

### 3.4 Beobachtete Eigenheiten

Diese Punkte sind der Grund für die strikte Schema-Validierung:

1. **`food.ingredients` mischt zwei Namensräume.** Die Liste enthält sowohl Codes aus
   `meta.ingredients` als auch aus `meta.markers` (im Beispiel ist `"53"` = „Sprint-Menü“ ein
   Marker). Die Auflösung muss beide Wörterbücher konsultieren und den `kind` festhalten.
2. **Codes sind Strings, keine Zahlen** — auch die rein numerischen (`"52"`). Es gibt zusätzlich
   alphanumerische Codes (`"A1"`, `"G2"`) und Codes mit Sonderzeichen (`"A!"`, `"G!"`).
3. **Preise kommen als JSON-Zahl mit unterschiedlicher Genauigkeit** (`7` statt `7.00`). Sie werden
   als `Decimal` gespeichert, nie als `float`.
4. **Labels liegen ausschließlich auf Deutsch vor.** Sie werden **nicht** maschinell übersetzt.
   Bei `locale=en` bleibt der deutsche Quelltext erhalten und wird als `translationFallback`
   markiert.
5. **Die Antwort kann sehr klein sein.** Location 22 lieferte im geprüften Zeitraum genau einen
   Eintrag. Eine kleine Antwort ist **kein** Fehlersignal — eine leere Antwort löscht trotzdem
   niemals bestehende Daten.
6. `extra_1` bis `extra_4` sind häufig leere Strings und werden vor dem Speichern gefiltert.

### 3.5 Semantische Zuordnung (Traits und Allergene)

Die App filtert **nie** über die Codes der Quelle. Sie sind nirgends dokumentiert, mischen zwei
Namensräume und können sich ändern. Stattdessen ordnet
`apps/backend/src/modules/canteen/meal-semantics.ts` sie einmalig stabilen Schlüsseln zu, die die
API in `traits` und `allergens` ausliefert (siehe [api.md](api.md)).

Zwei Regeln gelten für jeden Eintrag dieser Tabelle:

- **Nichts wird erfunden.** Ein Schlüssel entsteht nur dort, wo die Quelle die Eigenschaft
  tatsächlich erklärt. Ein unbekannter Code bleibt ein normaler Marker ohne Schlüssel.
- **Nichts wird über die deklarierte Hierarchie hinaus abgeleitet.** Die beiden Elternfacetten
  (`gluten`, `nuts`) folgen aus ihren Untertypen, weil die Quelle sie selbst so modelliert. Ein
  veganes Gericht wird **nicht** stillschweigend zu einem vegetarischen: die Küche markiert beides,
  wenn sie beides meint.

| Quelle                                             | Schlüssel                                                                                                               |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `50`, `51`, `52`                                   | `meatless`, `vegetarian`, `vegan`                                                                                       |
| `is_sprint` des Planeintrags                       | `sprint` (**nicht** Marker `53`)                                                                                        |
| `A!` / `A1`–`A5`                                   | `gluten` / `gluten_wheat`, `gluten_rye`, `gluten_oats`, `gluten_barley`, `gluten_spelt`                                 |
| `G!` / `G1`–`G7`                                   | `nuts` / `nuts_hazelnut`, `nuts_almond`, `nuts_walnut`, `nuts_cashew`, `nuts_pecan`, `nuts_pistachio`, `nuts_macadamia` |
| `B`, `C`, `D`, `E`, `F`                            | `crustaceans`, `egg`, `peanuts`, `soy`, `milk`                                                                          |
| `H`, `I`, `J`, `K`, `L`, `M`, `N`                  | `celery`, `mustard`, `sesame`, `sulphites`, `lupin`, `molluscs`, `fish`                                                 |
| `45`–`49`, `56` (Fleischarten), Zusatzstoffnummern | **kein** Schlüssel — bleiben reine Marker                                                                               |

Der Code ist der primäre Schlüssel. Zusätzlich greift eine geprüfte **Label-Normalisierung**
(Kleinschreibung, Umlaute ausgeschrieben, Diakritika entfernt, Satzzeichen zu Leerzeichen): Wird ein
Code umnummeriert, heißt aber weiterhin „enthält Erdnüsse", bleibt die Zuordnung erhalten. Beide
Wege sind in `meal-semantics.spec.ts` gegen das reale Wörterbuch der Quelle abgesichert.

Bewusst **nicht** zugeordnet ist `48` „Fisch": das ist die Fleischart, nicht die Allergendeklaration
`N` „enthält Fisch".

### 3.6 Preisgruppen

| Feld      | Slug       | Label DE    | Label EN  |
| --------- | ---------- | ----------- | --------- |
| `price_1` | `student`  | Studierende | Students  |
| `price_2` | `employee` | Bedienstete | Employees |
| `price_3` | `guest`    | Gäste       | Guests    |

**Alle** verfügbaren Preisgruppen werden gespeichert und ausgeliefert. Die Zuordnung
Feld → Bedeutung ist Backend-Wissen; die Labels sind API-eigene, zweisprachige Texte.
Der Studierendenpreis wird in der App hervorgehoben.

### 3.7 Abrufregeln

| Regel             | Wert                                                                                        |
| ----------------- | ------------------------------------------------------------------------------------------- |
| Intervall         | alle 2 Stunden (`CANTEEN_SYNC_CRON="0 */2 * * *"`)                                          |
| Zeitraum je Abruf | aktuelle + kommende Woche                                                                   |
| Timeout           | `CANTEEN_HTTP_TIMEOUT_MS`, Standard 15000                                                   |
| Retry             | 3 Versuche, exponentieller Backoff                                                          |
| Manueller Sync    | administratives CLI-Kommando — **kein** öffentlicher Sync-Endpunkt                          |
| Tests             | ausschließlich gegen anonymisierte Fixtures unter `apps/backend/test/fixtures/meine-mensa/` |

### 3.8 Rechtliches

- Daten werden inhaltlich unverändert übernommen und der Quelle zugeordnet.
- **Keine Mensabilder.** `food.image_url` wird nicht persistiert und nicht ausgeliefert.
- Preise und Allergenangaben sind Angaben der Quelle ohne Gewähr; die App weist darauf hin.
- Eine abschließende Nutzungsfreigabe durch den Betreiber ist ein offenes Release-Gate.

### 3.9 Lokaler NFC-Guthabencheck

Der NFC-Guthabencheck ist **keine Quelle für Mensaplandaten** und verwendet weder `meine-mensa.de`
noch die Campus API. Er kommuniziert nach einer bewussten Nutzeraktion ausschließlich lokal per
DESFire/ISO-DEP mit der vorgehaltenen Karte:

1. Anwendung auswählen: `90 5A 00 00 03 5F 84 15 00`
2. Nur nach erfolgreichem Statuswort lesen: `90 6C 00 00 01 01 00`
3. Exakt vier Nutzdatenbytes als vorzeichenbehafteten Int32 Little Endian interpretieren und durch
   `1000` in Euro umrechnen.

Länge, Statuswort und ein defensiver Plausibilitätsbereich werden strikt geprüft. Das native Modul
stellt nur den Transport bereit; Parser und Fehlerklassifikation sind für Android und iOS gemeinsam.
Es gibt keine Schreib-APDU, keinen Hintergrundscan und keine Speicherung oder Übertragung von
Kartenkennung, Rohantwort oder Saldo. Android kann einen per `TECH_DISCOVERED` erkannten ISO-DEP-Tag
nach der systemseitigen Öffnen-Aktion direkt verarbeiten. iOS kann eine Drittanbieter-App außerhalb
einer bereits laufenden Core-NFC-Sitzung nicht auf diese Weise starten und bietet deshalb nur den
manuellen Scan aus der Mensaansicht an.

---

## 4. WebUntis — öffentliche Stundenplanansicht

> ⚠️ **Kein offizieller Vertrag.** Genutzt wird die **interne View-API** der öffentlichen
> WebUntis-Weboberfläche. Sie ist nicht dokumentiert, nicht versioniert und kann sich jederzeit
> ohne Ankündigung ändern. Ein Parserfehler ist deshalb zuerst als Änderung der Quelle zu
> behandeln, nicht als Bug im eigenen Code.

Beobachtet und verifiziert am **22.07.2026**.

### 4.1 Endpunkte

Basis: `https://hsa.webuntis.com/WebUntis/api/rest/view/v1`

| Endpunkt             | Methode | Pflichtparameter                                                | Pflicht-Header                             |
| -------------------- | ------- | --------------------------------------------------------------- | ------------------------------------------ |
| `/app/data`          | GET     | —                                                               | `anonymous-school: hsa`                    |
| `/timetable/filter`  | GET     | `resourceType=CLASS`                                            | zusätzlich `X-Webuntis-Api-School-Year-Id` |
| `/timetable/entries` | GET     | `start`, `end` (`YYYY-MM-DD`), `format=2`, `resourceType=CLASS` | zusätzlich `X-Webuntis-Api-School-Year-Id` |

Die Schuljahres-ID ist **dynamisch** und wird zur Laufzeit aus `/app/data` gelesen. Sie ist
nirgends im Quellcode hinterlegt.

### 4.2 Beobachtete Eigenheiten

1. **Ein fehlender Pflichtparameter liefert HTTP 500**, nicht 400, mit dem Parameternamen im
   JSON-Body. Der Status allein ist hier also ein schlechtes Fehlersignal.
2. **`entries` ohne Ressourcen-IDs liefert alle Klassen auf einmal.** Gemessen: 270 Klassen ×
   5 Tage = 1350 Tagesobjekte, ~505 KB, ~1,2 s. Genau deshalb ist die Synchronisation ein
   **Batch pro Zeitfenster** und keine 270 Einzelabrufe.
3. **`position1` … `position7` haben keine feste Bedeutung.** Allein in der aufgezeichneten Stichprobe
   erschien `ROOM` auf Position 2 und 3, `CLASS` auf 3 und 4, `SUBJECT` auf 1 und 2. Ausgewertet wird
   deshalb ausschließlich über `current.type` — eine indexbasierte Auswertung würde Räume still als
   Klassen einsortieren.
4. `duration.start`/`duration.end` sind **lokale Wandzeit ohne Zone** und werden als
   `Europe/Berlin` interpretiert. Beim Import wird in absolute UTC-Zeitpunkte umgerechnet.
5. `ids[]` ist der stabile Quellschlüssel und enthält gelegentlich mehr als einen Wert.
6. `lessonInfo` enthält optional die „Information zur Stunde“. Das Feld wurde am
   **25.09.2026** erneut als Textwert geprüft und wird getrennt von `lessonText` und
   `substitutionText` übernommen. Die App bietet jeden unterschiedlichen Text als eigene,
   standardmäßig aktivierte Filteroption an. Für Einträge ohne Text gibt es eine separate Option;
   die Auswahl wird pro Stundenplangruppe lokal gespeichert.
7. Beobachtetes Vokabular — **was gesehen wurde, nicht was existiert**:
   `type` = `NORMAL_TEACHING_PERIOD`, `ADDITIONAL_PERIOD`;
   `status` = `REGULAR`, `CHANGED`, `CANCELLED`, `ADDITIONAL`.
   Unbekannte Werte werden auf `unknown` abgebildet und brechen den Import nicht.

### 4.3 Abrufregeln

| Regel           | Wert                                                                                  |
| --------------- | ------------------------------------------------------------------------------------- |
| Feature-Flag    | `WEBUNTIS_ENABLED`, **Default `false`**                                               |
| Gruppenkatalog  | täglich (`WEBUNTIS_GROUP_SYNC_CRON`, Default `0 2 * * *`)                             |
| Stundenplan     | täglich (`WEBUNTIS_ENTRY_SYNC_CRON`, Default `15 2 * * *`), ein Request je Klasse     |
| Abrufvolumen    | abhängig von der Zahl der Klassen in den Schuljahren des Zeitfensters                 |
| Zeitfenster     | 7 Tage zurück, 28 Tage voraus (konfigurierbar)                                        |
| API-Zeitraum    | maximal 42 Tage                                                                       |
| Timeout / Retry | 20 s, 3 Versuche, Backoff mit Jitter, `Retry-After` wird beachtet                     |
| Abstand         | 1,5 s zwischen Fremdrequests                                                          |
| Größenschutz    | `WEBUNTIS_MAX_RESPONSE_BYTES`, Default 16 MB                                          |
| Tests           | ausschließlich gegen redigierte Fixtures unter `apps/backend/test/fixtures/webuntis/` |

Die App ruft WebUntis **nie** direkt auf. Kein Client-Request löst einen Fremdabruf aus.
Die Schuljahre werden vorab über `/schoolyears` ermittelt; dadurch sind Gruppen und Einträge
des kommenden Semesters schon vor dem Wechsel des aktuellen Schuljahres verfügbar. Ein fehlerhafter
Klassenabruf verwirft den gesamten Lauf, ohne vorhandene Daten zu löschen.

### 4.4 Personenbezogene Daten

Die Quelle liefert **Lehrpersonennamen**. Diese werden gespeichert und angezeigt, weil sie
Bestandteil des öffentlich einsehbaren Stundenplans sind. In den committeten Fixtures sind sie
durch deterministische Pseudonyme ersetzt — die Live-Antwort enthielt 145 echte Namensvarianten,
keine davon liegt im Repository.

**Offen und vor einer Produktivfreigabe zu klären:**

- Erlaubnis zur automatisierten Nutzung der internen View-API
- akzeptable Abrufrate
- Zusage zur Schnittstellenstabilität beziehungsweise eine offizielle API
- gewünschte Quellenangabe
- zulässige Speicherung und Anzeige von Lehrpersonennamen sowie Aufbewahrungsfristen

Bis dahin bleibt `WEBUNTIS_ENABLED=false`. Das gilt auch für die versionierten
Deployment-Templates. Da produktive Secrets und Umgebungswerte nicht im Repository liegen, wird
der effektive Wert vor dem Rollout direkt auf dem Zielsystem und zusätzlich über
`GET /v1/timetable/status` geprüft; ein Template allein ist kein Nachweis des Live-Zustands.

**Festgestellte Produktionsabweichung (1. Oktober 2026):** Die öffentliche Statusroute der
Produktions-API antwortete mit HTTP 200 und `featureEnabled: true` sowie einem frischen
Synchronisationsstand. Damit ist der effektive Live-Wert trotz des weiterhin als offen
dokumentierten Freigabe-Gates aktiv. Die versionierten Templates wurden auf `false` zurückgesetzt;
die nicht versionierte Live-Konfiguration muss durch den Betreiber deaktiviert oder die erteilte
organisatorische Freigabe nachvollziehbar dokumentiert werden. Diese Repository-Änderung nimmt
keine Live-Umschaltung vor.

---

---

## 5. calendar.google.com — öffentlicher ICS-Feed

> ⚠️ **Kein Google-Konto, kein API Key, kein SDK.** Es gibt weder ein Google-Cloud-Projekt noch
> OAuth noch eine Anbindung persönlicher Google-Konten. Der Worker lädt ausschließlich den
> **öffentlichen** ICS-Feed eines vom Inhaber freigegebenen Kalenders.

### 5.1 Von der Freigabe zur Feed-URL

Redakteur:innen tragen in Strapi einen **öffentlichen Freigabelink** ein
(`https://calendar.google.com/calendar/u/0?cid=<base64url>`). Das Backend extrahiert daraus die
Kalender-ID und konstruiert die feste Feed-URL **selbst**:

```text
https://calendar.google.com/calendar/ical/{URL-kodierte-ID}/public/basic.ics
```

Die App ruft diesen Feed **nie** direkt ab. Kalender-ID und Feed-URL bleiben backendintern, sind
nie ein DTO-Feld und werden nie geloggt.

### 5.2 Validierung und SSRF-Schutz

Der Freigabelink wird an **zwei** Stellen unabhängig validiert (beim Eintragen und erneut an der
Backend-Vertrauensgrenze): HTTPS-only · Host exakt `calendar.google.com` · kein Userinfo, kein Port
· Pfad-Allowlist · genau ein `cid` · Base64-Roundtrip · striktes UTF-8 · Längenlimits · keine
Steuerzeichen. Abgelehnt werden unter anderem `http`, `webcal`,
`calendar.google.com.attacker.example`, IPs sowie direkt eingefügte `basic.ics`- oder
`private-…`-Links.

Der ICS-Client konstruiert Scheme, Host und Pfad selbst, nimmt **keine** Basis-URL aus Strapi oder
dem Environment entgegen und folgt **keinen** Redirects — ein `3xx` wird abgelehnt.

### 5.3 Beobachtete Eigenheiten

1. **Zeitzonen sind uneinheitlich.** Der Feed mischt `VTIMEZONE`, UTC, `TZID` und zonenlose
   („floating“) Zeiten. Letztere werden mit einer kontrollierten Fallback-Zone interpretiert
   (`PUBLIC_CALENDAR_FALLBACK_TIME_ZONE`, Default `Europe/Berlin`).
2. **Ganztägige Termine haben ein exklusives `DTEND`.** Sie werden als lokales Kalenderdatum
   behandelt, ohne UTC- oder Gerätezeitzonen-Verschiebung.
3. **Wiederholungsregeln können unbegrenzt expandieren.** `FREQ=MINUTELY` ist gültiges RFC 5545 und
   würde ohne Obergrenze Millionen Zeilen erzeugen. Expandiert wird deshalb nur im Zielfenster, mit
   harten Grenzen pro Event und pro Lauf (`recurrenceLimitExceeded`).
4. **Der Feed enthält personenbezogene Felder**, die bewusst **nie gelesen** werden: `ATTENDEE`,
   `ORGANIZER`, `CONTACT`, `ATTACH`, Konferenzdaten, Alarme und `X-*`. So gelangt keine
   E-Mail-Adresse in die Datenbank.
5. `DESCRIPTION` und `LOCATION` werden nur bei entsprechendem Strapi-Flag übernommen, immer als
   **Plain Text**, nie als HTML.

### 5.4 Abrufregeln

| Regel           | Wert                                                                                    |
| --------------- | --------------------------------------------------------------------------------------- |
| Feature-Flag    | `PUBLIC_CALENDAR_ENABLED`, **Default `false`**                                          |
| Katalog         | alle 10 Minuten (`PUBLIC_CALENDAR_CATALOG_SYNC_CRON`)                                   |
| Termine         | alle 10 Minuten (`PUBLIC_CALENDAR_EVENT_SYNC_CRON`)                                     |
| Schonung        | `If-None-Match`/`If-Modified-Since` → 304, zusätzlich Kurzschluss über Inhalts-Hash     |
| Zeitfenster     | 30 Tage zurück, 180 Tage voraus (konfigurierbar)                                        |
| Timeout / Retry | 20 s, 2 Versuche, nur bei 5xx/429/Transportfehlern                                      |
| Abstand         | 1 s zwischen Fremdrequests                                                              |
| Größenschutz    | `Content-Length`-Vorabprüfung **und** Streaming-Byte-Limit, Default 8 MB                |
| Parser          | `ical.js` (Mozilla, MPL-2.0) — Netzwerkfunktionen der Bibliothek werden nicht verwendet |

### 5.5 Rechtliches

Technisch öffentlich lesbar ist **nicht** dasselbe wie rechtlich frei weiterveröffentlichbar. Vor
dem produktiven Eintrag eines Kalenders sind zu klären: Zustimmung des Inhabers, zulässiger
Quellenhinweis, ob Beschreibung und Ort gezeigt werden dürfen, Ansprechpartner und das Verhalten
bei Entzug der Freigabe. Teilnehmer- und Organizer-Adressen werden nie übernommen.

Vollständige Beschreibung inklusive Redaktionshandbuch: [public-calendars.md](public-calendars.md).

---

## 6. Geräteseitige Direktquellen

Diese Quellen erreicht **ausschließlich die App**. Ein Backend darf sie nie abrufen; es gibt für
sie keine API-Route, keine Strapi-Collection, keinen Worker-Job und keine Datenbanktabelle.

| Quelle                               | Zweck                                                                                                                                                                                             | Besonderheit                                                                                                                                                                                                                                                         | Doku                               |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| `mail.hs-anhalt.de`                  | Studentisches Postfach                                                                                                                                                                            | IMAPS 993, SMTP 587 mit **Pflicht**-STARTTLS, kein Klartext                                                                                                                                                                                                          | [student-mail.md](student-mail.md) |
| `service.ssc.hs-anhalt.de`           | HIS-QIS-Notenspiegel                                                                                                                                                                              | **keine** offizielle API — HTML-Parsing über Spaltenüberschriften                                                                                                                                                                                                    | [grades.md](grades.md)             |
| `sscportal.ssc.hs-anhalt.de`         | HISinOne-Notenspiegel; zusätzlich **nur lesend** die drei festen Bescheinigungs-Druck-Buttons direkt auf der Notenübersichtsseite (volle Formularabgabe, kein AJAX) sowie auf der Seite „Studienservice" (mehrere Tabs, Wechsel per Voll-POST): Bescheinigungsübersicht, Personendaten/Kontaktdaten, Studiengangsübersicht. Der einmalige Abruf einer erzeugten Bescheinigung — aus beiden Quellen — ist zweistufig: zuerst `GET /qisserver/rds?state=docdownload…` auf dem Portal-Host, danach ein serverseitiger Redirect auf denselben Pfad/Zustand, aber die separate Origin `untrust-sscportal.ssc.hs-anhalt.de` — Ziel und Einweg-Token aus der aktuellen AJAX-Antwort bzw. dem Formular-Redirect, derselbe kurzlebige Cookie-Jar, vorhandener Content-Type sowie PDF-Magic/Größe geprüft; diese enge Pfad-/Parameter-Prüfung auf genau diese zwei Hosts ist **keine** allgemeine Allowlist | **keine** offizielle API — HTML-/JSF-Parsing; dieselben Zugangsdaten wie der Notenspiegel, kein zweiter Login; keine Prüfungsanmeldung, keine Adressänderung, keine sonstige Mutation                                                                                | [grades.md](grades.md)             |
| `moodle.hs-anhalt.de`                | Kurse, Materialien, Aufgaben, Ankündigungen, Deadlines                                                                                                                                            | feste, rein **lesende** Whitelist von `wsfunction`s                                                                                                                                                                                                                  | [moodle.md](moodle.md)             |
| `cloud.hs-anhalt.de`                 | Persönliche Nextcloud-Dateien                                                                                                                                                                      | Login Flow v2 im Systembrowser; OCS nur für eigene Nutzer-ID und App-Passwort-Widerruf; WebDAV **nur lesend** unter der eigenen Nutzerwurzel; kein persistenter Datei- oder Metadatencache                                                                         | [nextcloud.md](nextcloud.md)       |
| `REQUESTS_BASE_URL`                  | Finanzanträge und Feedback an das Gremiensystem des Studierendenrats                                                                                                                              | Adresse **nie** als Quellcode-Konstante, **HTTPS** erzwungen; Antrag als `multipart/form-data`, Feedback als `application/json`, beide mit Idempotenzschlüssel; Status per `POST` mit dem Link im Body                                                               | —                                  |

Gemeinsame Regeln: feste Host-Allowlist vor jedem Request · Redirects auf fremde Hosts oder auf
Klartext werden abgebrochen · Zertifikatsprüfung nie deaktiviert · Zugangsdaten und Token nur im
Keychain/Keystore · Inhalte nur verschlüsselt lokal · nichts davon in Logs oder Fehlermeldungen.

Für **Anträge und Feedback** gilt zusätzlich: Der zurückgegebene **Statuslink ist ein
Bearer-Credential** — er ist der einzige Zugang zum Vorgang, wird verschlüsselt lokal gespeichert und
**niemals** geloggt, gemeldet, geteilt oder als Route beziehungsweise Query-Parameter verwendet.
Quittungs- und Dokument-Links tragen denselben Token und werden genauso behandelt. Der Statusabruf
ist deshalb ein `POST` mit dem Link im JSON-Body und ohne Idempotenzschlüssel; er antwortet
`Cache-Control: no-store`, weshalb Statusantworten nur im Arbeitsspeicher gehalten werden. Entwürfe,
Anhänge — einschließlich des Studierendenausweises — und Ergebnis bleiben verschlüsselt auf dem
Gerät. Ein `400` oder `404` löscht **nie** einen lokal gespeicherten Vorgang.
Details: [requests.md](requests.md).

**Bekannte Fragilität:** Weder HIS-QIS noch HISinOne bieten eine JSON-API — das gilt für den
Notenspiegel genauso wie für die lesenden HISinOne-Funktionen (Bescheinigungen, Personen-/
Kontaktdaten, Studiengangsübersicht). Ändert die Hochschule eines der Portale, greift `portalStructureChanged` — mit
lokalisierter Meldung, **ohne** den Cache zu überschreiben und **ohne** die Antwort zu loggen. Wie
bei WebUntis gilt: eine Parseränderung ist zuerst als Änderung der Quelle zu behandeln, nicht als
eigener Bug.

---

## 7. Nicht genutzt

Stundenpläne für **Lehrpersonen oder Räume**, Raumverfügbarkeit („freie Räume“), persönlicher
WebUntis-Login sowie Abwesenheiten und Hausaufgaben. Die öffentliche WebUntis-Ansicht wird
ausschließlich für **Gruppenstundenpläne** genutzt.

Noten stammen **nicht** aus WebUntis, sondern ausschließlich aus dem HIS-QIS-Prüfungsportal und
werden direkt vom Gerät abgerufen (§6).

Ebenfalls dauerhaft ausgeschlossen: Google API Key, Google-OAuth, Google-SDK, die Anbindung
persönlicher Google-Konten sowie jeder Schreibzugriff auf Moodle.
