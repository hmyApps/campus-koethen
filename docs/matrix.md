# Campus-Chat (Matrix)

Stand: 11. Oktober 2026 · Status: in Umsetzung (Phase 1, Branch `feat/matrix`)

Das Modul „Chat“ bindet einen Matrix-Homeserver **direkt vom Gerät** an. Es ist die siebte
Ausnahme in `AGENTS.md` §2 und folgt denselben Grundsätzen wie Mail, Moodle und Nextcloud: kein
Campus-Köthen-Backend dazwischen, Zugangsdaten nur im Keychain/Keystore, Inhalte nur verschlüsselt
lokal.

## 1. Ziel

- Direkt- und Gruppenchats über Matrix, **Ende-zu-Ende-verschlüsselt** von Anfang an.
- Produktivbetrieb später auf einem Homeserver der Hochschule Anhalt mit den Hochschulkonten,
  einschließlich Meetings. Bis dahin dient `https://matrix.erikspace.eu` als Testserver.
- Experimentell und standardmäßig aus: HSA-GPT- und Mail-Unterhaltungen in derselben
  Chat-Oberfläche, um die übrige Oberfläche zu entlasten. Ausschalten ist der Rollback, es werden
  keine Daten migriert.
- Angeheftet erscheint das Modul mit einem Sprechblasen-Icon.

## 2. Netzwerkgrenze

- Die Homeserver-Adresse kommt **ausschließlich** aus `--dart-define=MATRIX_HOMESERVER_URL=…`. Ohne
  gültigen HTTPS-Wert ist das Modul nicht Teil des Builds: Es fehlt in „Mehr“, in den
  Navigationseinstellungen und in der Leiste; die Route selbst meldet „nicht eingerichtet“.
- Eine gespeicherte Sitzung eines anderen Homeservers (etwa nach einem Build-Wechsel vom Test- auf den
  Produktivserver) wird beim Start lokal verworfen, ohne diesen Server zu kontaktieren.
- Raum-IDs gelangen nie in eine Route: Ein Raum wird mit seiner ID als `extra` geöffnet.
- Ein eigener HTTP-Client lässt nur Anfragen an genau diese Origin (Schema, Host, Port) zu und
  verfolgt keine Redirects. `.well-known`-Discovery und eine vom Nutzer eingegebene Serveradresse
  gibt es nicht.
- Kein Push-Gateway: Synchronisation läuft nur, solange die App im Vordergrund ist.

## 3. Anmeldung und Speicherung

- Phase 1: Matrix-Passwort-Login (`m.login.password`) am konfigurierten Homeserver. Das Passwort
  wird nur für den Login genutzt und nie gespeichert.
- Später: Konten der Hochschule Anhalt. Ob der HSA-Homeserver SSO (Login im Systembrowser, wie bei
  Nextcloud) oder einen Passwort-Login gegen das Hochschulverzeichnis anbietet, entscheidet die
  Anbindung; die Login-Schicht ist dafür austauschbar.
- Das Matrix-SDK speichert Sitzungstoken, Geräte- und Raumschlüssel sowie Nachrichten in seiner
  SQLite-Datenbank. Diese Datenbank wird mit **SQLite3MultipleCiphers** verschlüsselt geöffnet; der
  zufällige 256-Bit-Schlüssel liegt ausschließlich im Keychain/Keystore.
- `−` (Abmelden, im Kontomenü des Chats): Abmeldung des Geräts beim Homeserver (best effort), danach
  lokal verifiziertes Löschen von Datenbank und Schlüssel, auch wenn der Server nicht erreichbar ist.
  Eine nicht mehr lesbare Datenbank (fehlender oder falscher Schlüssel) wird nie still ersetzt; der
  Chat bietet dann ausdrücklich „Chat-Daten auf diesem Gerät löschen“ an.
- „Hochschulzugang vollständig löschen“ umfasst den Chat in Phase 1 **nicht**: Das Matrix-Testkonto ist
  kein Hochschulzugang. Sobald die Anmeldung über die Hochschulkonten läuft, wird der Chat ein
  eigener `DirectService` mit kanonischem Wipe.
- Lesebestätigungen werden nur privat gesendet (`m.read.private`).

## 4. Ende-zu-Ende-Verschlüsselung

- Olm/Megolm über **vodozemac** (`flutter_vodozemac`), vom SDK automatisch genutzt.
- Neue Direktchats werden verschlüsselt angelegt, sobald das Anlegen umgesetzt ist. Nicht
  entschlüsselbare Nachrichten werden ehrlich als solche angezeigt, nie als leer.
- Lässt sich vodozemac auf dem Gerät nicht laden, bleibt der Chat aus (`encryptionUnavailable`) statt
  unverschlüsselt zu laufen.
- Phase 1 enthält außerdem die Einrichtung bzw. Wiederherstellung des Schlüssel-Backups
  (Wiederherstellungsschlüssel) und die Verifizierung eines neuen Geräts mit einem bestehenden.
  Bis dahin sind Nachrichten aus der Zeit vor der Anmeldung auf diesem Gerät nicht lesbar.

## 5. Phasen

| Phase | Inhalt                                                                                                                                                   |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | Modul „Chat“ mit Anheften, Login, verschlüsselte Datenbank, Sync, Raumliste, Direkt- und Gruppenchats mit E2EE, Schlüssel-Backup und Geräteverifizierung |
| 2     | Experimentelle Schalter: HSA-GPT und Mail in der Chat-Oberfläche                                                                                         |
| 3     | Anhänge und Bilder, Lesebestätigungen, Tipp-Anzeige (eigene Ergänzung der Regel in `AGENTS.md`)                                                          |
| 4     | Meetings (MatrixRTC/Element Call), sobald die Hochschule die Server-Infrastruktur bereitstellt                                                           |

### Stand von Phase 1

| Baustein                                                                      | Stand  |
| ----------------------------------------------------------------------------- | ------ |
| Origin-Grenze, verschlüsselte Datenbank, Schlüssel im Keystore                | fertig |
| Login, Wiederherstellen, Abmelden mit verifiziertem Wipe                      | fertig |
| Sync nur im Vordergrund (`AppSyncHost`)                                       | fertig |
| Modul mit Sprechblasen-Icon, Raumliste, Einladungen, Verlauf, Textnachrichten | fertig |
| Datenschutzhinweis (nur in Builds mit Chat)                                   | fertig |
| Neue Direkt- und Gruppenchats anlegen                                         | offen  |
| Schlüssel-Backup / Wiederherstellungsschlüssel                                | offen  |
| Geräteverifizierung (SAS-Emoji)                                               | offen  |
| Geräteprüfung ohne Konto (vodozemac, Verschlüsselung, Login-Ablehnung)        | fertig |
| Test mit Testkonto gegen einen echten Server (Sync, Senden, E2EE)             | offen  |

## 6. Bauen und Testen

- Build mit Chat, z. B. gegen den Testserver (zusätzlich zu den übrigen `--dart-define`-Werten):
  `flutter build apk --debug --dart-define=MATRIX_HOMESERVER_URL=https://matrix.erikspace.eu`.
- `flutter_vodozemac` kompiliert vodozemac beim Build aus Rust. Lokal und in der CI wird dafür
  eine Rust-Toolchain mit den Android-Zielen benötigt.
- `package:sqlite3` lädt die SQLite3MultipleCiphers-Bibliothek beim Build aus den GitHub-Releases
  des Pakets (mit Prüfsummen) — der Build braucht dafür Netz.
- Host-Tests laufen gegen einen Demo-Homeserver (`test/support/fake_homeserver.dart`) und echtes
  SQLite3MultipleCiphers, ohne vodozemac (der Host hat keine Rust-Bibliothek); E2EE selbst wird auf
  dem Gerät geprüft. Automatisierte Tests gegen einen echten Server nutzen einen Wegwerf-Synapse in
  Docker, nie Zugangsdaten zu einem echten Konto.
- Geräteprüfung (manuell, nicht in der CI):
  `flutter test integration_test/matrix_device_check_test.dart -d <Gerät> --dart-define=MATRIX_HOMESERVER_URL=…`.
  Sie nutzt ein Temp-Verzeichnis und einen Speicher im Arbeitsspeicher (keine echten Chat-Daten) und
  kein echtes Konto. Am 11. Oktober 2026 auf dem Android-Emulator (API 36) gegen den Testserver grün:
  vodozemac lädt, die Datenbank liegt auf dem Gerät verschlüsselt, der Server lehnt einen erfundenen
  Login ab, und es bleibt nichts zurück; logcat enthält keine SDK-Ausgaben.

## 7. Logging

Die App protokolliert aus dem Chat nichts. Das SDK-Logging ist auf seine höchste Stufe begrenzt und
sammelt nichts im Speicher. Verbleibend: Einige SDK-Aufgaben laufen in der Root-Zone und können auf
dieser höchsten Stufe noch ausgeben; im Ausnahmefall eines doppelten `m.room.encryption`-Events
enthält diese Ausgabe das Event (Raum- und Nutzer-ID, kein Nachrichteninhalt, keine Schlüssel). Das
lässt sich ohne Änderung am SDK nicht unterdrücken und ist vor einem Produktivbetrieb zu klären.

## 8. Offene Punkte

- Produktiver Homeserver der Hochschule: Domain, Betreiber, Login-Verfahren.
- Meetings: MatrixRTC benötigt serverseitig zusätzlich eine LiveKit-Infrastruktur.
- Datenschutzhinweis: In der App vorhanden (nur in Builds mit Chat). Die veröffentlichten Fassungen
  unter `docs/legal/` werden vor einer Veröffentlichung eines Builds mit Chat ergänzt.
- Presence: Der Sync meldet den Server-Standard (online, solange die App synchronisiert); eine
  Einstellung dafür fehlt noch.
