# Campus API — Vertrag

Campus Köthen App · `AGPL-3.0-only` · Basis-Pfad `/v1`

Dies ist der **verbindliche Vertrag** zwischen Campus API und Flutter-Client. Die maschinenlesbare
Fassung liegt in [`packages/openapi/openapi.json`](../packages/openapi/openapi.json) und wird aus
den NestJS-DTOs erzeugt.

---

## 1. Grundregeln

| Regel                  |                                                                                         |
| ---------------------- | --------------------------------------------------------------------------------------- |
| Basis-Pfad für Inhalte | `/v1`                                                                                   |
| Technische Endpunkte   | `/health/live`, `/health/ready`, `/docs`, `/docs-json` (ohne `/v1`)                     |
| Format                 | `application/json; charset=utf-8`                                                       |
| Authentifizierung      | keine — alle Inhalte sind öffentlich lesbar                                             |
| Strapi-Internas        | **niemals** in der Antwort (`data.attributes`, `documentId`, `populate`, Strapi-`meta`) |
| Transportkodierung     | `br` oder `gzip`, sobald der Client sie anbietet — siehe unten                          |

Jede **inhaltliche** Antwort verwendet denselben Umschlag:

```jsonc
{
  "data": {/* oder [] */},
  "meta": {
    "requestedLocale": "de",
    "resolvedLocale": "de",
    "translationFallback": false,
  },
}
```

### Transportkodierung

Antworten ab **1 KiB** werden komprimiert, sobald der Client sie über `Accept-Encoding` anbietet:
`br`, wenn er Brotli kann, sonst `gzip`. Das lohnt sich vor allem für den Suchindex, den
Raumkatalog, den Speiseplan und den Stundenplan — alles große, stark redundante Nutzlasten.

Das ist **ausschließlich** eine Transportkodierung:

- Bietet ein Client nichts an oder nur `identity`, kommt die Antwort unkomprimiert und Byte für
  Byte so an wie zuvor. Ein Client muss dafür nichts tun; `dio` und die Dart-`HttpClient`-Ebene
  bieten `gzip` von sich aus an und dekodieren transparent.
- Der dekodierte Inhalt ist derselbe: dieselben Felder, dieselbe `meta`, dieselbe Reihenfolge.
- JSON-Antworten tragen `Vary: Accept-Encoding`, auch wenn sie unkomprimiert bleiben — sonst
  könnte ein zwischengeschalteter Cache einen komprimierten Körper an einen Client geben, der
  keinen angefordert hat.
- Antworten unter der Schwelle bleiben unkomprimiert; dort kostet die Kodierung mehr, als sie
  einspart.
- Der Bilder-Endpunkt (§ 11) wird **nicht** komprimiert.

## 2. Locale-Vertrag

Auflösung in dieser Reihenfolge:

1. Query-Parameter `locale` — Werte `de` oder `en`.
2. Header `Accept-Language` — nur wenn kein `locale`-Parameter gesetzt ist.
3. Standard `de`.

| Fall                              | Verhalten                                                             |
| --------------------------------- | --------------------------------------------------------------------- |
| `?locale=de` / `?locale=en`       | wird verwendet                                                        |
| `?locale=fr`                      | **`400 Bad Request`** — expliziter Wunsch wird nicht still verfälscht |
| `Accept-Language: fr-FR`          | stiller Fallback auf `de`                                             |
| `Accept-Language: en-GB,en;q=0.9` | `en`                                                                  |
| kein Hinweis                      | `de`                                                                  |

Metadaten jeder inhaltlichen Antwort:

| Feld                  | Bedeutung                                                                                        |
| --------------------- | ------------------------------------------------------------------------------------------------ |
| `requestedLocale`     | was der Client wollte                                                                            |
| `resolvedLocale`      | was tatsächlich ausgeliefert wurde                                                               |
| `translationFallback` | `true`, sobald **mindestens ein** ausgeliefertes Feld aus `de` stammt, obwohl `en` angefragt war |

**Externe Mensa-Texte werden nie übersetzt.** Gerichtsnamen, Zusatztexte und Zutaten-/Markerlabels
stammen aus einer rein deutschsprachigen Quelle. Bei `locale=en` sind sie immer Fallback; das
betroffene Objekt trägt zusätzlich `"sourceLanguage": "de"`. API-eigene Texte (Mensanamen,
Preisgruppen-Labels, Fehlermeldungen) sind zweisprachig.

## 3. Fehlerformat

```jsonc
{
  "error": {
    "status": 404,
    "code": "POST_NOT_FOUND",
    "message": "Der angeforderte Beitrag wurde nicht gefunden.",
    "requestId": "b1f0…",
  },
}
```

`message` ist in der aufgelösten Locale. Es werden **nie** interne Details, Stacktraces,
Upstream-URLs oder Tokens ausgegeben.

| Code                                                                         | Status |
| ---------------------------------------------------------------------------- | ------ |
| `VALIDATION_FAILED`                                                          | 400    |
| `UNSUPPORTED_LOCALE`                                                         | 400    |
| `NOT_FOUND` (unbekannte Route — ohne Aussage über die Ressourcenart)         | 404    |
| `POST_NOT_FOUND` / `CONTACT_AREA_NOT_FOUND` / `CANTEEN_NOT_FOUND`            | 404    |
| `TIMETABLE_GROUP_NOT_FOUND` / `PUBLIC_CALENDAR_NOT_FOUND` / `ROOM_NOT_FOUND` | 404    |
| `MEDIA_NOT_FOUND`                                                            | 404    |
| `UPSTREAM_UNAVAILABLE`                                                       | 503    |
| `UPSTREAM_TIMEOUT`                                                           | 504    |
| `INTERNAL_ERROR`                                                             | 500    |

Die vollständige, maßgebliche Liste steht in
[`apps/backend/src/common/errors/api-error.ts`](../apps/backend/src/common/errors/api-error.ts);
jede Meldung liegt dort zweisprachig vor.

## 4. Technische Endpunkte

### `GET /health/live`

Prüft **ausschließlich** den Prozess. Immer `200`, solange der Prozess antwortet.

```json
{ "status": "ok", "uptimeSeconds": 1234 }
```

### `GET /health/ready`

Prüft Datenbank und Strapi kontrolliert mit Timeout. `200` wenn bereit, sonst `503`.

```jsonc
{
  "status": "ok", // "ok" | "degraded"
  "checks": {
    "database": { "status": "ok", "latencyMs": 3 },
    "strapi": { "status": "ok", "latencyMs": 41 },
  },
}
```

### `GET /docs` · `GET /docs-json`

Swagger UI und OpenAPI-3-Dokument.

Beide Pfade sind an `DOCS_ENABLED` gebunden.

**Für dieses Projekt gilt: öffentlich, auch in Produktion.** Die Campus API ist
ein öffentlicher, read-only Vertrag — die Seite, die ihn dokumentiert, gehört
damit ebenfalls in die Öffentlichkeit (Entscheidung Erik, LEVIORA-180).
`infrastructure/vps/compose.yaml` setzt `DOCS_ENABLED` deshalb auf `true`, und
die Kante gibt `/docs` frei (`infrastructure/vps/edge/`).

Der **Code**-Default bleibt bewusst konservativ: ohne gesetzten Wert ist die
Seite ausserhalb von Produktion aktiv und bei `NODE_ENV=production` inaktiv.
Der Grund dafuer besteht fort — `/docs` ist echtes HTML unter einer bewusst
lockereren CSP als die API auf derselben Origin, und der Vertrag liegt ohnehin
versioniert in `packages/openapi/openapi.json`. Ein neues Deployment startet
deshalb geschlossen, und das Oeffnen ist eine sichtbare Zeile in der
Konfiguration statt einer stillen Voreinstellung. `DOCS_ENABLED=false` schliesst
die Seite jederzeit wieder.

Damit die Seite tatsaechlich erreichbar ist, muessen **beide** Stellen
zusammenpassen: `DOCS_ENABLED=true` im Backend und die Freigabe am Reverse
Proxy. Faellt eine davon weg, antwortet der Pfad mit 404.

### `GET /v1/environment`

Öffentliche, nicht geheime Kennzeichnung der verbundenen Deployment-Umgebung:

```jsonc
{
  "data": { "userTestData": true },
  "meta": { "requestedLocale": "de", "resolvedLocale": "de", "translationFallback": false },
}
```

`userTestData: true` verpflichtet den Client zu einem global sichtbaren Hinweis, dass Inhalte
synthetisch sein können. Der Wert bleibt so lange aktiv, wie der Deployment-Schalter gesetzt ist
**oder** noch vom kontrollierten User-Test-Seed angelegte Mensa-/Stundenplandaten existieren. Ein
versehentlich zu früh deaktivierter Schalter kann den Hinweis daher nicht verbergen. Details zum
Erstellen und Entfernen stehen in
[`infrastructure/vps/README.md`](../infrastructure/vps/README.md#controlled-user-test-dataset-test-environment-only).

## 5. Posts (News & Events)

### `GET /v1/posts/channels`

Nur **aktive** Kanäle, sortiert nach `sortOrder`, dann `name`.

```jsonc
{
  "data": [
    {
      "slug": "campus-news",
      "name": "Campus News",
      "description": "Nachrichten rund um den Campus Köthen.",
      "colorHex": "#5B3FD0",
      "sortOrder": 10,
      "defaultSubscribed": true,
      "publicCalendarSlug": "campus-calendar", // oder null
    },
  ],
  "meta": { "requestedLocale": "de", "resolvedLocale": "de", "translationFallback": false },
}
```

`slug` ist stabil und **nicht** lokalisiert. `defaultSubscribed` wird vom Client pro Slug
**genau einmal** ausgewertet — beim erstmaligen Auftauchen. `publicCalendarSlug` verknüpft einen
Kanal 1:1 mit einem öffentlichen Google-Kalender.

### `GET /v1/posts/tags`

Nur **aktive** Tags, sortiert nach `name`, dann `slug`. Tags sind vollständig dynamisch: ein
in Strapi angelegter Tag erscheint hier — und damit in der App — ohne Codeänderung.

```jsonc
{
  "data": [
    {
      "slug": "event",
      "name": "Event",
    },
  ],
  "meta": { "requestedLocale": "de", "resolvedLocale": "de", "translationFallback": false },
}
```

`slug` ist stabil und **nicht** lokalisiert. Anders als bei Kanälen gibt es kein
`defaultSubscribed`: Tags sind ein Inhaltsfilter und Taxonomie-Klassifikation.

### `GET /v1/posts`

| Parameter  | Typ           | Standard | Regeln                                                         |
| ---------- | ------------- | -------- | -------------------------------------------------------------- |
| `channels` | CSV von Slugs | _fehlt_  | max. 25 Werte, je max. 100 Zeichen ⇒ sonst `400` · siehe unten |
| `tags`     | CSV von Slugs | _fehlt_  | max. 25 Werte, je max. 100 Zeichen ⇒ sonst `400` · siehe unten |
| `page`     | Integer >= 1  | `1`      |                                                                |
| `pageSize` | Integer 1–50  | `20`     | Werte > 50 ⇒ `400`                                             |
| `locale`   | `de` \| `en`  | `de`     |                                                                |

**Verhalten von `channels` — vertraglich festgeschrieben:**

| Anfrage                        | Bedeutung                             |
| ------------------------------ | ------------------------------------- |
| Parameter **fehlt**            | alle aktiven Kanäle                   |
| `?channels=` (vorhanden, leer) | **bewusst keine** Kanäle ⇒ `data: []` |
| `?channels=campus-news`        | nur dieser Kanal                      |
| unbekannter Slug enthalten     | wird ignoriert, kein Fehler           |
| mehr als 25 Slugs              | `400 VALIDATION_FAILED`               |

Der Unterschied zwischen „fehlt“ und „leer“ ist wichtig: Deaktiviert der Nutzer **alle** Kanäle,
sendet der Client `?channels=` und erhält eine leere Liste — er darf **nicht** versehentlich alle
Beiträge laden.

**Verhalten von `tags` — vertraglich festgeschrieben:**

| Anfrage                    | Bedeutung                                                                                      |
| -------------------------- | ---------------------------------------------------------------------------------------------- |
| Parameter **fehlt**        | **kein** Tagfilter — alle nach `channels` erlaubten Beiträge                                   |
| `?tags=` (vorhanden, leer) | **bewusst keine** Tags ⇒ `data: []`                                                            |
| `?tags=event`              | nur Beiträge mit diesem **aktiven** Tag                                                        |
| unbekannter/inaktiver Slug | wird wie „kein Treffer“ behandelt ⇒ sichere leere Menge, **niemals** eine ungefilterte Antwort |

`tags` ist ein reiner Inhaltsfilter und **keine** Zugriffsbeschränkung wie `channels`: ein
fehlender Parameter liefert alle nach dem Kanalfilter erlaubten Beiträge, unabhängig von ihren Tags.
Sind `channels` und `tags` beide angegeben, kombinieren sie sich mit **UND** — ein Beitrag muss
beide Bedingungen erfüllen.

Nur veröffentlichte und zeitlich gültige Beiträge (`validFrom` <= jetzt <= `validUntil`).
Beiträge in mehreren angefragten Kanälen erscheinen **genau einmal**.
Sortierung: `publishedAt` DESC, dann `slug` ASC (deterministisch).

```jsonc
{
  "data": [
    {
      "slug": "semesterstart-2026",
      "title": "Semesterstart 2026",
      "publishedAt": "2026-07-20T09:00:00.000Z",
      "heroImage": { "url": "https://…", "alternativeText": "…", "width": 1600, "height": 900 },
      "tag": { "slug": "news", "name": "News" },
      "primaryChannel": { "slug": "campus-news", "name": "Campus News", "colorHex": "#5B3FD0" },
      "channels": [{ "slug": "campus-news", "name": "Campus News", "colorHex": "#5B3FD0" }],
      "sourceName": "Hochschule Anhalt",
      "sourceUrl": "https://www.hs-anhalt.de/…",
      "content": [{ "type": "paragraph", "children": [{ "type": "text", "text": "…" }] }],
      "eventStart": null,
      "eventEnd": null,
      "eventAllDay": false,
    },
  ],
  "meta": {
    "requestedLocale": "de",
    "resolvedLocale": "de",
    "translationFallback": false,
    "pagination": { "page": 1, "pageSize": 20, "total": 1, "totalPages": 1 },
  },
}
```

### `GET /v1/posts/events`

Reiner Event-Feed für Beiträge mit dem Tag `event`.

| Parameter  | Typ           | Standard           | Regeln                                                                        |
| ---------- | ------------- | ------------------ | ----------------------------------------------------------------------------- |
| `from`     | `YYYY-MM-DD`  | heute              | optional                                                                      |
| `to`       | `YYYY-MM-DD`  | `from` + Lookahead | optional, `to >= from`, Spanne max. Server-Maximalbereich (Standard 400 Tage) |
| `channels` | CSV von Slugs | _fehlt_            | max. 25 Werte, je max. 100 Zeichen                                            |
| `page`     | Integer >= 1  | `1`                |                                                                               |
| `pageSize` | Integer 1–50  | `20`               | Werte > 50 ⇒ `400`                                                            |
| `locale`   | `de` \| `en`  | `de`               |                                                                               |

Das Abfrageintervall ist als **Überlappung** definiert: `eventStart <= to AND (eventEnd ?? eventStart) >= from`.
Wie im Feed nur zeitlich gültige Beiträge (`validFrom` <= jetzt <= `validUntil`).
Sortierung: `eventStart` ASC, dann `slug` ASC (deterministisch).

### `GET /v1/posts/:slug`

Liefert genau denselben Aufbau wie ein Listeneintrag.
Es gelten dieselben Sichtbarkeitsregeln wie im Feed: Der Beitrag muss zeitlich gültig sein
(`validFrom` <= jetzt <= `validUntil`) und in mindestens einem **aktiven** Kanal liegen.
Unbekannter, gesperrter (Embargo), abgelaufener oder nur in inaktiven Kanälen liegender Slug ⇒
`404 POST_NOT_FOUND` — bewusst ununterscheidbar.

```jsonc
{
  "data": {
    "slug": "semesterstart-2026",
    "title": "…",
    "publishedAt": "…",
    "heroImage": null,
    "tag": { "slug": "news", "name": "News" },
    "primaryChannel": { "slug": "campus-news", "name": "Campus News", "colorHex": "#5B3FD0" },
    "channels": [],
    "sourceName": null,
    "sourceUrl": null,
    "content": [
      { "type": "heading", "level": 2, "children": [{ "type": "text", "text": "Überblick" }] },
      {
        "type": "paragraph",
        "children": [
          { "type": "text", "text": "Normaler Text " },
          { "type": "text", "text": "fett", "bold": true },
          {
            "type": "link",
            "url": "https://example.org",
            "children": [{ "type": "text", "text": "Quelle" }],
          },
        ],
      },
      {
        "type": "list",
        "format": "unordered",
        "children": [{ "type": "list-item", "children": [{ "type": "text", "text": "Punkt" }] }],
      },
      { "type": "quote", "children": [{ "type": "text", "text": "Zitat" }] },
      { "type": "image", "url": "https://…", "alternativeText": "…", "width": 800, "height": 600 },
    ],
    "eventStart": null,
    "eventEnd": null,
    "eventAllDay": false,
  },
  "meta": { "…": "…", "droppedBlockTypes": [] },
}
```

**Unterstützte Blocktypen im MVP:** `paragraph`, `heading`, `list`, `list-item`, `quote`, `image`
sowie inline `text` und `link`.

Unbekannte Blocktypen werden **serverseitig verworfen** und in `meta.droppedBlockTypes` gemeldet.
Der Client rendert damit nie einen unbekannten Typ; eine neue Strapi-Blockart kann die Detailseite
nicht zerstören. Inline-`link`-URLs werden auf `https:`, `mailto:` und `tel:` beschränkt.

## 6. Kontakte

### `GET /v1/contact-areas`

Nur aktive Bereiche, sortiert nach `sortOrder`, dann `name`.

```jsonc
{
  "data": [
    {
      "slug": "studierendenrat",
      "name": "Studierendenrat",
      "shortDescription": "Die gewählte Vertretung der Studierendenschaft.",
      "iconKey": "students-council",
      "sortOrder": 10,
      "generalEmail": null,
      "phone": null,
      "website": null,
      "appointmentBookingUrl": null,
      "address": null,
      "openingHours": null,
      "personCount": 0,
    },
  ],
  "meta": { "…": "…" },
}
```

Alle Kontaktfelder sind **optional** und `null`, wenn nicht gepflegt. Ein Bereich **ohne**
Kontaktperson ist gültig (`personCount: 0`) und muss im Client vollständig nutzbar bleiben.

### `GET /v1/contact-areas/:slug`

Zusätzlich `description` (Blocks, gleiche Regeln wie News-`content`) und `persons` — nur aktive
Personen, sortiert nach `sortOrder`, dann `name`.

Welche Personen ein Bereich hat, bestimmt in jeder Sprache die kanonische deutsche Fassung — dieselbe
Quelle, aus der die Liste `personCount` zählt; das gilt auch für den Suchindex. Aus der
Übersetzung kommen nur `role` und `description`. Fehlt dort ein gepflegter Text, bleibt der
deutsche stehen und `translationFallback` ist `true`.

```jsonc
{
  "data": {
    "slug": "studierendenrat",
    "name": "…",
    "shortDescription": "…",
    "iconKey": "…",
    "generalEmail": null,
    "phone": null,
    "website": null,
    "appointmentBookingUrl": null,
    "address": null,
    "openingHours": null,
    "description": [],
    "persons": [
      {
        "name": "…",
        "role": "…",
        "description": null,
        "email": null,
        "phone": null,
        "website": null,
        "profileImage": null,
      },
    ],
  },
  "meta": { "…": "…" },
}
```

Eine Person kann in **mehreren** Bereichen erscheinen.

### `GET /v1/contact-areas/search-index`

Alles, was die Kontaktsuche treffen kann, in **einer** Antwort.

Der Listenendpunkt trägt bewusst keine Detaildaten. Eine Suche über Beschreibungen, Telefonnummern
oder Raumnummern müsste deshalb jeden Bereich einzeln nachladen — ein N+1 bei jedem Tastendruck.
Stattdessen lädt der Client diesen Index **einmal**, cacht ihn und sucht lokal.

```jsonc
{
  "data": [
    {
      "slug": "studierendenrat",
      "name": "…",
      "shortDescription": "…",
      "iconKey": "…",
      "descriptionText": "Wir helfen bei Anträgen.\nSprechzeiten nach Vereinbarung.",
      "generalEmail": null,
      "phone": null,
      "website": null,
      "appointmentBookingUrl": null,
      "address": null,
      "openingHours": null,
      "rooms": [{ "roomKey": "…", "roomNumber": "B.201", "…": "…" }],
      "persons": [
        {
          "name": "…",
          "role": "…",
          "description": null,
          "email": null,
          "phone": null,
          "website": null,
          "rooms": [],
        },
      ],
    },
  ],
  "meta": { "…": "…" },
}
```

Verbindliche Regeln:

- **Nur aktive** Bereiche und **nur aktive** Personen.
- Ausschließlich **explizit gemappte, öffentliche** Felder. Keine Strapi-Internas, keine IDs.
- **Kein `profileImage`:** Nach einem Bild sucht niemand, und ein Index ist der falsche Ort, um
  mehr herauszugeben als die Frage braucht.
- `descriptionText` ist die **bereinigte** Beschreibung als Klartext. Eine Suche trifft Wörter,
  keine Formatierung: Links steuern ihren Linktext bei, ihre URL nicht, Bilder gar nichts.
  Blöcke sind durch `\n` getrennt.
- Locale-Auflösung und Raum-Mapping verhalten sich exakt wie beim Detailendpunkt; fehlt die
  englische Fassung, bleibt der deutsche Text und `translationFallback` ist `true`.
- Höchstens **zwei** Strapi-Anfragen (kanonisch plus angeforderte Sprache), unabhängig von der
  Anzahl der Bereiche.

## 7. Mensa

### `GET /v1/canteens`

Ausschließlich aus Backend-Daten. Der Client kennt **keine** `location_id`.

```jsonc
{
  "data": [
    {
      "slug": "koethen-fasanerieallee",
      "displayName": "Mensa Köthen",
      "campusLabel": "Fasanerieallee",
      "lastSuccessfulSyncAt": "2026-07-22T12:00:04.000Z",
      "dataStale": false,
    },
  ],
  "meta": { "…": "…" },
}
```

`displayName` und `campusLabel` sind API-eigene, zweisprachige Texte.

### `GET /v1/canteens/:slug/menu`

| Parameter | Typ          | Standard         | Regeln                                              |
| --------- | ------------ | ---------------- | --------------------------------------------------- |
| `from`    | `YYYY-MM-DD` | heute            | „heute“ ist der Kalendertag in `Europe/Berlin`      |
| `to`      | `YYYY-MM-DD` | `from` + 13 Tage | `to >= from`, Spanne **max. 31 Tage** ⇒ sonst `400` |
| `locale`  | `de` \| `en` | `de`             |                                                     |

```jsonc
{
  "data": {
    "canteen": { "slug": "…", "displayName": "…", "campusLabel": "…" },
    "days": [
      {
        "date": "2026-07-20",
        "meals": [
          {
            "id": "58033",
            "name": "Bulgur-Pfanne",
            "subtitle": "mit Kichererbsen, Wirsing und Kräuterdip",
            "sourceLanguage": "de",
            "counterId": 44,
            "isSprint": true,
            "extras": [],
            "markers": [
              { "code": "52", "label": "vegan", "kind": "ingredient" },
              { "code": "53", "label": "Sprint-Menü", "kind": "marker" },
              { "code": "A1", "label": "enthält Weizengluten", "kind": "ingredient" },
            ],
            "traits": ["vegan", "sprint"],
            "allergens": ["gluten", "gluten_wheat"],
            "prices": [
              { "group": "student", "label": "Studierende", "amount": "1.95", "currency": "EUR" },
              { "group": "employee", "label": "Bedienstete", "amount": "4.95", "currency": "EUR" },
              { "group": "guest", "label": "Gäste", "amount": "7.00", "currency": "EUR" },
            ],
          },
        ],
      },
    ],
  },
  "meta": {
    "requestedLocale": "en",
    "resolvedLocale": "en",
    "translationFallback": true,
    "lastSuccessfulSyncAt": "2026-07-22T12:00:04.000Z",
    "dataStale": false,
    "from": "2026-07-20",
    "to": "2026-08-02",
  },
}
```

Verbindliche Regeln:

- **Es gibt kein Bildfeld.** `food.image_url` der Quelle wird weder gespeichert noch ausgeliefert.
- `amount` ist ein **String in Dezimaldarstellung**, damit keine Float-Rundung entsteht. Die
  Formatierung übernimmt der Client locale-gerecht.
- Es werden **alle** in der Quelle vorhandenen Preisgruppen ausgeliefert. Fehlt eine Gruppe, fehlt
  der Eintrag — es wird **kein** Preis geschätzt. Der Client hebt `group: "student"` hervor.
- `group` ist ein stabiler technischer Schlüssel, `label` der übersetzte Anzeigetext.
- `markers` führt Zutaten und Marker in **einer** Liste mit unterscheidendem `kind`, weil die
  Quelle beide Namensräume in `food.ingredients` mischt.
- `traits` und `allergens` sind **stabile semantische Schlüssel**. Clients filtern ausschließlich
  darüber — **nie** über `markers[].code` oder `markers[].label`. Der Codenamensraum gehört der
  Quelle: er ist nirgends dokumentiert, mischt zwei Namensräume und darf sich jederzeit ändern.
  Details zur Zuordnung: [data-sources.md](data-sources.md).

  | Feld        | Werte                                                                                                                                                                                                                                                                                                                                         |
  | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | `traits`    | `vegetarian`, `vegan`, `meatless`, `sprint`                                                                                                                                                                                                                                                                                                   |
  | `allergens` | `gluten` (+ `gluten_wheat`, `gluten_rye`, `gluten_oats`, `gluten_barley`, `gluten_spelt`), `crustaceans`, `egg`, `peanuts`, `soy`, `milk`, `nuts` (+ `nuts_hazelnut`, `nuts_almond`, `nuts_walnut`, `nuts_cashew`, `nuts_pecan`, `nuts_pistachio`, `nuts_macadamia`), `celery`, `mustard`, `sesame`, `sulphites`, `lupin`, `molluscs`, `fish` |

  Ein Untertyp wird **immer** zusammen mit seiner Elternfacette ausgeliefert: Wer Gluten meidet,
  muss nicht wissen, dass `A1` Weizen bedeutet. Beide Arrays sind nach dieser Taxonomie sortiert,
  nicht nach der Reihenfolge der Quelle.

- Ein Marker, den die API **nicht** einordnen kann, bleibt in `markers` sichtbar und bekommt
  **keinen** erfundenen Schlüssel. `traits` und `allergens` sagen damit nur aus, was die Quelle
  tatsächlich erklärt hat.
- `sprint` stammt aus dem `is_sprint`-Feld des Planeintrags, nicht aus einem Marker-Code.
- `sourceLanguage: "de"` zeigt an, dass `name`, `subtitle`, `extras` und `markers[].label` aus der
  deutschsprachigen Quelle stammen und **nicht** übersetzt wurden.
- Ein Tag **ohne** Gerichte erscheint als leeres `meals`-Array — ein echter leerer Tag ist damit
  vom Ladefehler unterscheidbar.
- `dataStale` ist `true`, wenn `lastSuccessfulSyncAt` älter als `CANTEEN_STALE_AFTER_MINUTES` ist.
  `lastSuccessfulSyncAt: null` bedeutet: noch nie erfolgreich synchronisiert.

## 8. Stundenplan

Quelle ist die **öffentliche** WebUntis-Ansicht. Sie wird ausschließlich serverseitig abgerufen —
siehe [data-sources.md](data-sources.md). Der Client sieht **niemals** eine WebUntis-URL, einen
WebUntis-Header, eine Schuljahres-ID oder eine externe Gruppen-ID.

Das Feature ist über `WEBUNTIS_ENABLED` schaltbar und steht **standardmäßig auf `false`**, bis die
Nutzung organisatorisch freigegeben ist. Deaktiviert antworten die Endpunkte weiterhin mit `200`
und einem klaren Zustand — nicht mit einem Fehler, damit der Client das verständlich darstellen
kann statt wie ein Absturz.

### `GET /v1/timetable/groups`

| Parameter    | Typ                      | Regeln                                                      |
| ------------ | ------------------------ | ----------------------------------------------------------- |
| `query`      | String, max. 100 Zeichen | Suche über Kurzname, Langname und Bereich; case-insensitive |
| `department` | String                   | exakter Bereichsfilter (`shortName`)                        |
| `page`       | Integer, mindestens 1    | Seite; Standard `1`                                         |
| `pageSize`   | Integer, 1 bis 50        | Einträge pro Seite; Standard `20`                           |
| `locale`     | `de` \| `en`             | wie überall                                                 |

Liefert den vollständigen sichtbaren Katalog **paginiert** und ohne feste
Gesamtkappung. `query` wird serverseitig ausgewertet, damit auch Treffer hinter
der ersten Seite auffindbar sind. Sortierung: `shortName`, `longName`,
`department`, `id` jeweils aufsteigend. Exakte, anhand ihrer Stundenplandaten
bestätigte Aliasse werden innerhalb desselben Semesterkatalogs auf einen sichtbaren
Eintrag konsolidiert; Gruppen mit abweichenden Plänen bleiben auch bei gleichem Namen
getrennt sichtbar, ebenso gleichnamige Gruppen verschiedener Semester.

```jsonc
{
  "data": [
    {
      "id": "8f1c…", // Campus-UUID, stabil
      "shortName": "AIN2 - BT",
      "longName": "AIN2-Angewandte Informatik Vertiefung: Biotechnologie",
      "department": "FB5", // oder null
    },
  ],
  "meta": {
    "requestedLocale": "de",
    "resolvedLocale": "de",
    "translationFallback": false,
    "pagination": {
      "page": 1,
      "pageSize": 20,
      "total": 503,
      "totalPages": 26,
    },
    "featureEnabled": true,
    "from": "2026-07-30",
    "to": "2026-08-27", // Ende des konfigurierten Stundenplan-Zeitfensters
    "lastSuccessfulSyncAt": "…",
    "dataStale": false,
  },
}
```

Es gibt **kein** Feld mit der WebUntis-ID.

### `GET /v1/timetable/groups/:groupId`

Löst eine bereits gespeicherte **Campus-UUID** einzeln auf. Dadurch müssen
Kaltstart, Einstellungen und Kalender nicht den Gruppenkatalog laden. Ein durch
die Dublettenprüfung ausgeblendeter Alt-Alias liefert seinen sichtbaren
Vertreter aus demselben Semesterkatalog, nie eine gleichnamige Gruppe eines
anderen Semesters; der Client kann die lokale Campus-UUID darauf migrieren. Die Antwort
hat dieselbe öffentliche Gruppenform und dieselben Zeitraum-/Freshness-Metadaten
wie der Katalog, aber keinen Pagination-Block. Unbekannte oder syntaktisch
ungültige UUIDs liefern den unten beschriebenen Fehlervertrag. Externe IDs
werden auch hier nie ausgegeben.

### `GET /v1/timetable/periods`

Liefert bis zu acht synchronisierte Semesterkataloge in chronologischer Reihenfolge. Der
Semester-Assistent nutzt die Zuordnung ausschließlich, um nach Ende des gewählten Zeitraums einen
neuen Hauptkurs vorzuschlagen; ein Wechsel erfolgt nie automatisch. Deaktiviertes WebUntis liefert
eine leere Liste. Schuljahres- und Klassen-IDs der Quelle bleiben serverintern.

```jsonc
{
  "data": [
    {
      "id": "6ca8…",
      "name": "2026/2027",
      "validFrom": "2026-10-05",
      "validTo": "2027-03-31",
      "groups": [
        {
          "id": "8f1c…",
          "shortName": "AIN3",
          "longName": "Angewandte Informatik 3. Semester",
          "department": "FB5",
        },
      ],
    },
  ],
  "meta": {
    "requestedLocale": "de",
    "resolvedLocale": "de",
    "translationFallback": false,
    "featureEnabled": true,
    "lastSuccessfulSyncAt": "…",
    "dataStale": false,
  },
}
```

Ein vollständiger, nicht-leerer Kataloglauf aktualisiert die Gruppen-Zuordnung eines Zeitraums
transaktional. Eine leere, teilweise nicht persistierbare oder fehlgeschlagene Antwort behält die
letzte erfolgreiche Zuordnung.

### `GET /v1/timetable/modules`

`groupId` ist erforderlich und muss eine Campus-UUID sein; unbekannte Gruppen liefern
`404 TIMETABLE_GROUP_NOT_FOUND`. Der Endpunkt listet die bereits für diese Studiengruppe
beobachteten Module aus dem operativen Campus-Datenbestand. Er löst keinen WebUntis-Aufruf aus und
liefert weder Schuljahres-, Klassen- noch andere interne Quell-IDs.

```jsonc
{
  "data": [
    {
      "subjectCode": "MATH2",
      "title": "Mathematik 2",
    },
    {
      "subjectCode": null,
      "title": "Wahlpflichtfach Robotik",
    },
  ],
  "meta": {
    "requestedLocale": "de",
    "resolvedLocale": "de",
    "translationFallback": false,
    "featureEnabled": true,
    "lastSuccessfulSyncAt": "…",
    "dataStale": false,
  },
}
```

Codes und Titel stammen unverändert aus der Quelle. Die App bildet daraus nur lokal einen stabilen
Auswahlschlüssel, lädt den Zeitplan der zugehörigen Studiengruppe über deren Campus-UUID und lässt
bei einem Modul-Abo alle nicht gewählten Module dieser Gruppe aus der Zusammenführung heraus.

### `GET /v1/timetable/entries`

| Parameter | Typ          | Regeln                                                                |
| --------- | ------------ | --------------------------------------------------------------------- |
| `groupId` | UUID         | **erforderlich**; unbekannt ⇒ `404 TIMETABLE_GROUP_NOT_FOUND`         |
| `from`    | `YYYY-MM-DD` | **erforderlich**                                                      |
| `to`      | `YYYY-MM-DD` | **erforderlich**, `to >= from`, Spanne max. **42 Tage** ⇒ sonst `400` |
| `locale`  | `de` \| `en` |                                                                       |

```jsonc
{
  "data": {
    "group": { "id": "8f1c…", "shortName": "AIN2 - BT", "longName": "…", "department": "FB5" },
    "days": [
      {
        "date": "2026-07-20",
        "entries": [
          {
            "id": "…",
            "start": "2026-07-20T08:00:00.000Z",
            "end": "2026-07-20T09:30:00.000Z",
            "timezone": "Europe/Berlin",
            "title": "Englisch als Fremdsprache",
            "subjectCode": "Englisch als Fremdsp",
            "type": "regular_teaching | additional | unknown",
            "status": "regular | changed | cancelled | unknown",
            "teachers": [{ "shortName": "D-Demo01", "displayName": "Demo Demoperson01" }],
            "rooms": [{ "shortName": "D-04/201", "longName": "Seminarraum VM/GIN" }],
            "groups": [{ "id": "8f1c…", "shortName": "AIN2 - BT" }],
            "note": null,
            "lessonInfo": null,
          },
        ],
      },
    ],
  },
  "meta": {
    "requestedLocale": "de",
    "resolvedLocale": "de",
    "translationFallback": true,
    "timezone": "Europe/Berlin",
    "from": "2026-07-20",
    "to": "2026-08-02",
    "lastSuccessfulSyncAt": "…",
    "dataStale": false,
    "dataState": "ready | pending | unavailable",
    "featureEnabled": true,
  },
}
```

Verbindliche Regeln:

- **Jeder Tag des Zeitraums** erscheint, auch ohne Einträge. Ein echter freier Tag ist dadurch vom
  Ladefehler unterscheidbar — dieselbe Regel wie beim Speiseplan.
- `start`/`end` sind **absolute UTC-Zeitpunkte**. Die fachliche Zone `Europe/Berlin` steht
  zusätzlich im Vertrag, weil die Quelle lokale Wandzeit ohne Zone liefert.
- `status` und `type` sind **normalisierte technische Schlüssel**. Ein unbekannter Quellwert wird
  auf `unknown` abgebildet und bricht nichts.
- `teachers`, `rooms`, `groups` und `title` stammen aus dem Fremdsystem und werden **nie**
  übersetzt. Deshalb ist `translationFallback` bei `locale=en` `true`.
- `lessonInfo` enthält die optionale „Information zur Stunde“ aus WebUntis und wird getrennt
  von `note` gespeichert und unverändert in der Quellsprache angezeigt.
- `dataState`:
  - `ready` — Daten liegen vor,
  - `pending` — Feature aktiv, aber noch kein erfolgreicher Lauf für diesen Zeitraum,
  - `unavailable` — Feature deaktiviert oder dauerhaft kein Datenstand.

### `GET /v1/timetable/lesson-info`

Liefert die filterbaren „Information zur Stunde“-Texte für eine Stundenplangruppe aus dem zuletzt
erfolgreich synchronisierten Zeitraum. `groupId` ist erforderlich und muss eine Campus-UUID sein;
unbekannte Gruppen liefern `404 TIMETABLE_GROUP_NOT_FOUND`. Der Endpunkt fragt WebUntis nicht live ab.

```jsonc
{
  "data": {
    "values": ["Gruppe1", "P1"],
    "hasWithoutInfo": true,
  },
  "meta": { "requestedLocale": "de", "resolvedLocale": "de", "translationFallback": false },
}
```

Die Texte werden exakt als unterschiedliche Filteroptionen übernommen; es gibt keine Ableitung
von Studiengang oder Praktikumsgruppe. `hasWithoutInfo` steuert die separate Option für Termine
ohne diese Angabe. In der App sind alle Optionen zunächst aktiviert. Abgewählte Optionen werden
lokal pro Stundenplangruppe gespeichert und filtern nur die Anzeige, nicht den Backend-Datenbestand.

### `GET /v1/timetable/status`

Öffentlicher, bewusst magerer Zustand. Enthält **keine** URLs, Header, externen IDs oder
Fehlerdetails der Quelle.

```jsonc
{
  "data": {
    "featureEnabled": true,
    "groupCount": 270,
    "lastGroupSyncAt": "2026-07-22T03:00:11.000Z",
    "lastEntrySyncAt": "2026-07-22T17:30:04.000Z",
    "dataStale": false,
    "coveredFrom": "2026-07-15",
    "coveredTo": "2026-08-19",
  },
  "meta": { "requestedLocale": "de", "resolvedLocale": "de", "translationFallback": false },
}
```

### Fehlercodes

| Code                        | Status                                                |
| --------------------------- | ----------------------------------------------------- |
| `TIMETABLE_GROUP_NOT_FOUND` | 404                                                   |
| `VALIDATION_FAILED`         | 400 (ungültiges Datum, `to < from`, Spanne > 42 Tage) |

## 9. Öffentliche Kalender

Quelle sind **öffentliche** Google-Kalender, die die Redaktion in Strapi freigibt. Der Worker lädt
deren **öffentlichen ICS-Feed** — siehe [public-calendars.md](public-calendars.md). Der Client
sieht **niemals** die Feed-URL, einen ETag oder den `lastContentHash`.

Eine bewusste Ausnahme ist die Google-Kalender-ID: Sie steckt base64-kodiert im `cid`-Parameter von
`googleOpenUrl` und im Klartext in den `src`-Parametern von `/v1/calendars/google-view-url`. Ohne
sie könnten diese Links nicht funktionieren. Das ist unkritisch, weil es sich per Definition um
Kalender handelt, die die Redaktion öffentlich geteilt hat — die ID ergibt sich ohnehin aus dem
öffentlichen Share-Link. Sie ist damit **kein** Geheimnis, anders als die Feed-URL und die
Sync-Validatoren, die backendintern bleiben.

Das Feature ist über `PUBLIC_CALENDAR_ENABLED` schaltbar und steht **standardmäßig auf `false`**.
Ausgeliefert werden ausschließlich Kalender, die aktiv **und** validiert sind **und** mindestens
einmal erfolgreich synchronisiert wurden.

### `GET /v1/calendars`

Der Katalog. Keine Parameter außer `locale`.

```jsonc
{
  "data": [
    {
      "id": "3d9a…", // Campus-UUID
      "slug": "stura-termine", // stabiler Bezeichner, Auswahlschlüssel der App
      "channelSlug": "campus-events", // oder null
      "name": "StuRa-Termine",
      "colorHex": "#5B3FD0",
      "sortOrder": 10,
      "defaultSubscribed": true,
      "dataState": "ready", // "ready" | "stale"
      "lastSuccessfulSyncAt": "2026-07-30T06:10:00.000Z",
      "dataStale": false,
      "googleOpenUrl": "https://calendar.google.com/…", // serverseitig konstruiert
    },
  ],
  "meta": {
    "requestedLocale": "de",
    "resolvedLocale": "de",
    "translationFallback": false,
    "featureEnabled": true,
    "from": "2026-07-30",
    "to": "2027-01-26", // Ende des konfigurierten Kalender-Importfensters
    "maxRangeDays": 120, // größte Spanne je Terminabfrage
  },
}
```

`defaultSubscribed` wertet die App **genau einmal** pro Slug aus — beim erstmaligen Auftauchen.
Ein Backend-Update überschreibt eine bewusste Abwahl nie. Dieselbe Regel wie bei Posts-Kanälen.
`channelSlug` verknüpft einen Kalender 1:1 mit einem redaktionellen Kanal (oder `null`).
Die Kalender-Liste teilt den Bereich bis `meta.to` in Abfragen von höchstens `meta.maxRangeDays`
Tagen; ihre Reichweite ist damit nicht auf eine feste Tageszahl im Client begrenzt.

### `GET /v1/calendars/events`

Aggregierte Termine über **mehrere** ausgewählte Kalender. Das Abfrageintervall ist als **Überlappung** definiert: `startsAt <= to AND endsAt >= from`.

| Parameter  | Typ          | Regeln                                                                                      |
| ---------- | ------------ | ------------------------------------------------------------------------------------------- |
| `calendar` | Slug         | **mehrfach** angebbar, ein Slug je Kalender; dedupliziert; max. 50                          |
| `from`     | `YYYY-MM-DD` | optional, Standard heute                                                                    |
| `to`       | `YYYY-MM-DD` | optional, `to >= from`, Spanne max. Server-Maximalbereich (Standard 400 Tage) ⇒ sonst `400` |
| `locale`   | `de` \| `en` |                                                                                             |

**Eine leere Auswahl liefert eine leere Liste — niemals „alle Kalender“.** Das ist bewusst so: Ein
vergessener Parameter darf nicht stillschweigend alles ausliefern.

Kalenderzahl und Zeitraum sind begrenzt, die Zahl der darin liegenden Termine ist es nicht. Die
Antwort ist deshalb zusätzlich auf `PUBLIC_CALENDAR_API_MAX_EVENTS` (Standard 2000) gedeckelt.
Wird die Grenze erreicht, steht `meta.truncated: true` in der Antwort — die Liste wird nie
stillschweigend gekürzt. Die Sortierung ist deterministisch, der Schnitt damit reproduzierbar.

```jsonc
{
  "data": [
    {
      "id": "…",
      "calendarId": "3d9a…",
      "calendarSlug": "stura-termine", // damit die App Farbe und Name zuordnen kann
      "title": "Sitzung des Studierendenrats",
      "description": null, // nur bei includeEventDescription, immer Plain Text
      "location": null, // nur bei includeEventLocation, immer Plain Text
      "start": "2026-08-04T16:00:00.000Z",
      "end": "2026-08-04T18:00:00.000Z",
      "allDay": false,
      "status": "confirmed", // "confirmed" | "tentative" | "cancelled"
    },
  ],
  "meta": {
    "requestedLocale": "de",
    "resolvedLocale": "de",
    "translationFallback": false,
    "from": "2026-07-30",
    "to": "2026-11-27",
  },
}
```

Die Sortierung ist deterministisch. Wiederholungen sind bereits serverseitig zu einzelnen Terminen
expandiert; der Client kennt **keine** `RRULE`.

### `GET /v1/calendars/:slug/events`

Termine **eines** Kalenders. Parameter `from`, `to`, `locale` wie oben. Unbekannter oder nicht
auslieferbarer Slug ⇒ `404 PUBLIC_CALENDAR_NOT_FOUND`.

Die Antwort trägt zusätzlich `lastSuccessfulSyncAt` und `dataStale` in `meta`, damit die App den
Frischezustand genau dieses Kalenders anzeigen kann. Dieselbe Obergrenze und dasselbe
`meta.truncated` wie bei der aggregierten Abfrage gelten auch hier.

### `GET /v1/calendars/google-view-url`

| Parameter  | Typ  | Regeln                                                     |
| ---------- | ---- | ---------------------------------------------------------- |
| `calendar` | Slug | **erforderlich**, mehrfach angebbar, dedupliziert, max. 50 |

```jsonc
{
  "data": { "url": "https://calendar.google.com/calendar/embed?src=…&ctz=…" },
  "meta": { "requestedLocale": "de", "resolvedLocale": "de", "translationFallback": false },
}
```

Die URL wird **serverseitig** konstruiert (ein `src` je Kalender). Sie ist eine reine
**Ansicht** — es wird dabei nichts zum persönlichen Google-Konto der nutzenden Person hinzugefügt.
Stundenplan und Moodle sind keine Google-Quellen und niemals Teil dieser kombinierten Ansicht.

### Fehlercodes

| Code                        | Status                                                                                         |
| --------------------------- | ---------------------------------------------------------------------------------------------- |
| `PUBLIC_CALENDAR_NOT_FOUND` | 404                                                                                            |
| `VALIDATION_FAILED`         | 400 (ungültiger Slug, ungültiges Datum, mehr als konfigurierter Maximalbereich, > 50 Kalender) |

## 10. Räume (Lageplan)

Der öffentliche Raumkatalog des **fiktiven** Demo-Lageplans. Die Kartengeometrie ist **nicht** Teil
dieser API — sie ist ein gebündeltes App-Asset (siehe [campus-map.md](campus-map.md)). Hier kommen
nur Bezeichnungen und redaktionelle Texte.

Ausgeliefert werden ausschließlich Räume mit `catalogActive=true` **und** `isVisible=true`.

### `GET /v1/rooms`

| Parameter     | Typ          | Regeln                   |
| ------------- | ------------ | ------------------------ |
| `buildingKey` | Slug         | optional, exakter Filter |
| `floorKey`    | Slug         | optional, exakter Filter |
| `locale`      | `de` \| `en` | wie überall              |

Der Katalog ist klein und wird vollständig ausgeliefert: Der Client cacht ihn und sucht **lokal**.
Es gibt bewusst **keine** serverseitige Volltextsuche.

```jsonc
{
  "data": [
    {
      "roomKey": "ratke-gebaeude-first-floor-216", // stabiler Bezeichner, auch der Deep-Link-Schlüssel
      "roomNumber": "216",
      "buildingKey": "ratke-gebaeude",
      "buildingName": "Ratke-Gebäude", // lokalisiert
      "floorKey": "ratke-gebaeude-first-floor",
      "floorName": "1. Obergeschoss", // lokalisiert
      "roomType": "lecture", // stabiler technischer Schlüssel, Label kommt aus der App
      "displayName": null, // optional, redaktionell, lokalisiert
      "description": null, // optional, redaktionell, lokalisiert
      "mapVersion": "campus-koethen-2026-08-26",
      "sortOrder": 10,
    },
  ],
  "meta": { "requestedLocale": "de", "resolvedLocale": "de", "translationFallback": false },
}
```

`roomType` ist eines von `lecture`, `seminar`, `office`, `lab`, `meeting`, `service`. Ein der App
unbekannter Wert wird dort auf eine neutrale Bezeichnung abgebildet und bricht nichts.

### `GET /v1/rooms/:roomKey`

Ein Raum. Unbekannter, unsichtbarer oder deaktivierter Schlüssel ⇒ `404 ROOM_NOT_FOUND`.

### Raumreferenzen in Kontakten

`GET /v1/contact-areas/:slug` liefert für den Bereich **und** für jede Person zusätzlich `rooms`:

```jsonc
{
  "rooms": [
    {
      "roomKey": "ratke-gebaeude-first-floor-216",
      "roomNumber": "216",
      "buildingName": "Ratke-Gebäude",
      "floorName": "1. Obergeschoss",
      "displayName": null,
    },
  ],
}
```

**Eine leere Liste ist der Normalfall** — ein Kontakt braucht keinen Raum, und die App rendert
dann gar nichts. Eine Raumreferenz enthält nie eine Strapi-ID.

### Fehlercodes

| Code                | Status                                    |
| ------------------- | ----------------------------------------- |
| `ROOM_NOT_FOUND`    | 404                                       |
| `VALIDATION_FAILED` | 400 (ungültiger `buildingKey`/`floorKey`) |

## 11. Redaktionelle Bilder

### `GET /v1/media/uploads/:filename`

Liefert ein redaktionelles Bild aus der Mediathek des CMS — der einzige Endpunkt dieser API, der
Bytes statt JSON zurückgibt.

Er existiert, damit die App **niemals** mit Strapi sprechen muss (AGENTS.md §2.1). Strapis lokaler
Upload-Provider veröffentlicht ohnehin nur **relative** URLs, die auf einem Telefon nicht auflösbar
wären. Alle Bildfelder der API — `heroImage`, `image` eines Kontaktbereichs, `profileImage` einer
Kontaktperson und jeder `image`-Block — verweisen deshalb hierher.

Regeln, die der Endpunkt durchsetzt:

- **Nur** Dateien unmittelbar unter `/uploads/`. Kein Unterverzeichnis, kein `..` in irgendeiner
  Schreibweise, keine Query, kein Fragment, keine Prozentkodierung.
- **Nur Rasterbilder** (`image/png`, `image/jpeg`, `image/webp`, `image/gif`, `image/avif`). Alles
  andere wäre ein allgemeiner Dateiproxy für die gesamte Mediathek. `image/svg+xml` ist bewusst
  **nicht** dabei: ein SVG ist ein XML-Dokument, das `<script>` tragen kann, und die Antwort ist
  `Content-Disposition: inline` — ein Browser würde es auf der Origin dieser API ausführen.
  Verloren geht dadurch nichts, weil kein Client dieses Projekts entferntes SVG darstellt.
- Keine Weiterleitungen, harte Größengrenze, `X-Content-Type-Options: nosniff`.
- **Keine Transportkompression.** PNG, JPEG, WebP, GIF und AVIF sind bereits komprimierte
  Container; sie ein zweites Mal durch `gzip` zu schicken kostet auf beiden Seiten Rechenzeit und
  liefert ein eher größeres Ergebnis.
- `Cache-Control: public, max-age=86400` — ein ausgetauschtes Bild bekommt vom CMS einen neuen
  Dateinamen, sodass ein langer Cache nichts veraltet. Das gilt **nur** für `200` und `304`.
  Fehlerantworten (`404`, `503`, …) tragen wie jede Fehlerantwort der API
  `Cache-Control: no-store`, damit ein kurzer CMS-Ausfall kein Bild für einen Tag verschwinden
  lässt.

#### Revalidierung mit `If-None-Match`

Die Antwort trägt den `ETag` des CMS. Schickt der Client ihn als `If-None-Match` zurück, wird er
an das CMS **weitergereicht**: Ist das Bild unverändert, antwortet die API mit `304 Not Modified`
— mit `ETag` und `Cache-Control`, ohne Body — **ohne das Bild vorher zu laden**.

Für den Client ändert sich dadurch nichts: Ein `304` kam auch vorher schon zurück, weil Express
selbst auf Frische prüft. Neu ist, dass dabei nicht mehr das vollständige Bild (bis 12 MB) vom CMS
geholt und im API-Prozess gepuffert wird, nur um verworfen zu werden. Für einen Client, der
regelmäßig revalidiert, ist das der Unterschied zwischen einer teuren und einer billigen Antwort.

Akzeptiert werden `*` und kommaseparierte Entity-Tags, stark oder schwach, bis 256 Zeichen. Ein
Wert, der dieser Form nicht entspricht, wird **nicht** weitergereicht; die Anfrage verhält sich
dann wie eine ohne `If-None-Match` und liefert das vollständige Bild.

| Status | Bedeutung                                                     |
| ------ | ------------------------------------------------------------- |
| `200`  | Bild im Body, mit `ETag` und `Content-Type`                   |
| `304`  | Die Kopie des Clients ist aktuell; kein Body, kein Downstream |

Antwortet ein Pfad nicht diesen Regeln, ist die Antwort `404 MEDIA_NOT_FOUND` — bewusst dieselbe
wie für eine schlicht nicht vorhandene Datei.

#### Revalidieren mit `If-None-Match`

Die Antwort trägt den `ETag` des CMS. Schickt ein Client ihn als `If-None-Match` zurück und ist das
Bild unverändert, lautet die Antwort `304 Not Modified` — ohne Body, mit `ETag` und
`Cache-Control`. Andernfalls kommt das vollständige Bild mit `200`.

Der Header wird dabei **an das CMS durchgereicht**. Das ist der eigentliche Gewinn: ohne ihn zieht
das Backend bei jeder Revalidierung das ganze Bild aus dem CMS in den eigenen Speicher, nur um
festzustellen, dass der Client es längst hat. Dieser Endpunkt ist in Bytes der teuerste der API.

Was der Header **nicht** beeinflusst: die Zieladresse. Sie ergibt sich ausschließlich aus der
Pfad-Allowlist oben. Der Wert wird gegen die Grammatik aus RFC 9110 §8.8.3 geprüft (`*` oder eine
Liste von Entity-Tags) und ist auf 256 Zeichen begrenzt; ein Wert, der das nicht erfüllt, wird
**ignoriert** statt abgelehnt — die Anfrage läuft dann unkonditional und die Antwort ist die
gewohnte `200`.

Ohne `If-None-Match` verhält sich der Endpunkt unverändert.

| Code                   | Status |
| ---------------------- | ------ |
| `MEDIA_NOT_FOUND`      | 404    |
| `UPSTREAM_UNAVAILABLE` | 503    |

## 12. Was der Client garantiert nicht braucht

- keine Strapi-URL, kein Strapi-Token
- keine `location_id` und keine Kenntnis der Preisfeld-Nummerierung der Quelle
- keine WebUntis-URL, keinen WebUntis-Header, keine Schuljahres-ID, keine externe Gruppen-ID
- keine Google-Kalender-ID, keine ICS-Feed-URL und keinen ETag
- keine hartcodierte Kanal-, Mensa-, Bereichs-, Gruppen- oder Kalenderliste
- keine `RRULE`-Auswertung — Wiederholungen kommen bereits expandiert an
- keine Kartengeometrie: das SVG und die roomKey→Geometrie-Zuordnung sind gebündelte App-Assets

## 13. Nicht Teil dieser API

Die persönlichen Dienste **E-Mail**, **Noten** und **Moodle** laufen ausdrücklich **nicht** über
die Campus API. Die App spricht dafür direkt mit dem jeweiligen offiziellen Anbieter, damit weder
Campus API noch Strapi noch Worker Zugangsdaten oder persönliche Inhalte erhalten. Es gibt für sie
weder eine Route noch ein DTO noch eine Tabelle — siehe [architecture.md](architecture.md) §3.6 und
Grenzen G10–G12.
