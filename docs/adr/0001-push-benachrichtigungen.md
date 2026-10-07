# ADR-0001 — Benachrichtigungen aus lokal vorhandenen Daten, ohne Push-Server

Campus Köthen App · `AGPL-3.0-only` · Copyright © 2026 Leviora Studio and Jona Loreen Sommer

**Änderung vom 24.09.2026:** Die Uhrzeit der Tagesübersicht N2 ist nun im Onboarding und in den
Benachrichtigungseinstellungen frei wählbar (Standard 08:00 Uhr, Ortszeit). Das allgemeine
Zustellfenster von 07:00 bis 20:00 Uhr gilt dafür nicht; N2 wird zur gewählten Uhrzeit geplant.
Die folgenden älteren Festlegungen auf 08:00 Uhr sind insoweit durch diese Änderung ersetzt.

**Änderung vom 07.10.2026:** Der Event-Vorlauf N1 ist nicht mehr fest auf 24 Stunden begrenzt.
Lokal wählbar sind 15 Minuten, 1 Stunde, 6 Stunden, 1 Tag (Standard), 2 Tage und 1 Woche. Ein
einzelnes öffentliches oder gemerktes Event kann den Standard überschreiben oder die Erinnerung
abschalten. Die Regeln bleiben rein geräteseitig, klein und begrenzt gespeichert; Kategorie,
Zustellfenster, Identität, Datenschutz und Planung ohne Push-Server bleiben unverändert. Alle
folgenden Aussagen „exakt 24 Stunden“ beziehungsweise „nicht einstellbar“ sind insoweit ersetzt.

| Feld            | Wert                                                                                                                                 |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Status          | **Angenommen**                                                                                                                       |
| Datum           | 2026-08-24                                                                                                                           |
| Autor           | Johannes (Technical Architect)                                                                                                       |
| Vorgabe         | Erik, 2026-08-24: kein externer Push-Dienst; die Lösung arbeitet mit lokal vorhandenen Daten                                         |
| Produktfreigabe | Erik, 2026-08-24 (LEVIORA-159) — die fachlichen Regeln sind abgeschlossen, siehe [§ 6.1](#61-freigegebene-produktregeln-leviora-159) |
| Ticket          | LEVIORA-157, fortgeschrieben durch LEVIORA-168, unter LEVIORA-152                                                                    |
| Parallel        | LEVIORA-158 / LEVIORA-167 (UX- und Content-Spezifikation)                                                                            |
| Ersetzt         | —                                                                                                                                    |
| Ersetzt durch   | —                                                                                                                                    |

Dieses ADR entscheidet **Mechanismus, Datengrundlage und Grenzen** der Benachrichtigungen und hält
den **verbindlichen Planungsvertrag** fest, der aus der Produktfreigabe LEVIORA-159 folgt. Es
enthält **keine** Implementierung.

Die fachliche Auswahl der Benachrichtigungstypen ist seit LEVIORA-159 entschieden und wird hier
nicht neu bewertet. Was in einer früheren Fassung dieses ADRs noch als Vorschlag stand — keine
standardmäßig aktive Kategorie, 60 Minuten Vorlauf, Tagesübersicht als bloße Empfehlung —, ist
überholt und steht zur Nachvollziehbarkeit im [Anhang C](#anhang-c--historische-vorschläge-vor-der-produktfreigabe).

Die zuvor untersuchte Remote-Push-Architektur (Firebase Cloud Messaging) ist nicht verworfen, weil
sie technisch schlecht wäre, sondern weil eine ausdrückliche Vorgabe gegen die dafür nötige
Fremdanbindung steht. Ihre Analyse steht kompakt im
[Anhang A](#anhang-a--verworfen-remote-push-über-fcm).

---

## 1. Kontext

Die Campus App soll Benachrichtigungen erhalten, die auf Android und iOS funktionieren. Der Bestand
setzt dafür enge Rahmenbedingungen:

- Die App hat **kein eigenes Nutzerkonto**. Alle Präferenzen liegen lokal.
- Mail, Noten, Moodle und Anträge laufen bewusst **direkt vom Gerät** zum jeweiligen Anbieter
  (AGENTS.md § 2, `docs/architecture.md` G10–G12). Das Backend hat weder Zugangsdaten noch Inhalte.
- Das Projekt schließt Analytics, Tracking und Crash-Reporting **vollständig** aus. Es gibt heute
  **kein** Drittanbieter-SDK in der App.
- `docs/architecture.md` § 8 führt „Hintergrund-Sync bei geschlossener App“ als ausgeschlossen.
- Es gibt kein öffentliches Deployment, kein Firebase-Projekt und keinen Apple-Developer-Zugang.

Die Vorgabe lautet: **kein externer Push-Dienst, keine Anbindung eines Push-Servers; die Lösung
arbeitet mit den Daten, die ohnehin schon auf dem Gerät liegen.** Das ist keine Einschränkung im
luftleeren Raum — es ist dieselbe Regel, nach der die App schon heute gebaut ist: Was das Gerät
allein kann, verlässt das Gerät nicht.

## 2. Randbedingungen

| #   | Randbedingung                                                                                                 |
| --- | ------------------------------------------------------------------------------------------------------------- |
| R1  | Kein Firebase, kein APNs-Zugang, kein Push-Anbieter, keine Registrierung, kein serverseitiger Gerätedatensatz |
| R2  | Datengrundlage ist ausschließlich, was ohnehin schon lokal liegt                                              |
| R3  | Zustellung muss auf iOS **und** Android funktionieren, auch bei beendeter App                                 |
| R4  | Genau eine Person pflegt das System — Codemenge und Betriebsaufwand sind harte Kriterien                      |
| R5  | Kein neues Secret, keine neuen laufenden Kosten                                                               |
| R6  | Mail-, Noten-, Moodle- und Antragsdaten dürfen das Gerät nicht verlassen                                      |
| R7  | Was der Mechanismus **nicht** kann, muss offen benannt und nicht durch Halbheiten verdeckt werden             |
| R8  | Die fachlichen Regeln aus LEVIORA-159 sind gesetzte Eingangsgröße, keine Architekturentscheidung              |

## 3. Wie eine lokale Benachrichtigung funktioniert — und wo ihre Grenze liegt

Eine lokale Benachrichtigung wird **im Voraus beim Betriebssystem angemeldet**. Ab diesem Moment
gehört sie dem System: Sie erscheint zur geplanten Zeit, auch wenn die App längst beendet ist, ohne
Netz, ohne Server, ohne dass App-Code läuft.

Das ist der entscheidende Punkt, und er wird oft falsch verstanden:

> Eine lokale Benachrichtigung kann **zuverlässig zu einem künftigen Zeitpunkt erscheinen**.
> Sie kann **nicht** von etwas berichten, das die App erst erfahren würde, nachdem sie zuletzt lief.

Daraus folgt die einzige wirklich relevante Trennlinie im gesamten Vorhaben:

| Ereignisart                                                                                  | Lokal möglich?                                   |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **Datiert und schon bekannt** — ein Termin, eine Frist, ein Gericht am Donnerstag            | **Ja, vollständig und zuverlässig**              |
| **Neu entstanden, während die App nicht lief** — ein neuer Beitrag, eine kurzfristige Absage | **Nein** (ohne Hintergrundausführung, siehe § 5) |

Die gute Nachricht ist, dass der Bestand der App fast vollständig auf der ersten Seite dieser Linie
liegt.

## 4. Ist-Zustand: was liegt lokal und ist datiert?

Alles hier ist am Repository geprüft, nicht angenommen.

| Datenbestand                         | Speicher                               | Datiert?                      | Beleg                                                                     |
| ------------------------------------ | -------------------------------------- | ----------------------------- | ------------------------------------------------------------------------- |
| Gemerkte Events                      | `campus_saved_events_v1` (Hive, lokal) | ja — `start`, `end`, `allDay` | `features/events/domain/saved_event_snapshot.dart`                        |
| Stundenplan der gewählten Gruppe     | Inhaltscache, je Woche/Monat           | ja — `start`, `end`, `status` | `core/cache/cache_keys.dart` → `timetableEntries`                         |
| Öffentliche Kalender                 | Inhaltscache, je Fenster und Auswahl   | ja                            | `core/cache/cache_keys.dart` → `publicCalendarEvents`                     |
| Event-Beiträge (`/v1/posts/events`)  | Inhaltscache, seitenweise              | ja                            | `core/cache/cache_keys.dart` → `postEvents`                               |
| Moodle-Abgabefristen                 | verschlüsselte Box, rein lokal         | ja — `dueAt`                  | `features/moodle/domain/moodle_deadline.dart`                             |
| **Mensa-Speiseplan, 14 Tage voraus** | Inhaltscache                           | ja — je Tag                   | `features/canteen/data/canteen_repository.dart` (`cachedWindowDays = 14`) |
| Favoritengerichte                    | `SharedPreferences`, Gerichtsnamen     | —                             | `core/prefs/preference_keys.dart` (`canteen.favourites.v1`)               |
| Aufgabenliste                        | `campus_todos_v1` (Hive, lokal)        | **nein** — nur `createdAt`    | `features/todos/domain/todo.dart`                                         |

Der wichtigste Befund steht schon im Code: Der Kalender führt **fünf** Quellen lokal zusammen —
`timetable`, `moodle`, `publicCalendar`, `postEvent`, `savedEvents`
(`features/calendar/domain/calendar_entry.dart`). Es existiert also bereits ein **geräteseitiger,
zusammengeführter, datierter Terminbestand**. Genau darauf setzt der Benachrichtigungsplaner auf; er
braucht keine eigene Datenhaltung und keine neue Quelle.

### 4.1 Fünf Befunde, die den Planungsvertrag unmittelbar bestimmen

Diese fünf Punkte sind für LEVIORA-162 wichtiger als jede allgemeine Beschreibung, weil sie je einen
Fehler verhindern, der sonst erst im Test auffiele.

1. **`CalendarEntry.id` ist bereits stabil und quellenpräfigiert.**
   `features/calendar/application/calendar_merge.dart` erzeugt `timetable:<id>`, `moodle:<id>`,
   `publicCalendar:<slug>:<id>` und `savedEvent:<eventRef>`. Das ist genau das Schlüsselformat, das
   § 7.6 für die Benachrichtigungsidentität braucht — es muss **kein zweites** Identitätsschema
   eingeführt werden.
2. **Die Entdopplung „gemerkt“ gegen „live im öffentlichen Kalender“ existiert schon.**
   `savedEventEntriesForCalendar` in derselben Datei wendet die Regel des Events-Features
   (`event_dedup.isDuplicateCalendarEvent`) an. Der Planer arbeitet deshalb auf dem **bereits
   zusammengeführten und entdoppelten** Bestand; „genau ein Hinweis je Event“ ergibt sich daraus,
   statt ein zweites Mal implementiert zu werden.
3. **„Aktivierte Kalender“ hat eine echte Entsprechung im Code.**
   `publicCalendarSelectionProvider` beziehungsweise `PublicCalendarSelectionRules.effectiveSelection`
   ist die Y-von-X-Auswahl aus P3. `publicCalendarMonthEntriesProvider` liefert bereits nur Termine
   aus dieser Auswahl.
4. **Die Anzeigeschalter des Kalenders sind _nicht_ der Geltungsbereich der Benachrichtigungen.**
   `calendarEnabledSourcesProvider` und `calendarSavedEventsEnabledProvider` steuern, was der
   Kalenderscreen zeigt; letzterer ist **standardmäßig aus**. Würde der Planer sie mitlesen, wäre P3
   für gemerkte Events im Normalfall wirkungslos und ein ausgeblendeter Stundenplan verschwände
   still aus der Tagesübersicht. Der Planer liest die Quellen deshalb direkt — Geltungsbereich sind
   allein die Benachrichtigungseinstellungen (§ 6.1 P2) und die aktivierte Kalenderauswahl.
5. **Mensa-Favoriten sind nach Gerichtsnamen verschlüsselt, nicht nach `Meal.id`.**
   `features/canteen/domain/canteen_filter.dart` begründet das ausdrücklich: Die Quell-Id wechselt
   bei jeder Neuveröffentlichung eines Gerichts. Schlüssel und Abgleich in § 7.3 N3 müssen deshalb
   über den Namen laufen; `Meal.id` ist für Wiedererkennung über Tage hinweg unbrauchbar.

Zwei Details, die den Umfang unmittelbar erweitern:

- Der Speiseplan ist **14 Tage im Voraus** lokal vorhanden. „Am Donnerstag gibt es dein
  Lieblingsgericht“ ist damit **ohne jeden Server** planbar — und ohne die Favoritennamen irgendwohin
  hochzuladen. Das ist datensparsamer **und** zuverlässiger als der Remote-Weg es gewesen wäre.
- Stundenplaneinträge tragen lokal bereits `status` mit `cancelled`/`changed` (`docs/api.md` § 8).
  Ein Ausfall, der beim letzten Abruf schon eingetragen war, ist lokal bekannt und fließt damit in
  die Tagesübersicht ein — mit der Einschränkung aus § 9.

## 5. Optionen

### S1 — Reine Vorausplanung, kein Code bei geschlossener App · **empfohlen**

Die App plant beim Laufen alle künftigen Benachrichtigungen beim Betriebssystem ein. Danach passiert
ohne die App nichts mehr — und es muss auch nichts passieren.

- **Für:** deckt jeden datierten Kandidaten vollständig ab; keine Hintergrundausführung, kein
  Akkuverbrauch, keine neue Berechtigung, kein Widerspruch zu `docs/architecture.md` § 8; die
  gesamte Logik ist eine reine Funktion und damit ohne Plattform testbar.
- **Gegen:** kann grundsätzlich nichts melden, was erst nach dem letzten App-Lauf entstanden ist. Der
  geplante Vorrat läuft leer, wenn die App sehr lange nicht geöffnet wird (§ 9).

### S2 — Zusätzlich Hintergrundaktualisierung (WorkManager / BGTaskScheduler)

Das Betriebssystem weckt die App gelegentlich, sie ruft die **bereits angebundene** Campus API ab,
plant neu und meldet Neues als lokale Benachrichtigung. Weiterhin **kein** Push-Dienst, **keine**
Registrierung, **kein** serverseitiger Datensatz — nur Code, der auch im Vordergrund schon läuft.

- **Für:** erschließt „neuer Beitrag“ und „kurzfristige Stundenplanänderung“. Und — das ist die
  bemerkenswerte Umkehrung gegenüber Remote-Push — **auch „neue E-Mail“**: Die Zugangsdaten liegen im
  Keychain, die Verbindung geht direkt zum Anbieter, kein Server ist beteiligt. Ein Push-Anbieter
  hätte das nie leisten können, ohne die Systemgrenzen zu brechen.
- **Gegen:** **best effort, nicht zusagbar.** iOS entscheidet selbst, ob und wann eine
  Hintergrundaktualisierung läuft — je nach Nutzungsverhalten von mehrmals täglich bis praktisch
  nie. Unter Android greifen Doze und teils aggressive herstellereigene Akku-Optimierungen. Für
  „deine Vorlesung in einer Stunde fällt aus“ ist das der falsche Mechanismus, weil er genau dann
  schweigen darf, wenn es darauf ankommt.
- Zusätzlich: widerspricht der heutigen ausdrücklichen Nicht-Entscheidung in
  `docs/architecture.md` § 8 und kostet Akku, Testaufwand und eine Gerätematrix.

### S3 — Remote-Push über FCM

Durch die Vorgabe ausgeschlossen. Analyse im [Anhang A](#anhang-a--verworfen-remote-push-über-fcm),
damit die Entscheidung nachvollziehbar bleibt und nicht erneut von vorn untersucht werden muss.

## 6. Entscheidung

**S1 wird umgesetzt. S2 wird ausdrücklich offengehalten und erst nach S1 getrennt entschieden.**

Begründung:

1. S1 deckt jeden Kandidaten ab, der auf der planbaren Seite der Linie aus § 3 liegt — und das sind,
   gemessen am tatsächlichen Datenbestand (§ 4), die meisten. Alle drei fachlich freigegebenen
   Kategorien (§ 6.1) liegen vollständig darauf.
2. S1 hat **keine** Zuverlässigkeitseinschränkung innerhalb seines Geltungsbereichs. Eine geplante
   Erinnerung kommt. Das ist mehr, als S2 oder Remote-Push für ihren jeweiligen Bereich zusagen
   können.
3. S1 kostet nichts: kein Anbieter, kein Secret, kein Konto, keine Registrierung, kein
   serverseitiger Datensatz, keine Änderung an Backend oder API, keine Erweiterung der
   Datenschutzerklärung über den Berechtigungshinweis hinaus.
4. S2 ist danach jederzeit additiv nachrüstbar. Der Planer aus § 7 bleibt dabei unverändert; es käme
   nur ein weiterer Auslöser für „neu planen“ hinzu. Nichts an dieser Entscheidung muss dafür
   zurückgebaut werden.

**Bedingung, unter der neu zu entscheiden wäre:** Wenn sich herausstellt, dass „neuer Beitrag“ oder
„kurzfristige Absage“ fachlich unverzichtbar sind, führt kein Weg an S2 (unzuverlässig) oder
Remote-Push (Fremdanbindung) vorbei. Diese Abwägung gehört Erik, nicht der Architektur.

### 6.1 Freigegebene Produktregeln (LEVIORA-159)

Erik hat die fachlichen Regeln am 2026-08-24 abschließend freigegeben. Sie sind für dieses ADR
**Eingangsgröße, nicht Gegenstand**. Die Kennungen P1–P12 dienen der Rückverfolgbarkeit: Jede
technische Festlegung in § 7 nennt die Regel, aus der sie folgt.

| #   | Freigegebene Regel                                                                                                                                                                                                                                       |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1  | Ausschließlich lokale Vorausplanung. Kein externer Push-Anbieter, kein Benachrichtigungs-Backend, keine Hintergrundaktualisierung                                                                                                                        |
| P2  | Alle Benachrichtigungskategorien sind nach dem globalen Opt-in **standardmäßig aktiv**; die Zustellung setzt die Betriebssystem-Berechtigung voraus                                                                                                      |
| P3  | Für öffentliche Events **genau eine** Erinnerung **exakt 24 Stunden** vor dem Termin — nur für Events aus vom Nutzer aktivierten Kalendern und für selbst gemerkte Events                                                                                |
| P4  | Um **08:00 Uhr** eine Tagesübersicht mit den heutigen Mensa-Inhalten, Events, Lehrveranstaltungen und Moodle-Abgabefristen                                                                                                                               |
| P5  | Lehrveranstaltungen und Moodle-Abgabefristen lösen **keine** zusätzlichen Einzelerinnerungen aus                                                                                                                                                         |
| P6  | Gibt es ein favorisiertes Mensaessen, erscheint um **11:00 Uhr** ein zusätzlicher Einzelhinweis                                                                                                                                                          |
| P7  | Zustellfenster **07:00–20:00 Uhr**. Ein Eventhinweis, dessen exakter 24-Stunden-Zeitpunkt außerhalb liegt, wird zum nächstmöglichen Zeitpunkt um **07:00 Uhr** zugestellt                                                                                |
| P8  | Mehrere gleichzeitig fällige Hinweise werden **einzeln** zugestellt und nicht gebündelt                                                                                                                                                                  |
| P9  | Öffentliche Termindetails dürfen auf dem Sperrbildschirm **vollständig** sichtbar sein                                                                                                                                                                   |
| P10 | Inhalte mit persönlichen Daten bleiben vor dem Entsperren **neutral** und erscheinen vollständig erst danach; **Moodle ist die Referenz**                                                                                                                |
| P11 | Ein Tap auf einen Einzelhinweis öffnet **direkt** das betroffene Event, den Stundenplantermin, das Moodle-Element beziehungsweise das Mensagericht; die Tagesübersicht öffnet die Tagesansicht                                                           |
| P12 | Benachrichtigungen entsprechen dem **zuletzt lokal bekannten** Stand: abgelaufene oder lokal gelöschte Einträge lösen nichts mehr aus, lokal bekannte Änderungen schlagen auf ausstehende Hinweise durch. Keine Echtzeitgarantie ohne erneuten App-Abruf |

Zwei Folgerungen, die den Umfang gegenüber der früheren Fassung dieses ADRs deutlich verkleinern:

- **P5 streicht Einzelhinweise für Stundenplan und Moodle vollständig.** Beide Quellen erscheinen
  ausschließlich in der Tagesübersicht. Damit entfallen die früher als K3, K4 und K6 geführten
  Einzelbenachrichtigungen — und mit ihnen der größte Teil des Lärmrisikos und des Routingbedarfs.
- **Aus dreizehn Kandidaten werden drei Kategorien** (§ 7.3). Alles Weitere ist entweder durch die
  Freigabe ausgeschlossen oder gehört zu S2.

## 7. Zielarchitektur und Planungsvertrag

Alles liegt in `apps/mobile`. **Backend, Worker, Campus API, Datenbank und OpenAPI-Vertrag bleiben
unverändert.** Es entsteht kein Endpunkt, keine Tabelle, keine Migration.

```text
Datenquellen, die es bereits gibt
  campus_saved_events_v1 · Inhaltscache (Stundenplan, öffentliche Kalender, Event-Beiträge,
  Speiseplan 14 Tage) · verschlüsselte Moodle-Box · Einstellungen
        │
        ▼
NotificationPlanner            reine Funktion, keine Plattform, keine Nebenwirkung
  (Termine, Speiseplan, Einstellungen, jetzt, Zeitzone) ──► List<PlannedNotification>
        │                                        id · Zeitpunkt · Titel · Text · payload
        ▼
NotificationScheduler          Port über flutter_local_notifications
  cancelAll() ──► schedule(...) für jeden geplanten Eintrag   (vollständige Neuplanung)
        │
        ▼
Betriebssystem hält die Termine — App darf beendet sein
        │
        ▼
Tap ──► payload validieren ──► auf ein erlaubtes Ziel abbilden ──► navigieren
```

### 7.1 Vollständige Neuplanung statt Abgleich

Bei jedem Auslöser wird **alles verworfen und neu geplant**, nicht differenziell aktualisiert. Das
ist derselbe Konvergenzgedanke wie an anderen Stellen der App: Ein vollständiger Sollzustand kann
nicht auseinanderlaufen, ein Delta schon. Der Planer ist eine reine Funktion; damit ist „was wäre
jetzt geplant“ in einem Unit-Test ohne Gerät prüfbar.

Die vollständige Neuplanung ist zugleich die **gesamte** Umsetzung von P12: Aktualisieren,
Ersetzen und Stornieren sind keine eigenen Codepfade, sondern das Ergebnis davon, dass der Planer
einen abgesagten, gelöschten oder verschobenen Eintrag beim nächsten Lauf schlicht nicht mehr
beziehungsweise anders erzeugt.

**Auslöser einer Neuplanung**

- App-Start und Rückkehr in den Vordergrund
- nach **jedem** erfolgreichen Datenabruf (Stundenplan, Speiseplan, öffentliche Kalender,
  Event-Beiträge, Moodle)
- Merken/Entmerken eines Events, Favorit setzen/entfernen
- Wechsel von Stundenplangruppe, bevorzugter Mensa, Auswahl der öffentlichen Kalender
- Änderung einer Benachrichtigungseinstellung
- Erteilung, Verweigerung oder nachträglicher Entzug der Systemberechtigung
- Sprachwechsel (die Texte kommen aus den ARB-Dateien)
- Zeitzonenwechsel und Tageswechsel bei laufender App

**Zwei Anforderungen an die Ausführung**, weil `cancelAll()` und das erneute Einplanen zusammen
nicht atomar sind:

- Neuplanungen laufen **serialisiert**; ein zweiter Lauf startet nie parallel zu einem laufenden.
- Zwischen `cancelAll()` und dem letzten `schedule(...)` besteht ein kurzes Fenster ohne
  vorgemerkte Hinweise. Bricht der Prozess genau dort ab, bleibt es leer, bis die App das nächste
  Mal startet. Das ist hinnehmbar, weil jeder App-Start neu plant — aber es ist kein Nullrisiko und
  gehört in die Gerätematrix (§ 14).

### 7.2 Datenquellen des Planers — und was er ausdrücklich nicht liest

| Kategorie             | Liest                                                                                                                            | Liest **nicht**                                                        |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Events (N1)           | zusammengeführte, entdoppelte Kalendereinträge der Quellen `publicCalendar` (nur aktivierte Auswahl) und `savedEvents`           | `calendarEnabledSourcesProvider`, `calendarSavedEventsEnabledProvider` |
| Tagesübersicht (N2)   | dieselben Eventquellen plus `timetable` (gewählte Gruppe), `moodle` (verbundenes Konto) und den Speiseplan der bevorzugten Mensa | dieselben Anzeigeschalter                                              |
| Favoritengericht (N3) | Speiseplan der bevorzugten Mensa (`selectedCanteenSlugProvider`) und `canteen.favourites.v1` (Gerichtsnamen)                     | `Meal.id` als Wiedererkennungsmerkmal (§ 4.1, Befund 5)                |

Weitere verbindliche Punkte:

- Der Planer arbeitet **ausschließlich auf lokal vorhandenen Daten** und löst **nie** einen
  Netzabruf aus. Ein Lauf beim App-Start darf nicht auf eine Netzantwort warten; er plant aus dem
  Cache und wird nach dem nächsten erfolgreichen Abruf ohnehin erneut ausgeführt.
- Fehlt eine Quelle (kein Moodle-Konto, keine Stundenplangruppe, `WEBUNTIS_ENABLED=false`, leerer
  Speiseplancache), entfällt **nur ihr Anteil**. Die Tagesübersicht wird dadurch kürzer, nicht
  falsch, und keine andere Kategorie fällt aus.
- Der Planer ist eine reine Funktion. Das Einsammeln der Quellen ist ein dünner Adapter davor; die
  Providerwelt endet an dieser Grenze.

### 7.3 Die drei freigegebenen Kategorien

Legende der Kennungen: N-Kennungen sind der freigegebene Umfang; die früheren K-Kennungen sind in
§ 8 auf sie abgebildet.

#### N1 — `event.reminder`: Erinnerung an einen öffentlichen Event · P3

| Feld            | Festlegung                                                                                                                            |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Geltungsbereich | Kalendereinträge der Quellen `publicCalendar` aus der **aktivierten** Auswahl sowie `savedEvents` — und nur diese                     |
| Soll-Zeitpunkt  | `start` minus **exakt 24 Stunden** (absolute Dauer, nicht „gleiche Uhrzeit am Vortag“)                                                |
| Zustellfenster  | Verschiebung nach § 7.4                                                                                                               |
| Anzahl          | **genau eine** Erinnerung je Event. Die Entdopplung aus § 4.1 Befund 2 verhindert einen zweiten Hinweis für dasselbe Event            |
| Ausschlüsse     | Einträge mit `isCancelled`, verwaiste Merkeinträge (`isOrphaned`), Einträge in der Vergangenheit, Soll-Zeitpunkt in der Vergangenheit |
| Ganztägig       | `allDay`-Einträge haben einen definierten `start`; die 24-Stunden-Regel gilt darauf unverändert                                       |
| Tap-Ziel        | das Event selbst, siehe § 7.8                                                                                                         |

#### N2 — `daily.summary`: Tagesübersicht um 08:00 Uhr · P4

| Feld            | Festlegung                                                                                                                                                                                        |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Zeitpunkt       | **08:00 Uhr Ortszeit** des jeweiligen Tages, für jeden Tag **einzeln** geplant                                                                                                                    |
| Inhalt          | die für diesen Tag lokal bekannten Mensa-Inhalte der bevorzugten Mensa, Events aus aktivierten Kalendern und gemerkte Events, Lehrveranstaltungen der gewählten Gruppe sowie Moodle-Abgabefristen |
| Nicht           | **keine** wiederkehrende Systembenachrichtigung. Eine wiederkehrende Benachrichtigung würde den zum Planungszeitpunkt eingefrorenen Text wiederholen und nach kurzer Zeit falsche Zahlen zeigen   |
| Sperrbildschirm | aggregiert; keine Moodle-Kurs- oder Aufgabentitel (§ 7.7)                                                                                                                                         |
| Leerer Tag      | Hat ein Tag in **allen** vier Quellen keinen Eintrag, wird für ihn **keine** Tagesübersicht geplant. Begründung und Zuständigkeit: § 13.3                                                         |
| Tap-Ziel        | Tagesansicht des betreffenden Tages, siehe § 7.8                                                                                                                                                  |

#### N3 — `canteen.favourite`: Favoritengericht um 11:00 Uhr · P6

| Feld         | Festlegung                                                                                                                                                        |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Zeitpunkt    | **11:00 Uhr Ortszeit** des Angebotstages                                                                                                                          |
| Auslöser     | Im Speiseplan der bevorzugten Mensa steht an diesem Tag mindestens ein Gericht, dessen **Name** in `canteen.favourites.v1` enthalten ist                          |
| Anzahl       | ein Hinweis je Mensa und Tag, unabhängig von der Zahl der Treffer. Das ist keine Bündelung im Sinne von P8, sondern der Hinweis selbst — P6 sieht genau einen vor |
| Abgleich     | über den Gerichtsnamen (§ 4.1 Befund 5), nicht über `Meal.id`                                                                                                     |
| Reichweite   | begrenzt durch den lokalen Speiseplan von 14 Tagen                                                                                                                |
| Textvorsicht | ein Speiseplan kann sich nachträglich ändern; der Text formuliert entsprechend („laut Speiseplan“)                                                                |
| Tap-Ziel     | das Gericht im Speiseplan des betreffenden Tages, siehe § 7.8                                                                                                     |

**Keine weiteren Kategorien.** Insbesondere entstehen nach P5 **keine** Einzelhinweise für
Lehrveranstaltungen, Stundenplanausfälle oder Moodle-Abgabefristen.

### 7.4 Zustellfenster und Verschiebung · P7

Das Fenster gilt für den **geplanten** Zeitpunkt einer Benachrichtigung. N2 (08:00) und N3 (11:00)
liegen konstruktionsbedingt darin; verschoben werden kann nur N1.

```text
zulässig(t)  ⟺  07:00:00 ≤ Ortszeit(t) ≤ 20:00:00

soll = start − 24 h
wenn zulässig(soll)                → geplant = soll
sonst wenn Ortszeit(soll) < 07:00  → geplant = 07:00 desselben Tages
sonst (Ortszeit(soll) > 20:00)     → geplant = 07:00 des Folgetages
wenn geplant ≤ jetzt               → nicht planen
```

Drei Eigenschaften, die diese Regel nachweislich hat und die als Testfälle gehören:

- **Ein verschobener Hinweis liegt nie nach dem Event.** Die größte Verschiebung entsteht bei einem
  Soll-Zeitpunkt kurz vor Mitternacht und beträgt gut sieben Stunden — der Event liegt danach immer
  noch mehr als sechzehn Stunden in der Zukunft.
- **Die Verschiebung ist eindeutig.** Für jeden Soll-Zeitpunkt gibt es genau ein Ergebnis; es gibt
  keinen Fall, in dem „nächstmöglich um 07:00 Uhr“ mehrdeutig wäre.
- **Verschobene Hinweise können kollidieren.** Fallen zwei Events auf denselben verschobenen
  07:00-Termin, entstehen nach P8 **zwei** Benachrichtigungen mit eigenen Kennungen.

Grenzwerte sind bewusst als **einschließend** festgelegt: 07:00:00 und 20:00:00 sind zulässig.
Diese Konvention ist eine Architekturfestlegung zur Eindeutigkeit, keine neue fachliche Regel.

Zeitzone und Sommerzeit: Alle festen Uhrzeiten sind **Ortszeit-Wanduhrzeiten** und werden über
`zonedSchedule` mit der Gerätezeitzone geplant. Die 24 Stunden aus P3 sind dagegen eine **absolute
Dauer**; an einem Zeitumstellungstag weicht die Wanduhrzeit des Hinweises daher um eine Stunde von
der des Events ab. Das ist die wörtliche Umsetzung von „exakt 24 Stunden“.

### 7.5 Budget und Priorisierung

iOS begrenzt die Zahl gleichzeitig vorgemerkter lokaler Benachrichtigungen je App (dokumentierter
Richtwert **64**; gegen die eingesetzte Plattformversion zu verifizieren). Der Planer arbeitet
deshalb mit einem festen Budget:

- höchstens `maxScheduled` Einträge gleichzeitig, festgelegt auf **60** (Reserve unter der Grenze),
- Sortierung **aufsteigend nach geplantem Zeitpunkt**; bei identischem Zeitpunkt nach fester
  Kategorienreihenfolge `event.reminder` → `daily.summary` → `canteen.favourite`; bei weiterhin
  identischem Schlüsselpaar lexikografisch nach stabilem Schlüssel. Damit ist die Auswahl
  **deterministisch** und in einem Unit-Test reproduzierbar,
- Einträge in der Vergangenheit sowie lokal abgesagte, gelöschte oder verwaiste Einträge werden
  vorher aussortiert und belegen kein Budget,
- was nicht ins Budget passt, wird beim nächsten Lauf geplant — der Vorrat rückt nach.

Wird das Budget in einem Lauf ausgeschöpft, ist das ein **Zähler und eine Logzeile**, keine stille
Kürzung.

**Größenordnung unter den freigegebenen Regeln:** eine Tagesübersicht je Tag, höchstens ein
Favoritenhinweis je Tag, dazu die Eventhinweise. Sechzig Plätze reichen damit typisch für rund drei
bis vier Wochen im Voraus — deutlich mehr, als die Datenlage der Quellen ohnehin hergibt (Speiseplan
14 Tage). Der begrenzende Faktor ist in der Praxis die Datenreichweite, nicht das Budget.

### 7.6 Identität, Ersetzen und Stornieren · P12

Jede geplante Benachrichtigung hat einen **stabilen Schlüssel**:

| Art                 | Schlüssel                       | Beispiel                             |
| ------------------- | ------------------------------- | ------------------------------------ |
| `event.reminder`    | `n1:<CalendarEntry.id>`         | `n1:savedEvent:calendar:4711`        |
| `daily.summary`     | `n2:<YYYY-MM-DD>`               | `n2:2026-09-03`                      |
| `canteen.favourite` | `n3:<canteenSlug>:<YYYY-MM-DD>` | `n3:mensa-fasanerieallee:2026-09-03` |

- `CalendarEntry.id` wird **übernommen, nicht neu gebildet** (§ 4.1 Befund 1).
- Die vom Betriebssystem verlangte Ganzzahl-Kennung ist ein **deterministischer 31-Bit-Hash** des
  Schlüssels. Weil ohnehin vollständig neu geplant wird, ist eine Kollision folgenlos — die
  Stabilität dient der Diagnose, nicht der Korrektheit.
- **Ersetzen und Stornieren** ergeben sich aus § 7.1 und brauchen keinen eigenen Mechanismus: Ein
  verschobener Termin erzeugt denselben Schlüssel zu einem neuen Zeitpunkt, ein abgesagter oder
  gelöschter erzeugt gar keinen mehr.
- **Grenze, die offen bleiben muss:** Eine bereits **zugestellte** Benachrichtigung lässt sich nicht
  zurückholen. Wird eine Absage erst danach lokal bekannt, bleibt der Hinweis in der Historie des
  Geräts stehen. Die App zeigt beim Antippen den aktuellen Stand — mehr ist mit S1 nicht zusagbar.

### 7.7 Texte, Sperrbildschirm und Bündelung · P8, P9, P10

- Titel und Text kommen aus den bestehenden ARB-Dateien (`gen_l10n`, AGENTS.md § 6). Das ist ein
  echter Vorteil gegenüber Remote-Push: Dort hätte es einen zweiten, serverseitigen Textkatalog
  gebraucht, der mit den ARB-Dateien hätte synchron gehalten werden müssen.
- Fremdtexte werden **nicht** übersetzt: Gerichtsname, WebUntis-Fachtitel und Eventtitel erscheinen
  in der Sprache der Quelle, eingebettet in einen übersetzten Rahmen (AGENTS.md § 6).
- **Keine Bündelung (P8):** Die App vergibt **keinen** Gruppenschlüssel und erzeugt **keine**
  Sammelbenachrichtigung. Jeder Hinweis ist eine eigene Benachrichtigung mit eigener Kennung. Dass
  Android und iOS die Benachrichtigungen **einer App** im Benachrichtigungszentrum optisch
  untereinander stapeln, ist Systemverhalten und von der App nicht steuerbar — das ist keine
  Bündelung im Sinne von P8 und darf nicht als solche fehlinterpretiert werden.
- **Sperrbildschirm:** Die einzige plattformübergreifend zusagbare Umsetzung von P10 ist, den
  **Benachrichtigungstext selbst** neutral zu halten. Android bietet je Benachrichtigung eine
  Sichtbarkeitsstufe, iOS über `hiddenPreviewsBodyPlaceholder` einen Ersatztext — **beide greifen
  nur unter Nutzereinstellungen, die die App nicht kontrolliert**. Wer „Vorschauen: immer“ gewählt
  hat, sieht den vollen Text. Ein Schutz, der von einer fremden Einstellung abhängt, ist keiner.

Daraus die verbindliche Inhaltsregel je Kategorie:

| Kategorie           | Sperrbildschirm                                                                                           | Regel |
| ------------------- | --------------------------------------------------------------------------------------------------------- | ----- |
| `event.reminder`    | Eventtitel, Zeit und Ort dürfen **vollständig** erscheinen — öffentliche Termindaten                      | P9    |
| `canteen.favourite` | Gerichtsname und Mensa dürfen **vollständig** erscheinen — öffentliche Speiseplandaten                    | P9    |
| `daily.summary`     | Moodle erscheint **nur aggregiert** (Anzahl der heute fälligen Abgaben), **ohne** Kurs- und Aufgabentitel | P10   |

Details zu einer Moodle-Frist erscheinen ausschließlich in der App, nach dem Tap. Die konkrete
Textfassung — auch die Frage, wie ausführlich Lehrveranstaltungen in der Tagesübersicht genannt
werden — gehört in die UX- und Content-Spezifikation (LEVIORA-167) und ist durch die Regel oben
nach oben begrenzt, nicht ersetzt.

### 7.8 Payload und Tap-Ziele · P11

Der Payload ist ein lokal erzeugter, **versionierter** String der Form `v1|<art>|<schlüssel>`. Er
enthält **keinen Pfad und keine URL**, keine personenbezogenen Inhalte und kein Geheimnis. Die Route
baut der Client aus der Tabelle unten. Der Payload wird trotzdem validiert: Er überlebt App-Updates
und darf nach einem Update nicht auf ein Ziel zeigen, das es nicht mehr gibt. Unbekannte Version,
unbekannte Art oder unauflösbarer Schlüssel führen **nie** zu einem Absturz, sondern auf das
Fallbackziel — dort informiert eine dezente Meldung, dass der Eintrag nicht mehr vorhanden ist.

Ein Nebeneffekt von P5, der ausdrücklich festgehalten gehört: Weil es keine Moodle-Einzelhinweise
gibt, enthält **kein** Payload je eine Moodle-Kennung. Der Payload der Tagesübersicht ist ein
Datum. Damit liegt zu keinem Zeitpunkt ein Bezug auf persönliche Studiendaten im
Benachrichtigungsspeicher des Betriebssystems.

Es wird **kein** OS-Deep-Link eingeführt: kein Custom-Schema, keine App Links, keine Associated
Domains. Die Navigation ist app-intern.

#### Verfügbarkeit der direkten Ziele — am Bestand geprüft

Der folgende Befund ist gegen `apps/mobile/lib/app/app_routes.dart`, `app_router.dart` und die
betroffenen Features geprüft. **Keine Route ist erfunden.**

| Art laut P11                           | Direktes Ziel                 | Im Bestand vorhanden?                                                                                                                                                                                                                                                                       | Umsetzungsbedarf                                                                                                                                                | Fallback                                        |
| -------------------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| **Event** (`event.reminder`)           | Detailansicht des Events      | **Nein, nicht als Ziel.** Die Detailansicht existiert als `showCalendarEntrySheet(context, CalendarEntry)`, ist aber nur aus dem Kalenderscreen mit dem Objekt in der Hand erreichbar. `/calendar` nimmt keine Parameter entgegen; eine Detailroute für einen einzelnen Event gibt es nicht | **Ja:** Zielparameter an `/calendar` (Eintragskennung und Tag), Auflösung der Kennung gegen den zusammengeführten Bestand, danach Öffnen des vorhandenen Sheets | `/calendar` auf dem Tag des Termins, ohne Sheet |
| **Tagesübersicht** (`daily.summary`)   | Tagesansicht des Tages        | **Teilweise.** `/calendar` existiert, die Tagesansicht ist ein Zustand (`calendarViewModeProvider` mit `CalendarViewMode.day`, Standard) und `calendarFocusedDayProvider` hält den fokussierten Tag — aber die Route trägt keinen Tag und der Router liest keinen Parameter                 | **Ja:** derselbe Tagesparameter an `/calendar`, der den fokussierten Tag setzt und die Tagesansicht wählt                                                       | `/calendar` unverändert                         |
| **Mensagericht** (`canteen.favourite`) | Das Gericht im Speiseplan     | **Nein.** `/canteen` nimmt keine Parameter; Mensa und Tag liegen in `selectedCanteenSlugProvider` und `selectedMenuDayProvider`. Eine Hervorhebung eines einzelnen Gerichts gibt es nicht                                                                                                   | **Ja:** Parameter für Mensa, Tag und Gerichtsname an `/canteen`, Setzen der beiden Zustände und Hervorhebung der Karte                                          | `/canteen` unverändert                          |
| **Stundenplantermin**                  | Detailansicht des Termins     | **Nicht als Ziel** — dieselbe Lage wie beim Event: `showCalendarEntrySheet` existiert, eine Route dorthin nicht                                                                                                                                                                             | **Im freigegebenen Umfang nicht nötig** (P5: keine Einzelhinweise). Fällt mit dem Eintragsparameter des Events ohnehin ab                                       | entfällt                                        |
| **Moodle-Element**                     | Aufgabe beziehungsweise Frist | **Nicht als eigenes Ziel.** `/more/moodle` und die benannte Route `moodle-course` (`/more/moodle/course/:id`) existieren; `MoodleDeadline` trägt `courseId`. Eine Route auf eine einzelne Frist gibt es nicht                                                                               | **Im freigegebenen Umfang nicht nötig** (P5). Würde er je gebraucht, ist der Kurs über die vorhandene Route direkt erreichbar                                   | `/more/moodle`                                  |

Ergänzend gilt: Eine Route für einen **einzelnen Beitrag** existiert weiterhin nicht — der Feed
klappt Artikel an Ort und Stelle auf. Für die freigegebenen Kategorien ist das unerheblich; keine
von ihnen zeigt auf einen einzelnen Beitrag.

Ebenfalls **noch nicht vorhanden** ist die von der UX-Spezifikation vorgesehene Route
`/more/settings/notifications`. Sie ist Teil von LEVIORA-162 (§ 14) und keine Annahme dieses ADRs.

**Fazit für LEVIORA-162:** P11 ist mit dem Bestand **nicht** erfüllbar, aber mit geringem Aufwand
erreichbar. Es braucht **keine** neue Detailroute und **kein** neues Detail-UI, sondern genau zwei
Dinge: einen Zielparameter an `/calendar` und `/canteen` sowie eine Auflösung von Kennung zu
Eintrag. Beides ist rein additiv und berührt keinen bestehenden Vertrag.

### 7.9 Plattformdetails

| Punkt                      | Festlegung                                                                                                                                                                                                                                                                                                                                       |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Bibliothek                 | `flutter_local_notifications`, plus `timezone` für zonenrichtige Zeitpunkte und ein kleines Paket zur Ermittlung der Gerätezeitzone (exakte Auswahl gegen die eingesetzte Plugin-Version prüfen)                                                                                                                                                 |
| Terminierung               | `zonedSchedule` **inexakt** (`inexactAllowWhileIdle`) — damit braucht Android 12+ **kein** `SCHEDULE_EXACT_ALARM`                                                                                                                                                                                                                                |
| Genauigkeit am Fensterrand | Inexakte Terminierung kann einige Minuten später zustellen. Ein auf 19:5x geplanter Hinweis kann daher nach 20:00 Uhr erscheinen. Das Fenster aus P7 ist eine **Planungsregel**; eine Zustellung auf die Minute wäre nur mit `SCHEDULE_EXACT_ALARM` zusagbar, und dieser Preis steht in keinem Verhältnis. Die Abweichung ist zu messen (§ 13.2) |
| Android-Kanäle             | **drei** Kanäle, je einer für N1, N2 und N3, vor der ersten Planung angelegt. Kanäle sind kein Gruppenschlüssel und berühren P8 nicht                                                                                                                                                                                                            |
| Android-Berechtigung       | `POST_NOTIFICATIONS` ab Android 13; darunter gilt sie als erteilt — beides muss die UI korrekt darstellen                                                                                                                                                                                                                                        |
| Kleines Symbol (Android)   | monochrom, sonst zeigt Android ein graues Quadrat                                                                                                                                                                                                                                                                                                |
| iOS-Berechtigung           | erst nach erklärtem Nutzen anfragen: im letzten Onboarding-Schritt beim bewussten Abschluss mit aktiviertem Schalter oder später über einen kontextuellen Einstiegspunkt (LEVIORA-158/167)                                                                                                                                                       |
| iOS-Capabilities           | **keine.** Kein Push-Entitlement, kein `aps-environment`, keine Background Modes                                                                                                                                                                                                                                                                 |
| Vordergrund                | die App entscheidet selbst über die Darstellung; es kommt ohnehin nichts von außen                                                                                                                                                                                                                                                               |

## 8. Der frühere Kandidatenkatalog und was aus ihm geworden ist

Die dreizehn Kandidaten der ersten Fassung sind durch LEVIORA-159 entschieden. Die Tabelle bleibt
erhalten, damit nachvollziehbar ist, was bewusst nicht gebaut wird — sie ist **keine** offene Liste
mehr.

| #   | Kandidat                         | Entscheidung nach LEVIORA-159                                                  |
| --- | -------------------------------- | ------------------------------------------------------------------------------ |
| K1  | Gemerktes Event                  | **In N1 aufgegangen** — Erinnerung exakt 24 h vorher                           |
| K2  | Termin aus öffentlichem Kalender | **In N1 aufgegangen** — nur aus aktivierten Kalendern                          |
| K3  | Vor einer Lehrveranstaltung      | **Kein Einzelhinweis** (P5). Erscheint in N2, sobald WebUntis freigegeben ist  |
| K4  | Stundenplanausfall               | **Kein Einzelhinweis** (P5). Ein lokal bekannter Ausfall erscheint in N2       |
| K5  | Lieblingsgericht                 | **N3**, fest um 11:00 Uhr                                                      |
| K6  | Moodle-Abgabefrist               | **Kein Einzelhinweis** (P5). Erscheint aggregiert in N2                        |
| K7  | Tagesübersicht                   | **N2**, fest um 08:00 Uhr                                                      |
| K8  | Aufgabe fällig                   | Nicht Bestandteil der Freigabe. `Todo` hat weiterhin kein Fälligkeitsdatum     |
| K9  | Neuer Beitrag / neues Event      | **Bewusster Verzicht** (LEVIORA-159). Strukturell nur mit S2, dann best effort |
| K10 | Neue E-Mail                      | Nicht Bestandteil der Freigabe. Mit S2 grundsätzlich erreichbar, siehe § 13.4  |
| K11 | Neue Note                        | **Nein** — persönliche Daten, falsche Voreinstellung auf dem Sperrbildschirm   |
| K12 | Moodle-Ankündigung               | Nicht Bestandteil der Freigabe. Wie K10                                        |
| K13 | Notfallmeldung                   | **Nein** — keine autoritative Quelle, die App ist unabhängig und inoffiziell   |

**Aus dreizehn Kandidaten sind drei Kategorien geworden — ohne Server, ohne Anbieter, ohne einen
einzigen gespeicherten Datensatz außerhalb des Geräts.**

## 9. Grenzen, die nicht wegzuoptimieren sind

Diese Punkte gehören in die UX-Texte (LEVIORA-167), nicht ins Kleingedruckte. LEVIORA-159 hält
ausdrücklich fest, dass sie in Produkttexten nicht als Echtzeitverhalten dargestellt werden dürfen.

1. **Die App muss gelegentlich geöffnet werden.** Neu geplant wird nur, wenn die App läuft. Der
   Vorrat reicht typisch mehrere Wochen (60 vorgemerkte Einträge), aber er ist endlich. Wer die App
   einen Monat nicht öffnet, bekommt danach nichts mehr, bis er sie öffnet.
2. **Änderungen nach der Planung schlagen erst mit dem nächsten Abruf durch.** Ein Termin, der nach
   der Planung abgesagt wird, kann trotzdem erinnern, wenn die App die Absage nie gesehen hat. Das
   ist die Grenze von P12 und ausdrücklich keine Echtzeitgarantie. Milderung: bei jedem
   erfolgreichen Abruf neu planen; beim Antippen zeigt die App den aktuellen Stand.
3. **Eine bereits zugestellte Benachrichtigung ist nicht zurückholbar** (§ 7.6).
4. **Keine Nachholung verpasster Zeitpunkte.** War das Gerät aus, wird eine vergangene Erinnerung
   nicht nachgeholt. Das ist richtig so — eine Erinnerung an einen Termin von gestern ist Lärm.
5. **Streuung bei der Uhrzeit.** Inexakte Alarme können auf Android um einige Minuten verschoben
   zustellen; am Rand des Zustellfensters ist das sichtbar (§ 7.9).
6. **Herstellerseitige Akku-Optimierung.** Einzelne Android-Hersteller unterdrücken geplante
   Benachrichtigungen aggressiv. Das ist nicht vollständig lösbar; ein Hinweis in den Einstellungen
   ist die ehrliche Antwort.
7. **iOS-Obergrenze** gleichzeitig vorgemerkter Benachrichtigungen (Richtwert 64) — durch das Budget
   in § 7.5 abgefangen, aber real.
8. **Verweigerte Berechtigung ist endgültig genug.** iOS zeigt den Systemdialog nur einmal. Danach
   führt der Weg über die Systemeinstellungen. Wiederholtes Nachfragen ist ausgeschlossen.
9. **Der Sperrbildschirmschutz ist Textdisziplin, keine Plattformzusage** (§ 7.7).
10. **Die Reichweite der Quellen begrenzt den Vorlauf.** Der Speiseplan reicht 14 Tage; darüber
    hinaus gibt es keine Favoritenhinweise, auch wenn Budget frei wäre.

## 10. Datenschutz und Sicherheit

Die Bilanz ist ungewöhnlich kurz, und das ist der Punkt:

- **Kein** Auftragsverarbeiter, **kein** Push-Anbieter, **kein** Gerätetoken, **kein**
  Drittanbieter-SDK.
- **Kein** serverseitiger Datensatz. Backend, Datenbank und API bleiben unverändert; es entsteht
  kein Schreibpfad und damit auch keine der Missbrauchsflächen, die ein Registrierungsendpunkt
  mitgebracht hätte (Rate-Limiting, Enumeration, Registrierungsmüll).
- **Kein** neues Secret. Kein APNs-Schlüssel, kein Service-Account, keine Rotation, kein
  Umgebungsvertrag.
- Alle verarbeiteten Daten bleiben auf dem Gerät. Für Moodle-Fristen heißt das ausdrücklich: Die
  Fristen werden lokal gelesen und lokal ausgewertet; G10–G12 bleiben unangetastet.
- **Kein** Payload trägt eine Moodle-Kennung oder einen anderen personenbezogenen Bezeichner
  (§ 7.8). Im Benachrichtigungsspeicher des Betriebssystems liegen Kalenderkennungen, Daten und
  Gerichtsnamen — nichts davon ist ein persönliches Studiendatum.
- Die Datenschutzerklärung braucht dafür keinen Abschnitt über einen Empfänger, sondern nur einen
  Hinweis, dass die App die Benachrichtigungsberechtigung nutzt und Termine lokal auswertet.

**Was trotzdem zu beachten ist:** Der Inhalt einer Benachrichtigung erscheint je nach
Geräteeinstellung auf dem gesperrten Bildschirm. Die Umsetzung von P10 ist deshalb eine Regel über
den **Text**, nicht über eine Plattformeinstellung — siehe § 7.7. Konkret heißt das: Die
Tagesübersicht nennt keine Moodle-Kurs- oder Aufgabentitel.

Der Payload einer geplanten Benachrichtigung überlebt App-Updates. Er wird deshalb beim Antippen
validiert und nicht blind in eine Route übersetzt.

## 11. Rollout und Voraussetzungen

### 11.1 Voraussetzungen

| Voraussetzung                          | Status                                                                                                                                                  |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apple Developer Program                | **für diese Lösung nicht nötig** (für eine App-Store-Veröffentlichung ohnehin, aber ohne Push-Capability und ohne APNs-Schlüssel)                       |
| Firebase-Projekt                       | **entfällt**                                                                                                                                            |
| APNs-Authentifizierungsschlüssel       | **entfällt**                                                                                                                                            |
| Backend-Änderungen, Secrets, Migration | **entfällt**                                                                                                                                            |
| Physisches Android- und iOS-Testgerät  | ja — Berechtigungs- und Zustellverhalten ist im Simulator nicht belastbar                                                                               |
| Zusätzliche Flutter-Pakete             | `flutter_local_notifications`, `timezone` und ein kleines Paket für die Gerätezeitzone; Lizenzbewertung in `docs/legal/dependency-licenses.md` ergänzen |

### 11.2 Phasen

Die Reihenfolge folgt dem Aufwand, nicht der Wichtigkeit: N1 braucht die wenigsten Quellen und
zwingt trotzdem, den Zielparameter aus § 7.8 gleich mitzubauen.

| Phase | Inhalt                                                                                                                                                | Rückfall                      |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| 1     | Planer, Scheduler, Opt-in-UX, Einstellungsseite `/more/settings/notifications`, **N1** — einschließlich Eintragsparameter an `/calendar` und Fallback | Feature-Flag in der App       |
| 2     | **N2** (Tagesübersicht) mit Event-, Moodle- und Mensa-Anteil, einschließlich Tagesparameter an `/calendar`                                            | Kategorie einzeln abschaltbar |
| 3     | **N3** (Favoritengericht) einschließlich Ziel- und Hervorhebungsparameter an `/canteen`                                                               | dito                          |
| 4     | Stundenplananteil der Tagesübersicht — erst nach der WebUntis-Freigabe (`WEBUNTIS_ENABLED`)                                                           | Anteil entfällt ersatzlos     |
| 5     | Getrennt zu entscheiden: **S2** und damit K9/K10/K12                                                                                                  | S2 abschaltbar                |

Jede Kategorie ist einzeln abschaltbar; nach dem globalen Opt-in sind alle drei aktiv (P2). Ein
Notaus ist ein Schalter in den Einstellungen plus `cancelAll()` — es gibt keinen Serverzustand, der
nachziehen müsste.

**Kompatibilität:** rein additiv innerhalb der App. Kein API-, Payload- oder Datenbankvertrag ist
betroffen. Die neuen Zielparameter an `/calendar` und `/canteen` sind optional; beide Routen
funktionieren ohne sie unverändert.

## 12. Konsequenzen

**Positiv**

- Keine Fremdanbindung, kein Anbieter, keine Kosten, keine Secrets, keine Registrierung, kein
  serverseitiger Datensatz.
- Die Kernlogik ist eine reine Funktion und ohne Gerät testbar — deutlich bessere Testbarkeit als
  eine verteilte Sende-Kette.
- Texte kommen aus den vorhandenen ARB-Dateien; kein zweiter Textkatalog.
- Das Lieblingsgericht wird ohne Upload von Gerichtsnamen möglich — datensparsamer **und**
  zuverlässiger als der Remote-Weg.
- Moodle-Fristen werden möglich, ohne eine einzige Systemgrenze zu berühren — und nach P5 sogar,
  ohne dass eine Moodle-Kennung je in einen Payload gerät.
- **P5 verkleinert den Umfang erheblich:** kein Vorlauf-Modell je Terminart, keine Einzelhinweise
  für Stundenplan und Moodle, kein Anti-Spam-Verhältnis zwischen Übersicht und Einzelhinweis, zwei
  Tap-Ziele weniger.
- Die Umsetzung liegt vollständig in einem Repository-Bereich und in einer Rolle.
- LEVIORA-160 (Backend) und LEVIORA-161 (Firebase-/APNs-Provisionierung) sind für diesen Umfang
  gegenstandslos und wurden abgebrochen.

**Negativ, bewusst akzeptiert**

- „Neuer Beitrag“ und der kurzfristige Stundenplanausfall entfallen — LEVIORA-159 führt das
  ausdrücklich als bewussten Verzicht.
- Die App muss gelegentlich geöffnet werden, sonst läuft der Vorrat leer.
- Geplante Benachrichtigungen können veralten, wenn sich der Termin nachträglich ändert.
- Ein Hinweis am Rand des Zustellfensters kann durch inexakte Terminierung wenige Minuten außerhalb
  zugestellt werden.
- Herstellerseitige Akku-Optimierung kann auf einzelnen Android-Geräten Zustellungen unterdrücken.

**Risiken mit Frühindikator**

| Risiko                                                  | Frühindikator                                 | Gegenmaßnahme                                                           |
| ------------------------------------------------------- | --------------------------------------------- | ----------------------------------------------------------------------- |
| Zu viele Erinnerungen, Nutzer schalten alles ab         | Rückmeldungen; hohe Zahl geplanter Einträge   | Nach P5 nur drei Kategorien; jede einzeln abschaltbar                   |
| Vorrat läuft leer bei seltener Nutzung                  | in der Gerätematrix reproduzierbar            | Budget ausschöpfen, in der UX ehrlich erklären                          |
| Veraltete Erinnerung nach einer Absage                  | Testfall in der Gerätematrix                  | Neuplanung nach jedem Abruf; vorsichtige Textwahl                       |
| iOS-Grenze überschritten, Einträge fallen weg           | Zähler „Budget ausgeschöpft“                  | Budget 60 statt 64, Priorisierung nach Zeitpunkt                        |
| Abbruch zwischen `cancelAll()` und erneuter Planung     | leerer Planungsstand nach erzwungenem Beenden | Serialisierte Neuplanung; jeder App-Start plant neu; Fall in der Matrix |
| Planer liest versehentlich die Kalender-Anzeigeschalter | gemerkte Events erzeugen keine Hinweise       | Unit-Test auf den Geltungsbereich aus § 7.2                             |

**Umkehrbarkeit.** Sehr hoch. Rückbau heißt: `cancelAll()`, zwei bis drei Pakete entfernen, die
optionalen Zielparameter zurücknehmen. Es entsteht keine Migration, weil keine Daten das Gerät
verlassen und kein Schema angelegt wird. Ein späterer Wechsel auf S2 oder Remote-Push baut auf
demselben Planer auf.

## 13. Entscheidungsstand

### 13.1 Fachlich entschieden — keine offenen Punkte

Die früher hier geführten Entscheidungen E1–E10 sind abgeschlossen. Die Tabelle hält das Ergebnis
fest; die damaligen Vorschläge stehen im [Anhang C](#anhang-c--historische-vorschläge-vor-der-produktfreigabe).

| Frage von damals                              | Entschieden (LEVIORA-159, sofern nicht anders vermerkt)                                                               |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Kein Remote-Push, auch um den Preis von K9/K4 | Bestätigt; der Verzicht ist ausdrücklich benannt                                                                      |
| Welche Kandidaten kommen in den ersten Wurf?  | N1, N2 und N3 — der vollständige freigegebene Umfang                                                                  |
| Welche Kategorie ist standardmäßig an?        | **Alle**, nach dem globalen Opt-in (P2)                                                                               |
| Einzelerinnerung oder Tagesübersicht?         | Beides, aber getrennt geregelt: N1 für Events, N2 als Übersicht, keine Einzelhinweise für Stundenplan und Moodle (P5) |
| Was darf auf dem Sperrbildschirm stehen?      | Öffentliche Termindetails vollständig (P9), persönliche Inhalte neutral (P10)                                         |
| Vorlaufzeit der Erinnerungen                  | Exakt 24 Stunden für Events (P3); feste Uhrzeiten für N2 und N3. **Keine** einstellbare Vorlaufzeit                   |
| Bekommt `Todo` ein Fälligkeitsdatum?          | Nicht Bestandteil der Freigabe                                                                                        |
| Wird S2 angegangen?                           | Nicht Bestandteil der Freigabe; getrennt zu entscheiden (§ 13.4)                                                      |
| Was passiert mit LEVIORA-160 und LEVIORA-161? | Beide sind abgebrochen                                                                                                |
| Notfallmeldungen (K13)                        | Bleibt beim Nein                                                                                                      |

### 13.2 Technisch offen — ausdrücklich nicht als Annahme versteckt

Diese Punkte sind **technisch** und ändern keine Produktregel. Sie sind beim Einbau zu messen,
nicht zu schätzen.

- Die genaue Obergrenze gleichzeitig vorgemerkter lokaler Benachrichtigungen unter iOS ist gegen die
  eingesetzte Plattformversion zu **messen**.
- Welches Paket die Gerätezeitzone liefert und wie es sich zur eingesetzten
  `flutter_local_notifications`-Version verhält, ist beim Einbau zu prüfen.
- Wie stark die inexakte Terminierung auf den Zielgeräten streut — insbesondere am Rand des
  Zustellfensters und unter Doze — ist zu messen.
- Das Verhalten bei aggressiver herstellerseitiger Akku-Optimierung ist nur auf echten Geräten
  belastbar zu beurteilen und gehört in die manuelle Gerätematrix.
- Welche Sichtbarkeits- beziehungsweise Vorschau-Optionen die eingesetzte Plugin-Version je
  Plattform tatsächlich anbietet, ist zu prüfen. An der Textregel aus § 7.7 ändert das nichts; sie
  gilt unabhängig davon.

### 13.3 Eine Contentfrage, kein Architekturthema

LEVIORA-159 regelt nicht, ob an einem Tag **ganz ohne** Einträge trotzdem eine Tagesübersicht
erscheint. Architekturseitig ist der datensparsame Standard festgelegt (§ 7.3 N2: keine Übersicht
für einen leeren Tag), damit LEVIORA-162 nicht blockiert ist und nicht raten muss. Eine andere
Wahl — etwa eine bewusst freundliche „heute nichts“-Nachricht — ist eine Content-Entscheidung und
gehört zu LEVIORA-167 beziehungsweise zu Erik. Sie ändert am Planungsvertrag nur eine Bedingung.

### 13.4 Bewusst offengehalten

S2 (Hintergrundaktualisierung) und damit K9, K10 und K12 bleiben eine eigene, spätere Entscheidung.
Sie ist **additiv**: Der Planer aus § 7 bliebe unverändert, es käme nur ein weiterer Auslöser für
„neu planen“ hinzu.

## 14. Arbeitspakete

**LEVIORA-162 — Mobile** (dieser Umfang liegt vollständig hier):

1. `NotificationPlanner` als reine Funktion über den bereits zusammengeführten Terminbestand und den
   Speiseplan, mit den Regeln aus § 7.3 und § 7.4.
   _Akzeptanz:_ Unit-Tests für die 24-Stunden-Regel, beide Verschiebungsrichtungen des
   Zustellfensters, die einschließenden Grenzwerte 07:00 und 20:00, Budgetgrenze mit
   deterministischer Sortierung, Vergangenheitsfilter, abgesagte und verwaiste Einträge, leerer Tag,
   Zeitzonen- und Zeitumstellungswechsel — alles ohne Plattformaufruf.
2. Geltungsbereich nach § 7.2.
   _Akzeptanz:_ ein Test, der belegt, dass ein ausgeschalteter Kalender-Anzeigeschalter
   (`calendarEnabledSourcesProvider`, `calendarSavedEventsEnabledProvider`) die Planung **nicht**
   verändert, und einer, der belegt, dass ein abgewählter öffentlicher Kalender sie **sehr wohl**
   verändert.
3. `NotificationScheduler` als Port über `flutter_local_notifications`, vollständige Neuplanung,
   serialisiert nach § 7.1.
   _Akzeptanz:_ zweimaliges Planen desselben Zustands erzeugt keine Duplikate; zwei gleichzeitig
   angestoßene Neuplanungen führen zu genau einem Endzustand.
4. Opt-in-Flow, Einstellungsseite `/more/settings/notifications` und Kategorieschalter nach
   LEVIORA-167; alle drei Kategorien nach dem Opt-in aktiv (P2); Berechtigungsstatus korrekt für
   Android 13+, ältere Android-Versionen, iOS und den entzogenen Zustand.
   _Akzeptanz:_ verweigerte Berechtigung führt nicht in eine Sackgasse und fragt nicht erneut.
5. Neuplanung an allen Auslösern aus § 7.1, einschließlich Zeitzonen-, Sprach- und Tageswechsel.
6. Zielparameter und Auflösung nach § 7.8: Eintrags- und Tagesparameter an `/calendar`, Mensa-, Tag-
   und Gerichtsparameter an `/canteen`, Payload-Validierung mit Fallback.
   _Akzeptanz:_ ein Payload aus einer älteren App-Version führt weder zu einem Absturz noch zu
   beliebiger Navigation; ein nicht mehr vorhandener Eintrag landet auf dem Fallbackziel mit
   Hinweis; beide Routen funktionieren ohne Parameter unverändert.
7. Texte nach § 7.7 in den ARB-Dateien; die Tagesübersicht ohne Moodle-Kurs- und Aufgabentitel.
   _Akzeptanz:_ ein Test, der belegt, dass kein Moodle-Titel in einen Benachrichtigungstext oder
   Payload gelangt.
8. Manuelle Gerätematrix: Android 13+ und älter, iOS, beendete App, Neustart des Geräts,
   Zeitzonen- und Zeitumstellungswechsel, verweigerte und entzogene Berechtigung, Gerät mit
   aggressiver Akku-Optimierung, erzwungenes Beenden während einer Neuplanung, Streuung am Rand des
   Zustellfensters.
9. `docs/legal/dependency-licenses.md` um die neuen Pakete ergänzen.

**LEVIORA-160 / LEVIORA-161** — abgebrochen; sie gehörten zur verworfenen Remote-Variante.

**Dokumentation** (mit der Implementierung, nicht danach):

10. `docs/architecture.md` § 3.3 um den lokalen Benachrichtigungsplaner ergänzen und die Zeile in
    § 8 fortschreiben. Die bestehende Zeile „Hintergrund-Sync bei geschlossener App: ausgeschlossen“
    bleibt gültig und wird durch diese Lösung **nicht** berührt — es läuft kein Code im Hintergrund.
11. `README.md`: „Push-Nachrichten“ in der Spalte „Nicht enthalten“ präzisieren — zutreffend ist
    „keine Push-Nachrichten von einem Server; lokale Erinnerungen ja“.
12. Datenschutzerklärung: kurzer Hinweis auf die Benachrichtigungsberechtigung und die rein lokale
    Auswertung. **Kein** Abschnitt über einen Empfänger, weil es keinen gibt.

---

## Anhang A — Verworfen: Remote-Push über FCM

Festgehalten, damit die Entscheidung nachvollziehbar bleibt und nicht erneut von vorn untersucht
werden muss.

**Untersuchte Varianten:** FCM HTTP v1 mit serverseitigem pseudonymem Installationsregister; FCM
Topics ohne Serverzustand; APNs direkt für iOS plus FCM für Android; selbst gehosteter Push;
Push-SaaS.

**Warum insgesamt verworfen:** ausdrückliche Vorgabe gegen die Anbindung eines externen
Push-Dienstes. Diese Vorgabe hat mehrere Gründe auf ihrer Seite:

- Es entstünde der erste Auftragsverarbeiter der App. Google erhielte ein Gerätetoken und eine
  App-Instanzkennung — eine echte Abkehr von der bisher SDK-freien Haltung, mit Folgen für
  Datenschutzerklärung und Auftragsverarbeitungsvertrag.
- Die Campus API ist heute **vollständig lesend** — kein Schreibendpunkt, keine Authentifizierung,
  kein Rate-Limiting, CORS auf `['GET', 'OPTIONS']`. Ein Registrierungsendpunkt wäre der erste
  Schreibpfad des gesamten Systems und brächte Rate-Limiting, `trust proxy`, Body-Grenzwerte und
  eine Missbrauchsfläche mit.
- Es entstünden erstmals gerätebezogene Datensätze in `campus_app_<env>` samt Aufbewahrungs- und
  Löschpflichten.
- Es wären eine kostenpflichtige Apple-Developer-Mitgliedschaft, ein APNs-Schlüssel, zwei
  Firebase-Projekte und ein Service-Account-Secret mit Rotationsweg nötig.
- Die Mindest-Plattformversionen hätten voraussichtlich angehoben werden müssen
  (`IPHONEOS_DEPLOYMENT_TARGET = 13.0`), und Geräte ohne Google-Play-Dienste hätten nichts erhalten.

**Was Remote-Push zusätzlich gekonnt hätte:** „neuer Beitrag“ zeitnah und der kurzfristige
Stundenplanausfall zuverlässig. Das ist der reale Preis dieser Entscheidung, und LEVIORA-159 nennt
ihn ausdrücklich als bewussten Verzicht.

**Was Remote-Push nie gekonnt hätte:** Mail, Noten und Moodle — dort hat das Backend
konstruktionsbedingt weder Zugangsdaten noch Daten. Unter der lokalen Lösung fließen Moodle-Fristen
sofort in die Tagesübersicht ein, und neue E-Mails wären mit S2 grundsätzlich erreichbar.

**Einzelbewertungen, kompakt**

| Variante                    | Entscheidender Einwand                                                                                     |
| --------------------------- | ---------------------------------------------------------------------------------------------------------- |
| FCM + Installationsregister | tragfähigste Remote-Variante, aber genau die Fremdanbindung, die ausgeschlossen ist                        |
| FCM Topics                  | Widerruf serverseitig **nicht** durchsetzbar: ein „Aus“, dessen Abmeldung offline scheitert, sendet weiter |
| APNs direkt + FCM           | zwei Transporte, zwei Fehlerlandschaften, etwa doppelter Aufwand bei identischem Nutzen                    |
| Selbst gehosteter Push      | auf iOS kein Weg an APNs vorbei; auf Android wäre eine zusätzliche Distributor-App nötig                   |
| Push-SaaS                   | Tracking-orientiertes SDK, laufende Kosten, stärkere Bindung — widerspricht dem Analytics-Ausschluss       |

**Wann diese Entscheidung neu zu prüfen wäre:** wenn „neuer Beitrag“ oder der kurzfristige Ausfall
fachlich unverzichtbar werden und S2 sich in der Praxis als zu unzuverlässig erweist.

## Anhang B — Quellen

Stand 2026-08-24. Vor der Umsetzung erneut prüfen — Plattformdetails und Grenzwerte ändern sich.

- `flutter_local_notifications` — <https://pub.dev/packages/flutter_local_notifications>
- Apple, Berechtigung für Benachrichtigungen erfragen —
  <https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications>
- Apple, `UNUserNotificationCenter` —
  <https://developer.apple.com/documentation/usernotifications/unusernotificationcenter>
- Android, Laufzeitberechtigung für Benachrichtigungen —
  <https://developer.android.com/develop/ui/views/notifications/notification-permission>
- Android, Alarme planen —
  <https://developer.android.com/develop/background-work/services/alarms/schedule>
- Android, Benachrichtigungskanäle —
  <https://developer.android.com/develop/ui/views/notifications/channels>

Projektinterne Quellen: [`../architecture.md`](../architecture.md), [`../api.md`](../api.md),
[`../../AGENTS.md`](../../AGENTS.md), [`../product/mvp.md`](../product/mvp.md),
[`../design/notifications-ux-spec.md`](../design/notifications-ux-spec.md).

## Anhang C — Historische Vorschläge vor der Produktfreigabe

Diese Vorschläge stammen aus der ersten Fassung dieses ADRs, als die fachliche Auswahl noch offen
war. Sie sind **überholt**. Sie stehen hier, damit ein späterer Leser eine Formulierung aus einem
älteren Kommentar oder Ticket zuordnen kann und sie nicht für geltend hält.

| Damaliger Vorschlag                                                        | Geltende Regel                                                     |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| **Keine** Kategorie standardmäßig an; jede wird ausdrücklich eingeschaltet | Alle Kategorien sind nach dem globalen Opt-in aktiv (P2)           |
| Vorlaufzeit **60 Minuten**, in den Einstellungen änderbar                  | Exakt 24 Stunden für Events; keine einstellbare Vorlaufzeit (P3)   |
| K2 (öffentliche Kalender) standardmäßig **aus**, wegen Lärmrisiko          | Events aus aktivierten Kalendern sind Teil von N1 (P3)             |
| Tagesübersicht als **Empfehlung** neben Einzelerinnerungen                 | Feste Tagesübersicht um 08:00 Uhr (P4)                             |
| Einzelerinnerung **vor jeder Lehrveranstaltung** (K3)                      | Keine Einzelhinweise für Lehrveranstaltungen (P5)                  |
| Einzelerinnerung vor jeder **Moodle-Frist** (K6), Vorlauf offen            | Keine Einzelhinweise für Moodle-Fristen (P5)                       |
| Favoritenhinweis „am Vorabend oder am Morgen, feste Uhrzeit“ (K5)          | 11:00 Uhr am Angebotstag (P6)                                      |
| Sperrbildschirminhalt bei Moodle als offene Entscheidung geführt           | Persönliche Inhalte bleiben neutral (P10), Moodle ist die Referenz |
| Ruhezeiten und Bündelung als offene Fragen                                 | Zustellfenster 07:00–20:00 (P7), keine Bündelung (P8)              |
