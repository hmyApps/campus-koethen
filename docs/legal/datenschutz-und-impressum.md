# Campus Köthen – Datenschutzerklärung und Impressum

Stand: 24. September 2026

## Datenschutzerklärung

### Geltungsbereich und Verantwortliche

Diese Datenschutzerklärung beschreibt die Verarbeitung personenbezogener Daten in der mobilen App „Campus Köthen“. Für die Bereitstellung der App und die Verarbeitung auf dem Gerät ist Erik Engler, handelnd unter „Leviora Studio“, Gartenstraße 29C, 06406 Bernburg, E-Mail: [erik@leviora.studio](mailto:erik@leviora.studio), verantwortlich. Für die Campus-API, das Content-Management-System, die redaktionellen Inhalte sowie das Antrags- und Feedbacksystem ist die Studierendenschaft der Hochschule Anhalt, Körperschaft des öffentlichen Rechts, vertreten durch den Sprecherrat des Studierendenrates, Bernburger Straße 55, 06366 Köthen, E-Mail: [stura@hs-anhalt.de](mailto:stura@hs-anhalt.de), verantwortlich. Beide Stellen verantworten jeweils ihren beschriebenen Bereich.

### Campus-API und öffentliche Inhalte

Beim Abruf von News, Veranstaltungen, Kontakten, Raum-, Mensa-, Stundenplan- und öffentlichen Kalenderdaten verbindet sich die App verschlüsselt mit der Campus-API der Studierendenschaft. Technisch verarbeitet werden dabei insbesondere die IP-Adresse, Zeitpunkt und Ziel des Abrufs, übermittelte Abfrageparameter wie Zeitraum, Sprache oder ausgewählte Kursgruppe sowie übliche Verbindungsinformationen. Dies ist erforderlich, um die angeforderten Inhalte auszuliefern, Fehler zu erkennen und den Dienst gegen Missbrauch und Angriffe zu schützen. Rechtsgrundlage ist Art. 6 Abs. 1 Buchst. e DSGVO in Verbindung mit § 65 Abs. 1 HSG LSA. Die Campus-API führt keine Nutzerkonten, verwendet keine Werbe-, Analyse- oder Trackingdienste und erstellt keine Nutzungsprofile.

### Speicherdauer im Campus-Backend

Technische Verbindungsdaten können während eines Abrufs vorübergehend verarbeitet werden. Die serverseitigen Anwendungsprotokolle der Container werden größenbasiert rotiert. In der derzeitigen Standardkonfiguration werden je Container höchstens fünf Protokolldateien mit jeweils höchstens 10 MB vorgehalten. Sobald diese Grenze erreicht ist, wird die jeweils älteste Datei überschrieben. Eine feste kalendarische Speicherdauer besteht daher nicht; die tatsächliche Dauer hängt vom anfallenden Protokollvolumen ab. Daten zu einem konkreten Sicherheitsvorfall können bis zum Abschluss der Untersuchung und Abwehr sowie darüber hinaus aufbewahrt werden, soweit eine gesetzliche Pflicht dies verlangt. Die im Backend gespeicherten Campus-, Redaktions- und Synchronisationsdaten sind keine Nutzerprofile. Eine Zusammenführung mit den lokal gespeicherten App-Daten findet nicht statt.

### Hosting durch Hostinger

Das Campus-Backend wird auf einem VPS in Deutschland betrieben. Hosting-Dienstleister und Auftragsverarbeiter der Studierendenschaft ist Hostinger International Ltd., 61 Lordou Vironos Street, 6023 Larnaca, Zypern. Der primäre Serverstandort liegt damit innerhalb der Europäischen Union. Zwischen der Studierendenschaft und Hostinger besteht ein Auftragsverarbeitungsvertrag gemäß Art. 28 DSGVO. Hostinger verarbeitet die beim Hosting anfallenden Daten nach Weisung der Studierendenschaft und kann hierfür Unterauftragsverarbeiter einsetzen. Soweit dabei Daten außerhalb des Europäischen Wirtschaftsraums in ein Land ohne Angemessenheitsbeschluss der Europäischen Kommission übermittelt werden, sieht der Auftragsverarbeitungsvertrag die Standardvertragsklauseln gemäß Durchführungsbeschluss (EU) 2021/914 als geeignete Garantie vor. Informationen zu den eingesetzten Unterauftragsverarbeitern, möglichen Übermittlungen und den Garantien sind unter [https://www.hostinger.com/legal/dpa](https://www.hostinger.com/legal/dpa) abrufbar.

### Lokale Daten auf deinem Gerät

Die App speichert Einstellungen, Sprache und Darstellung, ausgewählte Kanäle, Kalender und Kursgruppe, Mensaeinstellungen und Favoriten, gemerkte Veranstaltungen, selbst erstellte Aufgaben sowie zwischengespeicherte öffentliche Inhalte ausschließlich auf deinem Gerät. Diese Speicherung ist erforderlich, um die von dir gewählten App-Funktionen und die Offline-Nutzung bereitzustellen (§ 25 Abs. 2 Nr. 2 TDDDG). Soweit dabei personenbezogene Daten verarbeitet werden, erfolgt dies zur Bereitstellung der von dir ausdrücklich gewünschten App-Funktionen auf Grundlage von Art. 6 Abs. 1 Buchst. b DSGVO. Die eigenen App- und Campus-Backend-Funktionen setzen keine Cookies ein. Bei der direkten Anmeldung an den Prüfungsportalen können technisch notwendige Sitzungscookies verwendet werden. Diese werden ausschließlich vorübergehend im Arbeitsspeicher gehalten und nach Abschluss des Abrufs gelöscht. Es gibt keine Werbe-ID und kein geräteübergreifendes Tracking. Einstellungen und lokale Inhalte bleiben gespeichert, bis du sie in der App löschst oder zurücksetzt. Für Zugangsdaten und persönliche Caches stehen in den jeweiligen Bereichen eigene Löschfunktionen bereit; verwende diese vor einer Deinstallation, weil das Betriebssystem die Löschung sicher gespeicherter Schlüssel bei einer Deinstallation unterschiedlich handhaben kann.

### Studentische E-Mail

Wenn du die studentische E-Mail nutzt, verbindet sich dein Gerät über TLS direkt mit dem Mailserver der Hochschule Anhalt (`mail.hs-anhalt.de`). Die App verwendet IMAP und SMTP sowie ausschließlich für Empfängervorschläge die Exchange-Funktion `ResolveNames`; Suchbegriffe werden dabei direkt an das Exchange-Adressbuch der Hochschule übertragen. Campus-API, Strapi und Worker sind nicht beteiligt und erhalten weder deine Zugangsdaten noch deine E-Mails oder Suchbegriffe. E-Mail-Adresse und Passwort werden ausschließlich im sicheren Schlüsselspeicher deines Geräts abgelegt. Für die Offline-Nutzung speichert die App E-Mail-Kopfzeilen, Nachrichteninhalte, beteiligte Adressen und – falls aktiviert – Anhänge in einem verschlüsselten Cache auf diesem Gerät. Das Löschen einer einzelnen E-Mail verschiebt oder entfernt sie auf dem Hochschulserver. Nach erfolgreichem „Account entfernen“ sind Zugangsdaten, lokaler Cache und dessen Verschlüsselungsschlüssel vom Gerät entfernt; diese Kontoentfernung verändert deine E-Mails auf dem Hochschulserver nicht.

### Noten

Wenn du die Noten nutzt, verbindet sich die App direkt und verschlüsselt mit dem für dein Konto ermittelten Prüfungsportal der Hochschule Anhalt: HIS-QIS unter `service.ssc.hs-anhalt.de` oder HISinOne unter `sscportal.ssc.hs-anhalt.de`. Es gibt keinen Zwischenserver: Weder Campus-Backend noch Hostinger erhalten deine Zugangsdaten oder Noten. Benutzername, Passwort und die Portalwahl werden ausschließlich im sicheren Schlüsselspeicher deines Geräts abgelegt; die Noten werden mit einem geräteeigenen Schlüssel verschlüsselt lokal zwischengespeichert. Ein automatischer Abruf erfolgt höchstens einmal in 24 Stunden, zusätzlich manuell auf deinen Wunsch. Über „Zugangsdaten und lokale Noten löschen“ werden Zugangsdaten, Portalwahl, Noten und Verschlüsselungsschlüssel vom Gerät gelöscht. Für die Verarbeitung auf den Prüfungsportalen ist die Hochschule Anhalt verantwortlich.

### Moodle

Wenn du Moodle verbindest, kommuniziert die App direkt und verschlüsselt mit `moodle.hs-anhalt.de`. Dein Passwort wird nur für die Anmeldung verwendet und nicht gespeichert. Das von Moodle ausgestellte Sitzungstoken, deine Moodle-Nutzerkennung sowie Kurse, Materialien, Aufgaben, Ankündigungen und Fristen werden sicher beziehungsweise verschlüsselt auf deinem Gerät gespeichert. Campus-Backend und Hostinger erhalten diese Daten nicht. Mit „Moodle-Verbindung entfernen“ werden Token, Nutzerkennung, Cache und zugehörige lokale Synchronisationsdaten gelöscht. Für die Verarbeitung auf Moodle ist die Hochschule Anhalt verantwortlich.

### Finanzanträge und Feedback

Wenn du einen Finanzantrag oder Feedback absendest, übermittelt die App die Angaben direkt und verschlüsselt an das Antragsportal der Studierendenschaft unter [https://antrag.sturahsa.de](https://antrag.sturahsa.de). Bei Finanzanträgen sind dies insbesondere Standort, Titel, Name der antragstellenden Person, Antragsdokument, Kopie des Studierendenausweises und optionale Anlagen; bei Feedback der gewählte Bereich, der Text und – nur wenn angegeben – der Name. Die Campus-API ist an dieser Übermittlung nicht beteiligt und erhält diese Daten nicht. Entwürfe, Anlagen, Idempotenzdaten und die geheimen Status- und Dokumentlinks werden verschlüsselt auf dem Gerät gespeichert. Nach erfolgreicher Übermittlung werden lokale Entwurfsanlagen entfernt; eingereichte Vorgänge bleiben lokal erhalten, bis du sie löschst. Für Bearbeitung, serverseitige Speicherung und Löschung der eingereichten Daten gelten die Datenschutzhinweise des Antragsportals. Die Studierendenschaft ist hierfür verantwortlich.

### Benachrichtigungen

Benachrichtigungen werden ausschließlich auf diesem Gerät erzeugt. Die App fragt die Berechtigung des Betriebssystems erst, nachdem du sie ausdrücklich aktiviert hast, und wertet dafür nur lokal bekannte Daten aus – Termine, Stundenplan, Moodle-Fristen, Speiseplan, Favoriten sowie die geräteseitig bestätigte Ankunft neuer E-Mails. Der E-Mail-Hinweis enthält weder Absender noch Betreff. Es gibt keinen Push-Dienst, keine Gerätekennung, kein Nutzerkonto und keinen Empfänger: Für die Benachrichtigung selbst verlassen keine Daten dein Gerät. Deine Einstellungen einschließlich der Kategorie „Neue E-Mails“ kannst du jederzeit unter Mehr → Einstellungen → Benachrichtigungen ändern oder alles wieder abschalten.

### Direkte Dienste und externe Links

Bei studentischer E-Mail, Noten und Moodle stellt die App lediglich die direkte Verbindung zu den Systemen der Hochschule Anhalt her; für die dortige serverseitige Verarbeitung ist die Hochschule Anhalt verantwortlich. Externe Webseiten, Telefon- oder E-Mail-Links werden erst nach deiner Auswahl an das Betriebssystem übergeben. Für deren Verarbeitung gelten die Hinweise des jeweiligen Anbieters. Die App enthält keine Analyse-, Werbe- oder Crash-Reporting-SDKs. Apple und Google können beim Download und bei Nutzung ihrer App Stores Daten in eigener Verantwortung verarbeiten.

### Erforderlichkeit der Angaben

Für öffentliche Inhalte ist keine Registrierung erforderlich. Die technisch anfallenden Verbindungsdaten sind für einen Online-Abruf unvermeidbar. Zugangsdaten und sonstige Angaben für E-Mail, Noten, Moodle, Finanzanträge oder Feedback stellst du freiwillig bereit; ohne sie kann die jeweils gewählte Funktion nicht oder nur eingeschränkt genutzt werden. Es findet keine automatisierte Entscheidungsfindung und kein Profiling statt.

### Deine Rechte

Soweit personenbezogene Daten durch einen der Verantwortlichen verarbeitet werden, hast du nach Maßgabe der DSGVO insbesondere Rechte auf Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, Datenübertragbarkeit und Widerspruch. Richte Anfragen zur App an [erik@leviora.studio](mailto:erik@leviora.studio) und Anfragen zum Campus-Backend, zu redaktionellen Inhalten oder zum Antragsportal an [stura@hs-anhalt.de](mailto:stura@hs-anhalt.de). Du kannst dich außerdem gemäß Art. 77 DSGVO bei einer Datenschutzaufsichtsbehörde beschweren, insbesondere bei der Landesbeauftragten für den Datenschutz Sachsen-Anhalt, Otto-von-Guericke-Straße 34a, 39104 Magdeburg, E-Mail: [poststelle@lfd.sachsen-anhalt.de](mailto:poststelle@lfd.sachsen-anhalt.de).

### Änderungen dieser Erklärung

Diese Erklärung wird angepasst, wenn sich Funktionen, Empfänger oder rechtliche Anforderungen ändern. Die jeweils in der App angezeigte Fassung gilt für die dort beschriebenen Verarbeitungen.

### Unabhängigkeitshinweis

Campus Köthen ist keine offizielle App der Hochschule Anhalt. Die App wird unabhängig von Erik Engler, handelnd unter „Leviora Studio“, entwickelt und über die App Stores bereitgestellt. Das Campus-Backend und die redaktionellen Inhalte werden von der rechtlich selbstständigen Studierendenschaft der Hochschule Anhalt betrieben. Die Hochschule Anhalt selbst ist weder Entwicklerin noch Betreiberin der App.

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

Campus Köthen ist keine offizielle App der Hochschule Anhalt. Die App wird unabhängig von Erik Engler, handelnd unter „Leviora Studio“, entwickelt und über die App Stores bereitgestellt. Das Campus-Backend und die redaktionellen Inhalte werden von der rechtlich selbstständigen Studierendenschaft der Hochschule Anhalt betrieben. Die Hochschule Anhalt selbst ist weder Entwicklerin noch Betreiberin der App.
