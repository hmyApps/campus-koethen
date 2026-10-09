<!-- Campus Köthen App · AGPL-3.0-only · Copyright © 2026 Leviora Studio and Jona Loreen Sommer -->

# Lokale Benachrichtigungen — Umsetzung, Plattformkonfiguration und Gerätematrix

Verbindliche Grundlage: [ADR-0001](adr/0001-push-benachrichtigungen.md) (Mechanismus und
Planungsvertrag) und [design/notifications-ux-spec.md](design/notifications-ux-spec.md) (Opt-in,
Einstellungen, Texte). Dieses Dokument beschreibt, **was im Code steht**, wie die beiden
Plattformen konfiguriert sind und was auf echten Geräten geprüft werden muss.

Der Kern in einem Satz: Datierte Hinweise meldet die App **im Voraus beim Betriebssystem des
eigenen Geräts** an; eine im Vordergrund per IMAP bestätigte neue E-Mail kann sie zusätzlich sofort
lokal anzeigen. Es gibt keinen Push-Dienst, kein Gerätetoken, keinen Registrierungsendpunkt,
keinen serverseitigen Datensatz und keinen Code, der bei geschlossener App läuft.

## 1. Aufbau

Alles liegt in `apps/mobile/lib/features/notifications`. Backend, Worker, Campus API, Datenbank und
OpenAPI-Vertrag sind **unverändert**.

```text
domain/          reine Werte und Verträge, ohne Flutter und ohne Plugin
  notification_category.dart      vier Kategorien (N1/N2/N3 geplant, N4 sofort)
  notification_request.dart       ein Kandidat: Kategorie, Ziel, Auslöser, Text, Sichtbarkeit
  planned_notification.dart       ein eingeplanter Eintrag + der 31-Bit-Systemschlüssel
  notification_plan.dart          Sollzustand + Diagnose (Zähler, keine Inhalte)
  delivery_window.dart            das Zustellfenster 07:00–20:00 (P7)
  notification_payload.dart       `v1|<art>|<schlüssel>` mit strenger Validierung
  notification_preferences.dart   Opt-in und Kategorieschalter
  notification_permission.dart    die vier Berechtigungszustände
  notification_gateway.dart       Port zum Betriebssystem (+ Noop-Variante)

application/
  canteen_favourite_candidates.dart  N3: Speiseplan × Favoriten → Kandidaten (reine Funktion)
  notification_planner.dart       REINE FUNKTION: Kandidaten → vollständiger Sollzustand
  notification_scheduler.dart     serialisierte, vollständige Neuplanung
  notification_settings_controller.dart
  notification_providers.dart     Verdrahtung, Berechtigung, Zeitzone, Plan
  notification_tap_router.dart    Payload → App-Route (mit Fallback)
  daily_summary.dart              REINE FUNKTION: Kalendereinträge → ein Tagesbefund je Tag
  daily_summary_content.dart      Tagesbefund → DE-/EN-Text (die einzige Stelle mit Sprache)
  daily_summary_providers.dart    liest die lokalen Quellen und erzeugt die N2-Kandidaten

data/
  local_notification_gateway.dart der EINZIGE Ort, der flutter_local_notifications kennt
  device_time_zone.dart           Gerätezeitzone (+ feste Variante für Tests)

presentation/
  notification_settings_screen.dart  /more/settings/notifications
  pre_permission_sheet.dart          das In-App-Sheet vor dem Systemdialog
  notification_host.dart             Lebenszyklus, Kanäle, Anwenden des Plans, Tap-Routing
```

### 1.0.1 Neue E-Mail (N4)

`mail.new` ist keine vorausgeplante Erinnerung und belegt keinen Platz im 60er-Planungsbudget.
Solange die App im Vordergrund ist, meldet IMAP IDLE eine mögliche Änderung. Der normale
Mail-Sync bestätigt anschließend mindestens eine bisher unbekannte UID; erst dann ruft der
`NotificationHost` `showNow(...)` auf. Der erste Inbox-Sync setzt nur die Ausgangsbasis.

Die Kategorie unterliegt demselben globalen Opt-in, ihrem eigenen Schalter und der
Betriebssystemberechtigung wie N1–N3. Titel und Text sind neutral und enthalten weder Absender noch
Betreff; der validierte Payload enthält nur die numerische IMAP-UID und öffnet den Posteingang.
Account-Wipe beziehungsweise Kontowechsel sind über die Mail-Session-Generation gegen verspätete
Ereignisse abgesichert. Bei pausierter oder geschlossener App ist keine Live-Zustellung zugesagt;
Start und Resume gleichen verpasste Nachrichten ab.

### 1.1 Vollständige Neuplanung, nie ein Delta

Jeder Lauf verwirft alle **vorgemerkten** Einträge (`cancelAllPending()`) und plant den gesamten
Sollzustand neu. Aktualisieren, Ersetzen und Stornieren haben deshalb **keinen eigenen Codepfad**:
Ein abgesagter, gelöschter oder verschobener Eintrag wird beim nächsten Lauf schlicht nicht mehr
beziehungsweise anders erzeugt.

**Bereits zugestellte Benachrichtigungen gehören nicht zum Sollzustand und bleiben unberührt.** Das
Gateway ruft dafür ausschließlich `cancelAllPendingNotifications()` des Plugins auf, nie dessen
`cancelAll()`: Letzteres entfernt in flutter_local_notifications 22.3.0 zusätzlich alles bereits
Angezeigte (Android `NotificationManager.cancelAll()`, iOS `removeAllDeliveredNotifications`). Weil
bei jeder Rückkehr in den Vordergrund neu geplant wird, verschwänden sonst ungelesene Hinweise —
Tagesübersicht, neue Mail, neue Note — genau in dem Moment aus der Mitteilungsleiste, in dem die App
geöffnet wird. Dasselbe gilt für das Abschalten: Es entfernt nur Vorgemerktes.

Läufe sind **serialisiert**. `cancelAllPending()` und das erneute Einplanen sind zusammen nicht
atomar; zwei überlappende Läufe würden einander die Einträge wegräumen. Der `NotificationScheduler`
hängt jeden Lauf an den vorherigen an.

Bewusst offen bleibt das kurze Fenster zwischen `cancelAllPending()` und dem letzten `schedule(...)`: Wird
der Prozess genau dort beendet, bleibt nichts vorgemerkt, bis die App das nächste Mal startet. Das
ist hinnehmbar, weil jeder App-Start neu plant — und es steht in der Gerätematrix (§ 4).

### 1.2 Wann neu geplant wird

Es gibt **keine Auslöserliste**, weil eine Liste die Stelle wäre, an der man einen Auslöser
vergisst.

- **App-Zustand** — jeder erfolgreiche Abruf, Merken/Entmerken, Favorit, Stundenplangruppe,
  bevorzugte Mensa, Kalenderauswahl, jede Einstellung, die Berechtigung: Diese Quellen liest
  `notificationCandidatesProvider` als Provider. Riverpod baut den Plan neu, sobald sich eine davon
  ändert, und `NotificationHost` überträgt ihn.
- **Kein App-Zustand** — Rückkehr in den Vordergrund, Zeitzonenwechsel, Tageswechsel bei laufender
  App, Sprachwechsel: Diese behandelt `NotificationHost` ausdrücklich.

### 1.2.1 Die Tagesübersicht (N2, LEVIORA-164)

Für jeden Tag der nächsten **14 Tage** entsteht höchstens **ein** Kandidat zur gewählten
Ortszeit (Standard **08:00 Uhr**). Die Uhrzeit lässt sich im Onboarding und später in den
Benachrichtigungseinstellungen ändern und wird lokal gespeichert.
Die Zahl ist die Länge des Speiseplans, den die API liefert; weiter zu planen hieße, Tage zu
nennen, über die noch nichts bekannt ist. Vierzehn von sechzig Budgetplätzen lassen außerdem
genug Raum für die Event-Erinnerungen, mit denen sie geteilt werden.

Quellen — allesamt die vorhandenen Provider der jeweiligen Features, keine zweite Datenhaltung und
kein zweiter Mapper:

| Inhalt              | Quelle                                                                                                                             |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Lehrveranstaltungen | `timetableWeekProvider` für Haupt-, Zusatzgruppen und Gruppen abonnierter Einzelmodule; Modulfilter lokal; ohne Hauptgruppe: keine |
| Relevante Events    | `publicCalendarMonthEntriesProvider` (aktivierte Kalender) + gemerkte Events                                                       |
| Moodle-Fristen      | der zwischengespeicherte Bestand, nur bei verbundenem Konto                                                                        |
| Mensa               | `canteenMenuProvider` der bevorzugten Mensa + `canteenFilterProvider` (Favoriten)                                                  |

Die Anzeigeschalter des Kalenders werden **nicht** gelesen; ein Test hält das fest (§ 3).

Regeln, die dabei gelten:

- **Ein leerer Tag erzeugt nichts.** Leer bedeutet: keine Lehrveranstaltung, kein Event, keine
  Moodle-Frist und kein Mensa-Speiseplan. Ein vorhandener Speiseplan ist nach P4 ein eigener Anteil
  der Tagesübersicht und begründet deshalb auch ohne weitere Quelle eine Meldung.
- **Eine abgesagte Lehrveranstaltung zählt nicht** und füllt keinen Tag.
- **Moodle bleibt aggregiert.** Der Tagesbefund hat kein Feld für einen Kurs- oder Aufgabentitel,
  der Text kann also keinen nennen. Ein Tag mit einer Frist wird zusätzlich als `neutral`
  markiert.
- **Höchstens vier Bestandteile**, jeder eine kurze Wendung: Lehrveranstaltungen (Anzahl plus
  Beginn der ersten), Events (ein Titel, ab zwei nur noch die Anzahl), Moodle (Anzahl), Mensa
  (Favorit oder Speiseplan). Das hält den Text bei zwei Zeilen.
- **Der Planungshorizont wandert mit dem Tag.** `notificationPlanningDayProvider` hält das
  aktuelle Datum; `NotificationHost` frischt es um Mitternacht und beim Zurückkehren auf.
- **Ohne Opt-in, ohne aktive Kategorie oder ohne Systemberechtigung wird gar nichts gelesen.** Der
  Planer würde ohnehin alles verwerfen — und ein Gerät, dessen Nutzerin nie Benachrichtigungen
  wollte, soll dafür auch keinen Abruf auslösen.

Ein Tap öffnet die Tagesansicht des Kalenders am Zieldatum; ist das Datum aus der Payload nicht
auflösbar, führt der Weg auf `/calendar` mit dezentem Hinweis.

**Einstiegspunkte C und D** (UX-Spezifikation § 2.2) bieten denselben globalen Opt-in an, den es
schon gibt — keine zweite Berechtigungslogik: nach der erstmaligen Wahl einer Stundenplangruppe
(aus dem Aufrufkontext heraus, nachdem das Sheet geschlossen ist) und nach einer erfolgreichen
Moodle-Verbindung (am Gate `MoodleScreen`, weil der Setup-Screen im selben Moment verschwindet).

### 1.3 Identität

| Art                 | Schlüssel                       | Payload                                                       |
| ------------------- | ------------------------------- | ------------------------------------------------------------- |
| `event.reminder`    | `n1:<CalendarEntry.id>`         | `v1\|event.reminder\|<CalendarEntry.id>`                      |
| `daily.summary`     | `n2:<YYYY-MM-DD>`               | `v1\|daily.summary\|<YYYY-MM-DD>`                             |
| `canteen.favourite` | `n3:<canteenSlug>:<YYYY-MM-DD>` | `v1\|canteen.favourite\|<slug>:<YYYY-MM-DD>[:<Gerichtsname>]` |

Schlüssel, Payload und die vom Betriebssystem verlangte Ganzzahl werden **alle drei** aus
Kategorie und Ziel abgeleitet und können deshalb nicht auseinanderlaufen. Der optionale
Gerichtsname von N3 ist die eine Ausnahme und ausdrücklich **nicht** Teil des Schlüssels: Wovon ein
Hinweis handelt, ist eine Mensa an einem Tag; welcher Favorit dort gerade passt, darf seine
Identität nicht verschieben. Er wandert allein in den Payload, damit ein Tap die richtige Karte
hervorheben kann, und wird beim Lesen von links geparst — ein Gerichtsname darf selbst einen
Doppelpunkt enthalten. Ein Name mit `|` verliert das Gerichtsziel, nicht den Hinweis. `CalendarEntry.id` wird
übernommen, nicht neu gebildet. Die Ganzzahl ist ein deterministischer 31-Bit-FNV-1a-Hash; eine
Kollision wäre folgenlos, weil ohnehin vollständig neu geplant wird.

**Kein Payload trägt eine Moodle-Kennung oder einen anderen personenbezogenen Bezeichner.** Nach
P5 gibt es keine Moodle- und keine Stundenplan-Einzelhinweise, und damit auch keine Kategorie, die
so etwas bräuchte. Ein Test hält das fest.

### 1.4 N1 — `event.reminder`, eine lokal konfigurierbare Erinnerung je Event

Umgesetzt in `application/event_reminder_candidates.dart` (LEVIORA-166). Die Kategorie besteht aus
drei Teilen, die getrennt prüfbar sind:

**Geltungsbereich** (`notificationEventEntriesProvider`). Zwei Quellen und nur diese: öffentliche
Kalendereinträge aus der **aktivierten** Auswahl und **gemerkte** Events. Der Bestand ist
ausdrücklich **nicht** `CalendarData` des Kalenderscreens — der wendet die Anzeigeschalter an, und
ein Anzeigeschalter darf eine Erinnerung nicht abschalten (ADR-0001 § 7.2). Insbesondere gilt der
Merkschalter des Kalenders (standardmäßig **aus**) hier nicht. Entdoppelt wird mit
`savedEventEntriesForCalendar`, also der wiederverwendbaren Regel des Events-Features — nicht mit
einer zweiten Fassung davon. Verwaiste (`isOrphaned`) und abgesagte Merkeinträge fallen heraus.

**Regel** (`eventReminderRequests`, reine Funktion). Der globale Vorlauf ist lokal zwischen
15 Minuten, 1 Stunde, 6 Stunden, 1 Tag (Standard), 2 Tagen und 1 Woche wählbar. Im Detail eines
öffentlichen oder gemerkten Events kann die Regel geerbt, überschrieben oder für genau dieses Event
abgeschaltet werden. Vorläufe sind **absolute Dauern**; das Zustellfenster aus § 7.4 wendet der
Planer an. Würde das Fenster einen kurzen Vorlauf hinter den Eventbeginn schieben, wird auf die
letzte zulässige 20:00-Grenze vor dem Event zurückgefallen. Stundenplan- und Moodle-Einträge
erzeugen hier **nie** einen Kandidaten (P5), ganztägige Einträge dagegen schon.

Dieselbe Regel gilt für die Moodle-Fristerinnerung (`moodle.deadline`): Der Auslöser beider
Kategorien nennt sein Ziel (`AbsoluteTrigger.before` = Eventbeginn beziehungsweise Frist), und der
Planer verschiebt über `DeliveryWindow.shiftIntoWindowBefore` **nie auf oder hinter** dieses Ziel.
Eine Abgabe um 23:59 Uhr mit 1 Stunde Vorlauf wird deshalb um 20:00 Uhr desselben Abends
erinnert, nicht um 07:00 Uhr am Folgetag nach Fristende.

**Text.** „Morgen: …" beziehungsweise „Heute: …", wenn der Hinweis am Eventtag selbst zugestellt
wird; liegt das Event zwei oder mehr Kalendertage nach der Zustellung (Vorlauf „2 Tage" oder
„1 Woche"), nennt der Text Wochentag und Datum („Mittwoch, 22. Juli: …", lokalisiert über `intl`).
Gezählt werden **Kalendertage** zwischen Zustellung und Eventbeginn, nicht 24-Stunden-Blöcke — über
eine Zeitumstellung hinweg bleibt „morgen" also morgen. Beide Seiten — Text und Zeitpunkt — fragen
dieselbe `DeliveryWindow`, können also nicht auseinanderlaufen.

**Tap.** Der Payload trägt die `CalendarEntry.id` und sonst nichts. `NotificationTapRouter` löst
sie über den zusammengeführten Bestand auf, fokussiert den Tag **des Eintrags** (nicht einen Tag
aus dem Payload, den es dort nicht gibt) und öffnet `showCalendarEntrySheet`. Löst sie nicht auf,
bleibt es bei `/calendar` plus dezentem Hinweis.

**Eine bewusste Abweichung von § 7.2, aktenkundig:** Der Bestand beobachtet
`publicCalendarMonthEntriesProvider` für den laufenden und den folgenden Monat. Gewartet wird nie —
gelesen wird `.value`, ein noch nicht geladener Monat trägt schlicht nichts bei und der Plan wird
neu gebaut, sobald er eintrifft. Das Beobachten eines noch nicht geholten Monats **stößt** aber
einen Abruf an, und § 7.2 sagt „löst nie einen Netzabruf aus". Der laufende Monat wird vom
Kalender ohnehin geholt; der Folgemonat ist der Unterschied. Wer die Regel wörtlich will, braucht
einen reinen Cache-Lesepfad in `CachedEndpoint` — der wäre allerdings vom Abrufzyklus entkoppelt
und verlöre den Auslöser „nach dem nächsten erfolgreichen Abruf neu planen".

### 1.5 Diagnose

`NotificationPlanDiagnostics.toLogLine()` und `NotificationSyncResult.toLogLine()` schreiben in
Debug-Builds **ausschließlich Zähler**: wie viele Kandidaten, wie viele geplant, wie viele je
Kategorie, wie viele je Verwerfungsgrund. Kein Titel, kein Text, kein Schlüssel, kein Datum, kein
Gerichtsname. Ein ausgeschöpftes Budget ist so ein Zähler und keine stille Kürzung.

## 2. Plattformkonfiguration

### 2.1 Android

| Punkt                    | Wert                                                                                                                                                    |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Berechtigung             | `POST_NOTIFICATIONS` bringt das Plugin selbst mit (ab Android 13). Darunter gilt sie als erteilt                                                        |
| `RECEIVE_BOOT_COMPLETED` | im App-Manifest — ohne sie ist nach einem Neustart **alles** Vorgemerkte verloren                                                                       |
| `SCHEDULE_EXACT_ALARM`   | **nicht** deklariert, und `USE_EXACT_ALARM` ebenso wenig                                                                                                |
| Terminierung             | `zonedSchedule(..., androidScheduleMode: inexactAllowWhileIdle)`                                                                                        |
| Receiver                 | `ScheduledNotificationReceiver` und `ScheduledNotificationBootReceiver`, beide `exported="false"`                                                       |
| Desugaring               | `isCoreLibraryDesugaringEnabled = true` + `desugar_jdk_libs:2.1.4` — Pflicht ab Plugin-Version 10, sonst schlägt bereits der Build fehl                 |
| Kanäle                   | vier, je einer für N1/N2/N3/N4, angelegt bevor etwas geplant oder sofort angezeigt wird. Ein Kanal ist **kein** Gruppenschlüssel und berührt P8 nicht   |
| Kanalnamen               | aus den ARB-Dateien; ein Sprachwechsel registriert die Kanäle unter derselben Id neu, wodurch Android Name und Beschreibung übernimmt                   |
| Kleines Symbol           | `@drawable/ic_notification`, einfarbig weiß und voll deckend — ein mehrfarbiges Icon stellt Android als graues Quadrat dar                              |
| Sperrbildschirm          | `visibility: public` für öffentliche Inhalte, `private` für neutrale (P10). Beides greift nur unter Nutzereinstellungen, die die App nicht kontrolliert |

Der Preis der inexakten Terminierung ist einige Minuten Streuung. Das Fenster aus P7 ist eine
**Planungsregel**, keine Zustellzusage auf die Minute: Ein auf 19:5x geplanter Hinweis kann nach
20:00 Uhr erscheinen. Eine minutengenaue Zustellung wäre nur mit `SCHEDULE_EXACT_ALARM` zusagbar,
und dieser Preis steht in keinem Verhältnis.

### 2.2 iOS

| Punkt                | Wert                                                                                                                                                     |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Capabilities         | **keine.** Kein Push-Entitlement, kein `aps-environment`, keine Background Modes                                                                         |
| `AppDelegate.swift`  | setzt `UNUserNotificationCenter.current().delegate` und den `setPluginRegistrantCallback` in `didInitializeImplicitFlutterEngine` (UIScene-Lebenszyklus) |
| Berechtigung         | wird **nie** beim Start angefragt: `DarwinInitializationSettings` fordert Alert, Badge und Sound ausdrücklich nicht an                                   |
| Systemdialog         | erscheint genau einmal pro Installation. Danach führt der Weg nur noch über die Systemeinstellungen                                                      |
| Vorschau-Platzhalter | die eingesetzte Plugin-Version bietet **kein** `hiddenPreviewsBodyPlaceholder`. P10 wird deshalb im **Text** umgesetzt (§ 2.3)                           |

### 2.3 Sperrbildschirm

Die einzige plattformübergreifend zusagbare Umsetzung von P10 ist **Textdisziplin**: Der Text ist
bereits ohne den sensiblen Teil geschrieben. Android-Sichtbarkeit und iOS-Vorschauen sind eine
zweite Schicht, nicht die erste — beide gehorchen einer Einstellung, die die App nicht
kontrolliert. Konkret: Die Tagesübersicht nennt Moodle nur aggregiert, ohne Kurs- und
Aufgabentitel. Fremdtexte (Gerichtsname, Fachtitel, Eventtitel) werden nicht übersetzt.

## 3. Automatisierte Tests

`apps/mobile/test/features/notifications/`:

| Datei                                        | Deckt ab                                                                                                                                                                                                                  |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `notification_planner_test.dart`             | 24-Stunden-Regel, beide Verschiebungsrichtungen, einschließende Grenzwerte 07:00/20:00, Zeitzonen, Sommerzeit, Vergangenheitsfilter, doppelte Schlüssel, Budget mit deterministischer Sortierung, Opt-in und Berechtigung |
| `notification_payload_test.dart`             | Round-Trip, unbekannte Version, entfallene Kategorie, jede Fehlform, keine personenbezogene Kennung                                                                                                                       |
| `notification_scheduler_test.dart`           | `cancelAllPending` vor dem Einplanen, zugestellte bleiben erhalten, keine Duplikate bei doppeltem Lauf, zwei gleichzeitige Läufe → genau ein Endzustand, Teilfehler                                                       |
| `notification_settings_test.dart`            | Standardzustand, alle Kategorien an nach dem Opt-in, Persistenz über den Neustart, defekte und unbekannte gespeicherte Werte                                                                                              |
| `notification_tap_router_test.dart`          | Ziel je Kategorie, optionales Gerichtsziel (auch mit Doppelpunkt im Namen), Fallback mit Hinweis, alte oder kaputte Payloads navigieren nirgendwohin                                                                      |
| `canteen_favourite_candidates_test.dart`     | N3 rein: Abgleich nach Gerichtsnamen, leere Favoriten, leerer und abgelaufener Cache, doppelte Namen, mehrere Treffer als ein Hinweis, Preis, Kürzung langer Namen, DE/EN, Schlüssel gegen Payload                        |
| `canteen_favourite_plan_test.dart`           | N3 über die Provider: Favorit gesetzt/entfernt, Menüwechsel, andere Mensa, Kategorie abgeschaltet, ohne Opt-in — jedes Mal als vollständiger neuer Sollzustand                                                            |
| `notification_settings_screen_test.dart`     | Berechtigungsbanner, deaktivierte Kategorien, Abschalten trotz Sperre, stummgeschalteter Kanal, Persistenz eines Schalters                                                                                                |
| `notification_scope_test.dart`               | Geltungsbereich (keine Kalender-Anzeigeschalter), kein Push-/Netz-/Hintergrundcode, ein einziger Plugin-Importeur, kein Gruppenschlüssel, Manifest- und Gradle-Zusicherungen                                              |
| `daily_summary_test.dart`                    | leerer, normaler und überfüllter Tag, abgesagte Lehrveranstaltung, Speiseplan ohne Favorit, mehrtägige Einträge, Horizont, Sommerzeit im Tagesraster                                                                      |
| `daily_summary_content_test.dart`            | DE-/EN-Text Wort für Wort, Moodle ohne Kurs- und Aufgabentitel, Sichtbarkeitsstufe, Kürzungsregeln, Ziel und Auslöser                                                                                                     |
| `daily_summary_candidates_test.dart`         | die vier Quellen einzeln, Dedup gemerkter Events, Gating über Opt-in/Kategorie/Berechtigung, ein Kandidat je nicht leerem Tag, Sprachwechsel, 08:00 Ortszeit über die Sommerzeitumstellung und in einer anderen Zone      |
| `notification_opt_in_entry_points_test.dart` | Einstiegspunkte C (Stundenplangruppe) und D (Moodle-Verbindung), einschließlich „schon abgelehnt" und fehlgeschlagener Verbindung                                                                                         |

## 4. Manuelle Gerätematrix

Diese Punkte sind auf **echten** Geräten zu prüfen; im Simulator ist Berechtigungs- und
Zustellverhalten nicht belastbar. Mit der Tagesübersicht (LEVIORA-164) gibt es echte Kandidaten;
für N1 und N3 (LEVIORA-165/166) bleibt die Matrix bis dahin auf Testkandidaten angewiesen.

**Für diese Änderung wurde noch auf keinem Gerät geprüft.** Automatisiert abgedeckt ist alles, was
ohne Gerät prüfbar ist (§ 3); die Matrix unten steht weiterhin offen.

| #   | Fall                                                             | Erwartet                                                                                               |
| --- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| 1   | Erster Start, Android 13+ und iOS                                | **kein** Systemdialog, keine Benachrichtigung vorgemerkt                                               |
| 2   | Opt-in über einen kontextuellen Einstiegspunkt                   | erst das In-App-Sheet, dann der Systemdialog; danach sind alle vier Kategorien an                      |
| 3   | „Nicht jetzt" im Sheet                                           | kein Systemdialog, Zustand bleibt „nie gefragt", kein erneutes Fragen am selben Einstiegspunkt         |
| 4   | Berechtigung im Dialog abgelehnt                                 | Hauptschalter aus, Banner mit Weg in die Systemeinstellungen, **kein** erneuter Dialog                 |
| 5   | Berechtigung nachträglich in den Systemeinstellungen entzogen    | beim Zurückkehren erkannt: Banner erscheint, vorgemerkte Einträge werden entfernt                      |
| 6   | Berechtigung dort wieder erteilt                                 | beim Zurückkehren erkannt: Banner verschwindet, es wird sofort neu geplant                             |
| 7   | Android unter 13                                                 | keine Laufzeitberechtigung, kein Banner, Zustellung funktioniert                                       |
| 8   | Android-Kanal in den Systemeinstellungen stummgeschaltet         | die betroffene Kategorie zeigt den Hinweis, die anderen bleiben unberührt                              |
| 9   | App vollständig beendet                                          | geplante Benachrichtigungen erscheinen trotzdem                                                        |
| 10  | Gerät neu gestartet                                              | geplante Benachrichtigungen erscheinen weiterhin (Boot-Receiver)                                       |
| 11  | Flugmodus / kein Netz                                            | Zustellung unverändert — es ist nichts Netzabhängiges beteiligt                                        |
| 12  | Zeitzonenwechsel bei laufender App                               | beim Zurückkehren neu geplant; feste Uhrzeiten liegen auf der neuen Ortszeit                           |
| 13  | Sommerzeitumstellung                                             | 08:00 und 11:00 bleiben 08:00 und 11:00; die 24-Stunden-Erinnerung verschiebt sich um eine Stunde      |
| 14  | Tageswechsel bei geöffneter App                                  | um Mitternacht wird neu geplant, nichts Vergangenes bleibt stehen                                      |
| 15  | Sprachwechsel                                                    | Kanalnamen und Texte folgen der neuen Sprache                                                          |
| 16  | Erzwungenes Beenden während einer Neuplanung                     | höchstens vorübergehend nichts vorgemerkt; der nächste App-Start stellt den vollen Stand her           |
| 17  | Gerät mit aggressiver Akku-Optimierung (Xiaomi, Huawei, Samsung) | dokumentieren, was tatsächlich zugestellt wird — hier ist kein Ergebnis zusagbar                       |
| 18  | Streuung am Rand des Zustellfensters                             | die Abweichung eines auf 19:55 geplanten Hinweises **messen** und hier eintragen                       |
| 19  | Tatsächliche iOS-Obergrenze vorgemerkter Einträge                | gegen die eingesetzte Plattformversion **messen** und mit `kMaxScheduledNotifications` (60) abgleichen |
| 20  | Tap auf eine Benachrichtigung bei kaltem Start                   | die App öffnet direkt am Ziel, ohne Zwischenschritt und ohne Absturz                                   |
| 21  | Tap auf eine Benachrichtigung zu einem gelöschten Eintrag        | Fallbackziel plus dezenter Hinweis, kein leerer Bildschirm                                             |

## 5. Grenzen, die bleiben

1. **Die App muss gelegentlich geöffnet werden.** Neu geplant wird nur, wenn die App läuft.
2. **Änderungen nach der Planung schlagen erst mit dem nächsten Abruf durch.** Keine Echtzeitgarantie.
3. **Eine bereits zugestellte Benachrichtigung ist nicht zurückholbar.**
4. **Verpasste Zeitpunkte werden nicht nachgeholt.** Eine Erinnerung an gestern ist Lärm.
5. **Inexakte Terminierung streut** um einige Minuten (Android).
6. **Herstellerseitige Akku-Optimierung** kann Zustellungen unterdrücken. Nicht vollständig lösbar.
7. **Verweigerte Berechtigung ist endgültig genug** — der Weg führt danach nur über die Systemeinstellungen.
8. **Der Sperrbildschirmschutz ist Textdisziplin**, keine Plattformzusage.
9. **N3 reicht so weit wie der lokale Speiseplan** — 14 Tage, und nur solange der Cache nicht älter
   als `CanteenFavouriteCandidates.maxMenuAge` (7 Tage) ist. Danach entfallen die Hinweise, statt
   ein Gericht zu versprechen, das die App seit einer Woche nicht geprüft hat.
10. **Der Abgleich läuft über den Gerichtsnamen**, nicht über `Meal.id` (ADR-0001 § 4.1, Befund 5).
    Ein auf Deutsch favorisiertes Gericht passt deshalb nicht auf den englischen Speiseplan;
    Gerichtsnamen werden nicht maschinell übersetzt (AGENTS.md § 6).
