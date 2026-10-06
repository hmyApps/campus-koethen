# Akademische Änderungen und Offline-Dokumenten-Wallet

Campus Köthen App · `AGPL-3.0-only` · Copyright © 2026 Leviora Studio and Jona Loreen Sommer

**Stand:** 06.10.2026 · **Status:** implementiert im Feature-Branch
`codex/academic-updates-wallet`

## Umfang

Diese Erweiterung umfasst vier voneinander getrennte Funktionen:

1. Nach einer erfolgreichen Noten-Aktualisierung erkennt die App lokal neu eingetragene
   Ergebnisse und zeigt – bei bestehendem Benachrichtigungs-Opt-in und aktivierter Kategorie –
   genau einen neutral formulierten Systemhinweis. Der Sperrbildschirm erhält weder Fachname noch
   Note, Benutzerkennung oder Portaladresse. Der erste geladene Bericht ist nur die Baseline;
   Korrekturen bereits vorhandener Noten werden nicht fälschlich als neue Note bezeichnet.
2. Erfolgreich geladene Stundenplan-Wochen werden lokal anhand ihrer stabilen Campus-API-ID mit
   dem vorherigen Stand derselben Gruppe und Woche verglichen. Künftige Ausfälle sowie Raum- und
   Zeitänderungen erscheinen als barrierefreier In-App-Hinweis. Ein fehlgeschlagener Abruf oder
   Cache-Fallback verändert die Baseline nicht. Die verschlüsselte Hinweisspeicherung ist additiv
   und darf das Laden des Stundenplans nie blockieren.
3. Immatrikulationsbescheinigung und Leistungsübersicht können nach dem expliziten Öffnen des PDFs
   bewusst in einer verschlüsselten Offline-Wallet gespeichert werden. Je Dokumentart bleibt nur
   die neueste PDF-Version erhalten. Die Wallet ist ohne Netzwerk lesbar, akzeptiert nur valide
   PDFs bis 25 MiB und wird bei Kontowechsel, Portalwechsel oder vollständigem Löschen der
   Notenverbindung mit entfernt.
4. Für bereits lokal verschlüsselt vorliegende Moodle-Fristen kann eine separate lokale Erinnerung
   geplant werden. Der Vorlauf ist in den Benachrichtigungseinstellungen wählbar (1 Stunde,
   6 Stunden, 1 Tag, 2 Tage oder 1 Woche; Standard 1 Tag). Text und Payload enthalten weder
   Aufgaben- noch Kursnamen und keine rohe Moodle-ID.

## System- und Aktualitätsgrenzen

- Es gibt weiterhin keinen Push-Server, kein Analytics-SDK und keinen Hintergrund-Netzwerkabruf.
- Eine neue Note oder Stundenplanänderung kann deshalb erst nach einem erfolgreichen Abruf in der
  geöffneten beziehungsweise wieder aktiven App erkannt werden.
- Moodle-Erinnerungen werden vom Betriebssystem aus dem letzten lokal bekannten Cache vorausgeplant.
  Eine nach dem letzten App-Lauf serverseitig geänderte Frist wird erst beim nächsten erfolgreichen
  Moodle-Abruf neu geplant.
- Noten, Dokumente, Moodle-Inhalte und Stundenplan-Hinweiszustände erreichen kein Campus-Backend.
  Die Wallet und die persönlichen Vergleichszustände liegen ausschließlich verschlüsselt auf dem
  Gerät.

## Lokale Daten und Löschung

| Datenart              | Speicherung                              | Begrenzung                                      | Löschung                                                                  |
| --------------------- | ---------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------- |
| Noten-Baseline        | bestehender verschlüsselter Notencache   | letzter erfolgreicher Bericht                   | bestehende Noten-Komplettlöschung                                         |
| Stundenplan-Vergleich | `campus_timetable_changes_v1`            | 12 Wochenbereiche, höchstens 50 offene Hinweise | nach Bestätigung je Gruppe; Box ist lokal verschlüsselt                   |
| Dokumenten-Wallet     | `campus_document_wallet_v1`              | neueste PDF je Art, maximal 25 MiB je PDF       | einzeln oder zusammen mit Konto-/Portalwechsel und Noten-Komplettlöschung |
| Moodle-Fristen        | bestehender verschlüsselter Moodle-Cache | bestehende Moodle-Regeln                        | bestehende Moodle-Komplettlöschung                                        |

## Bedienung und Barrierefreiheit

- Neue Kategorien besitzen getrennte Schalter und Android-Kanäle.
- Der Moodle-Vorlauf ist neben dem Moodle-Schalter erreichbar und wird lokal gespeichert.
- Stundenplanänderungen werden nicht nur farblich markiert: Icon, Text, Live-Region und eine
  beschriftete Detailansicht benennen Ausfall, alten/neuen Raum oder alte/neue Zeit.
- Die Wallet ist ein anheftbares Modul. PDFs öffnen im vorhandenen internen Dokumentbetrachter;
  Löschen erfordert eine Bestätigung und meldet einen Speicherfehler sichtbar.

## Abnahme

- Notenerkennung: Baseline, neue numerische und unbenotet bestandene Leistung, Korrektur und
  Aggregatknoten.
- Stundenplan: erste Baseline, Ausfall/Entfernung, Raum, Beginn/Ende, Vergangenheit, Deduplizierung,
  persistente Bestätigung und fehlerhafte verschlüsselte Daten.
- Wallet: Dokumentklassifikation, defensive Byte-Kopie, PDF-Signatur, Größenlimit, Ersetzung je
  Slot, korrupter Slot, verifizierte Löschung und Kontositzungs-Gate.
- Moodle: Vorlauf, vergangener Erinnerungszeitpunkt, neutrale Inhalte, opaque stabile Ziele,
  Kategorie-/Berechtigungs-Gates und Tap-Ziel.
