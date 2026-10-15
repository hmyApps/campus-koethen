# ADR-0002 — Periodischer Hintergrund-Abgleich auf dem Gerät

Campus Köthen App · `AGPL-3.0-only` · Copyright © 2026 Leviora Studio and Jona Loreen Sommer

| Feld          | Wert                                                                                                                         |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Status        | **Angenommen**                                                                                                               |
| Datum         | 2026-10-16                                                                                                                   |
| Entscheidung  | Erik, 2026-10-16: Hintergrund-Abgleich für E-Mail, Moodle und Veranstaltungs-Benachrichtigungen, etwa alle 10 bis 15 Minuten |
| Ersetzt       | [ADR-0001](0001-push-benachrichtigungen.md) **teilweise**: die Aussage „keine Hintergrundausführung“                         |
| Ersetzt durch | —                                                                                                                            |

## 1. Entscheidung

Die App führt auf dem Gerät **periodisch** einen Abgleich aus, auch bei geschlossener App:

- **E-Mail:** Posteingang abrufen und neue Nachrichten lokal ankündigen.
- **Moodle:** Kurse und Fristen abrufen (Moodles eigene Drosselung von höchstens einem automatischen
  Abruf pro Stunde gilt weiter).
- **Veranstaltungen und Stundenplan:** öffentliche Quellen über die Campus API höchstens etwa
  stündlich auffrischen und **alle** lokalen Erinnerungen aus dem Stand des Geräts neu planen.

Es gibt weiterhin **keinen Push-Server**, keine Gerätekennung, kein Konto und keinen Empfänger. Die
Läufe nutzen genau die Verbindungen, die die App im Vordergrund auch nutzt (Direktintegrationen nach
`AGENTS.md` §2 und Campus API). Das Backend erfährt nichts über Läufe.

## 2. Takt

- Android: WorkManager, Periode 15 Minuten, Flex-Fenster 5 Minuten. Ein Lauf beginnt damit 10 bis 15
  Minuten nach dem vorigen. 15 Minuten sind die kleinste Periode, die Android erlaubt; kürzere,
  zufällige Abstände sind nicht möglich.
- iOS: `BGAppRefreshTask`, frühester Beginn 10 Minuten. iOS entscheidet nach Nutzung und Akku selbst,
  wann ein Lauf stattfindet; ein fester Takt ist dort **nicht zusagbar** und im Alltag deutlich seltener.
- Energiesparmodus, Doze und herstellerspezifische Akkuoptimierungen können Läufe verzögern oder
  unterdrücken. Die App verspricht keine Zustellung zu einem bestimmten Zeitpunkt.
- Der Lauf braucht Netz (`NetworkType.connected`); ein Lauf endet nach spätestens 8 Minuten.

## 3. Schutzregeln

1. **Schalter:** „Im Hintergrund aktualisieren“ in den Benachrichtigungseinstellungen, standardmäßig
   an. Der Job ist nur registriert, wenn etwas zu tun ist (E-Mail oder Moodle verbunden oder
   Benachrichtigungen eingeschaltet).
2. **E-Mail-Inhalt:** Eine einzelne neue Nachricht darf **Absender und Betreff** zeigen, weil beides
   ausschließlich lokal aus der gespeicherten Kopfzeile gebildet wird. Gekürzt, ohne Steuerzeichen,
   Android-Sichtbarkeit „private“ (auf einem gesperrten Bildschirm ausgeblendet). iOS kennt dieses
   Flag nicht. Mehrere Nachrichten: nur die Anzahl. Kein Nachrichtentext, keine Anhänge.
3. **Exchange-Termine** gelangen weiterhin **nie** in Benachrichtigungen oder in das Widget (`AGENTS.md`
   §2). Der Lauf liest sie nicht.
4. **Abgelehntes Passwort:** Weist der Mailserver das gespeicherte Passwort ab, merkt sich der Lauf das
   dauerhaft und meldet sich nicht erneut an, bis neu angemeldet, abgemeldet oder ein Abruf gelingt.
   Jede abgelehnte Anmeldung zählt gegen das zentrale Hochschulkonto.
5. **Keine zwei Prozesse auf denselben Daten:** Lebt die App im selben Prozess, übernimmt **sie** den
   Lauf (`ForegroundBridge`). Nur ein eigens gestarteter Prozess öffnet die verschlüsselten Caches
   selbst und schließt sie danach wieder. Hive ist für zwei Isolates nicht sicher.
6. **Nichts im Log:** Ein Lauf protokolliert nur feste Schrittnamen und Zähler, nie Fehlertexte,
   Betreffe oder Absender.
7. **Ein fehlgeschlagener Schritt kostet die anderen nichts.** Ein fehlgeschlagener Abruf leert den
   letzten Stand nie (`AGENTS.md` §4).

## 4. Verworfen

- **Remote-Push (FCM/APNs):** unverändert verworfen, siehe ADR-0001 Anhang A.
- **Foreground Service mit dauerhafter Benachrichtigung:** würde einen echten 10-Minuten-Takt auf
  Android erlauben, ist aber ein sichtbarer Dauerdienst und für diesen Zweck unverhältnismäßig.
- **Eigener Backend-Cron:** würde Zugangsdaten oder Inhalte an ein Campus-Backend binden.

## 5. Folgen

- Neue Abhängigkeit `workmanager` (MIT).
- iOS: `UIBackgroundModes` `fetch` und `processing`, `BGTaskSchedulerPermittedIdentifiers`; **kein**
  `remote-notification`, kein Push-Entitlement.
- Die Datenschutzhinweise in der App und die Store-Angaben nennen den Hintergrund-Abgleich.
- Manuelle Geräteabnahme nötig (siehe `docs/notifications.md` § Hintergrund-Abgleich); die
  Automatiktests prüfen Logik, nicht das Verhalten des Betriebssystems.
