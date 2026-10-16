# Erweiterungsideen für Studierende der Hochschule Anhalt

Campus Köthen App · `AGPL-3.0-only` · Copyright © 2026 Leviora Studio and Jona Loreen Sommer

Stand: 16. Oktober 2026. Eine **Ideensammlung, keine Zusage**: Nichts davon ist beschlossen oder
geplant. Jede Idee ist gegen `AGENTS.md` §2 (Systemgrenzen) und `docs/product/mvp.md` (Nicht-Ziele)
geprüft; was eine neue Ausnahme oder die Freigabe Dritter braucht, steht dabei.

Aufwand: **S** wenige Tage · **M** ein bis zwei Wochen · **L** mehrere Wochen oder externe Abhängigkeit.

## 1. Bereits vorhandene Daten und Funktionen, die kaum genutzt werden

Diese Ideen brauchen **keine neue Schnittstelle**, nur Oberfläche.

| Idee                                          | Wo die Daten schon liegen                                                     | Nutzen                                                                                                                   | Aufwand |
| --------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------- |
| **Lernstand und Notenschnitt**                | Notenspiegel (HIS-QIS und HISinOne) liegt lokal vor                           | Gewichteter Durchschnitt, Credits gesamt gegen Studiengang, „noch offen“-Liste, Fortschrittsbalken. Rein lokale Rechnung | M       |
| **Modul-Deadlines im Wochenplan**             | Moodle-Fristen und Stundenplan sind schon im Kalender vereinigt               | Wochenansicht „diese Woche fällig“ mit Lernzeitfenstern zwischen den Vorlesungen                                         | S       |
| **Stundenplanwechsel erklären**               | Änderungen werden erkannt (`timetableChangeController`), aber nur als Hinweis | Verlauf „was hat sich geändert“ pro Woche, mit Raum- und Zeitvergleich                                                   | S       |
| **Freie Zeit zwischen Vorlesungen**           | Stundenplan plus Mensa plus Lageplan                                          | „Du hast 70 Minuten: Mensa öffnet, Weg ca. 5 Minuten“ als lokaler Vorschlag in der Tagesübersicht                        | M       |
| **Mensa: Zusatzstoffe, Allergene, Vorlieben** | Marker und Allergene werden geliefert und im Filter genutzt                   | Dauerhafte Ernährungsprofile („vegan, ohne Nüsse“) beim ersten Start, nicht nur als Filter                               | S       |
| **Mensa-Guthaben im Verlauf**                 | NFC-Check liest den Saldo                                                     | Lokaler Verlauf der letzten Werte („reicht für noch 6 Essen“); bleibt auf dem Gerät                                      | S       |
| **Termine in den Systemkalender exportieren** | ICS-Export existiert                                                          | Ein Tipp auf einen Stundenplan- oder Event-Eintrag fügt ihn dem Systemkalender hinzu, nicht nur der Gesamtexport         | S       |
| **Mail: Entwürfe und Vorlagen**               | Mailclient mit Senden vorhanden                                               | Textbausteine für Standardanfragen (Prüfungsamt, Praktikumsamt, Bescheinigung), lokal gespeichert                        | S       |
| **Mail: Anhänge direkt in Nextcloud/Wallet**  | Beide Module bestehen                                                         | „Speichern in Nextcloud“ aus einem Anhang, „In Wallet“ für Bescheinigungen                                               | M       |
| **Wallet: Ablauf und Erinnerungen**           | Wallet speichert Bescheinigungen verschlüsselt                                | Erinnerung vor Ablauf einer Immatrikulationsbescheinigung (z. B. BAföG, Krankenkasse)                                    | S       |
| **Aufgabenliste verknüpfen**                  | Lokale Aufgabenliste, Moodle-Fristen, Kalender                                | Moodle-Aufgabe oder Mail mit einem Tipp als To-do übernehmen                                                             | S       |
| **Suche über alles (lokal)**                  | Nicht-Ziel „globale Volltextsuche“, aber alle Daten liegen lokal              | Eine Suche über Kontakte, Räume, Kurse, Mails und Aufgaben **auf dem Gerät**; mit dem Nicht-Ziel abzustimmen             | L       |
| **Feedback-Status im Überblick**              | Anträge speichern Statuslinks verschlüsselt                                   | Statusliste aller eigenen Anträge mit Hinweis bei Statusänderung beim nächsten Öffnen                                    | S       |

## 2. Neue oder übersehene Services der Hochschule und der Studierendenschaft

Diese Ideen hängen an **Quellen, die wir noch nicht angebunden haben**. Verfügbarkeit und Rechte
müssen vorher mit der Hochschule geklärt werden (jeweils ein neuer Punkt in `AGENTS.md` §2, wenn
Zugangsdaten oder persönliche Daten fließen).

| Idee                                        | Quelle / Voraussetzung                                                      | Nutzen                                                                                                    | Aufwand |
| ------------------------------------------- | --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------- |
| **Bibliothek**                              | Bibliothekskatalog und Konto der Hochschulbibliothek (Schnittstelle prüfen) | Öffnungszeiten, ausgeliehene Medien, Rückgabefristen als Erinnerung, Verlängern per Tipp                  | L       |
| **Semesterticket und ÖPNV**                 | Abfahrten (z. B. über öffentliche ÖPNV-Daten für Köthen, Bernburg, Dessau)  | Nächste Abfahrten zur Haltestelle am Campus; Semesterticket-Gültigkeit als Hinweis                        | M       |
| **Rückmeldung, Gebühren, Fristen**          | HISinOne-Zahlungsübersicht (bereits lesend angebunden)                      | Erinnerung vor Rückmeldeschluss und offenen Gebühren, aus den schon gelesenen Statusdaten                 | S       |
| **Prüfungsanmeldung (nur Anzeige)**         | HISinOne, Fristen und Prüfungstermine; **ohne** Anmeldung (ausgeschlossen)  | Prüfungstermine, Anmeldefristen und Räume lesen und als Erinnerung zeigen                                 | M       |
| **Prüfungsordnung und Modulhandbuch**       | Öffentliche PDFs der Fachbereiche                                           | Studiengangsbezogener Zugriff, offline, mit Suche; Pflichtmodule gegen den Notenspiegel abgleichen        | M       |
| **Raumbelegung und freie Räume**            | WebUntis (öffentliche Ansicht, Räume)                                       | „Freie Lernräume jetzt“ je Gebäude. Aktuell ausdrücklich Nicht-Ziel; Entscheidung nötig                   | M       |
| **Wohnen und Studierendenwerk**             | Studierendenwerk-Angebote, Wohnheimplätze, Beratungstermine                 | Verlinkte Übersicht, Sprechzeiten; Datenquelle und Zuständigkeit klären                                   | M       |
| **Fachschaftsräte und Initiativen**         | Redaktionelle Pflege im CMS                                                 | Je Fachbereich ein Bereich mit Terminen, Ansprechpersonen und Räumen (Kontakte tragen den Standort schon) | S       |
| **Hochschulsport und Kurse**                | Hochschulsport-Anbieter, falls öffentlich zugänglich                        | Kurstermine, Anmeldelinks, Erinnerungen                                                                   | M       |
| **Sprechstunden und Terminbuchung**         | Kontaktbereiche tragen schon `appointmentBookingUrl`                        | Sprechstunden von Lehrenden als Termin im Kalender (nur, wenn die Fachbereiche sie veröffentlichen)       | M       |
| **Campus-Veranstaltungen nach Fachbereich** | News-Kanäle und Events existieren                                           | Fachbereichs-Voreinstellung im Onboarding, damit die richtigen Kanäle vorgeschlagen werden                | S       |
| **Karriere und Praktika**                   | Career-Service-Angebote, Jobbörse der Hochschule                            | Veröffentlichte Stellen, Messen und Workshops als eigener Kanal                                           | M       |
| **Auslandsamt und Internationales**         | Deutsch/Englisch bereits vorhanden                                          | Checklisten für Erstsemester und Austauschstudierende, Fristen zum Semesterstart                          | S       |
| **IT-Dienste der Hochschule**               | RZ-Informationen, WLAN (eduroam), VPN, Drucken                              | Anleitungen und Störungsmeldungen als redaktioneller Kanal, eduroam-Einrichtungshilfe                     | S       |

## 3. Fachbereichs- und studiengangsbezogene Angebote

Heute ist die App nach **Standort** gegliedert. Der naheliegende nächste Schritt ist der
**Fachbereich** oder der **Studiengang**:

| Idee                               | Beschreibung                                                                                                                  | Aufwand |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------- |
| **Studiengangsprofil**             | Beim Einrichten Fachbereich und Studiengang wählen; daraus Stundenplangruppe, News-Kanäle, Kontakte und Fachschaft vorbelegen | M       |
| **Labor- und Werkstattzeiten**     | Fachbereichsspezifische Öffnungszeiten und Einweisungen (Labore, Werkstätten, Rechnerräume)                                   | S       |
| **Projekt- und Abschlussarbeiten** | Fristenleiste für Anmeldung, Abgabe und Kolloquium; Vorlagen und Betreuungsbereiche als Links                                 | M       |
| **Fachbereichs-Mensa-Hinweise**    | Standortspezifische Angebote (z. B. Aktionstage in Dessau oder Bernburg) als News-Kanal                                       | S       |
| **Fachwörterbuch und Kürzel**      | Kürzel aus dem Stundenplan („PMedAnw“, „AIN1“) mit ausgeschriebenem Namen, aus der Redaktion                                  | S       |

## 4. Verbesserungen an Bedienung und Zugänglichkeit

| Idee                                   | Beschreibung                                                                                                                 | Aufwand |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------- |
| **Startseite „Heute“**                 | Eine Übersicht: nächste Vorlesung, Mensa-Favoriten, Fristen, neue Mails. Die Bausteine existieren einzeln                    | M       |
| **Widgets**                            | Kalender-Widget gibt es; ergänzend ein Mensa-Widget (heutiges Gericht der Lieblingsmensa) und ein „Nächste Vorlesung“-Widget | M       |
| **Stundenplan: Kollisionen zeigen**    | Überschneiden sich die Einzelmodule aus mehreren Gruppen, wird das markiert                                                  | S       |
| **Stundenplan: Modulfarben**           | Je Modul eine Farbe, im Plan und im Kalender                                                                                 | S       |
| **Dunkelmodus nach Zeit**              | Automatischer Wechsel nach Tageszeit zusätzlich zum Systemwert                                                               | S       |
| **Sprachen**                           | Weitere Sprachen für internationale Studierende (zuerst Ukrainisch, Arabisch, Türkisch nach Bedarf)                          | M       |
| **Einfache Sprache und große Schrift** | Optional kürzere Texte in Einstellungen und Datenschutz; Prüfung mit Screenreader-Nutzern                                    | M       |
| **Offline-Status**                     | Zentrale Anzeige „zuletzt aktualisiert“ je Quelle, statt Hinweise in jedem Bereich                                           | S       |
| **Export und Datensparsamkeit**        | „Meine lokalen Daten exportieren“ und „alles löschen“ an einer Stelle (Löschen besteht bereits getrennt)                     | M       |

## 5. Zusammenarbeit zwischen Studierenden (nur mit Zustimmung und Klärung)

Hier liegen die größten Chancen und die größten Risiken. Alles braucht Datenschutzklärung und eine
Betreiberentscheidung der Studierendenschaft.

| Idee                           | Beschreibung                                                                                         | Hinweis                                                                  |
| ------------------------------ | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **Lerngruppen**                | Gruppen für ein Modul bilden und Termine abstimmen                                                   | Braucht Konten oder einen Austausch; das Matrix-Vorhaben wurde verworfen |
| **Wegweiser für Erstsemester** | Geführter Ablauf der ersten Woche mit Checkliste (Immatrikulation, Mail, Moodle, Mensa, Stundenplan) | Rein redaktionell und lokal, ohne Konten; **empfohlen**                  |
| **Fundsachen**                 | Meldung gefundener Gegenstände je Standort                                                           | Betreiber und Moderation nötig                                           |
| **Mitfahr- und Tauschbörse**   | Mitfahrgelegenheiten zwischen den Standorten                                                         | Haftung, Moderation und Datenschutz klären                               |

## 6. Empfehlung zur Reihenfolge

1. **Wegweiser für Erstsemester** (Abschnitt 5): viel Nutzen, kein neuer Datenfluss, passt zum neuen
   Standortschritt.
2. **Lernstand und Notenschnitt** und **Fristen aus HISinOne** (Abschnitte 1 und 2): nutzen Daten,
   die bereits lokal vorliegen.
3. **Startseite „Heute“** und **Widgets**: bündeln, was schon da ist.
4. **Studiengangsprofil** (Abschnitt 3): macht Standort- und Studiengangsvorauswahl vollständig.
5. **Bibliothek** und **ÖPNV** (Abschnitt 2): größter externer Nutzen, aber mit Klärungsbedarf.

Offen vor jeder Umsetzung: Ist die Datenquelle öffentlich oder braucht sie Zugangsdaten? Wer pflegt
die Inhalte? Welche Hochschulstelle muss zustimmen?
