# Campus Köthen – Datenschutzerklärung und Impressum

Stand der Datenschutzerklärung: 4. Oktober 2026 · Stand des Impressums: 24. September 2026

## Datenschutzerklärung

### Geltungsbereich und Verantwortliche

Diese Datenschutzerklärung beschreibt die Verarbeitung personenbezogener Daten in der mobilen App „Campus Köthen“. Für die Bereitstellung der App und die Verarbeitung auf dem Gerät ist Erik Engler, handelnd unter „Leviora Studio“, Gartenstraße 29C, 06406 Bernburg, E-Mail: [erik@leviora.studio](mailto:erik@leviora.studio), verantwortlich. Für die Campus-API, das Content-Management-System, die redaktionellen Inhalte sowie das Antrags- und Feedbacksystem ist die Studierendenschaft der Hochschule Anhalt, Körperschaft des öffentlichen Rechts, vertreten durch den Sprecherrat des Studierendenrates, Bernburger Straße 55, 06366 Köthen, E-Mail: [stura@hs-anhalt.de](mailto:stura@hs-anhalt.de), verantwortlich. Beide Stellen verantworten jeweils ihren beschriebenen Bereich.

### Campus-API und öffentliche Inhalte

Beim Abruf von News, Veranstaltungen, Kontakten, Raum-, Mensa-, Stundenplan- und öffentlichen Kalenderdaten verbindet sich die App verschlüsselt mit der Campus-API der Studierendenschaft. Technisch verarbeitet werden dabei insbesondere die IP-Adresse, Zeitpunkt und Ziel des Abrufs, übermittelte Abfrageparameter wie Zeitraum, Sprache oder ausgewählte Kursgruppe sowie übliche Verbindungsinformationen. Dies ist erforderlich, um die angeforderten Inhalte auszuliefern, Fehler zu erkennen und den Dienst gegen Missbrauch und Angriffe zu schützen. Rechtsgrundlage ist Art. 6 Abs. 1 Buchst. e DSGVO in Verbindung mit § 65 Abs. 1 HSG LSA. Die öffentliche Campus-API führt keine Nutzerkonten, verwendet keine Werbe-, Analyse- oder Trackingdienste und erstellt keine Nutzungsprofile. Der getrennte CMS-Administrationsbereich nutzt dagegen Konten und technisch notwendige Sitzungen für berechtigte Redaktionsmitglieder; öffentliche App-Abrufe erfordern keine CMS-Anmeldung.

### Speicherdauer im Campus-Backend

Technische Verbindungsdaten können während eines Abrufs vorübergehend verarbeitet werden. Der vorgeschaltete Webserver kann in Zugriffs- oder Fehlerprotokollen insbesondere IP-Adresse, Zeitpunkt, angeforderten Pfad samt Abfrageparametern, Antwortstatus und technische Angaben zum Client festhalten. Nach Betreiberangabe sind im globalen Host-nginx `error_log /dev/null` im Hauptkontext sowie `access_log off` und `error_log /dev/null` im HTTP-Kontext gesetzt. Die versionierten Campus-Konfigurationen enthalten keine abweichenden Log-Ziele. Ob die wirksame Konfiguration auf dem laufenden Server weitere Überschreibungen enthält und ob für den Campus-Dienst nginx-Protokolle gespeichert werden, ist noch nicht verifiziert.

Bei Sicherheitsereignissen können außerdem IP-Adresse, Zeitpunkt und technische Merkmale eines Verbindungs- oder Angriffsversuchs in lokalen System- und Sicherheitsprotokollen des gemeinsam genutzten Servers erscheinen. Nach Betreiberangabe werden systemd-journald, die täglich rotierten rsyslog-Dateien und das Fail2ban-Protokoll im regulären lokalen Betrieb etwa 15 Tage vorgehalten. Das ist kein Löschversprechen für jede Server-Protokolldatei. Diese Daten dienen der Störungsanalyse sowie der Erkennung, Untersuchung und Abwehr von Angriffen. Rechtsgrundlage für die Studierendenschaft ist Art. 6 Abs. 1 Buchst. e DSGVO in Verbindung mit § 65 Abs. 1 HSG LSA.

Die VPS-Vorlage sieht für serverseitige Anwendungsprotokolle eine größenbasierte Rotation vor: je Container eine aktive Docker-Protokolldatei mit einer Rotationsschwelle von 4m (`max-file=1`, `max-size=4m`). Bei Erreichen der Schwelle wird die bisherige Datei verworfen. Im regulären Betrieb ist das eine Größenordnung von bis zu etwa 5 MB je Container; eine feste Obergrenze ist dies nicht, da ein einzelner Logeintrag die Schwelle überschreiten kann. Ob diese Konfiguration auf dem laufenden Server aktiv ist und ob Docker-Protokolle in den Hostinger-Backups enthalten sind, wurde noch nicht verifiziert. Eine feste kalendarische Speicherdauer besteht nicht; die tatsächliche Dauer hängt vom anfallenden Protokollvolumen ab. Die etwa 15 Tage für lokale System- und Sicherheitsprotokolle gelten weder für diese Containerprotokolle noch pauschal für Datenbanken, CMS-Konten oder andere Dienste. Daten zu einem konkreten Sicherheitsvorfall können bis zum Abschluss der Untersuchung und Abwehr sowie darüber hinaus aufbewahrt werden, soweit eine gesetzliche Pflicht dies verlangt. Die im Backend gespeicherten Campus-, Redaktions- und Synchronisationsdaten sind keine Nutzerprofile. Eine Zusammenführung mit den lokal gespeicherten App-Daten findet nicht statt.

### Hosting durch Hostinger

Das Campus-Backend wird auf einem VPS mit Ubuntu 24 in Deutschland betrieben. Hosting-Dienstleister und Auftragsverarbeiter der Studierendenschaft ist Hostinger International Ltd., 61 Lordou Vironos Street, 6023 Larnaca, Zypern. Der primäre Serverstandort liegt damit innerhalb der Europäischen Union. Zwischen der Studierendenschaft und Hostinger besteht ein Auftragsverarbeitungsvertrag gemäß Art. 28 DSGVO. Hostinger verarbeitet die beim Hosting anfallenden Daten nach Weisung der Studierendenschaft und kann hierfür Unterauftragsverarbeiter einsetzen. Soweit dabei Daten außerhalb des Europäischen Wirtschaftsraums in ein Land ohne Angemessenheitsbeschluss der Europäischen Kommission übermittelt werden, sieht der Auftragsverarbeitungsvertrag die Standardvertragsklauseln gemäß Durchführungsbeschluss (EU) 2021/914 als geeignete Garantie vor. Informationen zu den eingesetzten Unterauftragsverarbeitern, möglichen Übermittlungen und den Garantien sind unter [https://www.hostinger.com/legal/dpa](https://www.hostinger.com/legal/dpa) abrufbar.

Nach Betreiberangabe erstellt Hostinger wöchentlich ein automatisches Server-Backup auf Servern innerhalb der EU. Zwei Backups werden vorgehalten; mit einem neuen Backup wird das älteste gelöscht. Ein lokal etwa 15 Tage vorhandener Sicherheitslogeintrag kann, sofern er in einem Backup enthalten ist, dadurch planmäßig noch bis zu etwa 29 Tage nach seiner Entstehung in einer Sicherung enthalten sein. Diese Rechnung beschreibt nur solche Logeinträge, nicht die Speicherdauer anderer gesicherter Daten. Die Aufbewahrung eigener Hostinger-Protokolle sowie mögliche abweichende Regeln für andere Sicherungen sind nicht belegt.

### Lokale Daten auf deinem Gerät

Die App speichert Einstellungen, Sprache und Darstellung, ausgewählte Kanäle, Kalender und Kursgruppe, Mensaeinstellungen und Favoriten, gemerkte Veranstaltungen, selbst erstellte Aufgaben sowie zwischengespeicherte öffentliche Inhalte ausschließlich auf deinem Gerät. Diese Speicherung ist erforderlich, um die von dir gewählten App-Funktionen und die Offline-Nutzung bereitzustellen (§ 25 Abs. 2 Nr. 2 TDDDG). Soweit dabei personenbezogene Daten verarbeitet werden, erfolgt dies zur Bereitstellung der von dir ausdrücklich gewünschten App-Funktionen auf Grundlage von Art. 6 Abs. 1 Buchst. b DSGVO. Die eigenen App- und Campus-Backend-Funktionen setzen keine Cookies ein. Bei der direkten Anmeldung an den Prüfungsportalen können technisch notwendige Sitzungscookies verwendet werden. Diese werden ausschließlich vorübergehend im Arbeitsspeicher gehalten und nach Abschluss des Abrufs gelöscht. Es gibt keine Werbe-ID und kein geräteübergreifendes Tracking. Einstellungen und lokale Inhalte bleiben gespeichert, bis du sie in der App löschst oder zurücksetzt. Für Zugangsdaten und persönliche Caches stehen in den jeweiligen Bereichen eigene Löschfunktionen bereit; verwende diese vor einer Deinstallation, weil das Betriebssystem die Löschung sicher gespeicherter Schlüssel bei einer Deinstallation unterschiedlich handhaben kann.

### NFC-Guthabenprüfung der Mensakarte

Wenn du „Guthaben prüfen“ auswählst, liest die App über NFC ausschließlich den auf einer unterstützten Mensakarte gespeicherten Guthabenwert. Auf Android kann auch das Vorhalten einer ISO-DEP-Karte außerhalb der App eine Öffnen-Abfrage des Betriebssystems auslösen; erst dein Tippen auf diese Abfrage öffnet Campus Köthen und startet den Lesevorgang. Auf iOS ist der Scan technisch nur nach manuellem Start innerhalb der App möglich. Die App wertet die Kartenkennung nicht aus. Kartenkennung, rohe Kartenantwort und Guthaben werden weder gespeichert noch protokolliert oder an Campus-Backend, Studierendenschaft, Hochschule oder Dritte übertragen. Der angezeigte Betrag liegt nur flüchtig im Arbeitsspeicher und wird beim Schließen der Anzeige verworfen. Es gibt keinen Hintergrundscan. Die Verarbeitung erfolgt ausschließlich zur Bereitstellung der von dir angeforderten lokalen Funktion auf Grundlage von Art. 6 Abs. 1 Buchst. b DSGVO und § 25 Abs. 2 Nr. 2 TDDDG.

### Zentraler Hochschulzugang

Optional kannst du genau eine Hochschulkennung — Benutzername oder vollständige Hochschul-Mailadresse — und ein Passwort zentral hinterlegen. Die Speicherung erfolgt erst nach deiner ausdrücklichen Bestätigung und nachdem mindestens einer der Dienste E-Mail, Moodle oder Noten die Daten akzeptiert hat. Beide Werte liegen ausschließlich im gerätegebundenen sicheren Schlüsselspeicher. Für die E-Mail-Verbindung ergänzt die App einen Benutzernamen ohne `@` lokal zu `<Kennung>@hs-anhalt.de`; eine vollständige Mailadresse bleibt unverändert. Moodle und Noten erhalten die Kennung unverändert. Ein erkanntes früheres Drei-Feld-Schema wird vollständig gelöscht und nicht automatisch migriert. Die Werte werden weder an Campus-Backend, Strapi oder Worker übertragen noch in Einstellungen, Cache, Logs oder öffentlichem App-State abgelegt. Der zentrale Zugang ist nur eine lokale Eingabehilfe und keine gemeinsame SSO-Sitzung: Erst dein Tippen auf `+` meldet den ausgewählten Dienst separat und direkt beim jeweiligen Hochschulsystem an. `−` löscht nur die dienstbezogene Session und deren lokale Daten; der zentrale Zugang bleibt für andere Dienste erhalten. „Hochschulzugang vollständig löschen“ trennt zuerst alle Dienste und löscht den zentralen Zugang zuletzt. Scheitert ein Dienst, bleibt der zentrale Zugang für einen erneuten Versuch erhalten. Bei einem Passwortwechsel kannst du die Daten unter „Zugangsdaten aktualisieren“ erneut durch einen gewählten Dienst prüfen und ersetzen.

Nextcloud erhält diese zentrale Identität nie und verwendet stattdessen den Browser-basierten Login Flow v2.

### Studentische E-Mail

Wenn du die studentische E-Mail nutzt, verbindet sich dein Gerät über eine TLS-geschützte Verbindung direkt mit dem Mailserver der Hochschule Anhalt (`mail.hs-anhalt.de`). Campus-API, Strapi und Worker sind nicht beteiligt und erhalten weder deine Zugangsdaten noch deine E-Mails. Die dienstbezogene E-Mail-Adresse und das Passwort werden ausschließlich im sicheren Schlüsselspeicher deines Geräts abgelegt. Für die Offline-Nutzung speichert die App E-Mail-Kopfzeilen, Nachrichteninhalte, beteiligte Adressen und – falls aktiviert – Anhänge in einem verschlüsselten Cache auf diesem Gerät. Nach erfolgreichem „E-Mail-Verbindung und lokale Daten löschen“ sind die dienstbezogenen Zugangsdaten, der lokale Cache und dessen Verschlüsselungsschlüssel entfernt; ein optional hinterlegter zentraler Hochschulzugang bleibt erhalten. Deine E-Mails auf dem Hochschulserver bleiben unverändert.

### Noten

Wenn du die Noten nutzt, verbindet sich die App direkt und verschlüsselt mit dem für dein Konto ermittelten Prüfungsportal der Hochschule Anhalt: HIS-QIS unter `service.ssc.hs-anhalt.de` oder HISinOne unter `sscportal.ssc.hs-anhalt.de`. Es gibt keinen Zwischenserver: Weder Campus-Backend noch Hostinger erhalten deine Zugangsdaten oder Noten. Dienstbezogener Benutzername, Passwort und Portalwahl werden ausschließlich im sicheren Schlüsselspeicher deines Geräts abgelegt; die Noten werden mit einem geräteeigenen Schlüssel verschlüsselt lokal zwischengespeichert. Ein automatischer Abruf erfolgt höchstens einmal in 24 Stunden, zusätzlich manuell auf deinen Wunsch. Über „Noten-Verbindung und lokale Noten löschen“ werden dienstbezogene Zugangsdaten, Portalwahl, Noten und Verschlüsselungsschlüssel gelöscht; ein optional hinterlegter zentraler Hochschulzugang bleibt erhalten. Für die Verarbeitung auf den Prüfungsportalen ist die Hochschule Anhalt verantwortlich.

Auf HISinOne bietet dir die Notenübersicht zusätzlich bis zu drei feste Bescheinigungs-Buttons (z. B. Leistungsübersicht bestandener und Übersicht fehlender Leistungen) an. Erstellst du eine davon, sendet die App dieselbe Formularseite direkt an `sscportal.ssc.hs-anhalt.de` und ruft das Ergebnis über denselben zweistufigen, eng begrenzten Pfad ab wie die Studienservice-Bescheinigungen (siehe unten): zuerst `/qisserver/rds?state=docdownload` auf dem Portal selbst, danach ein Weiterleiten auf die separate Adresse `untrust-sscportal.ssc.hs-anhalt.de` mit demselben Pfad. Das Dokument bleibt nur im Arbeitsspeicher und wird in der App geöffnet beziehungsweise über die Teilen-Funktion deines Betriebssystems weitergegeben, nie dauerhaft auf dem Gerät archiviert.

Ist dein Konto auf HISinOne eingerichtet, bietet die App im Modul „HISinOne" zusätzlich rein lesenden Zugriff auf eine Seite „Studienservice" mit mehreren Bereichen: deine Bescheinigungsübersicht samt Download, deine Personen- und Kontaktdaten sowie deine Studiengangsübersicht — über dieselbe Verbindung und dieselben Zugangsdaten wie der Notenspiegel, ohne zweite Anmeldung. Die Portal-Seiten und Formularaktionen gehen ausschließlich an `sscportal.ssc.hs-anhalt.de`; der einmalige Abruf einer erzeugten Bescheinigung geht zuerst dorthin (eng begrenzt auf den Pfad `/qisserver/rds?state=docdownload`) und wird von dort auf die separate Adresse `untrust-sscportal.ssc.hs-anhalt.de` desselben Pfads weitergeleitet. Diese Funktionen ändern keine Hochschuldaten; es wird nie eine Prüfungsanmeldung, Adressänderung oder sonstige Mutation gesendet. Heruntergeladene Bescheinigungen werden nicht dauerhaft auf dem Gerät archiviert, sondern nur im Arbeitsspeicher gehalten und in der App geöffnet beziehungsweise über die Teilen-Funktion deines Betriebssystems weitergegeben. Die Studienservice-Übersicht wird verschlüsselt lokal zwischengespeichert. Das Löschen der Noten-Verbindung wartet laufende Abrufe ab und entfernt auch diesen Cache samt Schlüssel sowie den Zugriff auf die Funktionen.

### Moodle

Wenn du Moodle verbindest, kommuniziert die App direkt und verschlüsselt mit `moodle.hs-anhalt.de`. Der Moodle-Anmeldevorgang speichert dein Passwort nicht im Moodle-Konto; optional kann dasselbe Passwort nach deiner ausdrücklichen Bestätigung getrennt im zentralen Hochschulzugang liegen. Das von Moodle ausgestellte Sitzungstoken, deine Moodle-Nutzerkennung sowie Kurse, Materialien, Aufgaben, Ankündigungen und Fristen werden sicher beziehungsweise verschlüsselt auf deinem Gerät gespeichert. Campus-Backend und Hostinger erhalten diese Daten nicht. Mit „Moodle-Verbindung und lokale Daten löschen“ werden Token, Nutzerkennung, Cache und zugehörige lokale Synchronisationsdaten gelöscht; ein optional hinterlegter zentraler Hochschulzugang bleibt erhalten. Für die Verarbeitung auf Moodle ist die Hochschule Anhalt verantwortlich.

### Nextcloud

Wenn du Nextcloud verbindest, startet die App den offiziellen Login Flow v2 von `cloud.hs-anhalt.de` im Systembrowser. Dein Hochschulpasswort wird nur dort eingegeben und gelangt nicht an Campus Köthen. Nextcloud stellt der App ein widerrufbares App-Passwort aus; dieses sowie Loginname und Nutzer-ID liegen ausschließlich im gerätegebundenen sicheren Schlüsselspeicher. Die App liest Ordner und von dir ausgewählte Dateien direkt und verschlüsselt per WebDAV unter deiner eigenen Nutzerwurzel. Verzeichnislisten, Dateimetadaten und geladene Dateien werden nicht dauerhaft zwischengespeichert, sondern nur vorübergehend im Arbeitsspeicher gehalten. Erst eine bewusste Teilen-/Speichern-Aktion übergibt eine Datei an das Betriebssystem. Beim Trennen versucht die App, das App-Passwort bei Nextcloud zu widerrufen, und löscht die lokale Berechtigung auch bei einem Serverfehler. Campus-Backend, Strapi und Hostinger erhalten diese Daten nicht. Für die serverseitige Verarbeitung in Nextcloud ist die Hochschule Anhalt verantwortlich.

### Finanzanträge und Feedback

Wenn du einen Finanzantrag oder Feedback absendest, übermittelt die App die Angaben direkt und verschlüsselt an das Antragsportal der Studierendenschaft unter [https://antrag.sturahsa.de](https://antrag.sturahsa.de). Bei Finanzanträgen sind dies insbesondere Standort, Titel, Name der antragstellenden Person, Antragsdokument, Kopie des Studierendenausweises und optionale Anlagen; bei Feedback der gewählte Bereich, der Text und – nur wenn angegeben – der Name. Die Campus-API ist an dieser Übermittlung nicht beteiligt und erhält diese Daten nicht. Entwürfe, Anlagen, Idempotenzdaten und die geheimen Status- und Dokumentlinks werden verschlüsselt auf dem Gerät gespeichert. Nach erfolgreicher Übermittlung werden lokale Entwurfsanlagen entfernt; eingereichte Vorgänge bleiben lokal erhalten, bis du sie löschst. Für Bearbeitung, serverseitige Speicherung und Löschung der eingereichten Daten gelten die Datenschutzhinweise des Antragsportals. Die Studierendenschaft ist hierfür verantwortlich.

### Benachrichtigungen

Benachrichtigungen werden ausschließlich auf diesem Gerät geplant. Die App fragt die Berechtigung des Betriebssystems erst, nachdem du sie ausdrücklich aktiviert hast, und wertet dafür nur Daten aus, die ohnehin schon lokal gespeichert sind – Termine, Stundenplan, Moodle-Fristen, Speiseplan und deine Favoriten. Es gibt keinen Push-Dienst, keine Gerätekennung, kein Nutzerkonto und keinen Empfänger: Zu keinem Zeitpunkt verlassen dafür Daten dein Gerät. Deine Einstellungen kannst du jederzeit unter Mehr → Einstellungen → Benachrichtigungen ändern oder alles wieder abschalten.

### Direkte Dienste und externe Links

Bei studentischer E-Mail, Noten, Moodle und Nextcloud stellt die App lediglich die direkte Verbindung zu den Systemen der Hochschule Anhalt her; für die dortige serverseitige Verarbeitung ist die Hochschule Anhalt verantwortlich. Externe Webseiten, Telefon- oder E-Mail-Links werden erst nach deiner Auswahl an das Betriebssystem übergeben. Für deren Verarbeitung gelten die Hinweise des jeweiligen Anbieters. Die App enthält keine Analyse-, Werbe- oder Crash-Reporting-SDKs. Apple und Google können beim Download und bei Nutzung ihrer App Stores Daten in eigener Verantwortung verarbeiten.

### Erforderlichkeit der Angaben

Für öffentliche Inhalte ist keine Registrierung erforderlich. Die technisch anfallenden Verbindungsdaten sind für einen Online-Abruf unvermeidbar. Zugangsdaten und sonstige Angaben für E-Mail, Noten, Moodle, Nextcloud, Finanzanträge oder Feedback stellst du freiwillig bereit; ohne sie kann die jeweils gewählte Funktion nicht oder nur eingeschränkt genutzt werden. Es findet keine automatisierte Entscheidungsfindung und kein Profiling statt.

### Deine Rechte

Soweit personenbezogene Daten durch einen der Verantwortlichen verarbeitet werden, hast du nach Maßgabe der DSGVO insbesondere Rechte auf Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, Datenübertragbarkeit und Widerspruch. Richte Anfragen zur App an [erik@leviora.studio](mailto:erik@leviora.studio) und Anfragen zum Campus-Backend, zu redaktionellen Inhalten oder zum Antragsportal an [stura@hs-anhalt.de](mailto:stura@hs-anhalt.de). Du kannst dich außerdem gemäß Art. 77 DSGVO bei einer Datenschutzaufsichtsbehörde beschweren, insbesondere bei der Landesbeauftragten für den Datenschutz Sachsen-Anhalt, Otto-von-Guericke-Straße 34a, 39104 Magdeburg, E-Mail: [poststelle@lfd.sachsen-anhalt.de](mailto:poststelle@lfd.sachsen-anhalt.de).

### Änderungen dieser Erklärung

Diese Erklärung wird angepasst, wenn sich Funktionen, Empfänger oder rechtliche Anforderungen ändern. Die jeweils in der App angezeigte Fassung gilt für die dort beschriebenen Verarbeitungen.

### Unabhängigkeitshinweis

Campus Köthen ist keine offizielle App der Hochschule Anhalt. Die App wird von Erik Engler über die App Stores bereitgestellt. Das Campus-Backend und die redaktionellen Inhalte werden von der rechtlich selbstständigen Studierendenschaft der Hochschule Anhalt betrieben. Die Hochschule Anhalt selbst ist weder Entwicklerin noch Betreiberin der App.

---

## Impressum

### Anbieter der mobilen App

Erik Engler<br>
handelnd unter „Leviora Studio“<br>
Gartenstraße 29C<br>
06406 Bernburg<br>
Deutschland

E-Mail: [erik@leviora.studio](mailto:erik@leviora.studio)<br>
Telefon: [+49 151 10481071](tel:+4915110481071)

### Entwicklung

Leviora Studio (Erik Engler)

Mitentwicklung: Jona Loreen Sommer<br>
Jona Loreen Sommer ist nicht Teil von Leviora Studio.

### Betrieb des Campus-Backends und Herausgabe der Inhalte

Studierendenschaft der Hochschule Anhalt<br>
Körperschaft des öffentlichen Rechts<br>
vertreten durch den Sprecherrat des Studierendenrates<br>
Bernburger Straße 55<br>
06366 Köthen<br>
Deutschland

E-Mail: [stura@hs-anhalt.de](mailto:stura@hs-anhalt.de)

### Verantwortlich für journalistisch-redaktionelle Inhalte gemäß § 18 Abs. 2 MStV

Erik Engler<br>
Vorsitzender des Studierendenrates Köthen<br>
Bernburger Straße 55<br>
06366 Köthen<br>
Deutschland

### Urheberrecht

Copyright © 2026 Erik Engler, handelnd unter „Leviora Studio“, und Jona Loreen Sommer

### Unabhängigkeitshinweis

Campus Köthen ist keine offizielle App der Hochschule Anhalt. Die App wird von Erik Engler über die App Stores bereitgestellt. Das Campus-Backend und die redaktionellen Inhalte werden von der rechtlich selbstständigen Studierendenschaft der Hochschule Anhalt betrieben. Die Hochschule Anhalt selbst ist weder Entwicklerin noch Betreiberin der App.
