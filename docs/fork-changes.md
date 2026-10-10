# Neuerungen im Fork

Nur die Funktionen, die dieser Fork **zusätzlich** zum Original (`upstream/main`) einführt.
Bereits im Original vorhandene Funktionen (u. a. Mail-Client IMAP/SMTP, Notenspiegel HIS‑QIS **und**
HISinOne, Moodle, Anträge & Feedback, Stundenplan inkl. Kurs-Ausblenden, Mensa-Menüs mit Filter,
Benachrichtigungs-Basis, quellenübergreifender Kalender, lokale To-dos, Kontakte, News, Lageplan mit
Raumsuche) sind hier **bewusst nicht** aufgeführt.

Grundlage: Tree-Vergleich `upstream/main` ↔ `main`. Alle persönlichen Dienste laufen direkt vom
Gerät, kein Backend-Proxy, kein Tracking, Zugangsdaten nur im Keychain/Keystore.

---

## Komplett neue Funktionsbereiche

- **Nextcloud-Dateiexplorer** — Browser-Login (Flow v2), Ordner/Download, Upload, Löschen,
  öffentliche Read-only-Links, Suche, Sortierung, Favoriten.
- **HSA-GPT (HAWKI)** — KI-Chat direkt zu `ki.hs-anhalt.de` mit widerrufbarem Token, das nur im
  Keychain/Keystore liegt, und eigenem Zustimmungsbildschirm. **Derzeit vorübergehend deaktiviert:**
  `ki.hs-anhalt.de` läuft noch mit HAWKI 2.4.0 ohne die benötigte Modell-API.
- **Dokumenten-Wallet** — Immatrikulations-, Gebühren- und Leistungs-/Studienfortschritts-PDFs
  verschlüsselt offline auf dem Gerät.
- **Studienservice (HISinOne)** — zusätzlich zum bestehenden Notenspiegel, **nur lesend**:
  Bescheinigungen, Personen-/Kontaktdaten, Studiengangsübersicht.
- **Zentraler Hochschulzugang** — optionale, rein lokale Eingabehilfe für Mail/Moodle/Noten/HSA-GPT
  (keine SSO-Sitzung, kein App-Konto).

## Erweiterungen bestehender Funktionen

- **E-Mail** — neu: optional **lesender Exchange-Kalender**, **Empfängersuche** (EWS `ResolveNames`),
  **Löschen/Verschieben** in den Papierkorb, **Live-Abgleich per IMAP IDLE** im Vordergrund.
- **Stundenplan** — neu: **Semester-Assistent** und **Mehrfach-Abos** (Hauptkurs plus weitere
  Studiengruppen oder einzelne Module, lokal zusammengeführt).
- **Kalender** — neu: **ICS-Export**, **Kalenderfarben pro Quelle**, **Home-Screen-Widget**
  (Android/iOS) und favorisierte **Mensa-Gerichte** als Kalendereinträge.
- **Mensa** — neu: lokaler **NFC-Guthabencheck** (Android/iOS).
- **Benachrichtigungen** — neu: **akademische Alerts** (neue Note, Stundenplanänderung,
  Moodle-Frist-Vorlauf) und neutraler **Neue-E-Mail-Hinweis** — rein lokal, ohne Push-Server.

## Backend & Qualität

- Stundenplan-Katalog erweitert um **Perioden-/Modul-Endpunkte** für Semester-Assistent und
  Modul-Abos.
- Sicherheitshärtung der direkten Dienste: Per-Hop-Host-/Redirect-Prüfung (u. a. HAWKI),
  Größen-/Format-Grenzen beim Parsen externer Antworten (EWS, WebDAV, Wallet-PDFs).

## Bugfix-Release 2.0.1

Aus dem Mehragenten-Bughunt ([`bughunt-audit-2026-10-07.md`](bughunt-audit-2026-10-07.md)) sind 85
von 94 validierten Funden behoben, darunter alle 9 mit hoher Schwere: u. a. die IMAP-Reconnect-Schleife
gegen den Hochschul-Login, der mögliche Verlust von Antrags-Statuslinks, Moodle-Erinnerungen nach
Fristende sowie Fehler im Stundenplan- und Kalender-Sync des Backends. Die übrigen neun Funde mit
niedriger Schwere sind als Maintainer-Entscheidung offen; Stand und Folgeaufgaben stehen in
[`agent-memory.md`](agent-memory.md).

---

**Status (2.0.1+11):** `flutter analyze` ohne Befund, `flutter test` 3088/3088; Backend inklusive
Integrationstests gegen PostgreSQL 16 mit 58/58 Suites (811 Tests). Unabhängige, inoffizielle App —
siehe Unabhängigkeitshinweis in der [`README.md`](../README.md).
