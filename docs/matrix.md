# Campus-Chat (Matrix)

Stand: 11. Oktober 2026 · Status: in Umsetzung (Phase 1)

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
  Wert (oder ohne HTTPS) ist der Chat nicht konfiguriert und zeigt das an, statt zu raten.
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
- `−` (Abmelden): Abmeldung des Geräts beim Homeserver (best effort), danach lokal verifiziertes
  Löschen von Datenbank und Schlüssel, auch wenn der Server nicht erreichbar ist.

## 4. Ende-zu-Ende-Verschlüsselung

- Olm/Megolm über **vodozemac** (`flutter_vodozemac`), vom SDK automatisch genutzt.
- Neue Direktchats werden verschlüsselt angelegt. Nicht entschlüsselbare Nachrichten werden
  ehrlich als solche angezeigt, nie als leer.
- Phase 1 enthält außerdem die Einrichtung bzw. Wiederherstellung des Schlüssel-Backups
  (Wiederherstellungsschlüssel) und die Verifizierung eines neuen Geräts mit einem bestehenden.

## 5. Phasen

| Phase | Inhalt                                                                                                                                                   |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | Modul „Chat“ mit Anheften, Login, verschlüsselte Datenbank, Sync, Raumliste, Direkt- und Gruppenchats mit E2EE, Schlüssel-Backup und Geräteverifizierung |
| 2     | Experimentelle Schalter: HSA-GPT und Mail in der Chat-Oberfläche                                                                                         |
| 3     | Anhänge und Bilder, Lesebestätigungen, Tipp-Anzeige (eigene Ergänzung der Regel in `AGENTS.md`)                                                          |
| 4     | Meetings (MatrixRTC/Element Call), sobald die Hochschule die Server-Infrastruktur bereitstellt                                                           |

## 6. Bauen und Testen

- `flutter_vodozemac` kompiliert vodozemac beim Build aus Rust. Lokal und in der CI wird dafür
  eine Rust-Toolchain mit den Android-Zielen benötigt.
- `package:sqlite3` lädt die SQLite3MultipleCiphers-Bibliothek beim Build aus den GitHub-Releases
  des Pakets (mit Prüfsummen) — der Build braucht dafür Netz.
- Unit-Tests laufen gegen Fakes und die `FakeMatrixApi` des SDKs; automatisierte Tests gegen einen
  echten Server nutzen einen Wegwerf-Synapse in Docker, nie Zugangsdaten zu einem echten Konto.

## 7. Offene Punkte

- Produktiver Homeserver der Hochschule: Domain, Betreiber, Login-Verfahren.
- Meetings: MatrixRTC benötigt serverseitig zusätzlich eine LiveKit-Infrastruktur.
- Datenschutzhinweise in den rechtlichen Seiten vor der Veröffentlichung ergänzen.
