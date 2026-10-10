# Anträge & Feedback

Finanzanträge und Feedback an das Gremiensystem des Studierendenrats. Der Bereich ist eine der
**vier** in [`AGENTS.md`](../AGENTS.md) §2 festgehaltenen direkten Geräteanbindungen: Die App spricht
ohne Umweg mit dem Gremiensystem.

---

## 1. Warum direkt vom Gerät

Eine Einreichung trägt den Namen der antragstellenden Person und eine **Kopie des
Studierendenausweises**. Genau solche Daten sollen kein Campus-Köthen-Backend erreichen. Deshalb:

- **kein** Backend-Proxy, **keine** serverseitige Speicherung, **kein** Analytics- oder Logging-Umweg;
- ein **eigener** `dio`-Client ohne `LogInterceptor` und ohne Campus-API-Interceptor;
- die Adresse ist **nie** eine Quellcode-Konstante, sondern kommt aus `REQUESTS_BASE_URL`.

Anders als Mail, HIS-QIS und Moodle ist dieser Dienst **nicht nutzerauthentifiziert**. Ausschlaggebend
ist der Inhalt, nicht die Anmeldung.

## 2. Konfiguration

```bash
flutter run --dart-define=REQUESTS_BASE_URL=https://gremio.example
```

- Ohne den Wert ist der Bereich **nicht angebunden**: Entwürfe lassen sich schreiben, eingereicht wird
  nichts, und die Oberfläche sagt das. Eine Adresse wird nie geraten.
- **HTTPS ist Pflicht.** Ein `http://`-Wert gilt als nicht konfiguriert und wird nicht stillschweigend
  hochgestuft — über diese Verbindung laufen ein Ausweis und ein bearer-äquivalenter Link.
- DEV und PROD unterscheiden sich **ausschließlich** über diesen Wert (AGENTS.md §2.5).

Aus der Basisadresse entsteht eine exakte **Origin-Allowlist** (`GremioOrigin`): Schema, Host und Port
müssen übereinstimmen. Kein Suffixvergleich — `gremio.example.angreifer.invalid` endet auf den
konfigurierten Host und wird trotzdem abgelehnt.

## 3. Endpunkte

| Zweck               | Methode und Pfad                    | Format                |
| ------------------- | ----------------------------------- | --------------------- |
| Standorte           | `GET /api/public/v1/locations`      | JSON                  |
| Antrag einreichen   | `POST /api/public/v1/applications`  | `multipart/form-data` |
| Feedback-Bereiche   | `GET /api/public/v1/feedback-areas` | JSON                  |
| Feedback einreichen | `POST /api/public/v1/feedback`      | `application/json`    |
| Status abrufen      | `POST /api/public/v1/status`        | JSON                  |

### Finanzantrag

Gesendet werden **genau** diese Felder:

`locationId`, `title` (max. 200), `applicant` (max. 200), `finance_request` (PDF), `student_card`
(PDF/PNG/JPEG) sowie optional `annex_a` und `annex_b` (PDF). Höchstens 25 MB je Datei.

Es gibt **keinen** Betrag, keine Kategorie, keinen Verwendungszweck, keine Beschreibung und keine
Kontaktadresse: Die Schnittstelle nimmt sie nicht entgegen, und die Zahlen stehen im angehängten PDF.
Der Studierendenausweis wird ausschließlich intern verarbeitet und erscheint **nie** in der
öffentlichen Statusansicht — die App zeigt ihn deshalb auch nirgends an und erwartet ihn nicht zurück.

### Feedback

```json
{ "areaId": 1, "submitterName": "optional", "feedback": "Text" }
```

`feedback` fasst bis zu 10.000 Zeichen. Bleibt das Namensfeld leer, wird `submitterName`
**vollständig weggelassen**; das Gremium vermerkt solche Einreichungen selbst als „Anonym". Die App
sendet dieses Wort nicht — es der Person in den Mund zu legen wäre eine Behauptung über sie. Laut
Schnittstelle sind ein fehlender Name und „Anonym" für die Idempotenz derselbe Request.

Feedback hat keine Uploads und keinen Titel: Der Kartentitel wird serverseitig aus dem Text abgeleitet.

## 4. Idempotenz und die 30-Tage-Grenze

Jeder neue Entwurf bekommt **einmalig** eine UUID v4 als `Idempotency-Key`, die zusammen mit ihm lokal
gespeichert wird. Ein Retry sendet denselben Schlüssel mit **identischen** Daten; die Antwort ist dann
`200` mit `Idempotency-Replayed: true` und es entsteht keine zweite Karte. Derselbe Schlüssel mit
veränderten Daten ergibt `409`.

Endet ein Sendeversuch **uneindeutig** — Timeout, Verbindungsabbruch, 5xx —, ist offen, ob der Vorgang
angekommen ist. Dann gilt:

- Der Entwurf wird **eingefroren** (`PendingSubmission`). Das Formular verweigert Änderungen, denn
  seine Daten sind der Retry-Payload.
- Zusätzlich wird ein **Fingerabdruck** des gesendeten Payloads gespeichert. Stimmt er beim Retry
  nicht mehr, wird nicht gesendet — ein Fehler wird so zum Stopp statt zum Duplikat.
- Der Zeitpunkt des **ersten** Versuchs zählt. Ein späterer Retry verlängert das Fenster nicht, weil
  der Server ebenfalls vom Original aus misst.
- Nach **30 Tagen** verfällt der Schlüssel serverseitig. Danach behauptet die App **nicht**, ein Retry
  sei duplikatfrei: Sie warnt, sendet nicht von selbst und erzeugt auch nicht stillschweigend einen
  neuen Schlüssel. Weiterzugehen ist eine ausdrückliche Entscheidung der Person.

## 5. Erfolgreiche Einreichungen

Die Antwort enthält `statusUrl`, `receiptPdfUrl` und optional `number`. Danach in dieser Reihenfolge:

1. Antwort defensiv prüfen; beide Links müssen HTTPS sein und **exakt** zum konfigurierten Origin
   gehören.
2. Vorgang **verschlüsselt speichern**.
3. Erst dann den Entwurf entfernen.
4. Erst dann die lokalen Anhänge löschen.
5. Sofort versuchen, den Status zu laden; scheitert das, bleibt die Einreichung trotzdem gespeichert.

Scheitert Schritt 2, bleibt der Entwurf **mit seinem Schlüssel** erhalten und die App sagt deutlich,
dass der Vorgang existiert, der Zugang aber verloren gehen könnte. Der Entwurf wird dabei
**eingefroren**: Der Server kennt den Schlüssel jetzt, also darf nur noch ein unveränderter Retry
folgen, der den Link als Replay erneut abholt — ein geänderter bekäme `409`.

Besteht Schritt 1 nicht — `200`/`201`, aber ein Link fehlt, ist kein HTTPS oder gehört zu einem
fremden Origin —, gilt der Ausgang als **unbekannt**, nicht als gescheitert: Der Vorgang existiert
sehr wahrscheinlich. Ohne verwendbaren Link wird nichts gespeichert, und der Entwurf wird wie nach
einem Timeout eingefroren.

Vor dem Senden prüft die App, ob die gespeicherten Vorgänge lesbar sind. Ist das nicht der Fall,
wird **nichts** gesendet — sonst ginge der Statuslink der Antwort mangels Speicherziel verloren.
Solange ein Entwurf gesendet wird, lässt er sich weder ändern noch löschen, seine Dateien nicht
ersetzen und kein zweiter Versand starten — auch nicht aus einer zweiten Instanz des Formulars; die
Liste kennzeichnet ihn als „Wird übermittelt …“.

## 6. Der Statuslink ist ein Bearer-Credential

Wer ihn hat, sieht den Vorgang. Er wird nicht per E-Mail verschickt und lässt sich nicht
wiederherstellen. Deshalb wird er

- **nie** geloggt, an Crash-Reporting oder Analytics gegeben oder in Ausnahmetexte aufgenommen,
- **nie** als Route, Query-Parameter oder Deep Link verwendet — Routen tragen ausschließlich die
  lokale Vorgangs-ID (`/more/requests/submission/:id`),
- **nie** vollständig angezeigt, in die Zwischenablage kopiert oder allgemein geteilt,
- **nur** an den Status-Endpunkt derselben Instanz gesendet oder nach der ausdrücklichen Aktion
  „Zum Antrag“ an den externen Browser übergeben. Auch dafür wird vorher die exakte Origin gegen
  `REQUESTS_BASE_URL` geprüft; fremde Origins werden abgewiesen.

Die Browserübergabe ist der einzige bewusste Export des Statuslinks. Der Browser kann den Link in
seinem Verlauf behalten; die App übergibt ihn weder an andere Apps noch an eine Share-Funktion.

`receiptPdfUrl` und jede `downloadUrl` enthalten denselben Token und werden genauso behandelt. Für die
Eingangsbestätigung ist das Teilen im Dokumentbetrachter deshalb **abgeschaltet**.

## 7. Statusabruf

```
POST /api/public/v1/status
{ "statusUrl": "<lokal gespeicherter Link>" }
```

**Warum POST für einen lesenden Abruf:** Als Query-Parameter landete der Link in Browser-Historien,
Proxy- und Access-Logs, Monitoring und Referrer-Headern. Im Body bleibt er davon verschont. Der
Aufruf verändert nichts und bekommt deshalb **keinen** Idempotency-Key.

Aktualisiert wird:

- beim Öffnen der Hauptansicht, mit höchstens **drei** gleichzeitigen Abrufen;
- per Pull-to-refresh;
- beim Öffnen der Detailansicht sofort und danach etwa alle **60 Sekunden**, solange sie sichtbar und
  die App im Vordergrund ist. Beim Verlassen oder Wechsel in den Hintergrund stoppt das Polling
  sofort. Es gibt **keinen** ungebremsten Hintergrunddienst.
- Bei `429` wird `Retry-After` respektiert und bis dahin nichts gesendet.
- Gleichzeitige Abrufe desselben Vorgangs werden als **Single-Flight** zusammengeführt.

Der Endpunkt antwortet `Cache-Control: no-store`. Statusantworten bleiben deshalb **im
Arbeitsspeicher** und werden beim Öffnen neu geladen. Offline zeigt die App keinen alten Stand als
aktuell an. Dauerhaft gespeichert werden nur Nummer und Titel — beides nicht geheim —, damit die Liste
auch ohne Netz lesbar ist.

Ein `400` oder `404` löscht **niemals** einen lokal gespeicherten Vorgang. Der Endpunkt antwortet
`404` absichtlich identisch für unbekannten Token, gelöschten Vorgang und Token des falschen Typs;
daraus eine Löschung abzuleiten würde einen Vorgang unerreichbar machen.

## 8. Lokale Speicherung

| Was                                              | Wo                                         |
| ------------------------------------------------ | ------------------------------------------ |
| Entwürfe, Idempotenzdaten, eingereichte Vorgänge | `EncryptedBox` `campus_requests_secure_v1` |
| Anhänge (inkl. Studierendenausweis)              | `EncryptedBox` `campus_request_files_v1`   |

Der AES-Schlüssel liegt ausschließlich im Keychain/Keystore. **Nichts** davon landet in
SharedPreferences oder einer unverschlüsselten Hive-Box.

**Lesefehler sind keine leere Liste.** Lässt sich die Box nicht öffnen oder eine gespeicherte Liste
nicht dekodieren, zeigt die App einen Fehler mit „Erneut laden“ und schreibt **nichts** — sonst
würde der nächste Schreibvorgang alle Statuslinks überschreiben. Eine Box, die ihr gültiger
Schlüssel nicht öffnen kann, wird für diese Daten nicht wie ein Cache gelöscht, sondern bleibt bis
zum nächsten Versuch oder zur ausdrücklichen Löschung liegen. Einzelne Einträge, die dieser Build
nicht versteht, werden bei jedem Schreiben unverändert mitgeführt.

Die Dateigröße wird über die Picker-Metadaten geprüft, **bevor** Inhalt gelesen wird. Neue Anhänge
werden in verschlüsselten Blöcken von 256 KiB abgelegt und beim Multipart-Upload blockweise wieder
entschlüsselt; Einzel-, Anzahl- und Gesamtbudget werden vor und während dieses Pfads erneut geprüft.
Es entsteht zu **keinem** Zeitpunkt eine entschlüsselte Datei auf der Platte, also auch keine, die
ein Absturz zurücklassen könnte. Die Originaldatei der Person wird nie verändert oder gelöscht.
Bereits vorhandene Ganzdatei-Einträge der ersten verschlüsselten Fassung bleiben lesbar und werden
beim nächsten Ersetzen automatisch im Blockformat gespeichert.

**Migration:** Entwürfe der ersten Fassung lagen in einer Klartext-Box (`campus_requests_v1`). Sie
werden gelesen, verschlüsselt geschrieben, zurückgelesen — und **erst dann** wird die alte Box von der
Platte gelöscht. Schlägt etwas dazwischen fehl, bleibt die Klartextkopie liegen und der Versuch
wiederholt sich beim nächsten Start: Ein Duplikat ist behebbar, ein verlorener Entwurf nicht.

Übernommen werden `title`, `applicant`, `locationId` und vorhandene Dateien; bei Feedback die alte
`description` als neuer Text. Ein alter `category`-Wert wird **nicht** als `areaId` gelesen — das sind
verschiedene Vokabulare, und ein geratener Wert würde das Feedback bei irgendeinem Gremium einreichen.

## 9. Statusnamen

Die öffentlichen Statusnamen kommen vom Server und werden **nicht** in ein festes Enum wie
accepted/rejected gezwungen: Die Gremien benennen ihre Spalten selbst, und „In Bearbeitung" in
„akzeptiert" zu übersetzen hieße, etwas zu berichten, das niemand gesagt hat. Ist `status.name` null,
zeigt die App „Status nicht angegeben". Bei Anträgen ist `archived` das verlässliche
Abschlussmerkmal.

## 10. Dokumente

`documents` liefert `kind`, `label`, `filename`, `mimeType` und `downloadUrl`. Bekannte Arten:
`finance_request`, `annex_a`, `annex_b`, `other` (nachgereichte Datei oder Quittung). Ein unbekanntes
`kind` wird als Dokument angezeigt statt verworfen.

Heruntergeladen wird erst auf Nutzeraktion, dann im gemeinsamen nativen Betrachter
(`core/documents/`) — PDFs, Bilder und Text vollständig in der App, ohne Browserweiterleitung. Vor
jedem Download werden HTTPS und der exakte Origin geprüft; fremde Origins, `http`, Zugangsdaten in der
URL und **Weiterleitungen** werden abgelehnt. Nichts wird dauerhaft gespeichert; alles bleibt im
Arbeitsspeicher des Betrachters.

Weiterleitungen lehnt nicht nur der Download ab, sondern der gesamte Requests-Client
(`requestsDioProvider`): `followRedirects: false`. Sonst entscheidet die Gegenstelle, welchen Host
die App als Nächstes kontaktiert — Dio folgt standardmäßig, und ein `303` auf ein `POST` wird
Cross-Host als `GET` mit den ursprünglichen Headern weiterverfolgt. Die Origin-Allowlist ist das
einzige Routing dieses Features; ein `3xx` gilt deshalb als unbrauchbare Antwort.

## 11. Fehlerbehandlung

**Einreichung:** `200` Replay · `201` neu · `400` Validierung, feldbezogen · `404` Ziel weg ·
`409` Idempotenzkonflikt · `413` zu groß · `415` falscher Content-Type · `429` mit `Retry-After` ·
`500`/Transport = **unbekannter Ausgang**.

**Status:** `200` · `400` ungültiger Link · `404` nicht gefunden · `413`/`415` Protokollfehler ·
`429` mit `Retry-After` · `500`/Transport temporär.

Serverseitige `issues` werden über ihre `field`-Werte den echten Formularfeldern zugeordnet und dort
angezeigt. Ein Feldname, den dieser Build nicht kennt, wird zusätzlich als allgemeine Meldung gezeigt
statt verworfen.

**Keine Eingabe und keine Datei geht durch einen Fehler verloren.** Nach Validierungs-, Netzwerk-,
Server- oder Rate-Limit-Fehlern bleibt das Formular vollständig erhalten.

## 12. Offene Grenzen der Schnittstelle

Zwei Dinge bleiben bewusst unfertig, weil die öffentliche API sie nicht anbietet. Nichts davon wird
simuliert oder durch einen erfundenen Endpunkt ersetzt.

- **Nachreichungen und Quittungen.** `availableActions` meldet `canUploadDocuments` und `submitMode`
  (`resubmission`, `receipt` oder `null`). Die App zeigt das verständlich an, kann es aber nicht
  ausführen: Es gibt keinen öffentlichen Upload-Endpunkt dafür. Sie sagt deshalb, dass das
  Gremiensystem diesen Schritt bisher nur über seine Weboberfläche anbietet. Sobald eine öffentliche
  Schnittstelle existiert, geschieht es nativ.
- **„Wichtige Dokumente".** Das Webformular zeigt einen solchen Bereich; in der OpenAPI gibt es dafür
  keinen Endpunkt. Es wird **nicht** gescrapt, es werden **keine** Downloadlinks hartkodiert und kein
  leerer Bereich vorgetäuscht. Benötigt wird ein öffentlicher, strukturierter Endpunkt.
