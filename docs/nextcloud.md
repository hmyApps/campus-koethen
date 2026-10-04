# Nextcloud-Dateiexplorer

Campus Köthen App · `AGPL-3.0-only` · Copyright © 2026 Leviora Studio and Jona Loreen Sommer

---

## 1. Zweck und Systemgrenze

Das Modul zeigt die persönlichen Dateien des angemeldeten Kontos in der Nextcloud-Instanz der
Hochschule Anhalt. Die App verbindet sich **direkt vom Gerät** und ausschließlich mit der exakten
Origin `https://cloud.hs-anhalt.de`. Campus API, Strapi und Worker sind nicht beteiligt und erhalten
weder Zugangsdaten noch Dateinamen, Metadaten oder Dateiinhalte.

Der erste Umfang ist bewusst lesend:

- Anmeldung über den offiziellen Nextcloud Login Flow v2 im Systembrowser;
- Ordner auflisten und öffnen;
- Dateien bis 25 MiB bewusst laden und im vorhandenen lokalen Dokumentbetrachter öffnen oder über
  dessen explizite Teilen-/Speichern-Aktion an das Betriebssystem übergeben;
- Verbindung trennen und das ausgegebene App-Passwort widerrufen.

Nicht enthalten sind Upload, Umbenennen, Verschieben, Löschen, Freigabelinks, öffentliche Shares,
Favoriten, Versionsverwaltung, Synchronisation im Hintergrund und frei konfigurierbare Server.

## 2. Anmeldung

Campus Köthen verwendet [Nextcloud Login Flow v2](https://docs.nextcloud.com/server/stable/developer_manual/client_apis/LoginFlow/index.html):

1. Die App sendet einen anonymen `POST` an `/index.php/login/v2`.
2. Login- und Poll-URL werden vollständig validiert und müssen auf der exakten erlaubten Origin
   liegen. Die Login-URL wird im **Systembrowser** geöffnet.
3. Die App pollt den zurückgegebenen Endpunkt im vorgesehenen Ein-Sekunden-Abstand. `404` bedeutet
   „noch nicht abgeschlossen“; nur die einmalige `200`-Antwort wird akzeptiert. Nach 20 Minuten
   endet der Vorgang.
4. `server`, `loginName` und `appPassword` werden streng typisiert geprüft. `server` muss erneut
   exakt `https://cloud.hs-anhalt.de` sein.
5. Über `/ocs/v2.php/cloud/user?format=json` ermittelt die App die tatsächliche Nutzer-ID für den
   DAV-Pfad; `loginName` darf laut Nextcloud davon abweichen.

Das zentrale Hochschulpasswort wird Nextcloud **nicht** von der App übermittelt. SSO beziehungsweise
die Hochschul-Anmeldung findet nur innerhalb des von Nextcloud geöffneten Browserflows statt. Das
ausgestellte App-Passwort ist widerrufbar und wird zusammen mit `loginName`, Nutzer-ID und fester
Server-Origin ausschließlich im gerätegebundenen Keychain/Keystore gespeichert. Öffentlicher
Riverpod-State enthält nur `loginName` und Nutzer-ID, nie App-Passwort oder Poll-Token.
Scheitert die Nutzer-ID-Abfrage, die sichere Speicherung oder trifft ein Abbruch erst nach der
Ausstellung ein, versucht die App das gerade ausgestellte App-Passwort kompensierend zu widerrufen
und entfernt jeden teilweise geschriebenen lokalen Wert.

## 3. WebDAV-Vertrag

Verzeichnislisten laufen per `PROPFIND` mit `Depth: 1` ausschließlich unter
`/remote.php/dav/files/{eigene Nutzer-ID}/…`. Downloads verwenden `GET` unter derselben Wurzel.
Jeder vom Server gelieferte `href` wird vor Verwendung erneut gegen Schema, Host, Port,
Benutzerinformation und die eigene DAV-Wurzel geprüft. Pfadsegmente `.`/`..`, eingebettete
Separatoren, Steuerzeichen, fremde Nutzerwurzeln, unerwartete Nachfahren und Redirects werden
abgewiesen.

Multistatus-Antworten sind auf 4 MiB beziehungsweise 10.000 Einträge begrenzt. Die App akzeptiert
nur XML mit DAV-Namensraum und erfolgreichem `propstat`, lehnt DTD/Entities sowie fehlerhafte
Metadaten ab und wertet ausschließlich erfolgreiche Eigenschaften aus. Dateidownloads prüfen eine
deklarierte Größe vorab und zählen zusätzlich die tatsächlich
empfangenen Bytes. Oberhalb von 25 MiB wird der In-Memory-Download beendet. Netzwerkantworten,
Pfade und Tokens erscheinen nie in Exceptions oder UI-Fehlern; die Oberfläche erhält nur
klassifizierte Fehler.

## 4. Datenhaltung und Löschung

Verzeichnislisten, Metadaten und geladene Dateien bleiben im ersten Umfang nur im Arbeitsspeicher.
Es gibt keinen Hive- oder SharedPreferences-Cache und keine Hintergrundsynchronisation. Der
Dokumentbetrachter hält eine geladene Datei nur so lange, wie die Ansicht beziehungsweise der
zugehörige Navigationsvorgang lebt. Eine Weitergabe erfolgt ausschließlich nach der bewussten
Teilen-/Speichern-Aktion der nutzenden Person.

`−` und „Hochschulzugang vollständig löschen“ versuchen zuerst
`DELETE /ocs/v2.php/core/apppassword` mit dem aktuellen App-Passwort. Auch wenn Nextcloud offline
ist oder den Widerruf nicht bestätigt, wird die lokale Berechtigung verifiziert gelöscht. Ein
laufender Browserlogin wird vor der Gesamtlöschung abgebrochen; ein Generationsschutz verhindert,
dass eine verspätete Poll-Antwort das App-Passwort danach erneut schreibt.

## 5. Tests und manuelle Abnahme

Automatisiert geprüft werden mindestens:

- exakte Origin-Allowlist sowie abgewiesene Fremdhosts, Ports, Klartext und `userInfo`;
- strikte Login-/Poll-Antworten, OCS-Nutzer-ID und fehlende Auth-Header vor der Anmeldung;
- Secure-Storage-Readback, partieller Schreibfehler und verifizierter Wipe;
- Abbruch-/Lösch-Race ohne verspätetes Wiederherstellen;
- DAV-Wurzel, URL-Encoding, Traversal/Fremdnutzer, `Depth: 1` und XML-Parser;
- Größenlimit anhand Header und Stream;
- Ordnernavigation, Dokumentbetrachter, 320 dp und 200 % Textskalierung.

Vor einem Store-Release bleiben reale Tests auf Android und iOS erforderlich: Browserwechsel und
Rückkehr zur App, erfolgreicher SSO-Login, Abbruch, Ablauf nach 20 Minuten, Ordner mit Umlauten und
langen Namen, Datei knapp unter/über 25 MiB, Offline-Widerruf und Prüfung des App-Passworts in den
persönlichen Nextcloud-Sicherheitseinstellungen.

## 6. Primärquellen

- [Nextcloud Login Flow v2](https://docs.nextcloud.com/server/stable/developer_manual/client_apis/LoginFlow/index.html)
- [Nextcloud WebDAV API](https://docs.nextcloud.com/server/stable/developer_manual/client_apis/WebDAV/basic.html)
