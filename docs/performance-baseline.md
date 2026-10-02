# Performance-Baseline und Budgets

Campus Köthen App · `AGPL-3.0-only` · Copyright © 2026 Leviora Studio and Jona Loreen Sommer

---

## 1. Zweck

Dieses Dokument legt fest, **wie** in diesem Projekt gemessen wird, **was** dabei
herausgekommen ist und **welche Grenzen** eine spätere Änderung einhalten muss. Es ist die
Grundlage für die Optimierungstickets und die Abnahme: Ohne eine Messung nach diesem Verfahren
gilt eine Performance-Aussage hier als unbelegt.

Zwei Dinge stehen bewusst **nicht** hier: eine Liste wünschenswerter Optimierungen und
Mikrooptimierungen ohne messbaren Nutzen. Abschnitt 8 nennt umgekehrt ausdrücklich die Stellen,
die gemessen wurden und **keine** Arbeit rechtfertigen — damit sie nicht doch angefasst werden.

Alle Rohdaten liegen als JSON unter `artifacts/perf/`. Die Zahlen in diesem Dokument sind aus
genau diesen Dateien übernommen.

## 2. Messumgebung

Eine Zahl ohne ihre Umgebung ist nicht vergleichbar. Die Referenzumgebung dieser Baseline:

| Größe          | Wert                                                             |
| -------------- | ---------------------------------------------------------------- |
| CPU            | AMD EPYC 9354P, 4 vCPU sichtbar                                  |
| RAM            | 15 GiB                                                           |
| Kernel         | Linux 6.8.0-138-generic (x86-64)                                 |
| Node.js        | v24.19.0                                                         |
| PostgreSQL     | 16-alpine im Container, `--data-checksums`, loopback-gebunden    |
| Flutter / Dart | Flutter 3.47.0 stable · Dart 3.13.0                              |
| Campus API     | `NODE_ENV=production`, `node dist/main.js` (kein Watch, kein TS) |
| Messdatum      | 2026-08-25                                                       |

> **Node-24-Patchstand.** Die historische Referenzmessung lief mit 24.19.0; das Repository ist
> inzwischen auf 24.21.0 LTS gepinnt. Die vorhandenen Werte bleiben als historische Baseline
> erhalten, weil sie auf derselben Hauptversion erhoben wurden. Jede neue Vergleichsmessung muss
> den exakten Patchstand mitschreiben und für eine belastbare Vorher-/Nachher-Aussage beide Läufe
> auf demselben Patchstand ausführen.

Gemessen wird gegen einen Prozess im Produktionsmodus, nicht gegen `start:dev`. Der Watch-Modus
kompiliert TypeScript zur Laufzeit und misst damit den Compiler mit.

### 2.1 Warum ein Strapi-Stub statt des echten CMS

Für die redaktionellen Strecken (`/v1/posts*`, `/v1/contact-areas`, `/v1/rooms`) steht kein
echtes Strapi im Messaufbau, sondern `scripts/perf/strapi-stub.mjs`.

Das ist eine bewusste Trennung: Mit dem echten CMS im Pfad misst `/v1/posts` zusätzlich Strapis
Query-Planer, dessen Node-Prozess und einen Netzwerksprung — nichts davon kann eine Änderung in
`apps/backend` beeinflussen. Der Stub antwortet in bekannter, nahezu vernachlässigbarer Zeit;
was in der Messung übrig bleibt, ist genau der Anteil, den das Backend besitzt: Query-Kodierung,
begrenztes Lesen, JSON-Parsing, Block-Sanitising, DTO-Mapping, Serialisierung, Kompression.

**Folge für die Interpretation:** Die Zahlen für redaktionelle Strecken sind **kein**
Ende-zu-Ende-Wert. Die reale Latenz ist diese Zahl **plus** der Antwortzeit des CMS. Der Stub
kennt dafür `--upstream-delay-ms`, mit dem sich eine angenommene CMS-Latenz kontrolliert
zuschalten lässt; ein Ende-zu-Ende-Budget für Strapi selbst ist offen (Abschnitt 9).

### 2.2 Verifikation des Node-24.21.0-Pins

Die Toolchain-Migration wurde am 1. Oktober 2026 mit dem exakten Repository-Pin Node 24.21.0
und pnpm 11.15.1 erneut geprüft. Der Lauf umfasste den Frozen-Lockfile-Install, Prisma 7.9.1,
Nest- und Strapi-Build einschließlich des nativen `sharp`-Moduls, alle Workspace-Tests sowie die
Datenbank-Integrations- und Skalierungstests gegen eine isolierte, anschließend entfernte
PostgreSQL-16-Instanz. Die Produktionsimages wurden unter Linux mit Node 24.21.0 gebaut, als
unprivilegierter Benutzer gestartet und über `/health/live` beziehungsweise `/_health` geprüft.
Der High-/Critical-Scan der beiden fertigen Images blieb ohne Befund.

Dieser Lauf ist eine **Kompatibilitäts- und Regressionprüfung**, keine neue absolute
Latenzreferenz: Er lief auf einer Windows-/Docker-Desktop-Maschine und ist deshalb nicht mit den
Linux-Zahlen der Referenzumgebung vergleichbar. Die Werte aus Abschnitt 6 bleiben gültig; eine
neue Zahlenreihe darf sie erst ersetzen, wenn Vorher und Nachher auf derselben Maschine, mit
demselben Datenprofil und demselben Node-Patchstand gemessen wurden.

## 3. Datenprofile

Vergleichbar ist eine Messung nur gegen denselben Datenbestand. Zwei Profile, definiert in
`scripts/perf/dataset-profiles.ts`, jeweils mit der Begründung ihrer Größe im Code:

| Tabelle                  | `realistic` | `stress` | Herleitung                                                     |
| ------------------------ | ----------: | -------: | -------------------------------------------------------------- |
| `canteens`               |           2 |        2 | `canteens.config.ts` — feste Größe, kein Parameter             |
| `meals`                  |       8 760 |    8 760 | 2 Mensen × 365 Tage × 12 Gerichte                              |
| `meal_prices`            |      26 280 |   26 280 | 3 Preisgruppen je Gericht                                      |
| `sync_runs`              |       8 760 |   26 280 | `CANTEEN_SYNC_CRON` = 12 Läufe/Tag × 2 Mensen × 1 bzw. 3 Jahre |
| `timetable_groups`       |         270 |      480 | Codekommentar „~270"; Stress knapp unter `take: 500`           |
| `timetable_entries`      |      13 500 |   73 000 | 150 Tage × 90 bzw. 365 Tage × 200                              |
| `timetable_entry_groups` |      21 600 |  175 200 | 1,6 bzw. 2,4 Gruppen je Veranstaltung                          |
| `public_calendars`       |          12 |       50 | Stress = `PUBLIC_CALENDAR_API_MAX_CALENDARS`                   |
| `public_calendar_events` |       5 040 |   42 000 | 210 Tage (Lookback 30 + Lookahead 180) × 2 bzw. 4/Tag          |

`realistic` ist der erwartete Normalbetrieb und die Grundlage **aller** Budgets. `stress` ist die
Obergrenze, die die konfigurierten Guardrails noch zulassen; es dient dem Nachweis, dass ein
Budget mit wachsenden Daten hält — es ist **kein** eigenes Budget.

Der Generator ist deterministisch: fester Seed, fester Ankertag (2026-03-02), keine Uhrzeit aus
der Systemuhr. Zwei Läufe erzeugen denselben Bestand und damit dieselben Query-Pläne.

**Sauberkeitsbedingung.** Die Messdatenbank darf **ausschließlich** die Zeilen des Profils
enthalten. Ein Rest aus einem früheren Seed verschiebt Kardinalitäten und Planerstatistiken und
macht den Lauf unvergleichbar. Die Zeilenzahlen sind deshalb vor jeder Messung gegen
`expectedRowCounts()` zu prüfen (Abschnitt 10).

## 4. Messverfahren

**Zustände.** `cold` ist die erste Anfrage an eine Route, bevor irgendein anderer Verkehr sie
berührt hat — sie trägt die Erstkosten, die ein echter erster Nutzer zahlt: leerer TTL-Cache,
nicht vorbereitetes Statement, kalter JIT. `warm` sind 200 gemessene Anfragen nach 20 verworfenen
Aufwärmanfragen.

**Sequenziell, nicht parallel.** Gemessen wird die Bedienzeit einer Anfrage, nicht der Durchsatz
eines gesättigten Prozesses. Ein Lasttest beantwortet eine andere Frage und ist offen
(Abschnitt 9).

**Perzentile** entstehen per Nearest-Rank aus der sortierten Stichprobe: Ein p95 benennt immer
eine Anfrage, die es wirklich gegeben hat.

**Zeitnahme** bis zum vollständig gelesenen Antwortkörper, mit `accept-encoding: gzip, br`.
Ein Stoppen nach den Headern würde Serialisierung und Kompression verstecken — genau dort sitzt
serverseitige Arbeit.

**Query-Zahlen** entstehen beobachtend, nicht instrumentiert: PostgreSQL protokolliert jedes
Statement (`log_statement=all`, `log_min_duration_statement=0`), jede Route wird von
Sentinel-Statements eingerahmt, und was dazwischen liegt, wird ihr zugerechnet. Es wird **kein**
Anwendungscode zum Messen verändert.

**Mobile** wird in der Dart-VM (JIT, x86-64) gemessen, nicht AOT auf ARM. Die absoluten
Millisekunden sind daher **keine** Gerätewerte und dürfen nicht als solche zitiert werden;
belastbar ist der relative Vergleich zweier Läufe auf derselben Maschine.

## 5. Guardrails — unveränderlich

Diese Grenzen stehen **über** jedem Performance-Ziel. Eine Optimierung, die eine davon
aufweicht, ist abzulehnen, auch wenn sie ihr Budget erreicht. Sie sind keine neuen Regeln,
sondern die bestehenden aus `AGENTS.md` und `docs/architecture.md`, hier als Prüfliste für
Performance-Änderungen.

**Systemgrenzen.** Kein neuer direkter Zugriff der App auf Strapi, `meine-mensa.de`, WebUntis
oder den ICS-Feed — auch nicht „nur zum Cachen". Die vier ausdrücklich beschlossenen
Direktanbindungen (Mail, Noten, Moodle, Anträge) bekommen **keinen** Backend-Proxy, auch nicht
als Cache. Die Zusammenführung von Stundenplan, Moodle-Deadlines und öffentlichen Kalendern
bleibt lokal auf dem Gerät.

**Vertraulichkeit.** `googleCalendarId`, Feed-URL, ETag, `lastContentHash`, `ownerContact`,
`externalId`, `sourceLocationId` und WebUntis-Interna bleiben serverseitig. Der Statuslink der
Antragstellung wird nicht geloggt, nicht in eine Route aufgenommen und nicht geteilt.
Zugangsdaten bleiben im Keychain/Keystore, sensible Inhalte nur verschlüsselt lokal. Kein
Performance-Log darf personenbezogene Daten oder Secrets enthalten.

**Datenkonsistenz.** Eine leere, ungültige oder fehlgeschlagene Drittantwort löscht **niemals**
den letzten erfolgreichen Bestand. Upserts laufen über stabile Quell-IDs. Geldwerte bleiben
`Decimal`. Externe Gerichtsnamen werden nicht übersetzt. Ein Cache darf keinen veralteten Wert
als frisch ausgeben: `dataStale` / `lastSuccessfulSyncAt` müssen weiterhin die Wahrheit sagen.

**Grenzen und Validierung.** `pageSize`, Datumsbereiche, `PUBLIC_CALENDAR_API_MAX_*`,
`take`-Obergrenzen, `maxResponseBytes`, Timeouts, Retry- und Backoff-Verhalten werden nicht
gelockert. Eine Kürzung bleibt als `meta.truncated` sichtbar und wird nicht stillschweigend
vorgenommen. Caches bleiben in der Größe begrenzt (`TtlCache` mit `maxEntries`).

**Upstream-Last.** Eine Optimierung darf die Zahl der Anfragen an Dritte nicht erhöhen. Ein
Client-Request löst weiterhin **keinen** Upstream-Aufruf aus; das ist Aufgabe des Workers.

**Funktion und Barrierefreiheit.** Zustände werden nie allein über Farbe unterschieden,
Touch-Ziele bleiben ≥ 48 dp, Semantics bleiben erhalten. Ein „schnellerer" Screen, der eine
Ansage verliert, ist ein Rückschritt.

## 6. Baselines und Budgets — Campus API

Alle Werte in Millisekunden, Profil `realistic`, 200 Iterationen nach 20 Aufwärmläufen.
Quelle: `artifacts/perf/api-baseline-realistic.json`.

| Route (`name`)                | Klasse    |  cold |   p50 |   p95 |   max |   Antwort |
| ----------------------------- | --------- | ----: | ----: | ----: | ----: | --------: |
| `health-live`                 | probe     | 44,09 |  1,84 |  3,53 |  7,41 |      34 B |
| `canteens-list`               | app-start | 56,01 |  3,49 |  5,82 | 10,59 |     396 B |
| `timetable-status`            | app-start | 11,24 |  2,99 |  5,35 | 15,43 |     230 B |
| `calendars-list`              | app-start | 16,45 |  3,05 |  6,02 | 10,79 |    6,0 kB |
| `posts-channels`              | app-start |  6,71 |  2,02 |  4,71 |  9,61 |    1,7 kB |
| `canteen-menu-7d`             | primary   | 49,45 | 10,24 | 19,44 | 33,06 |   52,4 kB |
| `canteen-menu-14d`            | primary   | 15,60 | 14,07 | 25,35 | 36,08 |  103,1 kB |
| `calendar-events-single-30d`  | primary   |  9,98 |  4,93 | 10,10 | 19,13 |   20,7 kB |
| `posts-list-p1`               | primary   |  5,25 |  4,46 | 11,56 | 24,08 |  124,9 kB |
| `posts-events`                | primary   |  4,02 |  4,88 | 14,35 | 26,50 |  125,0 kB |
| `posts-detail`                | primary   | 22,51 |  2,36 |  8,72 | 16,51 |    6,3 kB |
| `calendar-events-agg-3x30d`   | primary   | 15,31 |  6,88 | 15,19 | 18,85 |   61,6 kB |
| `calendar-events-agg-12x30d`  | primary   | 18,17 | 13,01 | 25,53 | 31,40 |  245,9 kB |
| `calendar-events-agg-12x120d` | worst     | 34,34 | 29,07 | 46,32 | 87,08 |  661,0 kB |
| `timetable-groups`            | secondary |  8,60 |  5,01 |  8,96 | 16,33 |   34,4 kB |
| `timetable-groups-search`     | secondary |  6,26 |  4,89 | 10,23 | 18,65 |   12,9 kB |
| `contact-areas`               | secondary |  2,06 |  1,82 |  3,34 |  8,27 |    4,4 kB |
| `rooms-list`                  | secondary |  3,02 |  3,02 |  9,91 | 20,60 | 107,7 kB¹ |

¹ **Überholt, siehe Abschnitt 14.4.** Seit `0406bc7` besitzt der gebündelte
`@campus/map`-Katalog die technischen Raumdaten, und `/v1/rooms` ist durch dessen Umfang begrenzt
statt durch Strapi. Der gültige Bezugswert ist **18 378 Byte** über 60 Katalogräume; die 107,7 kB
beschreiben eine frühere Architektur.

### 6.1 Budgets

Die API ist heute überall deutlich schneller als jede sinnvolle Obergrenze. Ein Budget, das
lediglich den Ist-Zustand nachzeichnet, hätte keinen Nutzen; ein Budget, das weit darüber liegt,
erlaubt schleichende Verschlechterung. Deshalb gelten **zwei** Grenzen gleichzeitig, und die
strengere gewinnt:

**(a) Absolute Obergrenze je Klasse** — serverseitige Bedienzeit p95 auf der Referenzmaschine:

| Klasse    | p95-Obergrenze | Begründung                                                                                                                                                           |
| --------- | -------------: | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| probe     |          10 ms | Liveness muss innerhalb des Container-Healthcheck-Timeouts (5 s) auch unter Last weit im Grünen bleiben.                                                             |
| app-start |          25 ms | Diese Aufrufe liegen im Startpfad. Auf Mobilfunk dominiert die Netzlatenz (150–400 ms RTT); der Server darf davon nicht mehr als einen kleinen Bruchteil hinzufügen. |
| secondary |          40 ms | Bewusst geöffnete Ansicht; der Nutzer erwartet eine kurze Ladeanzeige, aber keinen Aussetzer.                                                                        |
| primary   |          80 ms | Inhaltsstrecken mit großer Antwort. 80 ms serverseitig bleiben auch mit Mobilfunk-RTT unter der Grenze, ab der eine Ansicht als zäh empfunden wird.                  |
| worst     |         120 ms | Der bewusst weit aufgezogene Fall (12 Kalender × 120 Tage). Er ist selten und durch `PUBLIC_CALENDAR_API_MAX_EVENTS` gedeckelt.                                      |

**(b) Nicht-Regressionsgrenze:** Kein p95 darf **125 %** seines hier festgehaltenen
Baseline-Werts überschreiten. Das ist die eigentlich wirksame Grenze — sie greift, lange bevor
eine absolute Schwelle erreicht wäre, und macht eine schleichende Verschlechterung sichtbar.

**(c) Query-Zahl je Anfrage ist fix.** Sie ist in Abschnitt 7 je Route festgehalten. Jede
Erhöhung gilt als Defekt, bis das Gegenteil begründet ist — eine mit der Ergebnismenge wachsende
Query-Zahl ist ein N+1.

**(d) Antwortgröße** darf ohne fachlichen Grund nicht wachsen. `calendar-events-agg-12x120d`
bleibt durch `PUBLIC_CALENDAR_API_MAX_EVENTS` gedeckelt; die Kürzung bleibt als
`meta.truncated` sichtbar.

**Toleranz.** Die Messung streut. Eine Überschreitung gilt erst als Regression, wenn sie in
**zwei** aufeinanderfolgenden Läufen auftritt. Einzelne `max`-Ausreißer sind kein Kriterium —
`max` ist dokumentiert, aber nicht budgetiert.

## 7. Belege — Datenbank und Wachstum

### 7.1 Query-Zahl je Anfrage (warm)

Quelle: `artifacts/perf/query-counts.json`.

| Route                                    | Queries | DB-Zeit gesamt |
| ---------------------------------------- | ------: | -------------: |
| `calendars-list`                         |       1 |        0,05 ms |
| `canteens-list`                          |       2 |        0,13 ms |
| `timetable-groups`                       |       2 |        0,35 ms |
| `calendar-events-single-30d`             |       2 |        0,32 ms |
| `calendar-events-agg-12x30d`             |       2 |        3,50 ms |
| `timetable-status`                       |       3 |        0,16 ms |
| `canteen-menu-7d`                        |       4 |        1,30 ms |
| `canteen-menu-14d`                       |       4 |        3,17 ms |
| `posts-*`, `contact-areas`, `rooms-list` |       0 |           0 ms |

**Kein N+1.** Die Query-Zahl ist auf jeder Strecke konstant und unabhängig von der Ergebnisgröße:
Ein 7-Tage- und ein 14-Tage-Menü kosten beide genau vier Queries, ein Kalender und zwölf
Kalender beide genau zwei. Das ist der wichtigste Einzelbefund dieser Baseline und zugleich der
Grund, warum auf der Serverseite wenig zu holen ist.

**Die redaktionellen Strecken stellen null Datenbankanfragen.** Ihre gesamte Zeit liegt im
Upstream-Aufruf und in der eigenen Verarbeitung — eine Datenbankoptimierung dort wäre wirkungslos.

> **Korrigiert in Abschnitt 14.4.** Die Zeilen für `canteen-menu-7d` und `canteen-menu-14d` sind
> vor der Ergänzung des API-Neustarts in Abschnitt 11 entstanden und mischen kalt und warm.
> Reproduzierbar sind 5 kalt / 2 warm beziehungsweise 4 kalt / 2 warm. Die fünfte Query ist das
> einmalige Laden des Zutatenverzeichnisses und kein N+1. Prüfungen nach Abschnitt 12 Kriterium 4
> beziehen sich auf die korrigierten Werte.

### 7.2 Wachstumsverhalten (`realistic` → `stress`)

| Route                         | p50 realistic | p50 stress | Antwort r → s | Bewertung                                        |
| ----------------------------- | ------------: | ---------: | ------------- | ------------------------------------------------ |
| `canteens-list`               |          3,49 |       3,98 | 396 B → 396 B | **hält** trotz 3× `sync_runs` (8 760 → 26 280)   |
| `timetable-groups`            |          5,01 |       4,97 | 34 → 61 kB    | **hält** trotz 480 statt 270 Gruppen             |
| `timetable-status`            |          2,99 |       2,79 | 230 B         | **hält** trotz 73 000 statt 13 500 Einträgen     |
| `calendar-events-single-30d`  |          4,93 |       6,28 | 21 → 41 kB    | wächst mit der Nutzlast, wie erwartet            |
| `calendar-events-agg-12x30d`  |         13,01 |      20,93 | 246 → 492 kB  | wächst mit der Nutzlast, wie erwartet            |
| `calendar-events-agg-12x120d` |         29,07 |      33,96 | 661 → 661 kB  | **gedeckelt** — Ergebnis bleibt bei 2 000 Events |

Der wichtigste Beleg steht in der ersten Zeile: `sync_runs` ist eine append-only-Tabelle, die
mit jedem Betriebstag wächst. Die dortige `LATERAL`-Abfrage (Kommentar in `canteen.service.ts`)
bleibt bei verdreifachter Historie unverändert schnell. Das Design ist an dieser Stelle belegt
tragfähig; es braucht keine Arbeit, sondern einen Regressionstest.

Die letzte Zeile belegt, dass `PUBLIC_CALENDAR_API_MAX_EVENTS` wirkt: Bei 3,5-facher
Datenmenge bleibt die Antwort gleich groß, weil sie sauber gekürzt und als `truncated` gemeldet
wird.

## 8. Belegte Engpässe und ihre Zuordnung

### 8.1 Mobile — `WeekLayout.placeDay` (Priorität 1)

**Messung** (`apps/mobile/benchmark/`, Dart-VM JIT):

| Messpunkt                             |      p50 |      p95 |
| ------------------------------------- | -------: | -------: |
| `week-layout-placeDay-x7`             | 3,214 ms | 4,129 ms |
| `week-layout-precomputed-probe-x7`    | 1,135 ms | 1,407 ms |
| `news-page-20-parse` (zum Vergleich)  | 0,839 ms | 2,160 ms |
| `calendar-merge-2000` (zum Vergleich) | 0,295 ms | 0,599 ms |

Das Layout einer Wochenansicht ist damit die mit Abstand teuerste Dart-Arbeit der App —
teurer als das Parsen einer ganzen News-Seite und rund elfmal so teuer wie die Zusammenführung
von 2 000 Kalendereinträgen. Es läuft beim Aufbau des Wochenrasters auf dem Main-Isolate; bei
16,7 ms Frame-Budget (60 Hz) sind 3,2 ms bereits rund 19 % eines Frames — auf einer schnellen
x86-Maschine im JIT. Auf einem Mittelklassegerät ist der Anteil höher.

**Belegte Ursache, nicht Vermutung.** `placeDay` leitet Start- und Endminute über `startOf`/
`endOf` her; beide rufen `DateTime.toLocal()`, `endOf` erzeugt zusätzlich zwei weitere
`DateTime`-Objekte für den Tagesvergleich. Kein Ergebnis wird gemerkt, und Cluster-Schleife,
Lane-Zuweisung und `PlacedEntry`-Konstruktion fragen jeweils erneut. Der Probe-Lauf führt
**denselben** Clustering-Algorithmus über einmal je Eintrag berechnete Minutenwerte aus und ist
damit 65 % schneller; eine Zusicherung im Benchmark prüft, dass beide Varianten identische Lanes
liefern. Der Unterschied ist also der Preis der wiederholten Umrechnung, nicht ein anderer
Algorithmus.

**Zuordnung:** Mobile (LEVIORA-183). **Ziel:** `week-layout-placeDay-x7` p50 ≤ **1,6 ms**
(≥ 50 % Verbesserung); die Probe zeigt 1,135 ms als erreichbar, die Differenz ist Spielraum.
**Bedingung:** identische Lane-Zuweisung, identisches Verhalten für über Mitternacht laufende
Einträge und für `minimumVisibleMinutes`.

**Stand nach LEVIORA-183 — behoben.** `placeDay` leitet Start- und Endminute jetzt einmal je
Eintrag her und entscheidet „endet an einem späteren Tag?" durch den Vergleich von Jahr, Monat
und Tag als Zahlen, statt zwei Mitternachts-`DateTime` zu bauen. Gemessen auf derselben
Maschine, mit demselben Benchmark, in drei abwechselnden Läufen (alt/neu/alt/neu/…), um
Maschinenrauschen nicht als Gewinn zu lesen:

| `week-layout-placeDay-x7` |   Lauf 1 |   Lauf 2 |   Lauf 3 |
| ------------------------- | -------: | -------: | -------: |
| vorher (p50)              | 3,186 ms | 3,175 ms | 3,158 ms |
| nachher (p50)             | 0,020 ms | 0,018 ms | 0,026 ms |

Damit p50 **0,020 ms** gegenüber 3,214 ms Baseline — rund 99 % weniger und weit unter dem Ziel
von 1,6 ms. Der Messpunkt ist von der teuersten Dart-Arbeit der App zur billigsten geworden.

**Die Ursache war größer als angenommen.** Die Baseline führte den Aufwand auf die _wiederholte_
Umrechnung zurück; das war richtig, aber nicht das Ganze. Teuer sind nicht die
Komponenten-Getter, sondern die beiden lokalen `DateTime(y, m, d)`, die `endOf` für den
Tagesvergleich baute: Ein lokales `DateTime` löst den Zonenoffset rückwärts auf und kostet auf
der Referenzmaschine **~8,2 µs** (200 000 Konstruktionen in 1,64 s) gegenüber **~14 ns** für
`hour` oder `minute`. Da die alte Fassung `endOf` mindestens dreimal je Eintrag aufrief, waren
das sechs solcher Konstruktionen pro Eintrag. Deshalb liegt die Probe
`week-layout-precomputed-probe-x7` heute mit ~1,05 ms **über** dem Produktionscode: Sie rechnet
die Minuten zwar nur einmal aus, baut die beiden `DateTime` aber weiterhin.

**Bedingungen eingehalten.** Die Lane-Zuweisung, das Verhalten über Mitternacht und
`minimumVisibleMinutes` sind unverändert. Abgesichert ist das nicht über eine Zeitmessung — die
wäre auf einem Build-Runner flaky und ohne Aussage —, sondern über einen Äquivalenztest in
`apps/mobile/test/features/calendar/week_layout_test.dart`: Er stellt `placeDay` gegen eine
naive Abschrift der alten Implementierung und vergleicht über 120 erzeugte Tage sowie die
Grenzfälle (Monats- und Jahreswechsel, Ende exakt um Mitternacht, UTC-Einträge, Cluster-Grenze)
jeden `PlacedEntry` vollständig. Der Test ist Teil von `flutter test` und damit des
Qualitätsgates.

Die P2-Guardrails sind im selben Lauf eingehalten; `CalendarDayIndex` bleibt der Rebuild-Pfad,
der lineare `entriesForDay` ist in `lib/` weiterhin nur innerhalb des Merge-Moduls erreichbar.

Was diese Zahl **nicht** sagt: Sie stammt weiter aus der Dart-VM (JIT, x86-64). Ob der Anteil
auf einem Gerät ebenso verschwindet, ist offen und gehört in die manuelle Routine 10.1 — Punkt
P3 des Tickets bleibt damit unbearbeitet.

### 8.2 Server — Preis-Nachladung im Mensa-Menü (Priorität 2)

Die vier Queries von `canteen-menu-14d` verteilen sich so:

| Query                               |         Zeit |
| ----------------------------------- | -----------: |
| `canteens` (Kopfdaten)              |     0,021 ms |
| `sync_runs` LATERAL (Frische)       |     0,083 ms |
| `meals` (Gerichte des Zeitraums)    |     0,419 ms |
| `meal_prices` (Preise der Gerichte) | **2,796 ms** |

Die Preis-Abfrage ist mit Abstand die teuerste und wächst linear mit der Zahl der Gerichte:
0,938 ms über 7 Tage, 2,796 ms über 14. Sie holt drei Preiszeilen je Gericht in einer separaten
Abfrage.

**Einordnung — bewusst niedrige Priorität.** Absolut geht es um wenige Millisekunden, und die
Route liegt mit p95 25,35 ms weit unter ihrem Budget von 80 ms. Der Punkt steht hier, weil er
der einzige messbar mit der Datenmenge wachsende Serveranteil ist, nicht weil er heute weh tut.
**Ein Umbau ist nur dann gerechtfertigt, wenn eine Messung nach diesem Verfahren einen Gewinn
zeigt** — und er darf `Decimal` nicht gegen `float` tauschen (Guardrail Abschnitt 5).

**Zuordnung:** Server (LEVIORA-184). **Erledigt** — Messung und Ergebnis in Abschnitt 13.

### 8.3 Server — Aggregierte Kalenderabfrage (Priorität 3, beobachten)

`calendar-events-agg-12x30d` ist mit 3,50 ms die teuerste Einzelquery der API und wächst mit
Kalenderzahl und Zeitraum: 13,01 ms p50 bei 12 Kalendern × 30 Tagen, 29,07 ms bei 120 Tagen.
Die Route ist durch `PUBLIC_CALENDAR_API_MAX_CALENDARS` (50), `PUBLIC_CALENDAR_API_MAX_RANGE_DAYS`
(120) und `PUBLIC_CALENDAR_API_MAX_EVENTS` (2 000) dreifach gedeckelt und bleibt auch im
Stress-Profil im Budget.

**Kein Handlungsbedarf.** Aufgenommen, damit die Budgetüberschreitung auffällt, falls eine
Änderung an den Grenzen oder am Index sie aus dem Rahmen laufen lässt.

## 9. Gemessen, aber ausdrücklich **kein** Handlungsbedarf

Damit diese Stellen nicht doch „optimiert" werden:

- **Query-Zahlen.** Konstant auf jeder Strecke. Es gibt kein N+1 zu beheben.
- **`sync_runs`-Wachstum.** Die `LATERAL`-Abfrage hält bei verdreifachter Historie. Kein Umbau —
  stattdessen ein Regressionstest, der genau das absichert.
- **`CalendarDayIndex`.** 0,005 ms je Tagesabfrage gegenüber 0,082 ms für den linearen Durchlauf
  (Faktor ~16). Bereits optimiert; **Guardrail**, nicht Aufgabe — der lineare `entriesForDay`
  darf auf dem Rebuild-Pfad nicht zurückkehren.
- **JSON-Parsing mobil.** 0,86 ms für ein 14-Tage-Menü (86 kB), 0,84 ms für 20 News-Artikel
  (101 kB). Gegenüber `placeDay` unauffällig; ein Wechsel auf einen anderen Parser oder ein
  Isolate wäre Aufwand ohne belegten Nutzen.
- **`calendar-merge`.** 0,295 ms für 2 000 Einträge.
- **Redaktionelle Strecken serverseitig.** Null Datenbankanfragen; p95 zwischen 3,3 und 14,4 ms
  bei bis zu 125 kB Antwort. Die reale Latenz wird vom CMS bestimmt, nicht vom Backend.

### 9.1 Build und Qualitätsgates

| Schritt                                          |    Dauer | Spitzenspeicher |
| ------------------------------------------------ | -------: | --------------: |
| `pnpm --filter @campus/cms build`                |   7,22 s |         1,70 GB |
| `pnpm --filter @campus/backend build`            |   4,93 s |          554 MB |
| `pnpm --filter @campus/backend test`             |  18,95 s |               — |
| `flutter analyze --fatal-infos --fatal-warnings` |   7,19 s |               — |
| `flutter test` (1 687 Tests)                     | 121,74 s |               — |

Alle vier sind unauffällig; der CMS-Build ist mit 1,7 GB Spitzenspeicher der einzige Wert, der
überhaupt eine Grenze berührt — auf einem Build-Runner mit 2 GB wäre er knapp. Festgehalten als
Betriebshinweis, nicht als Optimierungsaufgabe. Budget: keines; Nicht-Regression genügt.

## 10. Offene Messlücken

Diese Größen sind **nicht** gemessen. Sie haben deshalb hier auch **kein** Budget — ein
erfundener Wert wäre schlimmer als eine offene Stelle.

| Lücke                                                        | Warum offen                                                     | Nächster Schritt                                                           |
| ------------------------------------------------------------ | --------------------------------------------------------------- | -------------------------------------------------------------------------- |
| App-Start (cold/warm), Frame-Zeiten, Jank, Speicher, Energie | Kein Android-/iOS-Gerät und kein Emulator im Messaufbau         | Manuelle Routine 10.1 auf je einem realen Android- und iOS-Gerät           |
| Ende-zu-Ende-Latenz der redaktionellen Strecken              | Kein echtes Strapi im Aufbau (Abschnitt 2.1)                    | Wiederholung mit laufendem CMS; Stub-Wert als Untergrenze                  |
| Verhalten unter Parallellast                                 | Bewusst sequenziell gemessen                                    | Eigener Lasttest, sobald ein Zielprofil für gleichzeitige Nutzer existiert |
| Worker-Durchsatz (Mensa-, Stundenplan-, ICS-Sync)            | Braucht kontrollierte Upstream-Fixtures, sonst misst man Dritte | Sync gegen aufgezeichnete Antworten, Messpunkt `sync_runs`-Dauer           |
| CMS-Redaktionspfade zur Laufzeit                             | Erfordert eingerichtetes Strapi mit Admin-Konto                 | Nach Einrichtung einer DEV-Instanz                                         |
| Netzwerk- und Cache-Pfade der App (dio/Hive)                 | Braucht Gerät oder Emulator                                     | Zusammen mit 10.1                                                          |

### 10.1 Manuelle Geräteroutine (verbindlich, wenn Gerätewerte behauptet werden)

1. Release-Build (`flutter build apk --release` bzw. iOS-Release), **nicht** Debug — Debug-Builds
   sind um ein Vielfaches langsamer und ihre Zahlen sind bedeutungslos.
2. Gerät im Flugmodus aus, Display auf feste Helligkeit, Akku > 50 %, keine anderen Apps.
3. **Cold Start:** App vollständig beenden, starten, Zeit bis zum ersten interaktiven Frame
   fünfmal messen, Median notieren.
4. **Jank:** `flutter run --profile`, dann DevTools-Timeline für: Newsliste scrollen (60
   Einträge), Wochenkalender vier Wochen vor- und zurückblättern, Mensa-Menü über 14 Tage
   wischen, Campuskarte zoomen. Notiert werden Anzahl und Dauer der Frames > 16,7 ms.
5. **Speicher:** RSS nach Start und nach dem Durchlauf aus 4.
6. Jede Zahl mit Gerätemodell, OS-Version und Build-Nummer festhalten. Ohne diese Angaben ist
   der Wert nicht vergleichbar.

## 11. Messung wiederholen

```bash
# 1. Isolierte Messdatenbank (nicht den Entwicklungsstack benutzen)
docker run -d --name campus-perf-pg \
  -e POSTGRES_DB=postgres -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD="<lokal>" \
  -e APP_DB_NAME=campus_app_local -e APP_DB_USER=campus_app -e APP_DB_PASSWORD="<lokal>" \
  -e CMS_DB_NAME=campus_cms_local -e CMS_DB_USER=campus_cms -e CMS_DB_PASSWORD="<lokal>" \
  -e POSTGRES_INITDB_ARGS='--data-checksums' \
  -p 127.0.0.1:5443:5432 \
  -v "$PWD/infrastructure/local/initdb:/docker-entrypoint-initdb.d:ro" \
  postgres:16-alpine

# 2. Schema + Datenprofil
pnpm --filter @campus/backend exec prisma migrate deploy
pnpm --filter @campus/backend exec ts-node \
  --project ../../scripts/perf/tsconfig.json \
  ../../scripts/perf/seed-perf-dataset.ts --profile realistic --reset

# 3. Zeilenzahlen gegen das Profil prüfen — Abweichung = Lauf verwerfen
docker exec campus-perf-pg psql -U postgres -d campus_app_local -c \
  "select 'meals',count(*) from meals union all select 'sync_runs',count(*) from sync_runs \
   union all select 'cal_events',count(*) from public_calendar_events;"

# 4. Upstream-Stub und API im Produktionsmodus
#    WEBUNTIS_ENABLED ist nicht optional: ohne die Variable liefern
#    /v1/timetable/groups und /v1/timetable/status hinter dem Feature-Flag eine
#    leere Antwort (161 B statt 34,4 kB) und eine Query weniger. Die Zahlen in
#    Abschnitt 6 und 7 sind mit gesetztem Flag entstanden. Der Sync selbst wird
#    dadurch nicht ausgelöst — das ist Sache des Workers, und
#    WEBUNTIS_SYNC_ON_BOOT bleibt aus.
node scripts/perf/strapi-stub.mjs --port 4599 &
NODE_ENV=production STRAPI_BASE_URL=http://127.0.0.1:4599 \
  STRAPI_API_TOKEN=<beliebig, nur "gesetzt" zählt> WEBUNTIS_ENABLED=true \
  PORT=3099 HOST=127.0.0.1 LOG_LEVEL=warn \
  node apps/backend/dist/main.js &

# 5. Latenz
node scripts/perf/bench-api.mjs --base-url http://127.0.0.1:3099 \
  --iterations 200 --warmup 20 --out artifacts/perf/api-baseline-realistic.json

# 6. Query-Zahlen (setzt log_statement=all + log_min_duration_statement=0 voraus)
#    API vorher NEU STARTEN. Das Menü-Lesemodell hat einen TTL-Cache von 30 s;
#    ohne Neustart entscheidet die Laufzeit von `docker logs`, ob dieser Lauf
#    einen kalten oder einen warmen Cache misst, und die Query-Zahl derselben
#    Route schwankt zwischen 2 und 4. Nach einem Neustart ist der erste Aufruf
#    jeder Route sicher kalt und der zweite sicher ein Cache-Treffer.
node scripts/perf/measure-queries.mjs --base-url http://127.0.0.1:3099 \
  --container campus-perf-pg --out artifacts/perf/query-counts.json

# 7. Mobile Hot Paths
cd apps/mobile && flutter gen-l10n && flutter test benchmark/ --reporter expanded
```

Der Stub, der Generator und die Harnesse liegen in `scripts/perf/` beziehungsweise
`apps/mobile/benchmark/`. Nichts davon wird von der Anwendung geladen, und
`flutter test` ohne Argument führt `benchmark/` nicht mit aus.

## 12. Abnahme einer Optimierung

Eine Änderung aus LEVIORA-183 oder LEVIORA-184 gilt als abgenommen, wenn:

1. Vorher- und Nachher-Messung nach Abschnitt 11 auf **derselben** Maschine, mit **demselben**
   Profil und geprüften Zeilenzahlen vorliegen.
2. Der Zielwert aus Abschnitt 8 erreicht ist **oder** mit Evidenz begründet ist, warum nicht.
3. Keine andere Strecke ihre Nicht-Regressionsgrenze (125 % des Baseline-p95) reißt.
4. Keine Query-Zahl aus Abschnitt 7.1 gestiegen ist.
5. Kein Guardrail aus Abschnitt 5 berührt wurde.
6. Die Gates aus dem README grün sind.

Eine Änderung ohne Vorher-/Nachher-Messung ist unabhängig von ihrer Plausibilität keine
Optimierung, sondern eine Vermutung.

## 13. Ergebnis LEVIORA-184 — Preis-Nachladung im Mensa-Menü

Abschnitt 8.2 stellte den Umbau unter Vorbehalt: Er ist nur gerechtfertigt, wenn eine Messung
nach diesem Verfahren einen Gewinn zeigt. Sie tut es. Die DB-Zeit von `canteen-menu-14d` auf dem
Cache-Miss-Pfad fällt von **3,36 ms auf 1,51 ms** (Ziel: ≤ 2,0 ms), die Query-Zahl bleibt gleich,
die Antwort bleibt byte-identisch, keine Strecke verschlechtert sich.

### 13.1 Messumgebung dieses Laufs

Dieselbe Maschine für Vorher und Nachher, unmittelbar nacheinander, Profil `realistic`,
Datenbank vorher neu aufgebaut und Zeilenzahlen gegen `expectedRowCounts()` geprüft. Die beiden
Läufe unterscheiden sich in genau einer Sache: dem Stand dieses Tickets. Rohdaten:
`artifacts/perf/leviora-184-{before,after,after-2}-{api,queries}.json`.

| Größe      | Wert                                                 |
| ---------- | ---------------------------------------------------- |
| CPU        | AMD EPYC 9354P, 4 vCPU sichtbar                      |
| RAM        | 15 GiB                                               |
| Kernel     | Linux 6.8.0-138-generic (x86-64)                     |
| Node.js    | v24.19.0                                             |
| PostgreSQL | 16-alpine im Container, `--data-checksums`, loopback |
| Messdatum  | 2026-08-25                                           |

> **Diese Maschine war schneller als die der Baseline aus Abschnitt 6.** Die absoluten Werte
> unten sind deshalb **nicht** mit Abschnitt 6 vergleichbar; wirksam ist die
> Nicht-Regressionsgrenze, und die ist mit Abstand eingehalten. Vergleichbar ist ausschließlich
> Vorher gegen Nachher **innerhalb** dieses Abschnitts.

> **Zwei Abweichungen von der Befehlsfolge in Abschnitt 11**, beide in jedem Lauf gleich
> angewandt und beide inzwischen dort ergänzt: `WEBUNTIS_ENABLED=true`, ohne das zwei
> dokumentierte Strecken leer antworten, und ein API-Neustart zwischen Latenz- und
> Query-Messung, ohne den der 30-Sekunden-Cache des Menüs die Query-Zahl vom Zufall abhängig
> macht.

### 13.2 Vorher/Nachher — die geänderte Strecke

Zwei Nachher-Läufe, weil eine Überschreitung erst in zwei aufeinanderfolgenden Läufen als
Regression gilt (Abschnitt 6.1).

| Messpunkt `canteen-menu-14d`      |   vorher |  nachher | nachher (2) |
| --------------------------------- | -------: | -------: | ----------: |
| DB-Zeit, kalter Cache (4 Queries) |  3,36 ms |  1,51 ms |     1,78 ms |
| Query-Zahl, kalter Cache          |        4 |        4 |           4 |
| Query-Zahl, Cache-Treffer         |        2 |        2 |           2 |
| Route-p95                         |  6,64 ms |  6,13 ms |     8,87 ms |
| Antwortgröße                      | 105591 B | 105591 B |    105591 B |

### 13.3 Warum es wirkt — die Abfrage isoliert

`EXPLAIN (ANALYZE, BUFFERS)` auf demselben Datenbestand (26 280 Preiszeilen, 168 Gerichte
angefragt), Median aus je fünf Läufen nach einem verworfenen:

| Statement                                                        | Plan                | Ausführung |
| ---------------------------------------------------------------- | ------------------- | ---------: |
| `IN ($1 … $168)`, Spalten `id, group, amount, mealId` (vorher)   | Seq Scan            |    2,42 ms |
| dieselbe Form, deckender Index vorhanden                         | Seq Scan            |    3,58 ms |
| `= ANY($1::text[])`, Spalten `mealId, group, amount`, ohne Index | Seq Scan            |    2,20 ms |
| `= ANY($1::text[])`, Spalten `mealId, group, amount`, mit Index  | **Index Only Scan** |    0,41 ms |

Die mittleren beiden Zeilen sind der eigentliche Befund: **Keine der beiden Änderungen wirkt
allein.** Der Index allein bringt nichts, weil Prismas verschachtelte Relation zusätzlich
`p."id"` liest — eine Spalte, die der Index nicht führt, was jede Indexnutzung 504 Heap-Zugriffe
kosten würde und den sequentiellen Scan billiger macht. Die engere Abfrage allein bringt nichts,
weil die bestehende Unique-Constraint bei `(mealId, group)` endet und `amount` nicht trägt.
Erst zusammen liegen alle gelesenen Spalten im Index, und PostgreSQL beantwortet die Abfrage
ohne einen einzigen Heap-Zugriff (`Heap Fetches: 0`).

Der Array-Parameter trägt darüber hinaus etwas, das keine einzelne Messung zeigt: Die Form des
Statements hängt nicht mehr von der Länge des Zeitraums ab. Vorher war es ein anderes Statement
für sieben Tage als für vierzehn, mit einem Bindeparameter je Gericht; jetzt ist es dasselbe
Statement mit einem Parameter. Das ist der Grund, warum dies der einzige mit der Ergebnisgröße
wachsende Serveranteil war.

### 13.4 Nicht-Regression — alle Strecken

p95 in Millisekunden. „Grenze" ist 125 % des in Abschnitt 6 festgehaltenen Baseline-p95.

| Route                         | Grenze | vorher | nachher | nachher (2) | Antwort |
| ----------------------------- | -----: | -----: | ------: | ----------: | ------- |
| `health-live`                 |   4,41 |   2,12 |    1,93 |        1,89 | gleich  |
| `canteens-list`               |   7,28 |   3,87 |    3,73 |        4,10 | gleich  |
| `canteen-menu-7d`             |  24,30 |   5,47 |    5,95 |        7,10 | gleich  |
| `canteen-menu-14d`            |  31,69 |   6,64 |    6,13 |        8,87 | gleich  |
| `timetable-status`            |   6,69 |   2,48 |    3,01 |        4,48 | gleich  |
| `timetable-groups`            |  11,20 |   5,92 |    4,09 |       11,33 | gleich  |
| `timetable-groups-search`     |  12,79 |   5,64 |    3,91 |        4,30 | gleich  |
| `calendars-list`              |   7,52 |   4,64 |    2,77 |        3,03 | gleich  |
| `calendar-events-single-30d`  |  12,62 |   5,89 |    4,73 |        6,05 | gleich  |
| `posts-list-p1`               |  14,45 |   4,38 |    7,28 |        5,49 | gleich  |
| `posts-channels`              |   5,89 |   2,00 |    1,98 |        2,29 | gleich  |
| `posts-tags`                  |   7,35 |   2,05 |    2,30 |        1,96 | gleich  |
| `posts-detail`                |  10,90 |   1,96 |    2,14 |        2,68 | gleich  |
| `posts-events`                |  17,94 |   4,46 |    6,83 |       11,69 | gleich  |
| `contact-areas`               |   4,17 |   1,88 |    2,06 |        5,70 | gleich  |
| `rooms-list`                  |  12,39 |   1,62 |    1,63 |        4,86 | gleich  |
| `calendar-events-agg-3x30d`   |  18,99 |   7,25 |    7,83 |       14,76 | gleich  |
| `calendar-events-agg-12x30d`  |  31,91 |  16,49 |   15,95 |       28,81 | gleich  |
| `calendar-events-agg-12x120d` |  57,90 |  31,73 |   43,51 |       45,64 | gleich  |

Keine Strecke reißt ihre Grenze in zwei aufeinanderfolgenden Läufen. Drei Zellen liegen im
zweiten Nachher-Lauf einzeln darüber (`timetable-groups` 11,33, `contact-areas` 5,70,
`posts-events` 11,69); der erste Nachher-Lauf liegt bei allen dreien weit darunter, keine der
drei Strecken wird von dieser Änderung berührt, und der zweite Lauf ist durchgehend lauter. Das
ist Maschinenrauschen und genau der Fall, für den die Toleranzregel aus Abschnitt 6.1 da ist.

Query-Zahlen: unverändert auf jeder Strecke, kalt wie warm. Antwortgrößen: byte-identisch auf
jeder Strecke.

### 13.5 Was die Änderung nicht angetastet hat

Die ausgelieferte Antwort ist byte-identisch. Geprüft nicht nur über die Größe, sondern über den
Inhalt: vier Antworten (zwei Mensen, beide Locales, ein 14-Tage- und ein 30-Tage-Zeitraum sowie
`/v1/canteens`) vor und nach der Änderung erfasst und verglichen — 177 180 Bytes, kein
Unterschied.

`Decimal` bleibt `Decimal`. Der Treiber-Adapter bildet `numeric` auch bei einer Raw-Query auf
`Decimal` ab — nachgewiesen gegen die laufende Datenbank —, und die Ausgabe entsteht weiterhin
über `Decimal.toFixed(2)`. Kein Geldwert läuft durch einen `float`.

Ein fehlender Preis bleibt fehlend. Die Abfrage liefert die gespeicherten Zeilen und sonst
nichts; ein Gericht ohne Preisgruppe behält keine. Das ist als Test festgehalten.

Nicht berührt: Ergebnisgrenzen, Timeouts, Retry- und Backoff-Verhalten, Transaktionsgrenzen,
Datenisolation, Security-Header, `meta.truncated`, `dataStale` und `lastSuccessfulSyncAt`, die
Größenbegrenzung der Caches und die Zahl der Anfragen an Dritte. Ein Client-Request löst
weiterhin keinen Upstream-Aufruf aus. Der öffentliche Vertrag (`packages/openapi/openapi.json`)
ist unverändert.

### 13.6 Regressionsschutz (Abschnitt 7.2 als Test)

`apps/backend/test/read-path-scaling.integration.spec.ts` hält die Eigenschaft fest, die
Abschnitt 7.2 gemessen hat: Diese Lesepfade werden nicht teurer, wenn die Historie wächst. Der
Test misst jede Abfrage zweimal gegen ein echtes PostgreSQL — einmal auf einer Basisgröße, einmal
mit vervielfachtem Bestand — und prüft den Plan, nicht die Antwort:

| Pfad                                   | Wächst um   | Zugesichert                                                         |
| -------------------------------------- | ----------- | ------------------------------------------------------------------- |
| `sync_runs` LATERAL (Frische)          | 8× Historie | kein Seq Scan, genau eine Zeile je Mensa, Buffer-Wachstum ≤ 2×      |
| `meal_prices` (Preise eines Zeitraums) | 4× Tabelle  | Index Only Scan über den deckenden Index, Buffer-Wachstum ≤ 2×      |
| `public_calendar_events` (aggregiert)  | 4× Termine  | kein Seq Scan, Ergebnis bleibt bei `PUBLIC_CALENDAR_API_MAX_EVENTS` |

Die Basisgrößen sind bewusst nicht winzig: Auf ein paar tausend Zeilen ist ein sequentieller Scan
tatsächlich der billigste Plan, und dort eine Indexnutzung zu fordern hieße, dem Planer eine
Entscheidung vorzuschreiben, die er zu Recht anders trifft. Der Fixture vacuumiert außerdem
zwischen den Größen — ohne aktuelle Visibility Map steht ein Index Only Scan gar nicht zur
Auswahl, und ein frisch geladener Bestand würde an einem Plan gemessen, den kein laufendes System
je benutzt. Gegengeprüft wurde der Test, indem der deckende Index entfernt wurde: Er wird dann
rot.

Die aggregierte Kalenderabfrage bekommt bewusst **keine** Wachstumsgrenze: Sie wächst mit ihrer
Nutzlast, wie Abschnitt 7.2 festhält. Zugesichert ist dort die Deckelung, nicht flache Kosten.

### 13.7 Nebenbefund — der Generator war nicht lauffähig

`scripts/perf/seed-perf-dataset.ts` schrieb beim öffentlichen Kalender `descriptionDe`,
`descriptionEn`, `iconKey`, `showDescription` und `showLocation`. Diese Felder sind mit
`20260825170000_simplify_editorial_fields` entfallen beziehungsweise umbenannt worden, ohne dass
der Generator mitgezogen wurde — Schritt 2 der Befehlsfolge in Abschnitt 11 brach damit ab, und
ohne Schritt 2 ist keine Messung nach diesem Dokument möglich. Hier mit korrigiert.

## 14. Abnahme LEVIORA-185 — unabhängige Validierung und Regression-Gates

Alle Messungen aus Abschnitt 8 wurden unabhängig wiederholt, keine Zahl aus LEVIORA-183 oder
LEVIORA-184 wurde übernommen. **Kein freigegebenes Budget ist verfehlt.** Drei Gates wurden
ergänzt, weil die Prüfung gezeigt hat, dass die bestehenden genau die Rückfälle nicht sehen,
gegen die sie eingerichtet wurden.

### 14.1 Messumgebung

Dieselbe Maschinenklasse wie die Referenzumgebung aus Abschnitt 2: AMD EPYC 9354P (4 vCPU),
15 GiB RAM, Linux 6.8.0-138-generic, Node v24.19.0, PostgreSQL 16-alpine im Container,
Flutter 3.47.0 / Dart 3.13.0. Messdatum 2026-08-25. Profil `realistic`, Zeilenzahlen vor dem
Lauf geprüft. Rohdaten: `artifacts/perf/leviora-185-*`.

Die Maschine ist geteilt und trug während der Läufe andere Container. Das ist der Grund, warum
Abschnitt 14.3 die Streuung ausdrücklich mitmisst, statt sie anzunehmen.

### 14.2 Mobile — Vorher/Nachher auf derselben Maschine

Kein Vergleich gegen die dokumentierte Baseline, sondern gegen den tatsächlichen Codestand
**vor** LEVIORA-183 (`0406bc7`, in einem zweiten Worktree ausgecheckt), zehn Läufe je Seite auf
derselben Maschine. So trennt sich die Wirkung der Änderung von der Drift der Maschine.

| Messpunkt (p50, Median aus 10 Läufen) | Doku-Basis |   vorher |  nachher |   Delta |
| ------------------------------------- | ---------: | -------: | -------: | ------: |
| `week-layout-placeDay-x7`             |   3,214 ms | 3,165 ms | 0,017 ms | −99,5 % |
| `week-layout-precomputed-probe-x7`    |   1,135 ms | 1,046 ms | 1,059 ms |  +1,3 % |
| `news-page-20-parse`                  |   0,839 ms | 0,788 ms | 0,780 ms |  −1,1 % |
| `calendar-dayIndex-build-2000`        |   0,134 ms | 0,142 ms | 0,141 ms |  −0,4 % |
| `calendar-dayIndex-forDay`            |   0,005 ms | 0,005 ms | 0,005 ms |    ±0 % |
| `calendar-entriesForDay-linear`       |   0,082 ms | 0,070 ms | 0,070 ms |  +0,7 % |
| `calendar-merge-2000`                 |   0,295 ms | 0,255 ms | 0,285 ms | +12,0 % |
| `canteen-menu-14d-parse`              |   0,860 ms | 0,873 ms | 0,953 ms |  +9,1 % |

Das P1-Ziel (p50 ≤ 1,6 ms) ist bestätigt und um rund das Hundertfache übertroffen. Die
Vorher-Seite reproduziert die dokumentierte Baseline auf 1,5 % genau, was die Vergleichbarkeit
der Umgebung belegt.

Die beiden letzten Zeilen bewegen sich, obwohl LEVIORA-183 ihren Produktionscode nicht angefasst
hat: Der Diff an `benchmark/hot_paths_test.dart` besteht ausschließlich aus `dart format` und
Kommentaren, die Fixtures sind unverändert. Beide Deltas liegen innerhalb der Streuung derselben
Messpunkte auf der Vorher-Seite (Faktor 1,39 beziehungsweise 1,48) und sind Maschinenrauschen,
keine Regression.

### 14.3 Streuung — warum kaum ein Mobilwert ein Gate sein kann

Zehn Läufe auf einer ansonsten ruhigen Maschine, gegen die Nicht-Regressionsgrenze von 125 %
des Baseline-p50 gehalten:

| Messpunkt                          | min … max (p50) | Faktor | Läufe über 125 % |
| ---------------------------------- | --------------- | -----: | ---------------: |
| `week-layout-placeDay-x7`          | 0,016 … 0,021   |   1,31 |             0/10 |
| `week-layout-precomputed-probe-x7` | 1,045 … 1,075   |   1,03 |             0/10 |
| `calendar-dayIndex-build-2000`     | 0,137 … 0,156   |   1,14 |             0/10 |
| `calendar-entriesForDay-linear`    | 0,064 … 0,076   |   1,19 |             0/10 |
| `calendar-merge-2000`              | 0,266 … 0,314   |   1,18 |             0/10 |
| `calendar-dayIndex-forDay`         | 0,005 … 0,007   |   1,40 |             1/10 |
| `news-page-20-parse`               | 0,726 … 1,239   |   1,71 |             1/10 |
| `canteen-menu-14d-parse`           | 0,872 … 1,418   |   1,63 |             3/10 |

**Belegte Konsequenz:** Eine Zeitschwelle auf den Parse-Messpunkten wäre in bis zu 30 % der
Läufe rot, ohne dass sich Code geändert hat. `calendar-dayIndex-forDay` scheitert an der
Auflösung — bei 5 µs ist ein einziger Mikrosekundenschritt bereits 20 %. Die Entscheidung aus
LEVIORA-183, keine Wanduhrzeit ins Gate zu nehmen, ist damit gemessen bestätigt und nicht nur
plausibel — und zwar für **jeden** Messpunkt, `week-layout-placeDay-x7` eingeschlossen. Ein
erster Versuch, dessen grossen Abstand doch für ein Gate zu nutzen, ist an einer zweiten,
stärkeren Streuquelle gescheitert; Abschnitt 14.5 (2) hält fest, woran.

### 14.4 Server — Budgets, Query-Zahlen, Antwortgrößen

Zwei aufeinanderfolgende Läufe nach Abschnitt 11, API zwischen den Läufen neu gestartet.
**Keine Strecke reißt ihre Nicht-Regressionsgrenze, keine ihr Klassenbudget** — weder in einem
einzelnen Lauf noch in zweien. Der höchste gemessene Wert ist
`calendar-events-agg-12x120d` mit p95 31,70 ms gegen eine Grenze von 57,90 ms.

Query-Zahlen (`artifacts/perf/leviora-185-queries-final.json`) reproduzieren die Werte aus den
LEVIORA-184-Läufen exakt, kalt wie warm. Die DB-Zeit von `canteen-menu-14d` auf dem
Cache-Miss-Pfad liegt bei 1,92 ms und bestätigt den dort gemessenen Gewinn; das Statement läuft
gegen die laufende Datenbank belegt als `= ANY($1::text[])` mit einem einzigen Array-Parameter.

**Korrektur an Abschnitt 7.1.** Die dortige Tabelle nennt für `canteen-menu-7d` und
`canteen-menu-14d` je vier Queries, warm wie kalt. Reproduzierbar sind **5 kalt / 2 warm**
für `canteen-menu-7d` und **4 kalt / 2 warm** für `canteen-menu-14d` — in allen drei
LEVIORA-184-Läufen und in diesem. Ursache: Abschnitt 7.1 entstand vor der Korrektur der
Befehlsfolge, die den API-Neustart vorschreibt; ohne ihn entscheidet der 30-Sekunden-TTL-Cache
zufällig über kalt oder warm. Die fünfte Query von `canteen-menu-7d` ist der **einmalige** Laden
des Zutatenverzeichnisses (`ingredient_definitions`), das prozessweit gecacht wird und deshalb
nur die erste Menü-Anfrage eines Prozesses trifft — kein N+1. Wer Abschnitt 12 Kriterium 4
wörtlich gegen 7.1 prüft, meldet sonst einen Defekt, den es nicht gibt.

**Korrektur an Abschnitt 6 — `rooms-list`.** Der dort festgehaltene Wert (107,7 kB, p95 9,91 ms)
ist nicht mehr reproduzierbar, und zwar seit `0406bc7`, also **vor** LEVIORA-183 und -184:
`RoomsService.map` schlägt seither jeden `roomKey` im gebündelten `@campus/map`-Katalog nach und
verwirft die Zeile, wenn er dort fehlt. Der Stub erfand 420 Schlüssel, die in keinem Katalog
stehen; alle 420 wurden verworfen, und die Strecke antwortete mit **93 Byte**. Ihr p95 „verbesserte“
sich dadurch auf 1,68 ms, und zwei Abnahmeläufe verbuchten sie als grün. Der Stub liest den
Katalog jetzt (14.5), womit die Strecke wieder echte Arbeit misst: **18 378 Byte** über die
60 Katalogräume. Das ist der neue Bezugswert; die 107,7 kB beschreiben eine Architektur, in der
Strapi die technischen Raumdaten besaß.

Die übrigen Abweichungen der Antwortgrößen gegenüber Abschnitt 6 (`calendars-list` −21 %,
`posts-tags` −60 %, `posts-*` je −6 %, `contact-areas` −4 %) sind der Wegfall redaktioneller
Felder aus `20260825170000_simplify_editorial_fields` und fachlich gewollt. Abschnitt 6.1 (d)
verbietet nur das **Wachsen** einer Antwort; ein Einbruch war bis hierher durch nichts gedeckt.

### 14.5 Verankerte Gates

Drei Gates, alle in `verify-backend` beziehungsweise `verify-flutter` und damit auf jedem Merge
Request. Jedes wurde durch Mutation geprüft: erst rot gemacht, dann wieder grün.

**(1) `apps/backend/test/read-path-query-budget.integration.spec.ts` — Query-Zahl und -Form.**
Abschnitt 6.1 (c) erklärt die Query-Zahl je Anfrage für fix, und nichts hat das durchgesetzt.
`read-path-scaling.integration.spec.ts` kann es nicht: Es prüft den Plan von SQL-Konstanten, die
in den Test **kopiert** wurden, nicht das, was der Dienst tatsächlich absetzt. Belegt durch
Mutation: Wird `CanteenService.pricesByMeal` auf eine verschachtelte Prisma-Relation
zurückgebaut — also genau auf die Form, die LEVIORA-184 als Seq Scan über die ganze Preistabelle
gemessen hat —, bleibt jenes Gate **7/7 grün**. Rot wird allein ein Unit-Test, und der nur, weil
sein Prisma-Mock die Delegate nicht kennt; wer den Mock mitzieht, hat eine grüne Pipeline und
die Regression ausgeliefert.

Das neue Gate beobachtet die Statements einer echten HTTP-Anfrage und sichert eine
**Eigenschaft**, keine Zahl: Ein 14-Tage-Fenster darf nicht mehr Queries kosten als ein
7-Tage-Fenster, die Preisabfrage bleibt ein einzelner Array-Parameter, Gerichte und
Frische je genau eine Query. Unter derselben Mutation meldet es die zurückgekehrte
`IN ($1 … $168)`-Liste im Klartext.

**(2) `apps/mobile/test/features/calendar/week_layout_test.dart` — Kosten von `placeDay`.**
Der bestehende Äquivalenztest beweist, dass `placeDay` jeden Eintrag weiterhin dorthin legt, wo
ihn der alte Code hinlegte. Er kann nicht beweisen, dass die Optimierung noch da ist: Stellt man
die beiden `DateTime`-Konstruktionen je Eintrag wieder her, bleiben **alle 1 782 Mobiltests
grün**, während der Messpunkt von 0,017 ms auf 1,034 ms springt — Faktor 61, unbemerkt.

**Eine Zeitmessung kann diese Lücke nicht schliessen — auch nicht als Verhältnis.** Der erste
Anlauf verglich `placeDay` mit `_reference` im selben Lauf, in der Annahme, ein langsamer Runner
skaliere beide Seiten gleich. Er skaliert sie nicht: Was `_reference` teuer macht, ist genau die
Konstruktion eines lokalen `DateTime`, und deren Kosten hängen an der Zeitzonenkonfiguration.
Auf derselben Maschine, mit demselben Code, misst dieselbe Woche

| Umgebung           | `placeDay` | `_reference` | Verhältnis |
| ------------------ | ---------: | -----------: | ---------: |
| `TZ` nicht gesetzt |    ~170 µs |    ~2 800 µs |       ~16× |
| `TZ=Europe/Berlin` |     ~78 µs |      ~200 µs |       2,7× |
| Linux-CI-Runner    |     107 µs |       245 µs |       2,3× |

Die CI pinnt `TZ=Europe/Berlin`. Das Verhältnis schwankt also um mehr als das Sechsfache allein
mit einer Umgebungsvariablen; jede Schwelle, absolut oder relativ, liegt innerhalb dieser
Schwankung. Der Versuch ist entsprechend in der CI rot geworden und wurde zurückgenommen.

Das Gate sichert deshalb die **Form** statt der Zeit, so wie es die Icon- und
`image_url`-Wächter dieses Repositories tun: Der Rumpf von `placeDay` darf keinen
`DateTime`-Konstruktor enthalten. Das ist genau die Invariante aus Abschnitt 8.1, sie wird durch
Lesen der Quelle entschieden statt durch Messen, und sie fällt auf jeder Maschine gleich aus.
Ein zweiter Test stellt sicher, dass der Wächter den echten Rumpf liest und nicht durch eine
Umbenennung wirkungslos wird.

**(3) `scripts/perf/bench-api.mjs` — Untergrenze je Antwortgröße.** Eine leer antwortende
Strecke ist das gefährlichste Ergebnis dieses Harness, weil sie wie das beste aussieht. Jede
Route trägt jetzt eine großzügige Untergrenze; wird sie unterschritten, markiert der Lauf die
Zeile und endet mit Exit-Code 1, statt eine schmeichelhafte Zahl zu veröffentlichen. Der Wächter
hat sich sofort bewährt: Er fing einen Lauf ab, dessen Mensadaten von einer vorangegangenen
Testausführung geleert worden waren.

Zusätzlich liest `scripts/perf/strapi-stub.mjs` die Raumschlüssel jetzt aus
`packages/campus-map/catalog/campus-map.catalog.json`, statt sie zu erfinden — die Ursache des
Einbruchs aus 14.4.

### 14.6 Guardrails und Funktion

Die Guardrails aus Abschnitt 5 sind unberührt. Geprüft am laufenden System und am Diff:
`googleCalendarId`, Feed-URL und WebUntis-Interna erscheinen in keiner Antwort; Geldwerte bleiben
`Decimal`; `dataStale` und `lastSuccessfulSyncAt` melden weiterhin den wahren Stand; Ergebnis-
grenzen, Timeouts, Retry- und Backoff-Verhalten sowie `meta.truncated` sind unverändert; ein
Client-Request löst weiterhin keinen Upstream-Aufruf aus. Der öffentliche Vertrag
(`packages/openapi/openapi.json`) driftet nicht.

Gates lokal grün: `pnpm format:check`, Backend-Lint, -Typecheck, -Build, OpenAPI-Drift-Check,
`pnpm --filter @campus/backend test` (51 Suiten / 645 Tests gegen ein echtes PostgreSQL),
`dart format --set-exit-if-changed`, `flutter analyze --fatal-infos --fatal-warnings`,
`flutter test` (1 784 Tests, auch unter `TZ=Europe/Berlin` wie in der CI).

### 14.7 Verbleibende Risiken

| Risiko                                                                                   | Priorität | Owner   | Nächster Schritt                                                                                                                                     |
| ---------------------------------------------------------------------------------------- | --------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gerätewerte (Start, Frames, Jank, Speicher, Energie) weiterhin ungemessen                | P2        | Mobile  | Routine 10.1 auf je einem realen Android- und iOS-Gerät; ohne Gerät nicht schließbar                                                                 |
| `read-path-scaling` prüft kopiertes SQL, kann von der Produktion driften                 | P3        | Backend | Gate (1) deckt Form und Zahl ab; Zusammenführung beider Tests bei nächster Berührung                                                                 |
| Ende-zu-Ende-Latenz der redaktionellen Strecken (echtes Strapi)                          | P3        | Backend | Wiederholung mit laufendem CMS; Stub-Wert bleibt Untergrenze                                                                                         |
| Verhalten unter Parallellast, Worker-Durchsatz                                           | P3        | Backend | Erst nach Zielprofil für gleichzeitige Nutzer beziehungsweise aufgezeichneten Upstream-Antworten                                                     |
| CI pinnt Flutter 3.44.7, gemessen wurde mit 3.47.0                                       | P3        | Erik    | Bei nächster Toolchain-Pflege angleichen; Gate (2) ist versionsunabhängig                                                                            |
| Kein Gate schützt `placeDay` gegen einen Rückbau, der die Form wahrt, aber langsamer ist | P3        | Mobile  | Gate (2) deckt die belegte Ursache (DateTime-Konstruktion) ab; ein anders gearteter langsamer Umbau bliebe unbemerkt und fiele erst im Benchmark auf |

Die erste Zeile ist die einzige, die eine Aussage dieses Dokuments offen lässt: Alle Mobilzahlen
stammen aus der Dart-VM (JIT, x86-64) und sind **keine** Gerätewerte. Ob der Gewinn an
`placeDay` auf einem Mittelklassegerät ebenso sichtbar wird, ist unbelegt — plausibel, aber
nicht gemessen.
