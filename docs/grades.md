# Noten (HIS-QIS- und HISinOne-Notenspiegel)

Ein mobiler Bereich unter **Mehr → Noten**, der den persönlichen Notenspiegel **direkt vom
Gerät** abruft. Es gibt bewusst **keine** Backend-Beteiligung.

Die Hochschule Anhalt betreibt zwei Prüfungsportale parallel:

- **HIS-QIS** (Bestandsportal) — `service.ssc.hs-anhalt.de`, flache HTML-Tabelle.
- **HISinOne** (neueres Portal) — `sscportal.ssc.hs-anhalt.de`, JSF-MyFaces, hierarchischer
  Prüfungsbaum.

Ein Konto spricht **immer nur eines** der beiden Portale. Welches, wird bei der Einrichtung
einmalig ermittelt (siehe „Portalwahl" unten) und danach persistiert — jede weitere
Synchronisation spricht nur noch dieses eine Portal an.

## Direkter Datenfluss — nicht verhandelbar

- Die App spricht **ausschließlich** und **direkt** mit dem Host des aktiven Portals. Beide
  Portale haben eine **eigene, getrennte** Host-Allowlist — es gibt **keine** gemeinsame Liste,
  damit ein Fehler im einen Profil nie das andere aufweitet.
- Login bei **beiden** Portalen identisch: `application/x-www-form-urlencoded`-POST mit den
  Feldern `asdf` (Benutzername) und `fdsa` (Passwort).
- **Kein** Umweg über Campus API, Strapi, CMS, Campus-Backend, Proxy, Analytics- oder
  Logging-Dienst. Weder Zugangsdaten noch Sitzungscookies, `asi`/`authenticity_token`/
  `ViewState`, Noten oder Prüfungsnamen verlassen das Gerät — außer über die direkte
  TLS-Verbindung zum jeweiligen offiziellen Portal.
- Dies ist eine **ausdrücklich beschlossene, eng begrenzte Ausnahme** von der Regel „Flutter
  spricht nur mit der Campus API" (siehe `AGENTS.md`, § 2.1).

## Ablauf HIS-QIS (Bestandsportal, `LegacyQisGradesGateway`)

Unverändert gegenüber der bisherigen Fassung: Login → Prüfungsverwaltung → Notenspiegel →
Logout, mit dem dynamischen `asi`-Parameter aus den Links der jeweils aktuellen Sitzung.

## Ablauf HISinOne (`HisInOneGradesGateway`) — höchstens vier Requests

1. `POST /qisserver/rds?state=user&type=1&category=auth.login` (`asdf`/`fdsa`). Antwort ist
   immer `302`. **Erfolgssignal:** `Location` enthält `category=menu.browse`. **Fehlsignal:**
   `Location` zeigt auf `hisinoneStartPage.faces`. Der Redirect-Ziel-Host wird **vor** der
   Signal-Prüfung validiert, damit ein böswilliger Redirect immer als `tlsOrHostRejected`
   erkannt wird, nie als gewöhnlicher Login-Fehler.

   **Zusätzliche Absicherung — positiv, nicht negativ geprüft:** Die Zielseite gilt nur dann als
   eingeloggt, wenn sie einen Logout-Link (`category=auth.logout`, `QisHtmlParser.isAuthenticated`)
   enthält. **Nicht** geprüft wird, ob das Login-Feld `asdf` verschwunden ist — anders als beim
   alten Portal rendert HISinOne auf **jeder** Seite, eingeloggt oder nicht, ein verstecktes
   Formular `id="sessionTimeoutLoginForm"` mit genau den Feldern `asdf`/`fdsa`, für die
   Wiederanmeldung nach Sitzungsablauf. Eine reine Anwesenheitsprüfung auf `asdf` (wie sie das
   alte Portal zusätzlich zum Location-Signal einsetzt) ist auf HISinOne deshalb **immer**
   positiv und macht jeden Login — auch mit korrekten Zugangsdaten — als `invalidCredentials`
   fehlschlagen. Das war ein realer Bug in einer früheren Fassung dieses Ablaufs.

2. `GET /qisserver/pages/sul/examAssessment/personExamsReadonly.xhtml?_flowId=examsOverviewForPerson-flow`
   — liefert den (zugeklappten) Prüfungsbaum. Der `_flowExecutionKey` kommt vom Server und wird
   **nie** hart kodiert.
   **Vor jeder weiteren Aktion wird diese Seite klassifiziert**
   (`HisInOneHtmlParser.readOverview`), weil „Konto ohne Leistungen" und „Seite nicht
   erkannt" sonst identisch aussehen — beide ohne Aufklapp-Button:

   | `HisInOneOverviewKind` | Seite                                                                                         | Reaktion                        |
   | ---------------------- | --------------------------------------------------------------------------------------------- | ------------------------------- |
   | `expandable`           | zugeklappter Baum **mit** Aufklapp-Button                                                     | Schritt 3, dann parsen          |
   | `rendered`             | Baum **ohne** Aufklapp-Button                                                                 | direkt parsen                   |
   | `empty`                | Abschnitt „Leistungsdaten" vorhanden, aber ohne Baum („Es wurden keine Datensätze gefunden.") | **leerer Bericht**, kein Fehler |
   | `unrecognised`         | weder Formular `examsReadonly` noch Abschnitt „Leistungsdaten"                                | `portalStructureChanged`        |

   Der am 24.08.2026 an der Hochschule Anhalt ausgelieferte Stand liefert für ein Konto ohne
   HISinOne-Leistungen `empty`. Vorher meldete der Gateway dafür `portalStructureChanged`; das
   brach die Einrichtung ab, bevor HIS-QIS — wo die Leistungen dieses Kontos tatsächlich liegen
   — überhaupt probiert wurde. Ergebnis: gültige Zugangsdaten, aber keine einzige Note in der
   App.

3. Nur bei `expandable`: ein Form-POST auf die `action` des Formulars `id="examsReadonly"`
   klappt den Baum auf. Mitgesendet werden **alle** Hidden-Felder dieser Seite — insbesondere
   `authenticity_token`, `javax.faces.ViewState`, `examsReadonly_SUBMIT` und der dynamische
   `_flowExecutionKey` — plus der Button, gefunden über die ID-**Endung** `:expandAll2`
   (Fallback: `:expandAll`), **nie** über die (lokalisierte) Beschriftung. Der aktuell
   ausgelieferte Portalstand kennt diesen Button nicht mehr (Knoten werden einzeln über
   `t2g_*`-Buttons geschaltet) — deshalb der Zweig `rendered`.
4. `GET /qisserver/rds?state=user&type=3&category=auth.logout` im `finally`, danach wird der
   Cookie-Jar geleert.

`authenticity_token` und `ViewState` sind das HISinOne-Gegenstück zum `asi` des alten Portals:
immer aus der aktuellen Sitzung übernommen, nie gespeichert, nie geloggt.

### Parser (`HisInOneHtmlParser`)

Zieltabelle: `<table class="treeTableWithIcons">` **innerhalb** des Abschnitts, dessen ID
`examsReadonly:overviewAsTreeReadonly` lautet **oder** mit `examsReadonly:overviewAsTreeReadonly:`
beginnt. Die zweite, strukturgleiche Tabelle („Studienverlauf") liegt im Geschwister-Abschnitt
`examsReadonly:degreeProgramProgressForReportAsTree` und wird dadurch nie getroffen. Gematcht
wird der **Abschnitt**, nicht eine exakte innere ID: ältere Portalstände rendern die Tabelle
unter `…:tree:ExamOverviewForPersonTreeReadonly`, der aktuell ausgelieferte Stand nutzt diese
ID gar nicht mehr. Eine Pinnung auf die innere ID hat genau deshalb versagt. (Hinweis: `getElementById`/`#id`-CSS-Selektoren funktionieren nicht,
weil JSF-IDs `:` enthalten, das `html`-Paket das als Pseudoklassen-Selektor fehlinterpretiert —
der Parser sucht das Element daher über einen manuellen Attribut-Scan.)

- Kopfzeile: `<th class="invisible">Ebene</th>`, dann `<th colspan="…">Titel</th>` (die
  tatsächliche `colspan` wird gelesen, nicht hart auf 9 angenommen), danach eine Spalte je
  Feld (`Nummer, Versuch, Rücktritt, Bewertung, Bonus, Malus, Status, Freiversuch, Vermerk, Vorbehalt, Zusatzmerkmal, Freigabedatum, Aktionen`).
- Spaltenauswahl **ausschließlich** über den Kopfzeilentext, nie über feste Indizes — die
  sichtbaren Spalten sind pro Nutzerkonto konfigurierbar (dieselbe Regel wie im
  bestehenden `QisHtmlParser`).
- Datenzeile: erste Zelle `<td class="invisible">` = Pfad (z. B. `1.1.1.1`). Die Titelzelle ist
  die Zelle, bei der die aufsummierte `colspan` ab Position 1 die `colspan` der Kopfspalte
  „Titel" erreicht. Alle Zellen danach entsprechen 1:1 den Feld-Kopfspalten.
- **Blatt-Erkennung rein strukturell:** eine Zeile ist ein Prüfungsergebnis, wenn kein anderer
  Pfad mit `<eigenerPfad>.` beginnt — nicht über CSS-Klassen, Icons oder Nummernmuster. **Der
  Parser liefert trotzdem JEDE Zeile des Baums** (Modul-, Wurzel- und Blattknoten), inklusive der
  `C-Sammelkonto`-Zeile — die im echten Portal selbst ein innerer Knoten ist, kein Blatt. Ob eine
  Zeile ein Blatt ist, wird nur als `GradeEntry.isLeaf` mitgeführt; Modul-/Wurzelknoten liefern
  zusätzlich ihren Titel für `GradeEntry.module` (die Elternknoten-Bezeichnung des jeweiligen
  Blatts). Ein Blattfilter im Parser würde `C-Sammelkonto` verwerfen, bevor `GradeProjection` die
  Zeile je als Durchschnitt erkennen kann — die Auswahl „nur Blätter anzeigen" gehört deshalb in
  die Darstellung, nicht in den Parser (dieselbe Trennung wie bei Ausblenden und Umbenennen).
  Mehrere Abschlüsse ergeben mehrere Wurzeln; die flachste beobachtete Wurzeltiefe ist `1.1`,
  nicht `1` — der Parser nimmt nie eine feste Wurzeltiefe an.
- Fehlende Pflichtspalten (`Titel`, `Bewertung`, `Status`) oder keine gefundene Tabelle →
  `portalStructureChanged`, kein Cache-Überschreiben, keine Antwort im Log.

**Feldabbildung:** Nummer→`examNumber`, Titel→`title`, Bewertung→`grade`, Status→`status` +
`statusText`, Versuch→`attempt`, Freigabedatum→`examDate`, Bonus→`bonus`, Ebene→`path` (daraus
`depth`), übrige Spalten (`Rücktritt, Malus, Freiversuch, Vermerk, Vorbehalt, Zusatzmerkmal,
Aktionen`) → `extras: Map<String,String>` mit dem **originalen Kopfzeilentext** als Schlüssel.
`examiner` bleibt `null` (HISinOne führt keine eigene Prüferspalte in diesem Layout).

**Unterschiede zum alten Parser:**

- Dezimaltrennzeichen ist der **Punkt** (`2.7`, `3.0`); beide Trennzeichen werden von beiden
  Parsern akzeptiert (`domain/decimal_parsing.dart`, gemeinsam genutzt).
- Status-Kürzel: `BE` bestanden, `NB` nicht bestanden, `PV` Prüfung vorhanden. Unbekannte Kürzel
  → `ExamStatus.unknown` mit Originaltext, nie verworfen.
- Unbenotet bestanden: `Bewertung` leer + `Status = BE` → `Grade.passedUngraded()`. Die alte
  „0,0/0.0 + bestanden"-Regel gilt zusätzlich weiter.
- `Freigabedatum` ist `dd.MM.yyyy HH:mm:ss`, nicht `dd.MM.yyyy`.
- Der Durchschnitt steht in der Zeile **„C-Sammelkonto"** (Spalte `Bewertung`), nicht
  „Credit-Sammelkonto". `classifyQisRow` (in `grade_projection.dart`, portalunabhängig genutzt)
  erkennt nach Normalisierung `^c(redit)? sammelkonto$` — der Wert wird unverändert übernommen,
  nie selbst berechnet.
- Die Spalte `Bonus` trägt Werte, die wie Credits aussehen — sie wird **nie** als ECTS
  umgedeutet oder umbenannt; Kopfzeilentext und Wert werden wörtlich übernommen.

### Bescheinigungen auf der Notenübersichtsseite selbst (`ExamReportGateway`)

Dieselbe Notenübersicht (Schritt 2 oben) bietet im Formular `id="examsReadonly"` zusätzlich einen
eigenen Abschnitt mit bis zu drei festen Druck-Buttons (`class="submit_print_pdf"`, z. B.
Leistungsübersicht bestandener Leistungen auf Deutsch und Englisch, Übersicht fehlender
Leistungen). Anders als die Studienservice-Bescheinigung ist das **keine** AJAX-Auftrag/Polling-
Kette, sondern eine normale **volle** Formularabgabe (`myfaces.oam.submitForm`): alle Hidden-Felder
des Formulars plus der gedrückte Button plus `DISABLE_VALIDATION=true` werden an die Formular-
`action` gepostet; die Antwort ist ein Redirect auf

```
https://sscportal.ssc.hs-anhalt.de/qisserver/rds?state=docdownload&docId=…
```

— danach folgt derselbe zweite Redirect-Sprung wie beim Studienservice-Download, auf die separate
Origin `untrust-sscportal.ssc.hs-anhalt.de` (siehe unten), über eine eigene, separat benannte
Prüfung (`HisInOneProfile.allowsDocumentDownload`, kein gemeinsamer Pool mit
`StudentServiceProfile`). Die Liste der angebotenen Buttons (`ExamReportOffer`, Button-Id +
Beschriftung) wird bei jedem Notenabruf frisch mitgelesen (`HisInOneHtmlParser.findExamReports`)
und zusammen mit dem Bericht zwischengespeichert (`GradeReport.examReports`); vor dem Absenden wird
sie **erneut** von einer frisch geladenen Seite gelesen — ein Button, der dort nicht mehr auftaucht,
wird abgelehnt, statt eine veralterte Id zu posten. Zugangsdaten, Session- und Download-Mechanik
sind identisch zum übrigen Notenspiegel-Ablauf (Login → Seite → Form-POST → Download → Logout im
`finally`); es entsteht **kein** zweiter Login und **kein** eigener `+`/`−`-Eintrag. Ausgeschlossen
bleibt jede andere Formularaktion auf dieser Seite — insbesondere Prüfungsanmeldung.

## Lesende HISinOne-Funktionen jenseits des Notenspiegels

Dieselbe HISinOne-Verbindung (`sscportal.ssc.hs-anhalt.de`, **nicht** das HIS-QIS-Bestandsportal)
wird um weitere, ausschließlich **lesende** Funktionen erweitert. Erreichbar über ein eigenes,
anheftbares Modul „HISinOne" (`student_service`).

### Reale Seitenstruktur (Stand 01.10.2026, gegen die echte, laufende Seite verifiziert)

Anders als zunächst angenommen gibt es **keine** drei getrennten Seiten und **kein**
„Accountdatenblatt". Alles liegt auf **einer** Seite:

```
GET/POST https://sscportal.ssc.hs-anhalt.de/qisserver/pages/cm/stu/studyService/start.xhtml
         ?_flowId=studyservice-flow&_flowExecutionKey=e{N}s{N}
```

Fünf Tabs **in einem Formular** (`studyserviceForm`), Tab-Wechsel per **vollem Formular-POST**
(kein AJAX) mit jeweils neuem `_flowExecutionKey`:

| Tab-Button                       | Inhalt                                                          |
| -------------------------------- | --------------------------------------------------------------- |
| `…:stgStudent_TabBtn` (Standard) | Studiengangsübersicht                                           |
| `…:newContactData_TabBtn`        | Kontaktdaten (Semester-/Heimatanschrift, E-Mail, Telefon)       |
| `…:billsAndPayment_TabBtn`       | Zahlungen — einzige indirekte Quelle für einen Rückmeldehinweis |
| `…:report_TabBtn`                | Bescheide / Bescheinigungen                                     |
| `…:agreements_TabBtn`            | (nicht erschlossen)                                             |

Jeder Tab zeigt oben zusätzlich den eingeklappten Block `…:fieldsetPersoenlicheData`
(Personendaten: Matrikelnummer, **Hörerstatus**, Geburtsdatum/-ort/-land, Staatsangehörigkeit —
Label/Wert-Paare über `.labelWithBG`/`.answer`, nie als Tabelle).

**Es gibt kein eigenes Feld „Immatrikulationsstatus"** — der nächstliegende Wert ist der
„Hörerstatus" in den Personendaten. **Es gibt kein eigenes Feld „Rückmeldestatus"** — ableitbar
nur indirekt aus dem Zahlungen-Tab: eine leere offene-Zahlungen-Tabelle zeigt stattdessen den Text
„Sie haben keine offenen Zahlungen!"; vorhandene Posten erscheinen in einer Tabelle mit den Spalten
Zeitraum/Verwendungszweck/Soll/Ist. Diese beiden Werte werden deshalb als **Hinweise**, nicht als
verlässliche, eigenständige Statusfelder dargestellt.

**Bescheinigungen** sind kein direkter Download-Link, sondern ein mehrstufiger Ablauf: Button
klicken (`…:job2`, AJAX, die Antwort rendert drei Komponenten: das Overlay, den Download-Slot
`jobDownload` und die Meldungsbox) → sobald das Overlay den `<p:poll>`-Widget
`…:jobDownloadPoll` enthält, pollt dieser mit seiner eigenen, festen `:poll`-Quelle und rendert
sich selbst → sobald fertig, löst die Partial-Response per JavaScript einen `GET` aus:

```
https://sscportal.ssc.hs-anhalt.de/qisserver/rds?state=docdownload&docId=…
```

Diese Antwort ist selbst ein `307`-Redirect auf eine **separate** Origin,
`https://untrust-sscportal.ssc.hs-anhalt.de`, mit demselben Pfad/Zustand, aber einem reicheren
Parametersatz (`accountId`/`hash`/`timestamp`/`docId`/`docName`) — bestätigt am 2026-10-04 durch
einen echten `Location`-Header eines tatsächlich abgeschlossenen Auftrags, zusätzlich durch den
`Content-Security-Policy`-Header des Portals selbst belegt, der genau diesen Host unter
`child-src` listet. Eine Zwischenfassung dieser Dokumentation hatte diesen zweiten Host fälschlich
für erfunden erklärt: ein `503` bei einem händischen Testabruf der URL ohne die echten,
einweg-gültigen `accountId`/`hash`/`timestamp`-Werte wurde als Beweis für eine nicht existierende
URL missverstanden, obwohl er schlicht bedeutete, dass diese Werte fehlten. `docId` ist pro Vorgang
neu und **nicht im Voraus konstruierbar** — er muss aus der Partial-Response gelesen werden. Der
Ablauf ist anhand der realen Seitenstruktur und des JSF/MyFaces-Vertrags implementiert und durch
deterministische Start-/Polling-/ViewState-/PDF-Tests abgesichert.

### Konsequenzen für die Umsetzung

- **Kein zweiter Login.** Alle Tabs nutzen dieselben, bereits für den Notenspiegel hinterlegten
  Zugangsdaten (`GradeCredentialStore`) weiter und sind nur verfügbar, wenn das aktive Portal
  `GradePortal.hisInOne` ist — das Bestandsportal HIS-QIS bietet diese Seite nicht. Es gibt dafür
  **keinen** eigenen `+`/`−`-Eintrag im Hochschulzugang-Widget; das Modul selbst verweist auf die
  Noten-Einrichtung, solange keine HISinOne-Verbindung besteht.
- **Ausdrücklich ausgeschlossen** ist jede zustandsändernde Interaktion: keine Prüfungsanmeldung,
  keine Adressänderung und kein Antrag. Erlaubt sind nur die wiederverwendete Login-Mechanik,
  Tab-Wechsel sowie Start und Polling der bewusst gewählten Bescheinigung. Dieser Bereich bleibt
  fachlich reines Lesen.
- Die Session-/Redirect-/Host-Validierung (positive `isAuthenticated`-Prüfung statt Prüfung auf
  Abwesenheit von `sessionTimeoutLoginForm`) ist aus `HisInOneGradesGateway` in die geteilte
  Komponente `HisInOneSession` extrahiert und wird identisch genutzt.
- **Kapazitätserkennung statt Annahme:** Welcher Tab-Inhalt tatsächlich vorhanden ist, wird aus
  der jeweils geladenen Seite abgeleitet, nie angenommen. Eine nicht erkannte Seitenstruktur
  ergibt einen klassifizierten Fehler (`portalStructureChanged`) und überschreibt **nie** einen
  vorhandenen Cache-Stand.
- Heruntergeladene Bescheinigungen werden **nicht dauerhaft archiviert**: Die Bytes bleiben im
  Arbeitsspeicher, begrenzt auf dieselbe Obergrenze wie bei anderen Dokument-Downloads
  (`kMaxInMemoryPreviewBytes`), und werden ausschließlich über die sichere Teilen-/Öffnen-Aktion
  des Betriebssystems weitergegeben. Die Übersichten (Bescheinigungsliste, Personendaten,
  Kontaktdaten, Studiengangsübersicht) liegen verschlüsselt lokal, exakt wie der
  Notenspiegel-Cache.
- Logout/Wipe ist an dieselbe Session-Generation gekoppelt wie Noten und Moodle: ein nach dem
  Trennen verspätet eintreffendes Ergebnis darf den lokalen Stand nie wiederbeleben.
- Der Dokument-Download läuft über eine **eigene, explizite und pfadbegrenzte Allowlist** —
  genau zwei Hosts (der Portal-Host für den ersten Sprung, `untrust-sscportal.ssc.hs-anhalt.de`
  für den zweiten, siehe oben), aber eng auf ausschließlich HTTPS, Standardport, `/qisserver/rds`
  und `state=docdownload` geprüft und als **geordnete** Route je Download erzwungen: Einstieg nur
  auf dem Portal-Host, jeder folgende Redirect nur auf dem `untrust-`-Host, nie zurück (bei den
  Druck-Buttons der Notenübersicht ist davor nur der Umweg über die Notenübersichtsseite selbst
  erlaubt), getrennt von der allgemeinen Session-Allowlist gehalten
  (AGENTS.md §2: „kein gemeinsamer Pool"). Der Download läuft im selben kurzlebigen Cookie-Jar wie
  Job-Start und Polling. Andere Pfade, Statuswerte, Ports, User-Info oder Antwort-Hosts werden
  abgewiesen; es gibt keine generische Freigabe für von der Antwort genannte Hosts.
- **Die rotierende `javax.faces.ViewState` zwischen Polls hat eine eigene, dynamische
  `<update>`-Id**, z. B. `j_id__v_7:javax.faces.ViewState:1`, nie die bloße Zeichenkette
  `javax.faces.ViewState` — bestätigt 2026-10-04 aus einer echten Poll-Antwort. Eine Erkennung, die
  exakt auf die bloße Zeichenkette anankert, trifft nie und sendet auf jedem weiteren Poll
  unbemerkt den veralteten ersten ViewState erneut.

## Sicherheit (für beide Portale identisch)

- **Nur HTTPS**, **nur** der jeweils angeheftete Host. Ein Redirect auf einen anderen Host oder
  auf HTTP wird abgebrochen (`tlsOrHostRejected`). Zertifikatsprüfung ist **nie** deaktiviert;
  es gibt **kein** „accept all certificates".
- Dynamische Session-Werte (`asi` bzw. `authenticity_token`/`ViewState`) werden **aus der
  aktuellen Sitzung** übernommen, **nie** fest einprogrammiert oder persistiert.
- Cookies liegen **nur im Arbeitsspeicher** (In-Memory-Cookie-Jar, pro Abruf). Im `finally` wird
  der jeweilige Portal-Logout aufgerufen und der Cookie-Jar geleert.
- **Nichts** wird geloggt: keine Zugangsdaten, Cookies, Session-Tokens oder HTML. Fehler sind
  klassifizierte `GradeFailure`-Werte; `toString()` enthält nur die Kategorie.
- Zugangsdaten liegen **ausschließlich** im Keychain/Keystore (`flutter_secure_storage`), ohne
  unsicheren Fallback. Das Passwort wird **erst unmittelbar vor** einem Portalaufruf gelesen und
  **nie** dauerhaft im State/Controller gehalten. Der öffentliche Account-State enthält höchstens
  Benutzername und aktives Portal, **nie** das Passwort.
- Ein optionaler zentraler Hochschulzugang kann dasselbe Passwort getrennt im gerätegebundenen
  Keychain/Keystore halten. Er ist nur eine lokale Eingabehilfe: `+` übergibt die Identität nach
  Nutzeraktion an diese Portalwahl; es entsteht keine gemeinsame SSO-Sitzung.

## Portalwahl

Studierende wissen nicht, welches Portal ihr Studiengang nutzt.

- Bei der Einrichtung probiert die App **`hisInOne`, dann `hisQisLegacy`**
  (`kGradePortalTryOrder`). Sie nimmt das erste Portal, das Login **und** einen nicht leeren
  Notenspiegel liefert.
- Liefert das erste Portal einen Login, aber eine leere Liste, wird das zweite probiert. Sind
  beide leer, bleibt das erste erfolgreiche Portal aktiv (bestehende Meldung „Es wurden noch
  keine Noten gefunden.").
- **Höchstens zwei Loginversuche** pro Einrichtung (`kMaxSetupLoginAttempts`) — nie automatisch
  erneut probiert.
- Ein Fehler, der **ein Portal** betrifft (`invalidCredentials`, `portalStructureChanged`,
  `portalUnavailable`, `sessionExpired`), lässt Portal 2 genau einmal probieren. Der Fehler wird
  gemerkt und nur dann gemeldet, wenn **kein** Portal funktioniert.
- Ein Fehler der **Geräteseite** (`networkUnavailable`, `timeout`, `tlsOrHostRejected`,
  `secureStorageUnavailable`) bricht sofort ab — über dieselbe kaputte Verbindung kann das
  zweite Portal nur genauso scheitern.
- Grund für die Durchreichung: HISinOne akzeptiert die Zugangsdaten von Konten, deren
  Leistungen noch in HIS-QIS liegen. Ein harter Abbruch beim ersten Portal ließ diese Konten
  ohne jede Note zurück.
- Das Ergebnis wird persistiert (`GradePortalStore`, **dieselbe** sichere Ablage wie die
  Zugangsdaten) — jede weitere Synchronisation spricht nur noch dieses eine Portal an.
- **HISinOne ist das Standardportal.** Ein **bestätigt fehlender** Portalwert (Altkonto aus der
  Zeit vor der Portalwahl) wird einmalig auf `hisInOne` umgestellt und gespeichert. Wie bei jedem
  Portalwechsel wird dabei zuerst der lokale Notencache des bisherigen Portals verworfen: Dessen
  Noten erscheinen nie unter HISinOne, und der erste HISinOne-Sync meldet keine fremden Noten als
  „neu“. Scheitert das Verwerfen, bleibt der Fehler sichtbar und der nächste Start versucht es
  erneut. Vor der ersten Anmeldung zeigt auch der Gateway-Rückfall auf HISinOne. Der Umschalter
  „Prüfungsportal wechseln“ bleibt für Konten, deren Leistungen noch in HIS-QIS liegen. Ein
  Lesefehler des Keychain/Keystore oder ein unbekannter gespeicherter
  Wert ergibt dagegen den klassifizierten Fehler `secureStorageUnavailable` mit „Erneut
  versuchen“ — nie „abgemeldet“, nie einen stillen Portalwechsel und nie den Nachhol-Wipe von
  Wallet und Studienservice-Cache, der nur bei bestätigt fehlenden Zugangsdaten läuft.
- Im Notenbereich gibt es einen sichtbaren, faktischen Umschalter „Prüfungsportal wechseln" mit
  Anzeige des aktiven Hosts. Ein Wechsel verwirft den lokalen Cache und synchronisiert neu.
- „Noten-Verbindung und lokale Noten löschen" entfernt auch die Portalwahl in **einem** Schritt,
  behält aber einen optionalen zentralen Hochschulzugang für andere Dienste.

## Lokaler, verschlüsselter Notencache

- Die Noten werden in einer **verschlüsselten** Hive-CE-Box gespeichert
  (`campus_grades_cache_v2`, Schlüssel `grades.cache.key.v2`), geöffnet mit einem zufälligen
  **256-Bit-AES-Schlüssel** (`Hive.generateSecureKey()`, CSPRNG). **Nur** dieser Schlüssel liegt
  im Keychain/Keystore.
  - Die Box wurde von `v1` auf `v2` gehoben, weil `GradeEntry` für HISinOne neue Felder
    bekommen hat (`path`, `module`, `extras`). Migration = **verwerfen und neu laden**: `v1` ist
    schlicht ein anderer, nun ungenutzter Box-Name — er wird nie gelesen, es gibt also keinen
    Decodier-Schritt, der fehlschlagen könnte. Das Öffnen der `v2`-Box schlägt **nie** wegen
    `v1`-Inhalten fehl; die App startet einfach mit einem leeren Cache und lädt neu, wie bei
    jedem anderen Cache-Fehltreffer auch.
- **Keine** Noten in einer unverschlüsselten Box oder als JSON in SharedPreferences.
- „Noten-Verbindung und lokale Noten löschen" entfernt vollständig aus dem **Notendienst**:
  Benutzername, Passwort, aktive Portalwahl, Cacheinhalt, Cache-Schlüssel,
  Synchronisationszeitpunkte, Sitzungsspuren und den State. Die separate Komplettlöschung in den
  Einstellungen entfernt nach allen Dienst-Wipes auch die zentrale Identität.
- Eine leere, ungültige oder fehlgeschlagene Portalantwort **überschreibt den letzten
  erfolgreichen Cache nie** — nur ein verifizierter Notenspiegel wird geschrieben. Ein
  Portalwechsel ist die einzige absichtliche Ausnahme: er verwirft den Cache explizit, weil ein
  Bericht vom falschen Portal nie als aktuell gelten darf.
- Der Cache speichert weiterhin den **Rohbericht** je Portal unverändert (bei HISinOne: JEDE
  Baumzeile inklusive Modul-/Wurzelknoten und der `C-Sammelkonto`-Zeile, mit `module`/`isLeaf`
  angereichert — siehe Parserabschnitt oben; das Blattfiltern passiert erst in der Darstellung).

## Synchronisation — 24-Stunden-Regel

Unverändert für beide Portale: kein Hintergrund-Polling, kein Timer, kein Backend-Cron.
Automatisch (lazy) beim Öffnen des Bereichs, getrennte Zeitstempel für letzten Versuch und
letzten Erfolg, 24-Stunden-Sperre für automatische Versuche, manueller Refresh umgeht sie,
Single-Flight bei parallelen Auslösern. Details unverändert gegenüber der bisherigen Fassung.

Nach einem **erfolgreichen** Abruf vergleicht die App den neuen Bericht lokal mit dem vorherigen
erfolgreichen Cache. Eine bisher leere oder neu hinzugekommene Blattzeile mit numerischer Note oder
„unbenotet bestanden“ löst bei aktivierten lokalen Benachrichtigungen den neutralen Hinweis
„Neue Note eingetragen“ aus. Der erste Bericht legt nur die Baseline an; geänderte vorhandene Noten
und neu berechnete Aggregatzeilen werden nicht als neue Note gemeldet. Es gibt keinen
Hintergrundabruf und keine Echtzeitgarantie. Details:
[`academic-updates-and-document-wallet.md`](academic-updates-and-document-wallet.md).

## Offline-Dokumenten-Wallet

Eine im Dokumentbetrachter geöffnete Immatrikulationsbescheinigung oder Leistungsübersicht kann
bewusst verschlüsselt offline gespeichert werden. Andere Bescheinigungsarten und Listen fehlender
Leistungen werden nicht angeboten. Je Art ersetzt eine neue PDF die alte; beim Konto- oder
Portalwechsel sowie bei „Noten-Verbindung und lokale Noten löschen“ wird die Wallet verifiziert
mit entfernt. Die Dokumente werden nicht automatisch heruntergeladen und verlassen das Gerät
nicht. Details und Limits stehen in
[`academic-updates-and-document-wallet.md`](academic-updates-and-document-wallet.md).

Zusätzlich: Ein **leerer** Bericht überschreibt einen **nicht leeren** Cache nie. Liefert das
Portal plötzlich nichts, wo gestern noch Leistungen standen, heißt das nie „die Noten sind weg",
sondern Konto verschoben, Sitzung still verloren oder Seite geändert. Cache und
`lastSuccessfulSync` bleiben stehen, die Abweichung wird als `portalStructureChanged` gemeldet.
Ist noch **kein** Cache vorhanden, wird ein leerer Bericht normal übernommen — das ist der
legitime Fall „noch keine Noten".

## Darstellung: Durchschnitt, Gruppierung und ausgeblendete Zeilen

Beide Portale mischen unterschiedliche Dinge in dieselbe Antwort — HIS-QIS eine flache Tabelle
mit Sonderzeilen, HISinOne einen Baum mit Modul- und Wurzelknoten. Die App trennt das einmal
fachlich (`grade_projection.dart` für die HIS-QIS-Sonderzeilen; der HISinOne-Parser selbst für
die Baumebenen), statt in der Oberfläche gegen Zeichenketten zu vergleichen.

- **Credit-Sammelkonto / C-Sammelkonto → „Durchschnitt" / „Average".** Der Wert dieser Zeile
  **ist** der Durchschnitt. Die App übernimmt ihn unverändert und **berechnet keinen eigenen**.
  Angezeigt als eigene Zeile über der Liste, nicht als Prüfung.
- **Zulassung zur Abschlussarbeit** (nur HIS-QIS) wird nicht angezeigt.
- **Alles andere bleibt stehen**, auch unbekannte Zeilentypen/Statuscodes.
- **HISinOne-spezifisch:** Die Liste zeigt nur die Blattzeilen (echte Prüfungsergebnisse,
  `GradeEntry.isLeaf`), gruppiert unter dem Titel des jeweiligen Elternknotens als
  Abschnittsüberschrift (`GradeEntry.module`) — gefiltert in der Darstellung, **nicht** im
  Parser, damit `C-Sammelkonto` als innerer Knoten trotzdem als Durchschnitt gefunden wird. Das
  Detail-Sheet zeigt zusätzlich die Modulbezeichnung und die `extras`-Felder als Label/Wert-Paare
  mit den originalen Portalüberschriften. Bewusst **keine** aufwendigere Baumdarstellung.

Die Zuordnung ist unempfindlich gegen Groß-/Kleinschreibung, Leerzeichen und Bindestrich-
Varianten.

## Bekannte Fragilität (inoffizielle HTML-Integration)

Keines der beiden Portale bietet eine offizielle JSON-API; Login und Notenspiegel sind HTML.
Die Integration ist daher **inhärent fragil**:

- Beide Parser identifizieren ihre Tabelle über **erwartete Spaltenüberschriften** bzw. eine
  gepinnte Container-ID, **nicht** über Tabellenreihenfolge allein.
- Ändert die Hochschule eines der Portale, wird die Struktur nicht erkannt → klassifizierter
  Fehler `portalStructureChanged`, verständliche lokalisierte Meldung, **kein** Überschreiben
  des Caches, **kein** Loggen der Antwort.
- **Vorgehen bei Portaländerungen:** die Header-/Container-Erkennung in `qis_html_parser.dart` /
  `legacy_qis_gateway.dart` bzw. `his_in_one_html_parser.dart` / `his_in_one_grades_gateway.dart`
  anpassen, die anonymisierten Fixtures unter `test/features/grades/grade_fixtures.dart` bzw.
  `test/features/grades/his_in_one_fixtures.dart` aktualisieren, Tests grün machen.
- **Vor einer Veröffentlichung** sollte möglichst eine **Abstimmung mit der Hochschule Anhalt**
  über die automatisierte Nutzung **beider** Prüfungsportale erfolgen. Dies ist ein offenes
  Release-Gate.

## Screenshots und App-Switcher-Vorschau — überall erlaubt

Entschieden: **Jeder Bildschirm der App darf auf Android und iOS aufgenommen werden.** Die App
setzt weder Androids `FLAG_SECURE` noch einen eigenen iOS-Überleger für die App-Switcher-Vorschau
ein. Das gilt ausdrücklich auch für die drei Anmeldebildschirme (Mail, Noten und Moodle), das
Antragsformular, die Notenübersicht, Mailinhalte und alle Aufgabenansichten.

Damit bleiben Screenshots, Bildschirmaufnahmen und die normalen Vorschauen des Betriebssystems
appseitig uneingeschränkt. Passwortfelder verwenden weiterhin die normale verdeckte Darstellung;
Zugangsdaten bleiben im gerätegebundenen Keychain/Keystore und sensible lokale Inhalte bleiben
verschlüsselt. Diese Schutzmechanismen sind von der Screenshot-Entscheidung unabhängig.

Ein Quelltest prüft, dass in Flutter kein Screenshot-Schutz angefordert wird, Android kein
gesichertes Fenster setzt und iOS keinen Capture- oder App-Switcher-Überleger registriert.

## Schichten

```
features/grades/
  domain/         GradePortal, GradePortalProfile (Interface, je EIN Host pro Portal),
                  LegacyQisProfile, HisInOneProfile (inkl. allowsDocumentDownload),
                  GradeCredentials, Grade/GradeEntry/ExamStatus (typsicher, inkl.
                  path/module/extras), GradeReport (inkl. examReports), ExamReportOffer/
                  ExamReportDownloadResult, ExamReportGateway, GradeFailure, Clock,
                  decimal_parsing, Ports (Gateway, CredentialStore, PortalStore, CacheStore)
  data/           QisHtmlParser / LegacyQisGradesGateway (HIS-QIS), HisInOneHtmlParser /
                  HisInOneGradesGateway (HISinOne, Baum + ExamReportGateway-Implementierung),
                  SecureGradeCredentialStore, SecureGradePortalStore,
                  EncryptedGradeCache (+ Codec, v2, inkl. examReports)
  application/    Provider (inkl. Per-Portal-Gateways + aufgelöstes gradesGatewayProvider),
                  GradeAccountController (Portalwahl, Wechsel, Löschen), GradesController
                  (24h-Policy, Single-Flight)
  presentation/   Gate, Setup, Overview (Portal-Umschalter, Gruppierung), Tile, Detail-Sheet
                  (Modul + extras), Fehler-Mapping
```

UI und Controller kennen **keine** Dio-, Cookie- oder HTML-Typen — alles liegt hinter
`GradesGateway`, das für beide Portale identisch bleibt. Tests nutzen ausschließlich
anonymisierte Fixtures, In-Memory-Fakes und einen gescripteten HTTP-Adapter; **kein** Test
kontaktiert ein echtes Portal.

## Automatisierte Tests

```bash
flutter test test/features/grades/
```

- `qis_html_parser_test.dart` — HIS-QIS: Header-Erkennung, deutsche Dezimalnoten,
  `0,0`+bestanden → unbenotet bestanden, leere Noten, Datum `dd.MM.yyyy`, Whitespace/Entities,
  unbekannte Status, fehlende Pflichtspalten → `portalStructureChanged`, keine Dedup.
- `legacy_qis_gateway_test.dart` — HIS-QIS: form-urlencoded `asdf`/`fdsa`, HTTPS-Host-Allowlist,
  Redirect-Ablehnung (anderer Host / HTTP), Login-Erkennung (nicht nur HTTP 200), `asi` aus
  Session-Links, Logout auch bei Fehlern, keine Secrets/HTML in Fehlern.
- `his_in_one_html_parser_test.dart` — HISinOne: Hidden-Felder + Button über ID-Suffix
  (inkl. Fallback), Blatt-Erkennung über Pfade (**jede** Zeile landet im `GradeReport`, auch
  Modul-/Wurzelknoten und der nicht-blättrige `C-Sammelkonto`-Knoten — `isLeaf` unterscheidet
  sie), mehrere Wurzeln, Gruppierung unter Modul, Punkt-Dezimalzahlen, `dd.MM.yyyy HH:mm:ss`,
  `C-Sammelkonto` → Durchschnitt trotz `isLeaf == false`, unbekannter Status bleibt sichtbar,
  Studienverlauf-Decoy nie getroffen, fehlende Pflichtspalte → `portalStructureChanged`,
  `isAuthenticated` erkennt eine eingeloggte Seite auch dann, wenn das versteckte
  `sessionTimeoutLoginForm` (`asdf`/`fdsa`) noch im Markup steht; `readOverview` unterscheidet
  `empty` / `rendered` / `expandable` / `unrecognised` und liest einen Baum auch dann, wenn er
  direkt unter dem Abschnitt `examsReadonly:overviewAsTreeReadonly` liegt (Stand 24.08.2026,
  ohne die alte innere ID `…:tree:ExamOverviewForPersonTreeReadonly`).
- `his_in_one_grades_gateway_test.dart` — HISinOne: form-urlencoded `asdf`/`fdsa`,
  Erfolgs-/Fehlsignal per `Location`, Redirect-Host-Validierung vor der Signal-Prüfung,
  Hidden-Felder aus der Seite (nicht hart kodiert), Logout auch bei Fehlern; leerer Abschnitt
  „Leistungsdaten" → leerer Bericht ohne Aufklapp-POST, Baum ohne Aufklapp-Button → direkt
  geparst.
  **Regressionstest:** eine authentifizierte Landing-Page mit sichtbarem `sessionTimeoutLoginForm`
  gilt als erfolgreicher Login (nicht als `invalidCredentials`) — der Bug, der jeden Login,
  auch mit korrekten Zugangsdaten, scheitern ließ.
- `grade_portal_selection_test.dart` — Reihenfolge `hisInOne` → `hisQisLegacy`, „Login ok aber
  leer" → zweites Portal, maximal zwei Loginversuche, Persistenz, Wechsel verwirft Cache,
  Löschen entfernt auch die Portalwahl, Altkonten ohne gespeicherte Portalwahl fallen auf
  `hisQisLegacy` zurück; `portalStructureChanged`/`portalUnavailable` auf Portal 1 lassen
  Portal 2 probieren, beide strukturell defekt → Fehler wird gemeldet und **nichts**
  persistiert, `tlsOrHostRejected` bricht weiterhin sofort ab.
- `grade_cache_migration_test.dart` — `v1`-Boxinhalte werden nie gelesen; das Öffnen der
  `v2`-Box schlägt dadurch nie fehl.
- `grade_controller_test.dart` — Setup speichert erst nach Erfolg, kein Passwort im State,
  Secure-Storage-Fehler, Löschen wischt alles; 24h-Policy, Single-Flight, manueller Refresh,
  Fehler behält Cache, `lastSuccessfulSync` nur bei Erfolg; ein **leerer** Bericht überschreibt
  einen nicht leeren Cache nie (Cache und `lastSuccessfulSync` bleiben stehen), ohne
  vorhandenen Cache wird ein leerer Bericht normal übernommen.
- `grade_ui_test.dart` — „Noten" unter Mehr, Setup/Consent-Validierung, Anmeldung enthüllt
  Overview, Cache ohne Auto-Sync, Löschbestätigung; Bescheinigungen-Abschnitt erzeugt und öffnet
  ein PDF auf HISinOne, ein abgelehntes Dokument zeigt den Diagnosecode.
- `his_in_one_html_parser_test.dart` (zusätzlich) — `findExamReports` liest die
  `submit_print_pdf`-Buttons (Id + Beschriftung), `buildExamReportPostRequest` baut den vollen
  Formular-POST inkl. Hidden-Feldern und `DISABLE_VALIDATION=true`.
- `his_in_one_grades_gateway_test.dart` (zusätzlich) — ein Abruf füllt `entries` **und**
  `examReports` aus derselben Seite; `downloadExamReport` postet, folgt BEIDEN Redirect-Sprüngen
  (Portal-Host → `untrust-sscportal`-Host) und prüft die PDF-Magicbytes; ein Button, der auf
  einer frisch gelesenen Seite nicht mehr auftaucht, wird vor jedem POST abgelehnt.
- `his_in_one_profile_test.dart` — `allowsDocumentDownload` lässt `state=docdownload` unter
  `/qisserver/rds` auf BEIDEN gepinnten Hosts zu (Portal-Host, `untrust-sscportal`-Host) und lehnt
  jeden dritten Host, auch einen Subdomain-Treffer auf den `untrust-`-Host, ab.
- `grade_cache_migration_test.dart` (zusätzlich) — `examReports` übersteht einen Schreib-/
  Lesedurchlauf; ein vor dieser Änderung zwischengespeicherter Bericht (reines Array statt
  Wrapper-Objekt) liefert beim Lesen eine leere `examReports`-Liste statt eines Fehlers.
