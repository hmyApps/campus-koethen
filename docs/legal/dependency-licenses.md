<!-- Campus Köthen App · AGPL-3.0-only · Copyright © 2026 Leviora Studio and Jona Loreen Sommer -->

# Abhängigkeits-Lizenzen — Moodle-Integration & quellenübergreifender Kalender

Dieses Dokument belegt die Lizenz-Verträglichkeit **jeder** Abhängigkeit, die für die
Moodle-Integration und den quellenübergreifenden Kalender neu hinzukommt. Das Projekt steht unter
`AGPL-3.0-only`; jede direkte **und** transitive Abhängigkeit muss damit vereinbar sein.

## 1. Neu hinzugefügte Abhängigkeiten

**Keine.** Weder die Moodle-Integration noch der quellenübergreifende Kalender führen eine neue
Abhängigkeit ein.

Der Kalender nutzte zwischenzeitlich `table_calendar` (Apache-2.0) samt dessen transitiver
`simple_gesture_detector` für das Monatsraster. Beide sind mit dem Wegfall des Monatsrasters
**entfernt** worden: Tag-, Wochen- und Listenansicht bestehen aus gewöhnlichen Flutter-Widgets.
Die Bewertung entfällt damit, sie ist nur noch Historie.

## 2. Bereits vorhandene, von Moodle wiederverwendete Abhängigkeiten

Die Moodle-Integration nutzt ausschließlich Abhängigkeiten, die bereits für Mail/Noten geprüft und
in [`../../NOTICE.md`](../../NOTICE.md) dokumentiert sind:

| Paket                    | Lizenz         | Nutzung in der Moodle-Integration                                       |
| ------------------------ | -------------- | ----------------------------------------------------------------------- |
| `dio`                    | `MIT`          | HTTPS-Transport (nur `moodle.hs-anhalt.de`), Datei-Download             |
| `flutter_secure_storage` | `BSD-3-Clause` | Ablage des Web-Service-Tokens im Keychain/Keystore                      |
| `hive_ce`                | `Apache-2.0`   | verschlüsselter lokaler Cache (256-Bit-Schlüssel in Secure Storage)     |
| `pdfrx`                  | `MIT`          | PDF-Vorschau mit Formularfeldern (geteilter DocumentViewer)             |
| `share_plus`             | `BSD-3-Clause` | „Teilen/Speichern" als sichere Alternative zur In-App-Vorschau          |
| `html`                   | `BSD-3-Clause` | Reduktion von Moodle-HTML (Kurs-/Modulbeschreibungen) auf sicheren Text |
| `url_launcher`           | `BSD-3-Clause` | Öffnen externer Moodle-Links **ohne** Token (nur `https`)               |

## 3. Prüfvorgehen

- Lizenztyp je Paket aus der `LICENSE`-Datei im pub-cache-Verzeichnis **und** aus den pub.dev-
  Metadaten gelesen.
- Exakt eingebundene Versionen stammen aus [`../../apps/mobile/pubspec.lock`](../../apps/mobile/pubspec.lock).
- Transitiver Abhängigkeitsbaum über `flutter pub deps` geprüft.
- Eingebettete Schriften/JS/Assets, sowie `Commons-Clause`/`BSL`/`SSPL`/`PolyForm`/`NC`/`ND`
  ausgeschlossen.

## 4. Ergebnis (Moodle/Kalender)

Es kommt für Moodle und Kalender keine Abhängigkeit hinzu; die wiederverwendeten sind mit
`AGPL-3.0-only` **verträglich**. Das Lizenz-Gate für diese Arbeit ist erfüllt.

---

# Abhängigkeits-Lizenzen — öffentliche Google-Kalender (ICS)

Für die serverseitige ICS-Synchronisation öffentlicher Google-Kalender kommt genau **eine** neue
direkte Abhängigkeit im Backend hinzu; sie hat **keine** Laufzeit-Abhängigkeiten (Transitive =
leer). Kein Flutter-Paket wird neu eingeführt (die App nutzt das bereits vorhandene `url_launcher`).

| Paket     | Version | Lizenz    | Quelle                                                              | Zweck                                                                                                                                             | Transitive Prüfung                                                                                                                                                                           | AGPL-3.0-Bewertung                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| --------- | ------- | --------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ical.js` | 2.2.1   | `MPL-2.0` | `LICENSE` im Paket · <https://github.com/kewisch/ical.js> (Mozilla) | RFC-5545-Parser (VTIMEZONE, RRULE/RDATE/EXDATE, RECURRENCE-ID, Ganztag, DST) — nur Parsing des bereits geladenen Textes, **kein** Netzwerkzugriff | `dependencies: {}` in der veröffentlichten `package.json` und im installierten `node_modules/.pnpm/ical.js@2.2.1/…/package.json` verifiziert → **keine** transitiven Laufzeit-Abhängigkeiten | **Kompatibel.** MPL-2.0 ist dateiweise Copyleft und über die „Secondary License"-Klausel (§ 3.3) mit der AGPL-3.0 des Projekts vereinbar — dieselbe Bewertung wie für `enough_mail`/`enough_convert` (siehe [`../../NOTICE.md`](../../NOTICE.md) §4). Der Quellcode wird **nicht** einvendort und **nicht** verändert; er wird ausschließlich als unveränderte npm-Abhängigkeit eingebunden. Eigene TypeScript-Typen (`dist/types/module.d.ts`) — kein `@types`-Paket nötig. |

Prüfvorgehen: `npm view ical.js@2.2.1 license dependencies types` und die installierte
`package.json` gelesen (`license: MPL-2.0`, `dependencies: {}`, `types: dist/types/module.d.ts`);
eine `LICENSE`-Datei liegt dem Paket bei. **Es wird bewusst KEINE URL-Fetch-Funktion des Parsers
verwendet** — der Netzwerkzugriff bleibt ausschließlich im abgesicherten `GooglePublicIcsClient`;
dem Parser wird nur der bereits vollständig geladene, größenbegrenzte Text übergeben.

Da die MPL-2.0 dateiweise Copyleft ist und der Backend-Container den kompilierten Code enthält, wird
der Hinweis auf den **unveränderten** Quellcode in [`../../NOTICE.md`](../../NOTICE.md) geführt
(öffentlich und unverändert unter <https://www.npmjs.com/package/ical.js>; die exakt eingebundene
Version steht in `apps/backend/pnpm-lock.yaml`).

**Ergebnis:** Das Lizenz-Gate für die öffentliche-Kalender-Integration ist erfüllt.

## Lageplan

| Paket         | Version   | Lizenz | Bewertung                                                                                                                                               |
| ------------- | --------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `flutter_svg` | `^2.0.10` | MIT    | Permissiv, mit AGPL-3.0-only vereinbar. Wird ausschließlich mit lokalen, im Repository validierten Assets verwendet — nie mit SVG aus einer Netzquelle. |

`packages/campus-map` selbst ist **dependency-frei**: Validator, SVG-Reader und Generator kommen
ohne Laufzeitabhängigkeit aus, damit die Kette von der kanonischen Zeichnung bis zum gebündelten
App-Asset vollständig überprüfbar bleibt.

---

# Abhängigkeits-Lizenzen — Response-Kompression im Backend

Für die Transportkompression der JSON-Antworten (`docs/api.md` § 1, „Transportkodierung") kommt
genau **eine** neue direkte Laufzeit-Abhängigkeit im Backend hinzu, dazu ihre Typdefinitionen als
Dev-Abhängigkeit. Kein Flutter-Paket kommt hinzu: `dio` beziehungsweise die Dart-`HttpClient`-Ebene
bieten `gzip` bereits von sich aus an und dekodieren transparent.

| Paket                | Version | Rolle             | Lizenz | Zweck                                                        |
| -------------------- | ------- | ----------------- | ------ | ------------------------------------------------------------ |
| `compression`        | 1.8.1   | `dependencies`    | `MIT`  | Express-Middleware für `br`/`gzip`, exakt gepinnt (kein `^`) |
| `@types/compression` | 1.8.1   | `devDependencies` | `MIT`  | Typdefinitionen; landet nicht im Container                   |

Vollständiger transitiver Laufzeit-Baum von `compression` — alle **MIT**, jedes Paket mit
beiliegender `LICENSE`-Datei:

| Paket          | Version | Lizenz | Eigene Laufzeit-Abhängigkeiten |
| -------------- | ------- | ------ | ------------------------------ |
| `bytes`        | 3.1.2   | `MIT`  | keine                          |
| `compressible` | 2.0.18  | `MIT`  | `mime-db`                      |
| `mime-db`      | 1.54.0  | `MIT`  | keine                          |
| `debug`        | 2.6.9   | `MIT`  | `ms`                           |
| `ms`           | 2.0.0   | `MIT`  | keine                          |
| `negotiator`   | 0.6.4   | `MIT`  | keine                          |
| `on-headers`   | 1.1.0   | `MIT`  | keine                          |
| `safe-buffer`  | 5.2.1   | `MIT`  | keine                          |
| `vary`         | 1.1.2   | `MIT`  | keine                          |

Prüfvorgehen: `license` und `dependencies` je Paket aus der **installierten** `package.json` unter
`node_modules/.pnpm/<paket>@<version>/node_modules/<paket>/` gelesen und das Vorhandensein einer
`LICENSE`-Datei geprüft; die exakt eingebundenen Versionen stehen in der `pnpm-lock.yaml` im
Repository-Wurzelverzeichnis. `pnpm audit --audit-level high` bleibt ohne Befund — keiner der neuen
Einträge taucht in einem Advisory auf.

**Bewertung:** MIT ist permissiv und ohne Einschränkung mit `AGPL-3.0-only` vereinbar. Kein
Copyleft, keine `Commons-Clause`/`BSL`/`SSPL`/`PolyForm`/`NC`/`ND`-Klausel, kein einvendorter
Quellcode, kein Netzwerkzugriff und kein Postinstall-Skript in einem der Pakete. Daraus folgt
**kein** zusätzlicher Hinweispflicht-Eintrag in [`../../NOTICE.md`](../../NOTICE.md) über die dort
bereits geführte allgemeine MIT-/Apache-/BSD-Aussage hinaus.

**Ergebnis:** Das Lizenz-Gate für die Response-Kompression ist erfüllt.

---

# Abhängigkeits-Lizenzen — lokale Benachrichtigungen (LEVIORA-162)

Für die lokale Benachrichtigungsplanung nach [ADR-0001](../adr/0001-push-benachrichtigungen.md)
kommen **vier** direkte Flutter-Abhängigkeiten hinzu. Kein Backend-Paket, kein npm-Paket, kein
Push-SDK.

## 1. Direkte Abhängigkeiten

| Paket                         | Version | Lizenz         | Zweck                                                                                                             | AGPL-3.0-Bewertung                                                           |
| ----------------------------- | ------- | -------------- | ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `flutter_local_notifications` | 22.3.0  | `BSD-3-Clause` | Vormerken, Ersetzen und Stornieren lokaler Benachrichtigungen bei Android und iOS                                 | **Kompatibel.** Permissiv, kein Copyleft, keine Zusatzklausel                |
| `timezone`                    | 0.11.1  | `BSD-2-Clause` | IANA-Zeitzonendatenbank; Grundlage dafür, dass 08:00 Uhr auch am Tag der Zeitumstellung 08:00 Uhr bleibt          | **Kompatibel.** Permissiv                                                    |
| `flutter_timezone`            | 5.1.0   | `Apache-2.0`   | Ermittlung des IANA-Namens der Gerätezeitzone                                                                     | **Kompatibel.** Apache-2.0 ist mit `AGPL-3.0-only` vereinbar (GPLv3-Familie) |
| `app_settings`                | 9.0.0   | `MIT`          | Öffnen der Benachrichtigungseinstellungen des Betriebssystems, wenn die Berechtigung verweigert oder entzogen ist | **Kompatibel.** Permissiv                                                    |

`app_settings` steht **nicht** in der Paketliste von ADR-0001 § 11.1. Es wird gebraucht, weil die
UX-Spezifikation (§ 3.2, Zustand 4/5) den Weg „Zu den Systemeinstellungen" verlangt und keine
bereits vorhandene Abhängigkeit ihn auf **beiden** Plattformen anbietet: `url_launcher` kann unter
iOS `app-settings:` öffnen, unter Android nicht. Ohne dieses Paket bliebe die verweigerte
Berechtigung eine Sackgasse — genau der Zustand, den das Akzeptanzkriterium ausschließt.

## 2. Neue transitive Abhängigkeiten

| Paket                                            | Version | Lizenz         | Herkunft                              | Bewertung                                                                    |
| ------------------------------------------------ | ------- | -------------- | ------------------------------------- | ---------------------------------------------------------------------------- |
| `flutter_local_notifications_platform_interface` | 12.2.0  | `BSD-3-Clause` | `flutter_local_notifications`         | **Kompatibel.** Permissiv                                                    |
| `flutter_local_notifications_linux`              | 8.0.1   | `BSD-3-Clause` | dito, Desktop-Implementierung         | **Kompatibel.** Wird in der mobilen App nicht eingebunden                    |
| `flutter_local_notifications_web`                | 1.0.0   | `BSD-3-Clause` | dito                                  | **Kompatibel.** dito                                                         |
| `flutter_local_notifications_windows`            | 3.1.1   | `BSD-3-Clause` | dito                                  | **Kompatibel.** dito                                                         |
| `equatable`                                      | 2.1.0   | `MIT`          | `flutter_local_notifications_windows` | **Kompatibel.** Permissiv                                                    |
| `dbus`                                           | 0.7.15  | `MPL-2.0`      | `flutter_local_notifications_linux`   | **Kompatibel** — dieselbe Bewertung wie `enough_mail`/`ical.js`, siehe unten |

`dbus` ist der einzige Neuzugang mit Copyleft. Die MPL-2.0 ist dateiweise copyleft und über ihre
„Secondary License"-Klausel (§ 3.3) mit der AGPL-3.0 vereinbar; der Quellcode wird **nicht**
einvendort und **nicht** verändert. Er wird ausschließlich von der Linux-Implementierung des
Plugins eingebunden und gelangt damit in kein APK und in kein IPA. Der Hinweis auf den
unveränderten Quellcode steht dennoch in [`../../NOTICE.md`](../../NOTICE.md) § 4 —
Hinweispflicht vor Auslegungsspielraum.

## 3. Prüfvorgehen

- Lizenztyp je Paket aus der `LICENSE`-Datei im pub-cache-Verzeichnis der **exakt** eingebundenen
  Version gelesen; `flutter_local_notifications` und seine Plattformpakete tragen den
  BSD-3-Clause-Text mit der „Neither the name … endorse"-Klausel, `timezone` denselben Text
  **ohne** diese Klausel (BSD-2-Clause).
- Exakt eingebundene Versionen aus [`../../apps/mobile/pubspec.lock`](../../apps/mobile/pubspec.lock).
- Keine `Commons-Clause`/`BSL`/`SSPL`/`PolyForm`/`NC`/`ND`-Klausel, kein einvendorter Quellcode,
  keine eingebettete Schrift und kein Asset in einem der Pakete.
- **Kein** Paket dieser Gruppe führt Netzwerkcode aus. Das ist hier keine Formalie, sondern die
  Grundlage der Entscheidung: Ein Benachrichtigungspaket mit eigenem Transport wäre genau die
  Fremdanbindung, die ADR-0001 ausschließt.

**Ergebnis:** Das Lizenz-Gate für die lokalen Benachrichtigungen ist erfüllt.
