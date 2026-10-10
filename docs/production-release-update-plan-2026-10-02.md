# Production-Updateplan nach Cross-Validation

Stand: 3. Oktober 2026

Scope: Fehlerkorrekturen und Release-Härtung; keine Phase-14-Erweiterungen

Dieser Plan führt die rekursive Codex-Analyse und die unabhängig gemeldeten
Claude-Befunde zusammen. Matrix, Anny und sonstige neue Produktfunktionen
bleiben bis nach diesem Production-Cut zurückgestellt.

## Bestätigte Entscheidungen

- Bereits verknüpfte Dienste sollen bei einem Wechsel der zentralen
  Hochschulzugangsdaten automatisch neu verbunden werden. Der Wechsel muss
  dennoch fail-closed, cache-isoliert und mit einem ehrlichen Teilergebnis
  umgesetzt werden, da externe Dienste nicht gemeinsam transaktional sind.
  **Geändert am 2026-10-11:** Gilt nur noch für eine reine Passwortänderung
  derselben Kennung. Bei einem echten Kontowechsel wird nur der prüfende Dienst
  verbunden; jeder weitere Dienst erst nach Zustimmung über `+`, HSA-GPT über
  seinen eigenen Zustimmungsbildschirm (siehe `AGENTS.md` §2).
- Die organisatorischen und rechtlichen Freigaben für WebUntis und die
  öffentlichen Google-Kalender liegen laut Projektverantwortlichem vor. Die
  Release-Dokumentation und versionierten Deploymentvorlagen müssen deshalb
  mit diesem freigegebenen Betriebszustand abgeglichen werden.
- Die nicht verbundene Debug-APK wurde sehr wahrscheinlich ohne
  `API_BASE_URL` gebaut und verwendete dadurch `localhost` auf dem Mobilgerät.

## Umsetzungsstatus

| Phase | Status                                 | Nachweis                                                                                                                                                                                                                                                                                                                                       |
| ----- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| U0    | offen                                  | Betriebliche Werte und Dokumentation werden in dieser Phase abgeglichen.                                                                                                                                                                                                                                                                       |
| U1    | umgesetzt, technische Validierung grün | 13 Guard-Tests; Backend-Lint und Typecheck; abschließend 54 Backend-Suites mit 701 Tests gegen einen kurzlebigen PostgreSQL-16-Container unter dem exakten Repository-Node-Pin; Container anschließend entfernt.                                                                                                                               |
| U2    | umgesetzt, technische Validierung grün | Alle manuellen Setup- und Entfernen-Pfade laufen über den gemeinsamen Operation-Gate; deterministische Races für Mail, Moodle und Noten sowie Retain-Rollback sind abgedeckt. 32 gezielte Tests, vollständiger Mobile-Lauf mit 2550 Tests und `flutter analyze` sind mit Flutter 3.44.7 grün.                                                  |
| U3    | umgesetzt, technische Validierung grün | Kontowechsel invalidiert Sessions und sensible Caches vor Sichtbarkeit, führt zuvor verbundene Dienste kontrolliert nach und meldet Teilergebnisse dienstbezogen. Navigation verbindet keinen Dienst mehr implizit. Vollständiger Mobile-Lauf mit 2559 Tests und `flutter analyze` sind mit Flutter 3.44.7 grün.                               |
| U4    | umgesetzt, technische Validierung grün | Eingebettete und eigenständige Connect-Vorgänge sperren alle Navigations- und Eingabewege konsistent, kündigen ihren Status als Live-Region an und ignorieren verspätete UI-Ergebnisse. Einwilligung und API-Konfigurationshinweis sind gehärtet. Vollständiger Mobile-Lauf mit 2569 Tests und `flutter analyze` sind mit Flutter 3.44.7 grün. |
| U5    | umgesetzt, technische Validierung grün | Ausgeblendete Stundenplankurse fehlen nun auch in der Tageszusammenfassung; Mensaguthaben zeigt keine negative Null; ICS-Folgetage und Zeilenenden sind DST- beziehungsweise RFC-sicher. Vollständiger Mobile-Lauf mit 2573 Tests und `flutter analyze` sind mit Flutter 3.44.7 grün.                                                          |
| U6    | umgesetzt, technische Validierung grün | Paginierter und durchsuchbarer Gruppenkatalog; bedarfsgesteuerter Mobile-Abruf; 54 Backend-Suites mit 701 Tests und vollständiger Mobile-Lauf mit 2583 Tests grün.                                                                                                                                                                             |
| U7    | umgesetzt, technische Validierung grün | API-Origin- und Build-Gates, vereinheitlichter Node-Pin, gehärtete Abhängigkeiten und CMS-Grenztests; vollständige Mobile-, Backend-, CMS- und Map-Gates grün. Verbleibende Auditmeldungen sind unten transparent bewertet.                                                                                                                    |
| U8    | offen                                  | Reale signierte Builds, Geräte-, Portal-, NFC-, WCAG- und Produktions-Smoke-Tests bleiben menschliche Release-Abnahmen.                                                                                                                                                                                                                        |

## U0 — Betriebs- und Release-Gates

| Problem                                                                                                                                                           | Lösung                                                                                                                                       | Betroffene Dateien/Systeme                                                                                                                |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Dokumentation und Deploymentvorlagen behandeln WebUntis und öffentliche Kalender teilweise weiterhin als ungeklärt, während beide Freigaben nun bestätigt wurden. | Freigabestatus, verantwortete Aktivierung und Rückfallverfahren konsistent dokumentieren; reale Produktionswerte erneut prüfen.              | Produktive Deployment-Umgebung; `infrastructure/vps/*.example`; `docs/data-sources.md`; `docs/public-calendars.md`; `docs/product/mvp.md` |
| Noch nicht hardwarevalidierte oder nachweislich defekte Funktionen könnten in den Release gelangen.                                                               | HISinOne und NFC als ausdrückliche Release-Gates behandeln. Bei nicht bestandener Abnahme verständlich deaktivieren statt defekt ausliefern. | Mobile Feature-Gates; Release-Checkliste; Produktdokumentation                                                                            |

## U1 — Destruktive Tests absichern

| Problem                                                                                                                                                                    | Lösung                                                                                                                                                                                                                             | Betroffene Dateien                                                                                           |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Backend-Integrationstests verwenden `DATABASE_URL` und führen `TRUNCATE` aus. Eine normale Entwicklungs- oder falsch konfigurierte Datenbank kann dadurch gelöscht werden. | Ausschließlich `TEST_DATABASE_URL` akzeptieren; zusätzlich Testmodus und einen eindeutig als Campus-Testdatenbank markierten Datenbanknamen verlangen. Unsichere URLs geschlossen und ohne Ausgabe von URL oder Passwort abweisen. | `apps/backend/test/helpers/database.ts`; alle `apps/backend/test/*.integration.spec.ts`; Backend-Testskripte |
| Mehrere Integrationstests führen eigene, verteilte `TRUNCATE`-Anweisungen aus.                                                                                             | Alle destruktiven Resets über einen zentral gegateten Testhelfer ausführen.                                                                                                                                                        | Backend-Integrationstests und Testhelfer                                                                     |
| Die lokale Anleitung führt ohne sichere Trennung zum normalen Entwicklungsdatenbestand.                                                                                    | Einen isolierten temporären Testdatenbank-Workflow einschließlich Entfernung nach dem Lauf dokumentieren; CI verwendet ausschließlich seinen kurzlebigen PostgreSQL-Service.                                                       | `README.md`; `apps/backend/README.md`; `docs/local-development.md`; `.github/workflows/ci.yml`               |

Abnahme: Normale Entwicklungs- und Produktionsdatenbanknamen werden abgewiesen;
Fehlermeldungen enthalten keine Verbindungsdaten; Integrationstests laufen nur
gegen eine isolierte Testdatenbank.

## U2 — Credential-Gate und vollständiges Löschen

| Problem                                                                                                                                                    | Lösung                                                                                                                                                                      | Betroffene Dateien                                                                                                   |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Mail-, Moodle- und Noten-Setup umgehen mit den Wiederverwendungs-Checkboxen den `UniversityServiceOperationGate`.                                          | Den bisherigen direkten Login plus `retainVerified` durch genau einen vollständig gegateten Connect-Vorgang mit optionalem zentralen Retain ersetzen. Kein doppelter Login. | `mail_setup_screen.dart`; `moodle_setup_screen.dart`; `grade_setup_screen.dart`; `university_service_connector.dart` |
| Ein verspäteter Login kann die zentrale Identität nach gemeldeter vollständiger Löschung wiederherstellen.                                                 | Alle schreibenden Connect-, Retain-, Disconnect- und Delete-Vorgänge über denselben Gate führen und deterministische Race-Tests für alle drei Dienste ergänzen.             | University-Account-, Mail-, Moodle- und Noten-Controller samt Tests                                                  |
| „Vollständig löschen“ löscht nur Dienste, die der aktuelle Provider als verbunden erkennt. Loading-, Error- und Store-Lesefehler können Secrets übersehen. | Immer die kanonische Löschroutine aller drei Dienste ausführen, unabhängig vom UI-/Provider-Zustand; zentrale Identität zuletzt löschen.                                    | `sign_out_everywhere_controller.dart`; Dienstcontroller und Tests                                                    |
| Dienstlogin kann gespeichert sein, obwohl das zentrale Retain fehlschlägt.                                                                                 | Connector mit sicherer Kompensation versehen und die gerade erzeugte Dienstverbindung bei Retain-Fehler wieder entfernen.                                                   | `university_service_connector.dart`; Adapter und Tests                                                               |

Abnahme: Sämtliche manuellen Setup- und Entfernen-Pfade verwenden den gemeinsamen
Operation-Gate. Die vollständige Löschung ruft unabhängig vom beobachtbaren
Provider-Zustand alle drei kanonischen Wiper auf und löscht die zentrale Identität
erst danach. Ein fehlgeschlagenes zentrales Retain kompensiert die bereits erstellte
Dienstverbindung; ein fehlgeschlagener Rollback wird als eigener, verständlicher
Fehler gemeldet. Deterministische Tests decken die drei Setup-/Delete-Races sowie
beide Rollback-Ausgänge ab.

## U3 — Account-Isolation und echtes Plus/Minus

| Problem                                                                                       | Lösung                                                                                                                                                                                                                     | Betroffene Dateien                                                                                   |
| --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Ein Kontowechsel kann alte Mail-, Moodle- oder Notendaten unter der neuen Identität anzeigen. | Session-Generation vor Sichtbarkeit des neuen Kontos wechseln; sensible Caches löschen oder strikt accountbezogen verschlüsselt partitionieren.                                                                            | Account-Controller, verschlüsselte Caches, lokale Datenkoordinatoren und Provider aller drei Dienste |
| Das Öffnen eines abgemeldeten Dienstes meldet ihn automatisch wieder an.                      | Navigation darf keinen Connect auslösen. Nur die bewusste Plus-Aktion verbindet einen getrennten Dienst.                                                                                                                   | `university_identity_auto_connect.dart`; Dienst-Screens und Tests                                    |
| Neue zentrale Credentials können von bereits verbundenen Diensten abweichen.                  | Bereits verknüpfte Dienste kontrolliert mit der neuen Identität neu verbinden. Vorher alte Sessions und Caches invalidieren; Teilerfolge dienstweise melden und keinen alten Zustand als erfolgreich verbunden darstellen. | University-Service-Connector, zentrale Identität und alle Dienstcontroller                           |

Status: umgesetzt und technisch validiert. Mail, Moodle und Noten löschen bei
einem tatsächlichen Accountwechsel die vorherigen sensiblen Cache-Daten vor der
Veröffentlichung des neuen Kontos. Fehler nach Beginn einer lokalen Mutation
lassen das alte Konto nicht als erfolgreich verbunden erscheinen. Das bloße
Öffnen eines getrennten Dienstes löst keinen Login mehr aus. Beim Ändern des
zentralen Hochschulzugangs wird zuerst ein ausgewählter Dienst geprüft; danach
werden die übrigen Dienstgrenzen bereinigt und zuvor verbundene Dienste einzeln
neu verbunden. Fehlgeschlagene Neuverbindungen bleiben getrennt und werden in
der zugehörigen Dienstzeile gemeldet. Bereinigungs- und Keystore-Fehler besitzen
getestete Rollback-Pfade einschließlich Wiederherstellung des vorherigen
zentralen Secrets. `flutter analyze` und der vollständige Mobile-Testlauf mit
2559 Tests sind mit Flutter 3.44.7 grün.

## U4 — Onboarding, Einwilligung und WCAG

| Problem                                                                                     | Lösung                                                                                                                                      | Betroffene Dateien                                                          |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Während eines eingebetteten Connect-Vorgangs bleiben Zurück, Überspringen und Weiter aktiv. | Gemeinsamen Busy-/Cancellation-Zustand verwenden; Navigation sperren oder Vorgang kontrolliert abbrechen; verspätete Ergebnisse ignorieren. | `onboarding_screen.dart`; `onboarding_university_steps.dart`; Setup-Screens |
| Der Wiederverwendungstext nennt die Speicherung im sicheren Gerätespeicher nicht.           | Speicherung und spätere dienstbezogene Verwendung in Deutsch und Englisch ausdrücklich benennen.                                            | `app_de.arb`; `app_en.arb`; Lokalisierungs- und Widgettests                 |
| Lade- und Konfigurationszustände sind nicht überall ausreichend zugänglich.                 | Live-Regionen, Fokus, Touchziele, große Schrift und sichere Displaybereiche prüfen und absichern.                                           | Onboarding; Setup-Screens; `api_configuration_notice.dart`; Widgettests     |

Status: umgesetzt und technisch validiert. Der Busy-Zustand des eingebetteten
Onboarding-Connects wird an den übergeordneten Ablauf weitergegeben; Zurück,
Überspringen, Weiter, „Alles überspringen“ und System-Zurück sind bis zum Ende
des Vorgangs gesperrt. Dieselbe Sperre gilt für Mail-, Moodle-, Noten- und
zentralen Hochschulzugang-Setup einschließlich Passwortaktionen und
Header-Navigation. Beim Start wird der Eingabefokus beendet; Lade-,
Fehler- und API-Konfigurationszustände sind als Live-Regionen ausgezeichnet.
Der API-Hinweis berücksichtigt Safe Areas und vermeidet zusammen mit der
App-Shell doppelte obere Insets; Großschrift- und Mindest-Touchzielverhalten
bleiben über die bestehenden Design-Tokens abgesichert. Der zweisprachige
Wiederverwendungstext nennt nun ausdrücklich sichere Gerätespeicherung und
spätere dienstbezogene Nutzung. Deterministische Widgettests halten die
Netzwerkantworten für alle Connect-Pfade an und prüfen die gesperrten Zustände.
`flutter analyze` und der vollständige Mobile-Testlauf mit 2569 Tests sind mit
Flutter 3.44.7 grün.

## U5 — Isolierte Logikfehler

| Problem                                                                                                                          | Lösung                                                                                               | Betroffene Dateien                                 |
| -------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| Ausgeblendete Stundenplanveranstaltungen erscheinen in der Tageszusammenfassung.                                                 | Den bestehenden Lesson-Info-Filter auch beim Erzeugen der täglichen Benachrichtigungsdaten anwenden. | `daily_summary_providers.dart`; Notification-Tests |
| Werte von −1 bis −4 Milli-Euro erscheinen gerundet als `-0.00`.                                                                  | Bei null absoluten Cent kein negatives Vorzeichen ausgeben.                                          | `canteen_balance_apdu.dart`; APDU-Tests            |
| Der ganztägige ICS-Fallback verwendet 24-Stunden-Arithmetik und kann bei der Herbst-Zeitumstellung ein ungültiges Ende erzeugen. | Ausschließlich Kalenderdatumsarithmetik für den Folgetag verwenden.                                  | `calendar_ics_export.dart`; ICS-Tests              |
| Ein alleinstehendes Carriage Return bleibt in ICS-TEXT unnormalisiert.                                                           | CRLF sowie verbleibendes CR und LF normgerecht escapen.                                              | `calendar_ics_export.dart`; ICS-Tests              |

Status: umgesetzt und technisch validiert. Die Tageszusammenfassung
verwendet nun denselben gruppenspezifischen Lesson-Info- und Kursfilter wie
Stundenplan, Kalender und Export. Auf null Cent gerundete negative
Milli-Euro-Werte verlieren ausschließlich das irreführende Minuszeichen. Der
ganztägige ICS-Fallback bildet den Folgetag per Kalenderdatum und ist durch
einen deterministischen Test für die Berliner Herbst-Zeitumstellung abgesichert;
CRLF, alleinstehendes CR und LF werden einheitlich als ICS-TEXT-Zeilenumbruch
geschrieben. `flutter analyze` und der vollständige Mobile-Testlauf mit 2573
Tests sind mit Flutter 3.44.7 grün.

## U6 — Stundenplankatalog vollständig und effizient machen

| Problem                                                                                   | Lösung                                                                                                                                                | Betroffene Dateien                                         |
| ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Das Backend liefert durch `take: 500` nicht alle derzeit 503 Gruppen.                     | Begrenzte, validierte Pagination und serverseitige Suche einführen; keine neue feste Gesamtkappung.                                                   | Backend-Timetable-Service, Controller, Typen und Tests     |
| Die App sucht ausschließlich lokal in der abgeschnittenen Liste.                          | Picker auf paginierte Suche umstellen; Auswahl und benötigte Metadaten offline erhalten.                                                              | Timetable-Repository, Provider, Picker, Cache und Tests    |
| Der komplette Katalog wird auch ohne Auswahl beim Kaltstart und danach stündlich geladen. | Katalog nur beim Picker, Onboarding oder Auflösen einer gespeicherten Auswahl laden.                                                                  | App-Sync-Host; Timetable-Provider; Settings und Onboarding |
| Mehrere Gruppen haben denselben sichtbaren Namen.                                         | Echte Dubletten nach Datenprüfung konsolidieren; verschiedene Gruppen mit bereits öffentlichen Metadaten unterscheiden. Keine WebUntis-ID ausliefern. | Timetable-Synchronisation, DTO-Mapping und Picker          |

Status: umgesetzt und technisch validiert. Der Gruppenkatalog ist ohne feste
Gesamtkappung paginiert und über Kurzname, Langname sowie Bereich serverseitig
durchsuchbar. Die App lädt ihn ausschließlich im Picker; Kaltstart und
stündlicher Refresh verwenden den kleinen Status-Endpunkt, lösen nur eine
gespeicherte Campus-UUID auf und laden anschließend deren aktuelle Woche. Eine
im Picker gewählte Gruppe wird unabhängig vom Katalog offline gespeichert.
Nachweisliche Aliasse mit identischem öffentlichen Namen und identischem
Stundenplan werden konsolidiert; gleich benannte Gruppen mit abweichenden
Plänen bleiben anhand ihrer öffentlichen Metadaten unterscheidbar. Externe
WebUntis-IDs werden weder ausgeliefert noch angezeigt. Die aktualisierten
Fake-HTTP-Verträge decken Status, UUID-Auflösung, serverseitige Suche und den
300-ms-Debounce ab. `flutter analyze`, der vollständige Mobile-Testlauf mit
2583 Tests sowie alle 54 Backend-Suites mit 701 Tests sind grün; die
Timetable-Integrationstests wurden zusätzlich gegen eine isolierte temporäre
PostgreSQL-Datenbank ausgeführt.

## U7 — Build-, Abhängigkeits- und Repository-Härtung

| Problem                                                                                                                | Lösung                                                                                                                              | Betroffene Dateien                                                      |
| ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Eine Debug-APK ohne `API_BASE_URL` verwendet das Localhost des Mobilgeräts; der Hinweis ist in Debug verborgen.        | Fehlkonfiguration auch in Debug sichtbar machen und distributable Builds ohne reale API-Origin vor dem Build abbrechen.             | `api_config.dart`; `api_configuration_notice.dart`; Buildskripte und CI |
| Die URL-Prüfung akzeptiert HTTPS-Werte mit Pfad, Query oder Fragment.                                                  | Eine exakte Origin verlangen; Loopback nur für ausdrücklich lokale Entwicklung erlauben.                                            | API-Konfiguration und Tests                                             |
| Abhängigkeitsprüfung meldet verbleibende Produktionsadvisories.                                                        | Direkte und transitive Abhängigkeiten einzeln aktualisieren und betroffene Builds und Tests erneut ausführen.                       | Workspace-Manifeste und `pnpm-lock.yaml`                                |
| Toolchain, Formatierung, Dokumentationsstand und große Arbeitsbaumänderungen erschweren eine reproduzierbare Freigabe. | Repository-Pin und CI vereinheitlichen; Dokumente formatieren und aktualisieren; Änderungen in nachvollziehbare Einheiten zerlegen. | Root-Konfiguration; CI; README; Audit- und Produktdokumentation         |
| Teile der CMS-Konfiguration wurden im parallelen Audit nicht vollständig gesichtet.                                    | CMS-Plugins, Admin-Konfiguration und API-Controller gezielt gegen Auth-, Public-Role- und DTO-Grenzen prüfen.                       | `apps/cms/config`; `apps/cms/src/api`                                   |

Status: umgesetzt und technisch validiert. Die Mobile-App zeigt eine fehlende
oder ungültige `API_BASE_URL` nun auch in Debug-Builds verständlich an. Release-
und Profile-Builds für Android und iOS verwenden denselben Vorabprüfer und
brechen ohne eine exakte HTTPS-Origin bereits vor der eigentlichen
Kompilierung ab. HTTP-Loopback ist nur mit dem ausdrücklichen lokalen
`ALLOW_LOCAL_API`-Schalter zulässig. Der Android-Negativtest ohne Origin schlug
wie vorgesehen fehl; ein Release-Build mit einer syntaktisch gültigen
Test-Origin wurde erfolgreich erzeugt. Die iOS-Buildphase ist unter Windows
durch Vertragstests abgesichert; der reale Xcode-Build bleibt Bestandteil von
U8.

CI und lokale Gates beziehen die Node-Version nun einheitlich aus
`.node-version`. Unter dem exakten Pin Node 24.21.0 sind Frozen-Install,
Formatierung, Lint, Typecheck, Backend-Build, CMS-Build und Map-Check grün. Die
54 Backend-Suites mit 701 Tests liefen ausschließlich gegen einen anschließend
entfernten PostgreSQL-16-Testcontainer. Alle 90 CMS-Tests und alle 2594
Flutter-Tests sind grün; `flutter analyze` meldet keine Probleme und der
Mobile-OSV-Audit keine HIGH/CRITICAL-Advisories.

Strapi wurde auf 5.56.0 aktualisiert. Die rekursive Prüfung aller
CMS-Konfigurationen und API-Controller wird durch neue Auth-, Public-Role-,
DTO- und Query-Grenztests festgehalten. Der produktive pnpm-Audit beendet das
HIGH-Gate erfolgreich, meldet aber weiterhin drei Moderate sowie einen formal
als High eingestuften `braces`-Treffer. `braces` besitzt upstream noch keine
veröffentlichte korrigierte Version; deshalb ist genau diese Advisory-ID nach
einem lokalen Tiefenlimit-Patch und einem Regressionstest eng begrenzt
ausgenommen. Die drei Moderates in `react-router` und `stream-json` erfordern
derzeit einen mit Strapi inkompatiblen beziehungsweise nicht veröffentlichten
Major-Zielstand und bleiben für das nächste kompatible Strapi-Update sichtbar
nachzuverfolgen.

## U8 — Release-Abnahme

Vor dem Production Release müssen mindestens folgende Nachweise vorliegen:

1. vollständiger Flutter-Testlauf und `flutter analyze`;
2. Backend-, CMS- und Map-Gates mit der festgelegten Node-Version;
3. Backend-Integrationstests ausschließlich auf einer temporären Testdatenbank;
4. signierter Debug- und Release-Build mit realer `API_BASE_URL`;
5. Smoke-Test für News, Mensa, Kalender, Stundenplan und Mail;
6. HISinOne-Test mit dem real betroffenen Portal und sanitisierten Antworten;
7. Android-NFC-Test innerhalb der App, nicht nur über einen externen Intent;
8. iOS-CoreNFC-Test mit echter Mensakarte;
9. WCAG-Prüfung mit Screenreader, großer Schrift und allen Farbschemata;
10. erneute Prüfung der produktiven WebUntis- und Kalenderkonfiguration.

Nicht bestandene HISinOne- oder NFC-Abnahmen führen zu einem klaren,
lokalisierten deaktivierten Zustand und nicht zu einem still fehlschlagenden
Release.

## Abhängigkeiten

- U1 muss vor vollständigen Backend-Integrationstestläufen abgeschlossen sein.
- U2 muss vor U3 und U4 abgeschlossen sein.
- U5 kann nach U1 unabhängig umgesetzt werden.
- U6 umfasst gemeinsam zu veröffentlichende Backend- und Mobile-Verträge.
- U8 beginnt erst nach Abschluss aller für den Release ausgewählten
  Korrekturphasen.
