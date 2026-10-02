# Qualitätsaudit: App, UI, Logik, Barrierefreiheit und Dateneffizienz

Stand: 30. September 2026  
Projekt: Campus Köthen  
Prüfgegenstand: gesamter versionierter Repository-Bestand

## 1. Kurzfazit

Die Codebasis besitzt bereits eine überdurchschnittlich gute Grundlage: klare Systemgrenzen, typisierte Datenmodelle, explizite Parser, umfangreiche Tests, zentrale Design-Tokens, deutsche und englische Lokalisierung sowie viele gezielte Semantik-, Kontrast- und Textskalierungstests. Die Backend-Unit-Suite ist mit 540 Tests grün; Lint und TypeScript-Typprüfung sind ebenfalls grün.

Vor einem Release sollten trotzdem drei Fehlerklassen als Blocker behandelt werden:

1. Bei Anträgen kann ein fehlgeschlagenes Update des verschlüsselten Speichers fälschlich als erfolgreich gelten. Dadurch kann der geheime Statuslink eines bereits angenommenen Antrags verloren gehen.
2. Die Löschpfade für Noten- und Moodle-Daten verwenden teilweise eine nicht verifizierte „best effort“-Löschung. Die Oberfläche kann daher Abmeldung melden, obwohl sensible Daten oder Schlüssel noch vorhanden sind.
3. Bereits laufende Noten- oder Moodle-Synchronisationen werden beim Abmelden nicht logisch ungültig. Ein später eintreffendes Ergebnis kann den gerade geleerten Cache wieder mit privaten Daten füllen.

Danach haben die Korrektur des News-Caches, Schutz vor veralteten Paginationsergebnissen, ehrliche Persistenz von Aufgaben und gemerkten Events, Speichergrenzen für Anhänge und Mail sowie die kleinen bzw. nicht per Tastatur erreichbaren Interaktionsflächen höchste Priorität.

## 2. Umfang und Methode

Der vollständige, von Git versionierte Bestand wurde rekursiv inventarisiert. Quellcode, Tests, Konfigurationen, Schemas, Dokumentation und textbasierte Assets wurden mit Repository-Suchen, vorhandenen Prüfscripten und gezielter manueller Ablaufanalyse geprüft. Binärdateien wurden inventarisiert und hinsichtlich Größe, Einbindung und – soweit anwendbar – Metadaten betrachtet; sie können naturgemäß nicht wie Quelltext zeilenweise analysiert werden.

| Bereich               | Versionierte Dateien | Abdeckung                                                                                                                                                                                 |
| --------------------- | -------------------: | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apps/mobile`         |                  645 | 341 Dart-Dateien unter `lib`, 178 Flutter-Tests, Android/iOS/Web-Konfigurationen und 20 App-Assets inventarisiert; UI-, Zustands-, Cache-, Netzwerk- und Datenschutzpfade gezielt geprüft |
| `apps/backend`        |                  174 | 123 Dateien unter `src`, 29 Testdateien, Prisma-/API-/Sync-Pfade, Validierung, Paging und Datenbankzugriffe geprüft                                                                       |
| `apps/cms`            |                   83 | Content-Types, Konfigurationen, Policies und 18 Tests geprüft                                                                                                                             |
| `packages/campus-map` |                   27 | SVG-/Manifest-/Generatorpfad und Driftprüfung geprüft                                                                                                                                     |
| `packages/openapi`    |                    4 | OpenAPI-Vertrag und Pfadabdeckung geprüft                                                                                                                                                 |
| `infrastructure`      |                   26 | lokale und VPS-Container-, Proxy-, Umgebungs- und Secret-Konfigurationen geprüft                                                                                                          |
| `docs`                |                   49 | Architektur-, Produkt-, Datenschutz-, Integrations- und Rechtsdokumentation auf Konsistenz mit dem Code geprüft                                                                           |
| `artifacts`           |                   14 | Performance-Artefakte inventarisiert und mit der dokumentierten Baseline abgeglichen                                                                                                      |
| `scripts`             |                    8 | Schema-, Smoke- und Performance-Scripte geprüft                                                                                                                                           |
| `.github`             |                    3 | CI-Workflows, Action-Pinning und Gates geprüft                                                                                                                                            |
| Root-Dateien          |                   13 | Workspace, Lockfile, Formatierung, Lizenz, Hinweise und Repository-Regeln geprüft                                                                                                         |
| **Gesamt**            |            **1.046** | alle versionierten Dateien in der rekursiven Bestandsaufnahme enthalten                                                                                                                   |

Dateitypen mit dem größten Anteil sind 523 Dart-, 200 TypeScript-, 72 PNG-, 51 JSON-, 35 Markdown- und 30 SVG-Dateien. Alle SVG-Dateien ließen sich als XML lesen. Die zwei von einem allgemeinen JSON-Parser abgewiesenen Dateien sind erwartbar: eine absichtlich fehlerhafte WebUntis-Testfixture und die kommentierte `tsconfig.json`.

### Grenzen der Prüfung

- Flutter und Dart sind in der Prüfungsumgebung nicht installiert. `flutter analyze`, Flutter-Tests, Golden-Tests und ein tatsächliches Rendering auf Emulatoren konnten deshalb nicht neu ausgeführt werden.
- Es stand keine ausdrücklich isolierte temporäre PostgreSQL-Datenbank zur Verfügung. Datenbank-Integrationstests wurden deshalb entsprechend der Repository-Regel nicht gegen irgendeine vorhandene Datenbank gestartet.
- Visuelle Aussagen beruhen auf Widgetstruktur, Constraints, Tokens und vorhandenen Tests, nicht auf einer neuen manuellen Geräte-Matrix.
- Die Node-Prüfungen liefen mit Node 24.11.0; das Projekt fordert Node 22.x. Die Abweichung ist unten als Tooling-Risiko ausgewiesen.

## 3. Priorisierung

| Priorität | Bedeutung                                                                                                                                                  |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P0        | Release-Blocker: möglicher Verlust eines nicht wiederherstellbaren Geheimnisses, unzutreffende Löschzusage oder erneute Ablage sensibler Daten nach Logout |
| P1        | Hohe Nutzerwirkung: falsche Inhalte, möglicher Verlust nutzereigener Daten, erhebliche Speicherlast oder relevante Bedien-/Barrierefreiheitslücke          |
| P2        | Mittlere Wirkung: langfristige Ressourcenprobleme, Lastspitzen, Wartungs- oder Testbarkeit, Plattformanpassung                                             |
| P3        | Verbesserung: Qualitätssteigerung ohne derzeit nachgewiesenen Fehlzustand                                                                                  |

## 4. Grobe Fehler und Release-Blocker

### P0-01 – Der geheime Antragsstatus kann trotz angeblich erfolgreicher Speicherung verloren gehen

`EncryptedBox.write` verschluckt Schreibfehler. `EncryptedRequestStore.writeDrafts` und `writeCases` lesen danach zwar zurück, prüfen aber nur auf `null`. Existiert bereits ein alter Wert, gilt dieser bei einem fehlgeschlagenen Update als Erfolg, obwohl der neue serialisierte Inhalt nie geschrieben wurde.

Der konkrete Schadensablauf ist kritisch: `RequestsController._record` speichert nach einer erfolgreichen Serverannahme den Fall und entfernt anschließend Entwurf und Anhänge. Wird beim Aktualisieren einer bereits vorhandenen Fallliste der alte Wert zurückgelesen, fehlt der neue `statusUrl` dennoch dauerhaft. Laut Domänenvertrag ist dieser Link das einzige Zugriffsgeheimnis für den Vorgang.

**Lösung:** Den Payload genau einmal serialisieren, schreiben und anschließend auf exakte Gleichheit zurücklesen. Besser ist eine geprüfte API wie `writeChecked(key, value)` mit Revision oder Hash. Erst nach bestätigter Persistenz dürfen Entwurf und Anhänge gelöscht werden. Ein Regressionstest muss einen vorhandenen alten Wert plus einen simulierten Schreibfehler verwenden.

### P0-02 – Noten- und Moodle-Logout kann eine vollständige Löschung melden, ohne sie nachzuweisen

`EncryptedBox.wipe()` verwirft das Ergebnis von `wipeChecked()`. Genau diese nicht verifizierte Kompatibilitäts-API verwenden `EncryptedGradeCache.clear()` und `EncryptedMoodleCache.clear()`. `GradeAccountController.deleteEverything()` besitzt zwar eine ehrliche Fehlerbehandlung, kann aber keinen Fehler sehen, weil die konkrete Cacheimplementierung keinen wirft. Zusätzlich verschluckt `SecureGradePortalStore` alle Schreib- und Löschfehler.

**Lösung:** Für alle sensiblen Stores ausschließlich eine geprüfte Löschoperation verwenden und bei `!result.isComplete` einen typisierten Fehler werfen. Den Portal-Store nach Schreiben und Löschen verifizieren. Tests müssen die realen Adapter mit fehlschlagendem Keychain-/Hive-Zugriff prüfen, nicht nur Fakes, die künstlich werfen.

### P0-03 – Laufende Synchronisationen können einen Logout überholen und private Daten zurückschreiben

Moodle- und Notencontroller fassen parallele Syncs mit `_inFlight` zusammen, binden den Lauf aber nicht an eine Session-Generation. Ein Sync kann Token bzw. Zugangsdaten lesen, während des Netzaufrufs wird abgemeldet und der Cache geleert, danach schreibt der alte Sync sein Ergebnis wieder in den verschlüsselten Cache und veröffentlicht erneut UI-Zustand.

Der Mailbereich zeigt bereits das richtige Muster: Er erfasst `sessionGeneration` und prüft sie vor jedem Persistenz- und Zustandswechsel. Dieses Muster fehlt bei Noten und in der Moodle-Übersicht.

**Lösung:** Zu Beginn jedes Syncs Generation und Kontoidentität erfassen. Nach jedem `await` und zwingend vor jedem Cache- oder State-Schreibzugriff prüfen, ob die Session noch aktuell ist. Logout sollte laufende Operationen zusätzlich abbrechen oder auf ihr kontrolliertes Ende warten, bevor er löscht. Deterministische `Completer`-Tests müssen den Ablauf „Sync gestartet → Logout → Netzantwort“ abdecken.

## 5. Befundtabelle

| ID / Prio | Kategorie                        | Fundort / Datei                                                                                                                                                                                                                                                                               | Problem und Auswirkung                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Lösungsvorschlag                                                                                                                                                                                                                                                                                  |
| --------- | -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P0-01     | Logik / Datenintegrität          | `apps/mobile/lib/features/requests/data/encrypted_request_store.dart:59-84`; `apps/mobile/lib/features/requests/application/requests_controller.dart:199-235`; `apps/mobile/lib/core/cache/encrypted_box.dart:184-199`                                                                        | Readback prüft nur „nicht null“, nicht den tatsächlich geschriebenen Payload. Ein alter Wert maskiert einen Schreibfehler; der einmalige Statuslink eines angenommenen Antrags kann verloren gehen.                                                                                                                                                                                                                                                                                           | Exakten Payload bzw. Revision/Hash bestätigen; Entwurf und Anhänge erst nach bestätigtem Commit löschen; Fehlerszenario mit altem Wert testen.                                                                                                                                                    |
| P0-02     | Datenschutz / Logik              | `apps/mobile/lib/features/grades/data/encrypted_grade_cache.dart:71-75`; `apps/mobile/lib/features/moodle/data/encrypted_moodle_cache.dart:109-113`; `apps/mobile/lib/core/cache/encrypted_box.dart:217-235`; `apps/mobile/lib/features/grades/data/secure_grade_portal_store.dart:22-45`     | Sensible Löschung nutzt `wipe()` ohne Auswertung; Portal-Persistenz verschluckt Fehler. Logout bzw. Portalwechsel kann Erfolg anzeigen, obwohl Restdaten, Schlüssel oder alter Portalwert bleiben.                                                                                                                                                                                                                                                                                            | `wipeChecked().isComplete` erzwingen, typisierte Fehler weitergeben, Secure-Storage-Schreiben/-Löschen zurücklesen und konkrete Adapter testen.                                                                                                                                                   |
| P0-03     | Race Condition / Datenschutz     | `apps/mobile/lib/features/moodle/application/moodle_controller.dart:60-81,104-141`; `moodle_account_controller.dart:35-42`; `moodle_repository_impl.dart:79-141`; `apps/mobile/lib/features/grades/application/grades_controller.dart:59-75,101-145`; `grade_account_controller.dart:252-272` | Ein vor Logout gestarteter Sync kann nach dem Wipe Cache und UI wieder mit privaten Daten füllen.                                                                                                                                                                                                                                                                                                                                                                                             | Session-Generation wie im Mail-Sync erfassen und nach jedem `await` prüfen; CancelToken bzw. Abbruch; Logout-Race testen.                                                                                                                                                                         |
| P1-04     | Logik / Offline-Cache            | `apps/mobile/lib/features/news/data/news_repository.dart:54-83`; `apps/mobile/lib/core/network/cached_endpoint.dart:45-64`                                                                                                                                                                    | Jede erfolgreiche News-Seite schreibt auf den Schlüssel `postsFirstPage`; `allowCacheFallback: false` verhindert nur das Lesen, nicht das Schreiben. Seite 2 überschreibt daher Seite 1. Offline kann die App anschließend mit der zweiten Seite beginnen.                                                                                                                                                                                                                                    | Cache-Policy in Lesen und Schreiben trennen: nur Seite 1 schreiben oder seitenspezifische Schlüssel verwenden. Regression: Seite 1, Seite 2, danach Offline-Laden von Seite 1.                                                                                                                    |
| P1-05     | Race Condition / UI-Logik        | `apps/mobile/lib/features/news/application/news_feed_controller.dart:92-187`; `news_channel_feed_controller.dart:74-124`                                                                                                                                                                      | `loadMore()` verwendet mutable Locale-/Filterfelder. Ändert sich während des Requests der Filter und wird Seite 1 neu geladen, kann die alte nächste Seite anschließend in den neuen Feed gemischt werden.                                                                                                                                                                                                                                                                                    | Unveränderlichen Request-Scope erfassen, Generation erhöhen und veraltete Antworten verwerfen; alternativ Provider nach vollständigem Scope familisieren. Tests mit kontrolliert verspäteter Seite 2.                                                                                             |
| P1-06     | Datenintegrität                  | `apps/mobile/lib/features/todos/data/hive_todo_store.dart:37-86`; `todos/application/todos_controller.dart:15-49`; `events/data/saved_events_store.dart:10-66`; `events/application/saved_events_controller.dart:25-51`                                                                       | Aufgaben und gemerkte Events sind nutzereigene Daten, Lese- und Schreibfehler werden aber als leere Liste bzw. Erfolg behandelt. Der Schutz des Todo-Controllers vor fehlgeschlagenem Lesen greift mit dem konkreten Hive-Store deshalb nicht. Eine anschließende Mutation kann vorhandene Daten mit einer neuen kleinen Liste überschreiben; nach lautlos fehlgeschlagenem Schreiben verschwinden Änderungen beim Neustart. Zusätzlich wird bei jeder Mutation die ganze Liste serialisiert. | Store-Vertrag darf bei nutzereigenen Daten nicht „best effort“ sein. Lesefehler und Commit-Fehler typisiert weitergeben, UI-Zustand erst nach Commit bestätigen oder rollbacken; pro ID speichern bzw. atomaren Batch mit Revision nutzen.                                                        |
| P1-07     | Speicher / Anhänge               | `apps/mobile/lib/features/requests/data/attachment_picker.dart:60-103`; `encrypted_attachment_store.dart:50-69`; `gremio_request_gateway.dart:73-103`                                                                                                                                         | Die 25-MB-Grenze wird erst nach `readAsBytes()` geprüft. Bis zu vier Dateien werden vollständig gelesen, Base64 erhöht die lokale Größe um etwa ein Drittel, und der Multipart-Upload hält die Bytes erneut im Speicher. Sehr große Falschauswahlen oder vier Grenzdateien können OOM verursachen.                                                                                                                                                                                            | Dateilänge vor dem Lesen prüfen, Gesamtlimit einführen, verschlüsselt chunk-/dateibasiert speichern und Multipart aus begrenzten Streams erzeugen. Tatsächliche Streamgröße weiterhin serverseitig und clientseitig begrenzen.                                                                    |
| P1-08     | Speicher / Netzwerk / Suche      | `apps/mobile/lib/features/mail/domain/mail_cache_store.dart:7-40`; `mail/application/mail_sync_controller.dart:80-156`; `mail/data/mail_cache.dart:221-246`                                                                                                                                   | Der Mailcache wächst laut eigenem Vertrag unbegrenzt. Jeder Sync betrachtet den gesamten zusammengeführten Headerbestand für fehlende Bodies; lokale Suche entschlüsselt und parst für jede Suche jeden gespeicherten Body sequenziell. Optional gespeicherte Anhangsbytes verschärfen den Verlauf.                                                                                                                                                                                           | Alters-, Anzahl- und Bytebudget mit LRU/Retention einführen; nur die neuesten N Bodies vorladen; ältere Bodies bei Bedarf laden; kompakten normalisierten Suchindex getrennt halten; Cachegröße in Einstellungen sichtbar machen.                                                                 |
| P1-09     | Speicher / Mailversand           | `apps/mobile/lib/features/mail/data/mail_attachment_picker.dart:35-56,77-100`; `mail/presentation/mail_compose_screen.dart:120-180`; `mail/data/mail_mime_builder.dart:42-50`                                                                                                                 | Für Mailanhänge gibt es keine erkennbare Anzahl-, Einzel- oder Gesamtgrößengrenze. Beim Senden werden alle Dateien in `Uint8List` gehalten und danach in MIME überführt; große Auswahlen können RAM und SMTP-Limit überschreiten, bevor eine verständliche Fehlermeldung erscheint.                                                                                                                                                                                                           | Konfigurierbare servernahe Grenzen vor dem Lesen prüfen, Gesamtsumme anzeigen, MIME/SMTP möglichst streamen und bei Überschreitung lokal mit verständlicher Meldung abbrechen.                                                                                                                    |
| P1-10     | WCAG / Bedienung / Layout        | `apps/mobile/lib/features/calendar/presentation/week_grid_view.dart:70-89,324-337,507-542`; `calendar/domain/week_layout.dart:57-62`; `news/presentation/article_block.dart:215-251`                                                                                                          | Kalenderkopf ist 32 dp hoch; kürzeste Termine sind bei Standardtext 28 dp hoch und bei Überlappungen auch schmaler als 24 dp. Damit wird die projektspezifische 48-dp-Regel verletzt und überlappende Termine können WCAG 2.2 SC 2.5.8 unterschreiten. Der News-Kanallink ist nur etwa eine Textzeile plus 8 dp hoch und verwendet `GestureDetector`, also ohne regulären Tastaturfokus/-Aktivierung.                                                                                         | Header mindestens 48 dp; für dichte Termine getrennte mindestens 48-dp-Hitflächen oder barrierefreie Listenalternative als primäre Interaktion; Kanallink als `InkWell`/`TextButton` mit `ConstrainedBox(minHeight/minWidth: 48)` und Focus/Activate-Actions. Größen- und Tastaturtests ergänzen. |
| P2-11     | Cachewachstum / Dateneffizienz   | `apps/mobile/lib/core/cache/content_cache.dart:17-23`; `hive_content_cache.dart:18-79`; `core/cache/cache_keys.dart:79-110`                                                                                                                                                                   | Der allgemeine Inhaltscache kennt nur Lesen, Schreiben und Einzel-Löschen, aber kein Budget oder Eviction. Datumsbereichs- und Filterkeys für Stundenplan und Kalender können dauerhaft neue Einträge erzeugen.                                                                                                                                                                                                                                                                               | Namespace-Metadaten und LRU/TTL mit Maximalbytes/-einträgen ergänzen; alte Zeitfenster beim Öffnen oder periodisch bereinigen; Cachegröße messen.                                                                                                                                                 |
| P2-12     | Backend-Last                     | `apps/backend/src/modules/public-calendar/public-calendar-sync.service.ts:203-218`                                                                                                                                                                                                            | `Promise.all` startet für alle aktiven Kalender gleichzeitig Feed-, Parse- und Datenbankarbeit. Mit wachsender Redaktion kann das Lastspitzen, Upstream-Drosselung und DB-Contention erzeugen.                                                                                                                                                                                                                                                                                                | Begrenzte Parallelität, z. B. 3–5 Kalender, mit isolierten Ergebnissen beibehalten; Metriken für Dauer, Bytes und Fehlerquote je Feed.                                                                                                                                                            |
| P2-13     | Bildspeicher / UI-Performance    | `apps/mobile/lib/core/widgets/brand_mark.dart:10-80`; `features/about/presentation/about_screen.dart:93-103`; `apps/mobile/assets/branding/*`                                                                                                                                                 | 1024×1024-Icon und 1672×941-Wordmark werden für Darstellungen von 28–300 dp ohne zielgerechte Decodiergröße eingebunden. Die decodierten Raster benötigen grob 4 MiB bzw. 6 MiB im Image-Cache, unabhängig von der sichtbaren Größe.                                                                                                                                                                                                                                                          | Auflösungsvarianten (`2.0x`, `3.0x`) oder `cacheWidth/cacheHeight` passend zu DPR nutzen; About-Icon ebenfalls passend decodieren; visuelle Qualität per Golden-Test sichern.                                                                                                                     |
| P2-14     | Barrierefreiheit / Plattform     | `apps/mobile/lib/app/campus_app.dart:44`; gesamtes `apps/mobile/lib`                                                                                                                                                                                                                          | Reduzierte Animation wird berücksichtigt, eine Auswertung von `MediaQuery.highContrast` ist jedoch nicht vorhanden. Das ist kein nachgewiesener Kontrastfehler – die Paletten besitzen Tests –, aber die App reagiert nicht auf die Plattformpräferenz für höheren Kontrast.                                                                                                                                                                                                                  | Optionales `highContrastTheme`/`highContrastDarkTheme` und Tokenvarianten ergänzen; Fokusrahmen, Umrisse und Statusmarker auf beiden Plattformen testen.                                                                                                                                          |
| P2-15     | Wartbarkeit / Layoutregressionen | u. a. `campus_map_screen.dart` (1.055 Zeilen), `calendar_screen.dart` (882), `moodle_course_screen.dart` (741), `submission_detail_screen.dart` (676), `week_grid_view.dart` (658)                                                                                                            | Mehrere sehr große UI-Dateien vereinen Datenzustand, Gesten, Layout und Sheet-Aufbau. Änderungen sind schwer isoliert zu testen; Layout- und Zustandsregressionen werden wahrscheinlicher.                                                                                                                                                                                                                                                                                                    | Nach Verantwortlichkeit in private Widgets, Layoutmodelle und Controller zerlegen; keine künstliche Zeilengrenze, sondern testbare Schnittstellen. Für 320/360 dp, Querformat, Textskalierung 1/1,3/2 und Hell/Dunkel Golden-/Widget-Matrix aufbauen.                                             |
| P2-16     | Tooling / Reproduzierbarkeit     | Repository-Root; fehlende `.gitattributes`; `packages/campus-map`; Format-Gate                                                                                                                                                                                                                | Auf Windows setzt die globale Git-Konfiguration `core.autocrlf=true`, während das Repository keine EOL-Regel vorgibt. Dadurch meldet Prettier 297 Dateien und die Map-Driftprüfung alle 15 generierten Map-Assets als abweichend, obwohl der Arbeitsbaum sauber ist.                                                                                                                                                                                                                          | `.gitattributes` mit LF für Quell-/Generatorformate und expliziten Binärmustern einchecken; Generatoren mit deterministischem LF schreiben bzw. beim Vergleich EOL normalisieren. Danach einmal kontrolliert renormalisieren.                                                                     |
| P2-17     | Tooling / CI-Parität             | Root `package.json`, lokale Prüfungsumgebung                                                                                                                                                                                                                                                  | Projekt verlangt Node 22.x, geprüft wurde lokal mit Node 24.11.0. Erfolgreiche Ergebnisse sind hilfreich, aber nicht vollständig identisch zur unterstützten Laufzeit.                                                                                                                                                                                                                                                                                                                        | Node-Version über `.nvmrc`, `.node-version` oder Volta/Corepack eindeutig fixieren und in lokalen Gates früh hart prüfen; CI bleibt Referenz.                                                                                                                                                     |

## 6. UI- und Layoutbewertung

### Positiv

- Farben, Abstände, Radien und Mindestgrößen sind zentral typisiert; verstreute Screen-Hexwerte sind nicht das vorherrschende Muster.
- Die Theme-Buttonstile erzwingen überwiegend 48-dp-Ziele.
- Zahlreiche Screens besitzen Tests bei 320×480 dp und Textskalierung 2, darunter Kalender, Kontakte, Onboarding, Mail, Moodle, News und Stundenplan.
- Kalenderzustände werden nicht nur farblich vermittelt; Icons, Durchstreichung und Semantik ergänzen die Farbe.
- Große Inhaltsbereiche verwenden Sliver/Listen und flexible Constraints statt pauschal verschachtelter, vollständig materialisierter Spalten.
- Remote-Bilder werden semantisch behandelt und auf Zielgrößen dekodiert; die Branding-Komponente ist die auffällige Ausnahme.

### Zu verbessern

1. Die Wochenansicht braucht eine klare Trennung zwischen visueller Dichte und Bedienfläche. Ein 28-dp-Termin kann optisch korrekt skaliert sein, sollte aber nicht zugleich die einzige Hitbox darstellen.
2. Kleine Inline-Links müssen dieselbe Fokus-, Tastatur- und Zielgrößenstrategie wie Buttons erhalten.
3. Für die größten Screens sollte eine feste Layout-Testmatrix Bestandteil des CI-Gates werden. Besonders wichtig sind 320 dp Breite, Querformat, sehr lange englische/deutsche Strings, Textskalierung 2 sowie Screenreader-Semantik.
4. Eine High-Contrast-Variante sollte als Plattformanpassung ergänzt werden; die bestehende Kontrastberechnung kann dafür wiederverwendet werden.

## 7. WCAG-Bewertung

Die vorhandene Implementierung deckt viele relevante Anforderungen bereits gezielt ab:

| Aspekt                     | Bewertung                                                                                                                                                                                                                                        |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1.4.3 Kontrast             | Gute Grundlage: zentrale WCAG-Kontrasthelfer und Theme-Tests für Hell/Dunkel. Ohne laufendes Flutter konnten diese Tests hier nicht erneut ausgeführt werden.                                                                                    |
| 1.4.4 Textvergrößerung     | Viele Widgettests bei Faktor 2; dynamische Höhen in Kalender und Navigation sind erkennbar berücksichtigt.                                                                                                                                       |
| 1.4.11 Nicht-Text-Kontrast | Tokenbasierte Umrisse/Statusdarstellung vorhanden; High-Contrast-Plattformmodus fehlt als zusätzliche Anpassung.                                                                                                                                 |
| 2.1.1 Tastatur             | Standardbuttons und `InkWell` sind grundsätzlich geeignet. `_ChannelLink` verwendet dagegen nur `GestureDetector` und ist kein regulär fokussierbares Steuerelement.                                                                             |
| 2.5.8 Zielgröße (Minimum)  | Die meisten globalen Controls erfüllen die strengere Projektregel von 48 dp. Überlappende Kalendereinträge können unter 24 dp Breite fallen; Header und Inline-Link verfehlen zumindest die Projektregel und die erweiterte 44/48-dp-Empfehlung. |
| 4.1.2 Name, Rolle, Wert    | Viele explizite `Semantics`-Knoten und Tooltips vorhanden. Der Kalender kennzeichnet Einträge als Buttons und benennt Zeit/Status.                                                                                                               |
| Bewegung                   | `MediaQuery.disableAnimations` wird in die App überführt; das ist positiv.                                                                                                                                                                       |
| Farbe als einziges Mittel  | Für untersuchte Statusfälle werden Icon, Text oder Durchstreichung zusätzlich eingesetzt.                                                                                                                                                        |

## 8. Logik- und Datenflussbewertung

### Positiv

- Öffentliche Daten laufen in der mobilen App über `/v1`; die gefundenen direkten Hosts entsprechen den ausdrücklich erlaubten sensiblen Integrationen Moodle, Mail und den getrennten Notenportalen. Die Requests-Origin wird aus der Build-Konfiguration abgeleitet.
- Externe Backend-Antworten werden mit Zod validiert; Flutter verwendet typisierte Parser.
- Caches schützen mehrfach den letzten gültigen Bestand vor leeren oder strukturell fehlerhaften Drittantworten.
- Mail besitzt bereits Generation-Checks gegen Logout-Races und eine verifizierte Wipe-Koordination; dieses Muster sollte als Referenz für Moodle und Noten dienen.
- Backendabfragen sind überwiegend paginiert, beschränkt und gegen N+1-Probleme getestet.
- Die OpenAPI-Dokumentation enthält alle 24 geprüften Pfade.

### Zu verbessern

- „Cache“ und „nutzereigene Daten“ müssen getrennte Fehlerverträge besitzen. Best-effort ist für erneut ladbare öffentliche Inhalte sinnvoll, aber nicht für Aufgaben, gemerkte Events, Antragsstatus oder Logout-Zusagen.
- Jede asynchrone Operation, deren Ergebnis kontobezogen ist, benötigt eine Session-/Request-Generation. Das gilt ebenso für Filter-/Locale-basierte Pagination.
- Die gemeinsame `CachedEndpoint`-API sollte Lese- und Schreibpolicy ausdrücklich trennen; ein einzelnes `allowCacheFallback` suggeriert derzeit fälschlich „nicht cachen“.

## 9. Dateneffizienz

Die stärksten Effizienzrisiken liegen nicht in den Backend-DTOs, sondern in mobilen Langzeitdaten und großen Binärdaten:

1. Mailcache und allgemeiner Inhaltscache besitzen kein belastbares Byte-/Altersbudget.
2. Anhänge werden in mehreren Stufen vollständig materialisiert; Base64 und MIME erzeugen zusätzliche Kopien.
3. Lokale Mailsuche ist linear über alle verschlüsselten Bodies.
4. Aufgaben und gemerkte Events serialisieren bei jeder Kleinänderung die gesamte Liste.
5. Kalender-Sync startet beliebig viele Feeds gleichzeitig.
6. Branding-Raster werden deutlich größer dekodiert als angezeigt.

Empfohlen wird ein gemeinsames Messkonzept: Cachebytes, Eintragszahl, Evictions, Syncbytes, Parse-/Encode-Dauer und Peak-RSS in den vorhandenen Performance-Artefakten erfassen. Für personenbezogene Daten dürfen diese Metriken ausschließlich Zähler und Dauern enthalten, niemals Inhalte, IDs, URLs oder Zugangsdaten.

## 10. Allgemeine Verbesserungsvorschläge

### A. Einheitliche Persistenzklassen

Drei Verträge sollten im Code klar getrennt werden:

- **Re-fetchbarer Cache:** Fehler dürfen fail-soft sein.
- **Nutzereigener lokaler Zustand:** Schreiben muss bestätigt werden; Fehler werden sichtbar, der alte Zustand bleibt erhalten.
- **Sensible/irreversible Daten:** Schreiben und Löschen müssen verifiziert, möglichst transaktional und fail-closed sein.

`EncryptedBox` sollte deshalb nicht nur eine universelle best-effort-API anbieten, sondern explizite `writeBestEffort`, `writeChecked`, `deleteChecked` und `wipeChecked`-Semantik.

### B. Gemeinsames Generation-Guard-Muster

Mail besitzt bereits eine gute Vorlage. Ein kleiner, getesteter `SessionGuard` bzw. Request-Scope kann Moodle, Noten, News-Pagination und spätere kontobezogene Features vereinheitlichen. Vor jedem Seiteneffekt wird geprüft, ob Scope, Konto, Filter und Locale noch identisch sind.

### C. Accessibility-Gates erweitern

Zusätzlich zu Kontrast und Textskalierung sollten Widgettests messen:

- jede interaktive Fläche mindestens 48×48 dp nach Projektregel;
- Tastaturfokus und Aktivierung für alle Links/Custom Controls;
- sinnvolle Fokusreihenfolge;
- Semantikrollen und lokalisierte Namen;
- keine Overflows bei 320 dp, Querformat und Textskalierung 2;
- Hell, Dunkel und High Contrast.

### D. Cache- und Attachment-Budgets als Produktentscheidung

Grenzen dürfen nicht zufällig aus Implementierungsdetails entstehen. Empfohlen sind dokumentierte Budgets je Cache, eine nachvollziehbare Retention sowie sichtbare Größen-/Löschoptionen. Für Mailanhänge und Requests braucht es Einzel- und Gesamtgrenzen sowie Streaming.

### E. Deterministische Repository-Gates

Eine `.gitattributes`-Policy, die festgelegte Node-Version und verfügbare Flutter-Version sollten vor den eigentlichen Gates geprüft werden. Dadurch werden echte Drift- oder Formatfehler nicht von Plattformabweichungen überlagert.

## 11. Empfohlene Umsetzungsreihenfolge

### Sofort – vor Release

1. P0-01: exakte, geprüfte Speicherung des Antragsstatus.
2. P0-02: verifizierte Löschung für Noten/Moodle/Portalwahl.
3. P0-03: Generation-/Abbruchschutz für Noten- und Moodle-Sync.
4. Zugehörige Race-, Adapter- und Fehlerpfadtests zuerst rot schreiben, danach minimal beheben.

### Nächster Sprint

1. News-Cachekey/Schreibpolicy und Pagination-Generation.
2. Ehrliche Persistenz für Aufgaben und gemerkte Events.
3. Kalender-Hitflächen und fokussierbarer News-Kanallink.
4. Vorab- und Gesamtgrößenprüfungen für Requests- und Mailanhänge.

### Danach

1. Mail- und Content-Cachebudgets plus Suchindex.
2. Begrenzte Kalender-Sync-Parallelität.
3. Branding-Decodiergrößen und High-Contrast-Theme.
4. Große UI-Dateien entlang testbarer Verantwortlichkeiten teilen.
5. EOL- und Runtime-Pinning bereinigen.

## 12. Ausgeführte Prüfungen

| Prüfung                                 | Ergebnis                             | Einordnung                                                                                         |
| --------------------------------------- | ------------------------------------ | -------------------------------------------------------------------------------------------------- |
| `pnpm install --frozen-lockfile`        | erfolgreich                          | Lockfile reproduzierbar; Warnung wegen Node 24 statt 22                                            |
| `pnpm lint`                             | erfolgreich                          | nach Prisma-Client-Generierung mit prozesslokalem Platzhalter für die erforderliche `DATABASE_URL` |
| `pnpm typecheck`                        | erfolgreich                          | TypeScript strict ohne Fehler                                                                      |
| Backend-Unit-Suites ohne DB-Integration | 40/40 Suites, 540/540 Tests grün     | `DATABASE_URL` nur als nicht erreichter Platzhalter für die Konfigurationsvalidierung gesetzt      |
| CMS-Tests                               | 86/86 Tests grün                     | keine Fehler                                                                                       |
| OpenAPI-Prüfung                         | 24 Pfade abgedeckt                   | Vertrag konsistent                                                                                 |
| Campus-Map-Tests                        | 56/57 grün                           | Drift-Gate meldet 15 Assets; Befund passt zur fehlenden EOL-Policy unter `core.autocrlf=true`      |
| `pnpm format:check`                     | fehlgeschlagen, 297 Dateien gemeldet | sehr wahrscheinlich Plattform-/EOL-bedingt; sauberer Git-Arbeitsbaum, keine `.gitattributes`       |
| Flutter Analyze/Tests/Rendering         | nicht ausführbar                     | Flutter/Dart fehlen in der Umgebung; kein positives Ergebnis behauptet                             |
| DB-Integrationstests                    | nicht ausgeführt                     | keine ausdrücklich isolierte temporäre PostgreSQL-Datenbank konfiguriert                           |

## 13. Abnahmekriterien für die wichtigsten Korrekturen

- Ein simulierter verschlüsselter Schreibfehler bei vorhandenem Altwert darf Entwurf/Anhänge nicht löschen und muss als Fehler sichtbar werden.
- Nach Noten- oder Moodle-Logout müssen Schlüssel und Box nachweislich fehlen; jede Teilfehlfunktion verhindert eine Erfolgsmeldung.
- Ein nach Logout eintreffender Sync darf weder Cache noch UI verändern.
- Seite 2 eines News-Feeds darf den Offlinebestand von Seite 1 nicht verändern.
- Eine verspätete Seite eines alten Filters/Locale darf niemals in den aktuellen Feed gelangen.
- Aufgaben und gemerkte Events dürfen erst als gespeichert gelten, wenn der Store den Commit bestätigt.
- Keine Attachment-Auswahl darf vor der Größenprüfung den gesamten Inhalt in den Speicher laden; Gesamtbudgets sind getestet.
- Alle interaktiven Kalender- und Kanallink-Flächen erfüllen 48×48 dp und sind per Tastatur/Assistive Technology aktivierbar.
- Mail- und Content-Cache bleiben in Langzeittests innerhalb dokumentierter Byte- und Eintragsgrenzen.

## 14. Produktnachtrag: Stundenplan, Hochschulzugang, NFC, Farbschemen und Matrix

Dieser Abschnitt ergänzt das Audit um nachträglich benannte Produktanforderungen. Er unterscheidet bewusst zwischen bereits vorhandenem, aber nicht erreichbarem Code, echten Funktionslücken und Funktionen, die vor einer Implementierung eine neue Architektur- oder Datenschutzentscheidung benötigen.

### 14.1 Übersicht

| ID / Prio | Bereich                                | Ist-Zustand und Problem                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Empfohlene Umsetzung                                                                                                                                                                                                                                                                                                                                                                                            |
| --------- | -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A-01 / P1 | Stundenplan im Kalender                | Die lokale Zusammenführung ist bereits implementiert: `calendar_providers.dart:433-486` lädt die gewählte Stundenplangruppe, `calendar_merge.dart:22-72` erzeugt `CalendarEntry`-Objekte, und die Quelle ist standardmäßig aktiv. Sichtbar wird sie aber nur mit gewählter Gruppe und gelieferten Backenddaten. Die Backend- und lokalen Compose-Defaults stehen auf `WEBUNTIS_ENABLED=false`; die VPS-Produktionsvorlage setzt dagegen `true`. Der tatsächliche Deploymentwert ist aus dem Repository nicht ableitbar. | Deploymentstatus prüfen, WebUntis nur nach geklärter Freigabe aktivieren und im Kalender einen eindeutigen Diagnosezustand für „Backend deaktiviert“, „keine Gruppe“, „noch kein Sync“ und „Quelle ausgeblendet“ zeigen. Die bestehende lokale Zusammenführung beibehalten.                                                                                                                                     |
| A-02 / P1 | Eigenes Stundenplan-Modul              | `TimetableScreen` ist vollständig vorhanden und getestet, wird im Produktcode aber nirgendwo instanziiert. Es gibt weder eine `AppRoutes.timetable`-Route noch `AppModule.timetable`; der Kommentar in `app_routes.dart:22-24` erklärt sogar ausdrücklich, dass der Stundenplan als eigener Tab entfernt wurde.                                                                                                                                                                                                         | `AppModule.timetable` als anheftbares Studienmodul und `/timetable` als eigenen Router-Branch ergänzen. Kalender und Einzelansicht teilen weiterhin Gruppe, Filter, Provider und Detail-Sheet; keine zweite Datenhaltung einführen.                                                                                                                                                                             |
| A-03 / P1 | Hochschulzugang / gemeinsames Kennwort | Die Hochschule verwendet ein zentrales Kennwort; technisch sind es in der App trotzdem getrennte Anmeldeverfahren: HISinOne-Formlogin mit kurzlebigen Cookies, Moodle-Token und IMAP/SMTP-Zugang. Der Code speichert sie derzeit in getrennten Stores und besitzt keinen zentralen Verbindungsmanager. Ein gemeinsames Passwort ist nicht automatisch eine gemeinsame SSO-Sitzung.                                                                                                                                      | Optionalen lokalen „Hochschulzugang“ im Keychain/Keystore einführen, darüber aber weiterhin getrennte Service-Sessions erzeugen. Ein `+` verbindet genau einen Dienst nach bewusster Aktion, ein `−` ruft dessen kanonischen Logout/Wipe auf. „Dienst trennen“ und „Hochschulzugang vollständig löschen“ müssen getrennte Aktionen bleiben.                                                                     |
| A-04 / P2 | Weitere HISinOne-Funktionen            | Der Gateway ist bewusst ausschließlich auf den Notenspiegel begrenzt. Die Hochschule bestätigt im SSC unter anderem Bescheinigungen, Adressänderungen und – für umgestellte Studiengänge – Prüfungsanmeldungen. Diese Funktionen sind weder implementiert noch durch die derzeitige eng gefasste Architektur-Ausnahme „Notenspiegel“ freigegeben.                                                                                                                                                                       | Zuerst nur bestätigte, lesende Funktionen wie Bescheinigungsübersicht/-download und Studien-/Rückmeldestatus untersuchen. Prüfungsan-/abmeldung, Adressänderungen und Anträge sind irreversible Schreibvorgänge und dürfen nicht über fragiles HTML-Scraping automatisiert werden; sie benötigen einen stabilen Vertrag bzw. eine offizielle Schnittstelle, explizite Bestätigung und eine belastbare Quittung. |
| A-05 / P1 | Mensa-NFC-Guthaben                     | Es gibt weder NFC-Abhängigkeit noch Android-Berechtigung, iOS-Nutzungsbeschreibung oder Reader-Entitlement. Der gewünschte DESFire/IsoDep-Leseablauf ist nicht vorhanden.                                                                                                                                                                                                                                                                                                                                               | Rein lokalen, ausschließlich lesenden `CanteenBalanceReader` hinter einer Plattform-Schnittstelle ergänzen. Scan nur nach bewusstem Tippen auf „Guthaben prüfen“, Statuswörter und Antwortlänge strikt validieren, keine Kartenkennung speichern oder loggen und auf Geräten ohne NFC einen erklärten Fallback zeigen.                                                                                          |
| A-06 / P2 | Doppelter Mensa-Header                 | `CanteenScreen` setzt den ausgewählten Mensanamen als `eyebrow` und direkt darunter noch einmal `title: "Mensa"`. Enthält der Anzeigename selbst „Mensa“, entsteht genau die beobachtete Wiederholung. Der Kommentar in der Datei bezeichnet dies derzeit als Absicht.                                                                                                                                                                                                                                                  | Einmalige Hierarchie verwenden: `eyebrow` = Bereich „Campus“, `title` = konkreter Mensaname; ohne Auswahl bleibt `title` = „Mensa“. Auswahl und Filter bleiben Aktionen.                                                                                                                                                                                                                                        |
| A-07 / P2 | Farbschemen                            | Es gibt nur Hell/Dunkel; `ThemeMode.system` wird beim Lesen und Schreiben auf Hell reduziert. Beide Helligkeiten verwenden eine fest eingebaute rosa Primärpalette. Deshalb ist „dunkel und alles rosa“ der erwartbare aktuelle Zustand.                                                                                                                                                                                                                                                                                | Helligkeit (`system`, `light`, `dark`) und Akzentpalette (`pink`, `green`, `blue`, optional weitere geprüfte Paletten) als zwei unabhängige Einstellungen modellieren. Jede Akzentfarbe braucht eigene Hell-/Dunkel-Tokens und automatisierte WCAG-Kontrasttests.                                                                                                                                               |
| A-08 / P1 | Matrix-Dev-Modul                       | Im Repository existiert noch keine Matrix-Abhängigkeit, Route, Konfiguration oder Datenhaltung. Eine direkte Matrix-Anbindung ist außerdem noch keine der exakt vier erlaubten Drittanbieter-Ausnahmen aus `AGENTS.md`. Ein Dev-Flag allein hebt diese Systemgrenze nicht auf.                                                                                                                                                                                                                                          | Zunächst eine lokale, netzwerklose Platzhalterroute per Build-Flag erlauben. Vor echter Anmeldung Matrix ausdrücklich in `AGENTS.md`, Datenschutztext und Löschkonzept aufnehmen. Danach Homeserver ausschließlich aus Build-Environment, Token im Keychain/Keystore, verschlüsselten lokalen Store und vollständigen Matrix-Logout/Wipe implementieren.                                                        |

### 14.2 Stundenplan: konkreter Zielzustand

Der Stundenplan soll auf zwei Wegen sichtbar sein, ohne Daten zu duplizieren:

1. **Kalenderquelle:** Die bereits vorhandene Quelle `CalendarSource.timetable` bleibt standardmäßig aktiviert. Der Kalender zeigt Vorlesungen gemeinsam mit öffentlichen Terminen und Moodle-Fristen.
2. **Eigenes Modul:** In „Einstellungen → Navigationsleiste“ erscheint „Stundenplan“ als anheftbares Modul. Es öffnet den bereits vorhandenen `TimetableScreen` mit Wochenwechsel, Gruppenauswahl und Stundenplanfiltern.

Die erforderlichen Codepunkte sind begrenzt: stabiler Storage-Wert `timetable`, `AppRoutes.timetable`, `AppModule.timetable`, ein zusätzlicher `StatefulShellBranch` und lokalisierte Modultexte. Die Navigation muss gespeicherte alte Konfigurationen weiterhin reparieren können. `NavigationConfig` besitzt dafür bereits die richtige Normalisierung.

Vor einer UI-Änderung muss jedoch der operative Pfad geprüft werden. `apps/backend/.env.example`, die lokalen Infrastrukturbeispiele und die Compose-Defaults verwenden `WEBUNTIS_ENABLED=false`; `infrastructure/vps/campus-production.example` und `campus-test-api.example` setzen dagegen `true`. Der echte Deploymentwert ist nicht versioniert und muss operativ geprüft werden. Ist er deaktiviert, kann weder der Kalender noch ein eigener Tab reale Stundenplandaten zeigen. Die Oberfläche sollte den vom Statusendpunkt gelieferten Zustand sichtbar benennen, statt nur eine leere Kalenderansicht zu hinterlassen.

„In den Kalender importieren“ bedeutet hier den bestehenden appinternen, rein lokalen Merge. Ein Export in den Systemkalender von Android/iOS wäre eine andere Funktion mit zusätzlichen Kalenderberechtigungen, Dubletten-/Update-Logik und einem eigenen Datenschutzentscheid; er ist in diesem Vorschlag nicht implizit enthalten.

### 14.3 Hochschulzugang und HISinOne

Die Hochschule Anhalt beschreibt das verwendete Kennwort als zentrales Passwort für ihre digitalen Dienste. Ihre aktuelle HISinOne-Anleitung nennt für das SSC-Portal ausdrücklich dieselben HSA-Zugangsdaten wie für Moodle und Webmail. Das bestätigt die gemeinsame Identität, aber nicht eine technisch geteilte Session: Die aktuelle App muss für Mail, Moodle und HISinOne weiterhin drei unterschiedliche Protokolle bedienen.

Offiziell bestätigte Funktionen der Hochschule sind derzeit insbesondere:

- Abruf von Studien-, Immatrikulations- und Studienverlaufsbescheinigungen;
- Abruf des Accountdatenblatts;
- Pflege bzw. Meldung von Adress- und Namensänderungen;
- Prüfungsanmeldung im HISinOne-EXA-Portal für die bereits umgestellten Studiengänge;
- Noten- und Leistungsübersicht.

HISinOne kann produktseitig außerdem Studienstatus, Rückmeldung, Gebühren, Hindernisse, Curriculum-/Studienfortschritt, Prüfungstermine, Veranstaltungs- und Prüfungsbelegung abbilden. Ob jede dieser Funktionen an der Hochschule Anhalt für jedes Konto freigeschaltet ist, darf die App jedoch nicht annehmen. Sie muss Fähigkeiten vom konkreten Portalstand ableiten oder mit der Hochschule vertraglich festlegen.

#### Empfohlener lokaler Account-Manager

Ein neues Widget „Hochschulzugang“ kann die verbundenen Dienste zeigen:

| Dienst           | `+`                                                                                                                                  | `−`                                                                                                   |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| Noten / HISinOne | Gespeicherte Identität nach ausdrücklicher Bestätigung verwenden, Portal erkennen und Notenverbindung einrichten                     | Portalzugangsdaten, Portalwahl und Notencache verifiziert löschen                                     |
| Moodle           | Mit der Identität ein Moodle-Token anfordern; das Passwort selbst nicht an Moodle cachen                                             | Token und verschlüsselten Moodlecache verifiziert löschen                                             |
| Mail             | Mailadresse plus zentrales Passwort gegen IMAP und SMTP prüfen                                                                       | Mailzugangsdaten und Mailcache verifiziert löschen                                                    |
| Matrix, nur Dev  | Den vom Homeserver angebotenen Loginflow verwenden; ein HSA-Passwort nur dann nutzen, wenn der Server diesen Flow offiziell anbietet | Matrix-Logout auf dem Server ausführen, anschließend Token, Geräteschlüssel und lokalen Store löschen |

Wichtige Sicherheitsregeln:

- Das zentrale Kennwort bleibt ausschließlich im Keychain/Keystore und erreicht nie Campus API, Strapi, Logs oder Analytics.
- Ein `+` ist eine bewusste Nutzeraktion, optional durch Biometrie/Device Credential bestätigt. Kein stilles Verbinden aller Dienste beim Start.
- Ein `−` trennt nur den gewählten Dienst. Eine eigene Aktion löscht die zentrale Identität und trennt anschließend alle Dienste.
- Nutzername und Mailadresse sind getrennte Felder; die App darf keine Mailadresse aus einem Benutzernamen erraten.
- Cookies und Service-Tokens bleiben dienstgebunden. Es gibt keinen gemeinsamen Cookie-Jar und kein injiziertes WebView-Passwort.
- Die P0-Befunde dieses Audits zur verifizierten Löschung und zu Logout-Races müssen vor einem zentralen Account-Manager behoben sein; sonst vergrößert er nur den Schadensradius.

Für neue HISinOne-Bereiche gilt zusätzlich: Die aktuelle Architektur-Ausnahme erlaubt direktes Portalhandling ausdrücklich für den **Notenspiegel**, nicht pauschal für alle SSC-Funktionen. Bescheinigungen, persönliche Stammdaten oder Prüfungsanmeldungen müssen vor ihrer Implementierung in `AGENTS.md`, Datenschutzdokumentation und Lösch-/Cachekonzept explizit ergänzt werden.

### 14.4 Mensa: NFC-„€-Check“

Der vorgeschlagene Ablauf ist ein lokaler Read-only-Scan einer ISO-DEP/DESFire-Karte:

```text
SELECT APPLICATION: 90 5A 00 00 03 5F 84 15 00
GET VALUE file 01:  90 6C 00 00 01 01 00
```

Nach erfolgreichem Select darf der zweite Befehl nur gesendet werden, wenn das Statuswort Erfolg meldet. Die Guthabenantwort muss exakt vier Nutzdatenbytes plus erfolgreiches Statuswort besitzen. Die vier Bytes werden als Int32 Little Endian interpretiert; `Wert / 1000` ergibt EUR. Unerwartete Längen, Statuswörter, Kartentechnologien oder offensichtlich unplausible Werte werden als nicht unterstützte Karte behandelt, niemals als `0,00 €`.

Empfohlene UX:

1. Aktion mit NFC-/Euro-Icon im einmaligen Mensa-Masthead: „Guthaben prüfen“.
2. Modal mit kurzer Erklärung und bewusstem Startknopf.
3. „Karte an die Rückseite des Geräts halten“ mit Abbrechen-Aktion und Screenreader-Live-Status.
4. Ergebnis nur im laufenden UI anzeigen. Standardmäßig weder Karten-ID noch Saldo persistieren.

Technische Mindestanforderungen:

- Android: `android.permission.NFC`, NFC als optionales Hardwarefeature (`required=false`), Laufzeitprüfung und ausschließlich `IsoDep.transceive` nach expliziter Reader-Aktivierung.
- iOS: `NFCReaderUsageDescription`, Tag-Reader-Entitlement und Prüfung, ob die konkrete DESFire-Karte über `NFCTagReaderSession`/ISO7816 erreichbar ist.
- Ein `NfcBalanceReader`-Port hält APDUs, Plattformplugin und UI getrennt und erlaubt Tests mit aufgezeichneten, anonymisierten Antworten.
- Keine Hintergrundscans, kein Schreiben auf die Karte, keine Telemetrie und kein Logging von Rohantworten.
- Die APDUs wurden vom Product Owner als validiert bestätigt. Vor Release bleiben Regressionstests für Antwortlänge/Statuswort sowie ein Gerätecheck mit den tatsächlich ausgegebenen Kartengenerationen erforderlich; eine hart codierte Folge ohne Versions-/Antwortprüfung wäre zu fragil.

### 14.5 Farbschemen

Die Einstellung sollte zwei Achsen besitzen:

```text
Helligkeit:  System | Hell | Dunkel
Akzent:      Pink | Grün | Blau | Violett | Bernstein
```

Empfohlene Struktur:

- `BrightnessPreference` und `AccentScheme` als stabile, gespeicherte Enums;
- Registry aus je einer hellen und dunklen `AppColors`-Palette pro Akzent;
- bestehende semantische Farben für Fehler, Erfolg, Warnung und Kalenderquellen nicht blind mit dem Akzent umfärben;
- `ThemeMode.system` real unterstützen statt als Hell zu serialisieren;
- Migration: bestehende Installationen erhalten ihren Hell-/Dunkelwert und `pink` als Akzent, sodass sich nichts unerwartet ändert;
- Kontrasttests für jede Kombination sowie Golden-Tests der zentralen Screens.

Die Auswahl sollte Farbfelder zusätzlich mit Text und Auswahlmarkierung zeigen. Farbe allein darf auch hier nicht den Zustand vermitteln.

### 14.6 Matrix als Dev-Option

Eine sichere erste Stufe ist eine kompilierzeitgesteuerte Modulverfügbarkeit:

```dart
const bool matrixEnabled = bool.fromEnvironment(
  'MATRIX_ENABLED',
  defaultValue: false,
);
const String matrixHomeserver = String.fromEnvironment(
  'MATRIX_HOMESERVER_URL',
);
```

Bei `MATRIX_ENABLED=false` existiert Matrix weder in „Mehr“ noch in der Navigationsauswahl. Bei `true` und einer gültigen exakten HTTPS-Origin wird `AppModule.matrix` sichtbar und kann wie andere Module angeheftet werden. Eine gespeicherte Navigation wird beim Abschalten durch die vorhandene Reparaturlogik wieder auf vier gültige Module gebracht. Der Homeserver darf nie als Quellcode-Konstante oder frei editierbare URL verwendet werden.

Vor einem echten Client sind folgende Gates zwingend:

1. Matrix als fünfte erlaubte direkte sensible Integration in `AGENTS.md` beschließen; kein Campus-Backend-Proxy für Tokens oder Nachrichten.
2. Datenschutztext, lokale Aufbewahrung, Logout/Wipe und Account-Löschung dokumentieren.
3. SDK-Entscheidung und Lizenzprüfung. Das Matrix-Ökosystem listet das Matrix Dart SDK als stabil und AGPL-3.0-only, was grundsätzlich zur Projektlizenz passt, aber Abhängigkeiten und Releasepflege sind trotzdem separat zu prüfen.
4. Homeserver-Fähigkeiten über die standardisierten Matrix-Endpunkte ermitteln; angebotenen Loginflow verwenden statt HSA-Passwortauthentifizierung anzunehmen.
5. Zugangstoken, Refresh-Token, Device-ID und E2EE-Schlüssel sicher speichern. Ein „einfacher Chat“ ohne Geräteverifikation, Cross-Signing/Schlüsselwiederherstellung und korrektes Wipe ist für verschlüsselte Räume kein vertretbarer Release-MVP.
6. Erstes Dev-Inkrement: Login, Raumliste, lesende Timeline, Logout und lokaler Wipe. Senden, Anhänge, Push und vollständige E2EE-Verifikation folgen erst mit eigenen Tests und UX.

Die Nutzerbezeichnung sollte „Matrix“ oder „Chat“ lauten, nicht „WhatsApp“, damit keine fremde Marke oder technische Gleichwertigkeit suggeriert wird.

### 14.7 Offizielle Referenzen für den Produktnachtrag

- [Hochschule Anhalt: Selfservice SSC-Portale](https://www.hs-anhalt.de/studieren/im-studium/formalitaeten/selfservice-ssc.html) – bestätigte Bescheinigungen, Datenänderungen und zentrales Passwort.
- [Hochschule Anhalt: Prüfungsportale EXA/QIS](https://www.hs-anhalt.de/hochschule-anhalt/service/digitale-dienste/pruefungsportale.html) – parallele Portale und studiengangsabhängige Nutzung.
- [Hochschule Anhalt: HISinOne-EXA Prüfungsanmeldung](https://www.hs-anhalt.de/fileadmin/Dateien/Studierenden-Service-Center/Formulare_und_Anleitungen/HISinOne_-_EXA_Pruefungsanmeldung_Studierende.pdf) – Anmeldung mit denselben HSA-Zugangsdaten wie Moodle und Webmail.
- [HIS eG: Studierendenmanagement](https://www.his.de/hisinone/studierende) und [Prüfungen/Veranstaltungen](https://www.his.de/hisinone/pruefungen-und-veranstaltungen) – generischer HISinOne-Funktionsumfang; nicht automatisch eine Zusage, dass jede Funktion an der Hochschule Anhalt aktiviert ist.
- [Android Developers: NFC und IsoDep](https://developer.android.com/develop/connectivity/nfc/nfc) sowie [IsoDep-API](https://developer.android.com/reference/android/nfc/tech/IsoDep) – Berechtigung, Hardwareerkennung und ISO-DEP-I/O.
- [Apple Developer: Core NFC](https://developer.apple.com/documentation/CoreNFC) – ISO7816-/MIFARE-Tag-Reader und erforderliche Capability.
- [Matrix Client-Server API](https://spec.matrix.org/v1.15/client-server-api/) und [Matrix SDK-Übersicht](https://matrix.org/ecosystem/sdks/) – Loginflows, Sync, Logout und SDK-Reife/Lizenzen.
