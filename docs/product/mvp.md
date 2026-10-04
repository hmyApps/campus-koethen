# Campus Köthen — MVP-Definition

Stand: 25.08.2026 · Status: **in Entwicklung, nicht veröffentlicht**

---

## 0. Unabhängigkeitshinweis / Independence notice

**Deutsch**

> Campus Köthen ist keine offizielle App der Hochschule Anhalt. Die App wird von Erik Engler über
> die App Stores bereitgestellt. Das Campus-Backend und die redaktionellen Inhalte
> werden von der rechtlich selbstständigen
> Studierendenschaft der Hochschule Anhalt betrieben. Die Hochschule Anhalt selbst ist weder
> Entwicklerin noch Betreiberin der App.

**English**

> Campus Köthen is not an official Hochschule Anhalt app. The app is distributed
> through app stores by Erik Engler. The Campus backend and editorial content are operated by the
> legally independent student body of Hochschule Anhalt.
> Hochschule Anhalt itself neither develops nor operates the app.

Dieser Hinweis ist verbindlich und erscheint identisch in README, About-Screen und den rechtlichen
Seiten der App.

---

## 1. Produktidentität

|                            |                                                                                                 |
| -------------------------- | ----------------------------------------------------------------------------------------------- |
| Projektname                | Campus Köthen App                                                                               |
| Sichtbarer App-Name        | Campus Köthen                                                                                   |
| Bundle-ID / Application ID | `dev.erikengler.campuskoethen`                                                                  |
| Lizenz                     | `AGPL-3.0-only`                                                                                 |
| Copyright                  | Copyright © 2026 Leviora Studio und Jona Loreen Sommer                                          |
| App-Anbieter               | Erik Engler, handelnd unter „Leviora Studio“                                                    |
| Backend und Redaktion      | Studierendenschaft der Hochschule Anhalt, vertreten durch den Sprecherrat des Studierendenrates |
| Sprachen                   | Deutsch (Standard/Fallback), Englisch                                                           |

## 2. Zielgruppe und Nutzen

Studierende am Campus Köthen erhalten in einer App:

1. **News** aus mehreren, frei wählbaren redaktionellen Kanälen.
2. **Kalender**, der Stundenplan, öffentliche Campus-Kalender und Moodle-Deadlines in einer
   Ansicht zusammenführt — die Zusammenführung geschieht ausschließlich auf dem Gerät.
3. **Mensapläne** beider Köthener Mensen mit fester Filtertaxonomie für Ernährungsweise und
   Allergene.
4. **Kontakte** zu Anlaufstellen, funktional statt personenzentriert.
5. **Persönliche Dienste** — Studentenpostfach, Notenspiegel, Moodle und Nextcloud — jeweils direkt vom Gerät
   zum offiziellen Anbieter, ohne dass ein Server dieses Projekts beteiligt ist.

Die App funktioniert **ohne Nutzerkonto bei diesem Projekt**. Alle Präferenzen bleiben auf dem
Gerät. Für die persönlichen Dienste meldet man sich beim jeweiligen Hochschulsystem an; diese
Zugangsdaten verlassen das Gerät nur in Richtung des offiziellen Anbieters.

Optional kann eine zentrale lokale Hochschulidentität hinterlegt werden. Sie ist kein Konto und
keine gemeinsame SSO-Sitzung, sondern erspart nach einem bewussten `+` die erneute Passworteingabe
für Mail, Moodle oder Noten. Gespeichert wird erst nach Einwilligung und erfolgreicher Prüfung
mindestens eines Diensts, ausschließlich im gerätegebundenen Keychain/Keystore.
Nextcloud ist davon technisch getrennt: `+` startet den offiziellen Login Flow v2 im Systembrowser,
damit die App das Hochschulpasswort nie erhält und nur ein widerrufbares App-Passwort speichert.

## 3. Umfang

### 3.1 Enthalten

**Öffentliche Inhalte über die Campus API**

- News als endlos nachladender Inline-Feed mit dynamischer Kanal-Auswahl — die Artikel klappen
  in der Liste auf, es gibt **keine** Detailseite
- Mensa-Auswahl und Speiseplan mit Tagesnavigation, festem Trait-/Allergenfilter und dem Preis
  **einer** gewählten Personengruppe
- Freiwillige, rein lokale Guthabenprüfung einer unterstützten Mensakarte per NFC. Der Tap auf
  „Guthaben prüfen“ ist die bewusste Nutzeraktion und startet ohne zweite Bestätigung; Erklärung,
  Live-Status und Abbrechen bleiben während des Scans sichtbar. Android kann zusätzlich eine außerhalb der App
  erkannte ISO-DEP-Karte nach der systemseitigen Öffnen-Aktion unmittelbar lesen. iOS unterstützt
  nur den manuellen Einstieg innerhalb einer laufenden Core-NFC-Sitzung. Kartenkennung, rohe
  Kartenantwort und Saldo werden weder gespeichert noch geloggt oder übertragen.
- Kontaktbereiche und Kontaktdetail sowie eine **lokale Kontaktsuche** über einen einmal geladenen
  Suchindex (`/v1/contact-areas/search-index`) — kein Request pro Tastendruck, kein Nachladen pro
  Bereich
- **Gruppenstundenplan** aus der öffentlichen WebUntis-Ansicht — vollständig umgesetzt, aber
  serverseitig über `WEBUNTIS_ENABLED` **standardmäßig deaktiviert**, bis die Nutzung
  organisatorisch freigegeben ist (siehe Release-Gates). Er erscheint als Quelle im lokalen
  Kalender und als eigenes, über die Navigationseinstellungen anheftbares Studienmodul; beide
  Ansichten teilen Kursgruppe, Filter, Datenprovider und Details.
- **Öffentliche Google-Kalender** über deren öffentlichen ICS-Feed, redaktionell in Strapi
  gepflegt — vollständig umgesetzt, aber über `PUBLIC_CALENDAR_ENABLED` **standardmäßig
  deaktiviert**; ohne Google API Key, ohne OAuth, ohne Anbindung persönlicher Google-Konten

**Quellenübergreifender Kalender**

- Explizite Umschaltung **Tag ↔ Woche ↔ Liste**; die Wochenansicht zeigt standardmäßig Montag
  bis Freitag, das Wochenende ist ein lokaler Schalter
- Quellen: Stundenplan (Campus API), öffentliche Kalender (Campus API), Moodle-Deadlines (direkt),
  optional persönliche Exchange-Termine (direkt) sowie lokale gemerkte Events und Mensafavoriten
- Zusammenführung **ausschließlich lokal auf dem Gerät**; Quellen sind isoliert — ein Fehler einer
  Quelle blendet die anderen nicht aus, sondern erscheint als eigenes Banner
- „Kalender verwalten": lokale Auswahl der öffentlichen Kalender
- Granulare Quellenschalter gelten einheitlich für Tag, Woche, Liste und Export. Der
  Benachrichtigungsumfang bleibt davon getrennt und folgt den Benachrichtigungseinstellungen sowie
  der Auswahl öffentlicher Kalender; der Stundenplan-Lesson-Info-Filter gilt weiterhin auch für die
  Tageszusammenfassung. Exchange ist standardmäßig aus und wird zusätzlich im Onboarding sowie in
  den Mail-Einstellungen angeboten. Weil Widget- und Benachrichtigungs-Payloads persistiert werden,
  enthalten beide keine persönlichen Exchange-Termine.

**Persönliche Dienste, direkt vom Gerät**

- **Studenten-E-Mail** (`mail.hs-anhalt.de`): Posteingang mit verschlüsseltem Offline-Cache, alle
  Server-Ordner, serverseitige Suche über IMAP SEARCH, Anhänge anzeigen und in der App öffnen,
  optional lesender Exchange-Standardkalender ohne persistenten Termincache,
  Verfassen, Antworten und Allen antworten — reiner Text
- **Notenspiegel** (HIS-QIS **und** HISinOne): Notenübersicht mit Detailansicht, verschlüsselter
  lokaler Cache, 24-Stunden-Regel mit manueller Übersteuerung. Auf HISinOne zusätzlich **nur
  lesend**: die drei festen Bescheinigungs-Druck-Buttons direkt auf der Notenübersichtsseite
  (volle Formularabgabe, kein AJAX) sowie eine Seite „Studienservice" mit mehreren per Voll-POST
  gewechselten Tabs: Bescheinigungsübersicht, Personendaten (inkl. Hörerstatus) und Kontaktdaten,
  Studiengangsübersicht, sowie ein aus den Zahlungen abgeleiteter Rückmeldehinweis — dieselben
  Zugangsdaten, kein zweiter Login. Bescheinigungen werden — aus beiden Quellen — zweistufig
  abgerufen: zuerst `sscportal.ssc.hs-anhalt.de/qisserver/rds?state=docdownload`, das per
  Redirect weiter auf die separate Origin `untrust-sscportal.ssc.hs-anhalt.de` desselben
  Pfads/Zustands führt; keine Prüfungsanmeldung, keine Adressänderung, keine sonstige Mutation
- **Moodle**: Kurse, Materialien, Aufgaben mit Abgabestatus, Ankündigungen und Deadlines —
  **ausschließlich lesend**, verschlüsselter lokaler Cache, 24-Stunden-Regel
- **Nextcloud-Dateiexplorer** (`cloud.hs-anhalt.de`): Login Flow v2 im Systembrowser, Ordnernavigation
  und bewusstes Laden von Dateien bis 25 MiB über WebDAV — **ausschließlich lesend**, ohne
  persistenten Datei- oder Metadatencache. Das App-Passwort liegt nur im Keychain/Keystore.
- **Zentraler Hochschulzugang**: optionale lokale Eingabehilfe für Mail, Moodle und Noten mit
  getrennten `+`-/`−`-Aktionen; keine gemeinsame Sitzung und kein Campus-Backend-Konto
- **Ersteinrichtung**: eigener Kalender-Schritt für Stundenplan, Moodle-Fristen, Exchange-Termine,
  gemerkte Events, Lieblingsspeisen und öffentliche Kalender. Danach kann die gemeinsame Hochschulkennung einmal
  eingegeben und auf einem getrennten Schritt bewusst für Mail, Moodle und/oder Noten verwendet
  werden. Die Eingabe bleibt bis zur erfolgreichen Prüfung mindestens eines gewählten Diensts
  flüchtig; erst danach wird sie mit Einwilligung im Keychain/Keystore gespeichert.
- **Anträge & Feedback**: Finanzanträge **und** Feedback gehen **direkt** an die öffentliche API
  des Gremiensystems des Studierendenrats. Der Dienst ist als einziger der fünf nicht
  nutzerauthentifiziert; ausschlaggebend ist der Inhalt — eine Einreichung trägt den Namen der
  antragstellenden Person und eine Kopie des Studierendenausweises.
  - Der Antrag fragt genau das, was die Schnittstelle nimmt: Standort, Antragsgegenstand,
    Antragsteller und vier Dateifelder. Kein Betrag, keine Kategorie, kein Verwendungszweck — die
    Zahlen stehen im angehängten PDF.
  - Feedback fragt Bereich, einen optionalen Namen und den Text. Bleibt das Namensfeld leer, wird
    es weggelassen; das Gremium vermerkt solche Einreichungen selbst als „Anonym".
  - Eingereichte Vorgänge bleiben lokal nachverfolgbar. Ihr Stand wird nativ angezeigt — mit dem
    öffentlichen Statusnamen des Gremiums, Hinweisen, Zeitpunkten und Dokumenten im
    App-eigenen Betrachter. Ein Statusname wird nie in ein App-Vokabular übersetzt.
  - Entwürfe, Anhänge und Vorgänge liegen **verschlüsselt** auf dem Gerät; der Statuslink ist ein
    Bearer-Credential, wird niemals geloggt, geteilt oder in eine Route aufgenommen.
  - **Grenze der Schnittstelle:** Nachreichungen und Quittungen meldet die API zwar als möglich,
    bietet dafür aber keinen öffentlichen Endpunkt. Die App sagt das, statt es zu simulieren.
    Dasselbe gilt für den Bereich „Wichtige Dokumente" des Webformulars.

**Lageplan (fiktive Demonstration)**

- Zoombarer Demo-Etagenplan unter „Mehr → Lageplan" mit **30 fiktiven Räumen** (B.201–B.230)
- Raumsuche über Raumnummer, normalisierte Raumnummer (`B.201` = `B201`), Anzeigename sowie
  Gebäude- und Etagenbezeichnung
- Ein Treffer öffnet die Etage, rückt den Raum in den Blick und hebt ihn hervor —
  **nie** allein über Farbe
- **Räume sind auf dem Plan antippbar**; ein Tap wählt denselben Raum über denselben Weg aus wie
  ein Suchtreffer. Getroffen wird die gebündelte Geometrie, nicht ein SVG-Pfad
- Räume sind mit Kontaktpersonen und Kontaktbereichen verknüpfbar; ein Tippen öffnet den Plan
- Geometrie ist ein selbst erstelltes, gebündeltes Asset; Bezeichnungen kommen über die Campus API
- Der Democharakter ist in der App sichtbar und in DE/EN formuliert

**Lokales und Rahmen**

- Lokale Aufgabenliste unter „Mehr → Aufgaben" — rein auf dem Gerät, ohne jede Netzbeteiligung
- Lokale Einstellungen: Sprache, Theme, Kanal-Abos, bevorzugte Mensa, gewählte Stundenplangruppe,
  Kalenderauswahl, Anhänge-Download für E-Mail
- Offline-/Cache-Verhalten mit klarer Stale-Kennzeichnung
- About, Impressums-Platzhalter, Datenschutz-Platzhalter
- Deutsch und Englisch in App, CMS und API

### 3.2 Nicht enthalten

**Produktseitig:** Nutzerkonten für die App selbst · Push-Nachrichten · globale Volltextsuche ·
mehrere Mail- oder Moodle-Konten · serverseitige Synchronisierung der lokalen Aufgabenliste

**Lageplan:** Indoor-Navigation und Wegberechnung · Live-Position · Raumbelegung und Buchung ·
**reale** Gebäude, Räume und Grundrisse · SVG-Upload nach oder -Abruf aus Strapi ·
CMS-Schreibzugang in der App · Auswertung des SVG zur Laufzeit (ein Tap trifft die Geometrie aus
dem Katalog, nicht das Bild)

**Stundenplan:** persönlicher WebUntis-Login · Stundenpläne für Lehrpersonen oder Räume ·
Raumverfügbarkeit („freie Räume") · Zusammenführen mehrerer Gruppen in einen Plan ·
Abwesenheiten und Hausaufgaben

**Moodle:** jeder Schreibzugriff — keine Abgaben, keine Forenbeiträge, keine generische
„beliebige Funktion aufrufen"-Schnittstelle

**Nextcloud:** Upload, Umbenennen, Verschieben, Löschen, Freigabelinks, frei konfigurierbare
Server und Hintergrundsynchronisation

**Kalender:** Google API Key · Google-OAuth · Google-SDK · Anbindung persönlicher Google-Konten ·
automatisches Hinzufügen von Terminen zum persönlichen Google-Konto

**Technisch:** Analytics/Tracking · Sentry oder externes Crash-Reporting · Redis · SMTP ·
automatisches Deployment · Hintergrund-Sync bei vollständig geschlossener App · IMAP IDLE ·
Backend-Proxy für E-Mail, Noten, Moodle oder Nextcloud

Die Architektur muss diese Erweiterungen ermöglichen, es wird dafür aber **kein ungenutzter Code**
gebaut.

## 4. Fachliche Anforderungen

### 4.1 News

- News entstehen ausschließlich in Strapi und werden über Draft & Publish veröffentlicht.
- Eine News kann mehreren Kanälen zugeordnet sein und erscheint dennoch **nur einmal** in der Liste.
- Startkanäle: `campus-news` („Campus News“) und `fb5-news` („FB5 News“), beide
  `defaultSubscribed = true`.
- Ein **neuer Kanal in Strapi erscheint ohne Flutter-Codeänderung** in der App.
- `defaultSubscribed` wird pro Kanal **genau einmal** ausgewertet — beim erstmaligen Auftauchen.
  Bewusst deaktivierte Kanäle bleiben deaktiviert, auch über App-Neustarts hinweg.
- Sind **alle** Kanäle deaktiviert, zeigt die App einen klaren Empty State und lädt **nicht**
  stillschweigend „alle News“.
- Inaktive Kanäle verschwinden aus der Auswahl, ohne gespeicherte Präferenzen zu beschädigen.
- Redaktionelle Regel: eigene Beiträge oder eigene Zusammenfassungen **mit Quellenlink**; keine
  Übernahme fremder Volltexte; nur eigene oder freigegebene Bilder.

### 4.2 Mensa

- Startmensen: `koethen-fasanerieallee` (Quelle `location_id=7`) und `koethen-lohmannstrasse`
  (Quelle `location_id=22`).
- Die Mensenliste kommt **ausschließlich** aus der Campus API. Flutter kennt keine Location-IDs.
  Eine weitere Mensa erfordert höchstens eine Backend-Konfigurationsänderung, **kein App-Release**.
- Angezeigt werden Datum, Name, Zusatztext, Beilagen, Sprint-Kennzeichen und der Preis **einer**
  Personengruppe — der, die im Filter gewählt ist; Standard ist `student`. Fehlt dieser Preis,
  sagt die Karte das, statt den Preis einer anderen Gruppe zu zeigen.
- Die **Zutatenkennzeichnungen stehen nicht auf der Karte**: Dafür ist der Filter da, und ein
  Dutzend Chips unter jedem Gericht verdeckt genau die zwei Zeilen, die sich zwischen zwei
  Gerichten unterscheiden. Marker ohne Filterentsprechung (Bio, Klima-Teller und dergleichen)
  bleiben stehen, weil sie sonst nirgends stünden.
- Gefiltert wird über die **stabilen semantischen Schlüssel** der Campus API (`traits`,
  `allergens`), nie über die Marker-Codes der Quelle. Die Taxonomie ist fest, nicht aus dem
  sichtbaren Tag abgeleitet: „keine Erdnüsse" muss dienstags dasselbe heißen wie freitags.
  Die Auswahl bleibt **ausschließlich lokal** — Allergiepräferenzen erreichen kein Backend und
  werden nirgends geloggt.
- Gerichte können als Favorit markiert werden. Favoriten filtern **nicht** und ändern die
  Reihenfolge **nicht**: Die Thekenreihenfolge ist die Reihenfolge, in der ausgegeben wird.
- **Keine Mensabilder.** `food.image_url` wird weder gespeichert noch ausgeliefert.
- Die Aktion **„Guthaben prüfen“** liest ausschließlich nach einer bewussten Nutzeraktion zwei
  fest vorgegebene, nur lesende DESFire/ISO-DEP-Kommandos. Das Ergebnis bleibt nur bis zum
  Schließen der Anzeige im Arbeitsspeicher. Fehler, ungültige Antworten und nicht unterstützte
  Karten werden als eigener Zustand gezeigt, niemals als `0,00 €`.
- Android registriert NFC nur als optionales Gerätefeature. Ein Tap auf die systemseitige
  Öffnen-Abfrage nach einer außerhalb der App erkannten ISO-DEP-Karte gilt als Nutzeraktion und
  öffnet den bereits laufenden Lesezustand ohne zweiten Tap. Auf iOS beginnt der Scan immer
  manuell aus der Mensaansicht; diese Abweichung ist eine Plattformgrenze.
- Ist der einmalig von Android übergebene Tag beim Öffnen bereits außer Reichweite, wechselt
  „Erneut versuchen“ in den aktiven Reader-Modus und wartet auf eine erneut vorgehaltene Karte;
  derselbe verbrauchte Tag wird nicht wiederverwendet.
- Der Worker synchronisiert alle zwei Stunden (`CANTEEN_SYNC_CRON="0 */2 * * *"`).
- Eine leere, ungültige oder fehlgeschlagene Quellantwort **löscht niemals** den letzten
  erfolgreichen Datenbestand.
- Die API liefert `lastSuccessfulSyncAt` und `dataStale`; die App zeigt beides verständlich an.
- Die App aktualisiert bei App-Start und App-Resume sowie zusätzlich **höchstens alle fünf Minuten**
  im Vordergrund. Im Hintergrund läuft **kein** Timer.

### 4.3 Kontakte

- Kontaktbereiche sind dynamische Strapi-Datensätze und werden ohne Codeänderung angelegt,
  sortiert, beschrieben und deaktiviert.
- Ein Bereich ist **auch ohne Kontaktperson vollständig gültig und nutzbar** (z. B. SSC,
  Studentenwerk als allgemeine Stelle).
- Eine Kontaktperson kann mehreren Bereichen zugeordnet sein.
- E-Mail, Telefon, Website und Terminlink werden über sichere Betriebssystemaktionen geöffnet.
- Fehlende Felder werden ausgeblendet statt als leere Zeile dargestellt.
- **Keine erfundenen Personen, Telefonnummern, E-Mail-Adressen oder offiziellen Aussagen.**
  Startdaten sind als Demo gekennzeichnet.
- Die **Suche** durchsucht Bereiche _und_ Personen: Namen, Rollen, Beschreibungen, Kontaktkanäle,
  Adresse, Öffnungszeiten sowie zugeordnete Räume (Nummer, Name, Gebäude, Etage). Personen sind
  eigene Treffer und nennen ihren Bereich; jeder Treffer zeigt die Fundstelle. Groß-/Kleinschreibung,
  Umlaute in beiden Schreibweisen (`pruefungsamt` und `prufungsamt`) sowie Raumnummern mit und ohne
  Satzzeichen (`B.201` = `B201`) matchen gleichermaßen. Ein leeres Suchfeld ist **kein** Filter.

### 4.4 Kalender

- Der Kalender ist ein eigener Tab und führt die aktivierten Quellen zusammen: Stundenplan und
  öffentliche Kalender über die Campus API, Moodle-Deadlines und optional Exchange-Termine direkt
  vom Gerät sowie lokale gemerkte Events und Mensafavoriten.
- Die Zusammenführung geschieht **ausschließlich lokal**. Kein Server sieht die kombinierte Ansicht.
- **Quellen sind isoliert.** Ein Moodle-Fehler beeinträchtigt den Stundenplan nicht; ein
  Campus-API-Fehler entfernt die lokal gecachten Moodle-Deadlines nicht. Jeder Fehler erscheint als
  eigenes Banner pro Quelle.
- Explizite Umschaltung zwischen **Tag**, **Woche** und **Liste**. Die Wochenansicht zeigt
  standardmäßig Montag bis Freitag; das Wochenende ist ein lokaler, versionierter Schalter.
- Öffentliche Termine tragen einen Farbpunkt **plus** Kalendername und Icon — Farbe ist nie das
  alleinige Unterscheidungsmerkmal.
- Eine neue Quelle bedeutet: ein Wert in `CalendarSource`, ein Mapper und eine Verdrahtung im
  Aggregator. Mehr nicht.
- **Kalenderauswahl:** `defaultSubscribed` wird pro Slug **genau einmal** ausgewertet — beim
  erstmaligen Auftauchen. Bewusst deaktivierte Kalender bleiben deaktiviert; ein Backend-Update
  überschreibt die Auswahl nie; keine Auswahl bedeutet keine öffentlichen Termine, niemals „alle".
- Ein neuer öffentlicher Kalender erscheint **ohne App- und ohne Backend-Änderung**, sobald er in
  Strapi veröffentlicht und einmal erfolgreich synchronisiert wurde.

### 4.5 Persönliche Dienste (direkt vom Gerät)

Gemeinsame, nicht verhandelbare Regeln für E-Mail, Noten, Moodle und Nextcloud:

- Die App spricht **direkt** mit dem offiziellen Anbieter. Campus API, Strapi und Worker sind
  **nie** beteiligt und erhalten **weder Zugangsdaten noch persönliche Inhalte**.
- Feste Host-Allowlist, vor jedem Request geprüft. Redirects auf einen anderen Host oder auf
  Klartext werden abgebrochen. Zertifikatsprüfung ist nie deaktiviert.
- Zugangsdaten und Token liegen **ausschließlich** im Keychain/Keystore. Gibt es keinen sicheren
  Speicher, wird **nicht** gespeichert und ein klarer Fehler gezeigt — kein unsicherer Fallback.
- Die zentrale Identität (eine Kennung — Benutzername oder Mailadresse, je nach Eingabe — plus
  Passwort) wird erst nach ausdrücklicher Bestätigung und erfolgreicher Dienstprüfung gespeichert.
  Dieselbe Kennung und dasselbe Passwort gelten bei der Hochschule für Mail, Moodle und
  Noten/HISinOne gleichermaßen; die App fragt sie deshalb nur einmal ab. Moodle und Noten erhalten
  die Kennung unverändert. Ausschließlich der Mail-Adapter ergänzt einen reinen Benutzernamen lokal
  zu `<Kennung>@hs-anhalt.de`; eine vollständige Mailadresse bleibt unverändert. Ein erkanntes
  früheres Drei-Feld-Schema wird vollständig gelöscht statt still migriert. Das Passwort erscheint
  nie im öffentlichen State. `+` erstellt
  nur die gewählte Dienstverbindung; `−` löscht deren Credential-Kopie/Token und Cache, behält aber
  die zentrale Identität.
- Nextcloud erhält die zentrale Identität nie. Die Anmeldung läuft im Systembrowser; nur das
  ausgegebene App-Passwort wird sicher gespeichert. Ein Abbruch oder eine vollständige Löschung
  verhindert generation-sicher, dass eine verspätete Poll-Antwort es erneut schreibt.
- Persönliche Inhalte liegen nur **verschlüsselt** lokal. Der Mailcache umfasst Kopfzeilen,
  Inhalte, den Adressindex und optional Anhangbytes; das Passwort liegt **nie** im Cache.
- Nichts davon erscheint in Logs, Exceptions, `toString()` oder Fehlermeldungen.
- Eine leere, ungültige oder fehlgeschlagene Antwort **überschreibt den letzten guten Stand nie**.
- „Verbindung und lokale Daten löschen" entfernt die dienstbezogenen Zugangsdaten beziehungsweise
  Token, Cache, Cache-Schlüssel, Zeitstempel und State logisch; ein optionaler zentraler Zugang
  bleibt bestehen. Beim Mailkonto wird Erfolg erst
  nach bestätigter Abwesenheit der persistenten Artefakte gemeldet; ein Teilfehler bleibt gesperrt
  und kann wiederholt werden. Dies ist keine forensische Secure-Erase-Zusage für Flash oder Backups.
- „Hochschulzugang vollständig löschen“ trennt alle Dienste zuerst und entfernt die zentrale
  Identität zuletzt. Scheitert ein Dienst oder der sichere Löschvorgang, wird kein voller Erfolg
  gemeldet; die Identität bleibt für den Retry erhalten. Passwortänderungen werden über
  „Zugangsdaten aktualisieren“ erneut gegen einen ausgewählten Dienst validiert.

Dienstspezifisch:

| Dienst | Anmeldung                        | Sync                                                       | Umfang                                                                   |
| ------ | -------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------ |
| E-Mail | Adresse + Passwort, sonst nichts | App-Start, Anmeldung, alle 10 Minuten, manuell             | lesen, suchen (IMAP SEARCH), Ordner wechseln, Anhänge, antworten, senden |
| Noten  | Benutzername + Passwort          | lazy beim Öffnen, höchstens 1× pro rollenden 24 h, manuell | Notenspiegel mit Detailansicht                                           |
| Moodle | Benutzername + Passwort → Token  | lazy beim Öffnen, höchstens 1× pro rollenden 24 h, manuell | Kurse, Materialien, Aufgaben, Ankündigungen, Deadlines — **nur lesend**  |
| Nextcloud | Login Flow v2 → App-Passwort | nur beim Öffnen/Navigation, manuell | Ordner und Dateien über WebDAV — **nur lesend**, kein persistenter Cache |

Kein Hintergrund-Polling, kein Timer, kein Backend-Cron. Beim Moodle-Login wird das Passwort sofort
nach dem Tokenerwerb verworfen und nie gespeichert. HTML-Mails werden zu **reinem Text** reduziert;
es gibt kein WebView, kein JavaScript und keine automatische Nachladung entfernter Bilder.

### 4.6 Lageplan

- Der Plan ist **vollständig fiktiv**. Es wird kein realer Grundriss dargestellt, und der
  Democharakter ist in der App sichtbar.
- Geometrie und die roomKey→Geometrie-Zuordnung sind **gebündelte, generierte Assets**; sie werden
  zur Laufzeit nie geladen und nie aus Strapi bezogen.
- Raumbezeichnungen und redaktionelle Texte kommen über `/v1/rooms` und werden offline gecacht.
- Technische Raumfelder sind katalogverwaltet und in Strapi serverseitig geschützt; redaktionelle
  Felder, Sichtbarkeit und Kontaktrelationen bleiben bearbeitbar.
- Ein Raum ohne Geometrie im gebündelten Plan wird als Text gezeigt, die Kartenaktion ist
  deaktiviert — nie ein Absturz.
- Weicht die `mapVersion` ab, erklärt die App das und bleibt als Liste nutzbar.
- Ein weiterer Raum, eine weitere Etage oder ein weiteres Gebäude erfordert **keine**
  Flutter-Änderung.

Details: [`../campus-map.md`](../campus-map.md).

### 4.7 Lokale Aufgabenliste

- Vollständig **auf dem Gerät**. Kein Netzaufruf, keine API, keine Synchronisierung, kein Konto.
- Erreichbar unter „Mehr → Aufgaben".

### 4.8 Sprachen

- Standard- und Fallback-Locale ist `de`.
- Die App startet auf Deutsch und erlaubt eine explizite Auswahl zwischen Deutsch und Englisch.
- Datum, Uhrzeit und Preise werden locale-gerecht formatiert.
- **Externe Mensa-Gerichtsnamen werden nie erfunden übersetzt.** Liefert die Quelle nur Deutsch,
  bleibt der Quelltext erhalten und wird als Fallback markiert (`translationFallback`).
  API-eigene Labels (Mensanamen, Preisgruppen, Marker, Fehlertexte) sind zweisprachig.

### 4.9 Offline und Cache

Lokal gespeichert werden:

| Daten                                                         | Speicher                                     |
| ------------------------------------------------------------- | -------------------------------------------- |
| Kanal-Abos, Kalenderauswahl, bevorzugte Mensa, Sprache, Theme | `SharedPreferences` (kleine Skalare)         |
| Gewählte Stundenplangruppe, Anhänge-Download                  | `SharedPreferences`                          |
| Letzte News-Seite · Kanäle · Kontakte vollständig             | `hive_ce`                                    |
| Mensadaten aktuelle + kommende Woche                          | `hive_ce`                                    |
| Aufgabenliste                                                 | `hive_ce`, rein lokal                        |
| E-Mail-Kopfzeilen, -Inhalte, Adressindex, optional Anhänge    | **verschlüsselte** `hive_ce`-Box             |
| Noten, Moodle-Inhalte                                         | **verschlüsselte** `hive_ce`-Box             |
| Nextcloud-Verzeichnislisten und geladene Dateien              | nur flüchtig im Arbeitsspeicher               |
| Zugangsdaten, Token, Schlüssel der verschlüsselten Boxen      | `flutter_secure_storage` (Keychain/Keystore) |

Gecachte Daten werden klar als offline bzw. veraltet gekennzeichnet. **Ein Cachefehler darf nie zum
App-Crash führen** — er degradiert auf einen Netzwerkabruf. Umgekehrt darf eine leere oder
fehlgeschlagene Antwort den letzten guten Stand nie löschen.

Der frühere unverschlüsselte Mail-Testcache wird beim Upgrade ungeöffnet und idempotent entfernt;
eine Inhaltsmigration findet nicht statt. Der neue Mailcache-Schlüssel liegt ausschließlich im
Keychain/Keystore. Ist sicherer Speicher nicht verfügbar oder kann der Altcache nicht nachweislich
entfernt werden, bleibt Mail ohne persistente Ablage und legt keinen Klartextcache an.

### 4.10 Barrierefreiheit

Ausreichende Kontraste in Light und Dark · dynamische Schriftgrößen · Screenreader-Semantics ·
Touch-Ziele >= 48dp · keine reine Farbcodierung · Light/Dark/System-Theme.

## 5. Akzeptanzkriterien

| #    | Kriterium                                                                                                     |
| ---- | ------------------------------------------------------------------------------------------------------------- |
| A1   | Ein neuer Strapi-Kanal erscheint ohne Flutter-Codeänderung.                                                   |
| A2   | Campus News und FB5 News sind unabhängig aktivierbar; beide standardmäßig abonniert.                          |
| A3   | Auswahl bleibt nach App-Neustart erhalten; neue Default-Kanäle überschreiben keine Nutzerentscheidung.        |
| A4   | News in mehreren abonnierten Kanälen erscheint genau einmal.                                                  |
| A5   | Entwürfe sind nicht öffentlich sichtbar.                                                                      |
| A6   | Inaktiver Kanal verschwindet ohne App-Fehler.                                                                 |
| A7   | Alle Kanäle deaktiviert ⇒ Empty State, kein Request für alle Kanäle.                                          |
| A8   | Beide Startmensen erscheinen über Backend-Daten; Flutter kennt keine Location-IDs.                            |
| A9   | Nur der Preis der gewählten Personengruppe wird angezeigt; keine Mensabilder.                                 |
| A10  | Leere/ungültige Quellantwort löscht bestehende Mensadaten nicht.                                              |
| A10a | NFC-Guthaben wird nur nach Nutzeraktion gelesen, nie persistiert oder übertragen; Fehler sind kein Nullsaldo. |
| A11  | Wiederholter Import erzeugt keine Duplikate.                                                                  |
| A12  | Neuer Kontaktbereich erscheint ohne Codeänderung; Bereich ohne Person funktioniert.                           |
| A13  | Inaktive Bereiche/Personen werden nicht ausgeliefert.                                                         |
| A14  | API leakt keine Strapi-Internas (`data`/`attributes`/`documentId`/`populate`).                                |
| A15  | Flutter spricht nur mit `/v1` der Campus API.                                                                 |
| A16  | de/en sind in Flutter, Strapi und API real getestet.                                                          |
| A17  | Kein offizieller HSA-Eindruck, keine Hochschulassets; Unabhängigkeitshinweis sichtbar.                        |
| A18  | Keine Secrets im Repository oder in den Images.                                                               |
| A19  | Zwei getrennte Datenbanken mit getrennten Rollen.                                                             |
| A20  | Backend-, Strapi- und Flutter-Gates lokal grün.                                                               |
| A21  | Ein neuer öffentlicher Kalender erscheint ohne App- und ohne Backend-Änderung.                                |
| A22  | Keine Kalenderauswahl ⇒ keine öffentlichen Termine, niemals „alle".                                           |
| A23  | Google-Kalender-ID, Feed-URL und ETag erscheinen in keiner API-Antwort.                                       |
| A24  | Ein Fehler einer Kalenderquelle blendet die übrigen Quellen nicht aus.                                        |
| A25  | Kein Backend-Endpunkt, keine Tabelle und kein Log berührt E-Mail-, Noten-, Moodle- oder Nextcloud-Daten.       |
| A26  | Mailcache ist verschlüsselt; Zugangsdaten, Token und Cache-Schlüssel liegen nur im Keychain/Keystore.         |
| A27  | Ein Redirect auf einen fremden Host oder auf Klartext bricht den Aufruf ab, ohne Token weiterzugeben.         |
| A28  | Eine leere oder fehlgeschlagene Antwort überschreibt bei keiner Quelle den letzten guten Stand.               |
| A29  | Nach Mail-Wipe und Neustart sind alte Maildaten und Empfängervorschläge app-seitig unzugänglich.              |
| A30  | Moodle wird ausschließlich lesend angesprochen; es existiert keine generische Aufruf-Schnittstelle.           |
| A31  | Die Aufgabenliste funktioniert vollständig ohne Netzverbindung.                                               |
| A32  | Der Katalog enthält exakt die 30 vorhandenen roomKeys; generierte App-Assets sind driftgesichert.             |
| A33  | „Mehr → Lageplan" öffnet den fiktiven Demo-Plan mit sichtbarem Demo-Hinweis in DE/EN.                         |
| A34  | `B.201` und `B201` finden denselben Raum; die Auswahl fokussiert und markiert ihn.                            |
| A35  | Raumdaten funktionieren nach einem erfolgreichen Abruf offline aus dem Cache.                                 |
| A36  | Der CMS-Sync legt exakt 30 Demo-Räume an und ist idempotent; `--dry-run` schreibt nichts.                     |
| A37  | Technische Raumfelder sind über normale CMS-Wege nicht änderbar; redaktionelle Felder bleiben erhalten.       |
| A38  | Kontakte ohne Raum funktionieren unverändert und zeigen keine leere Zeile.                                    |
| A39  | Nextcloud nutzt nur `cloud.hs-anhalt.de`, speichert nur das App-Passwort sicher und liest DAV ohne Offline-Cache. |

## 6. Offene Release-Gates

Diese Punkte blockieren eine Veröffentlichung und dürfen **nicht** durch erfundene Werte ersetzt
werden:

1. **SMTP** — für Strapi-Einladungen und Passwort-Reset.
2. **Offsite-Backups** — beide Datenbanken und Strapi-Uploads.
3. **PROD-Domains.**
4. **Freigabe realer Kontaktdaten** und ggf. Personenfotos (Rechtsgrundlage).
5. **Nutzungsfreigabe der Mensa-Datenquelle** durch den Betreiber.
6. **Nutzungsfreigabe der WebUntis-Stundenplanquelle** — Erlaubnis zur automatisierten Nutzung
   der internen View-API, akzeptable Abrufrate, Stabilitätszusage beziehungsweise offizielle API,
   gewünschte Quellenangabe sowie zulässige Speicherung und Aufbewahrung von Lehrpersonennamen.
   Bis dahin bleibt `WEBUNTIS_ENABLED=false` — auch in den versionierten Produktions- und
   Test-Templates. Vor jedem Rollout wird zusätzlich der effektive, nicht versionierte Wert auf
   dem Zielsystem geprüft und `GET /v1/timetable/status` muss in Produktion
   `featureEnabled: false` melden. Ein Template allein belegt den realen Deploymentwert nicht.
7. **Abstimmung über die Prüfungsportale** — automatisierte Nutzung von HIS-QIS und HISinOne mit der
   Hochschule Anhalt klären; das schließt die lesenden HISinOne-Funktionen auf der Seite
   „Studienservice" (Bescheinigungen, Personen-/Kontaktdaten, Studiengangsübersicht) ausdrücklich
   ein.
8. **Veröffentlichungsrechte je öffentlichem Kalender** — Zustimmung des Inhabers, zulässiger
   Quellenhinweis, ob Beschreibung und Ort gezeigt werden dürfen, Ansprechpartner und Verhalten
   bei Entzug der Freigabe. Bis Kalender gepflegt sind, bleibt `PUBLIC_CALENDAR_ENABLED=false`.
9. **Reale Gebäudepläne** — Herkunft, Bearbeitungs- und Veröffentlichungsrecht, Ausschluss
   sicherheitsrelevanter Pläne (Flucht-, Rettungs- und Schließpläne), Personenbezug bei Büros und
   ein Pflegeprozess für Umbauten. Bis dahin bleibt es beim fiktiven Demo-Plan.
10. **Nextcloud-Abnahme** — realer Login Flow v2, SSO-Rückkehr, DAV-Zugriff, Offline-Widerruf und
    App-Passwort-Löschung auf Android und iOS mit einem freigegebenen Testkonto prüfen; aktualisierte
    Datenschutzhinweise vor Veröffentlichung organisatorisch freigeben.
