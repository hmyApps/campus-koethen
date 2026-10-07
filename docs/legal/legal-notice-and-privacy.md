# Legal notice

Last updated: 24 September 2026

## Provider of the mobile app

Erik Engler\
trading as “Leviora Studio”\
Gartenstraße 29C\
06406 Bernburg\
Germany

Email: erik@leviora.studio\
Phone: +49 151 10481071

## Development

Leviora Studio (Erik Engler)

Co-development: Jona Loreen Sommer\
Jona Loreen Sommer is not part of Leviora Studio.

## Operation of the Campus backend and publication of content

Student body of Hochschule Anhalt\
Public-law corporation\
represented by the spokespersons' council of the student council\
Bernburger Straße 55\
06366 Köthen\
Germany

Email: stura@hs-anhalt.de

## Person responsible for journalistic and editorial content under section 18(2) of the German State Media Treaty

Erik Engler\
Chair of the Köthen Student Council\
Bernburger Straße 55\
06366 Köthen\
Germany

## Copyright

Copyright © 2026 Erik Engler, trading as “Leviora Studio”, and Jona Loreen Sommer

## Independence notice

Campus Köthen is not an official Hochschule Anhalt app. The app is independently developed and distributed through app stores by Erik Engler, trading as “Leviora Studio”. The Campus backend and editorial content are operated by the legally independent student body of Hochschule Anhalt. Hochschule Anhalt itself neither develops nor operates the app.

---

# Privacy

Last updated: 24 September 2026

## Scope and controllers

This privacy policy describes the processing of personal data in the “Campus Köthen” mobile app. Erik Engler, trading as “Leviora Studio”, Gartenstraße 29C, 06406 Bernburg, Germany, email: erik@leviora.studio, is responsible for providing the app and for processing on the device. The student body of Hochschule Anhalt, a public-law corporation represented by the spokespersons' council of the student council, Bernburger Straße 55, 06366 Köthen, Germany, email: stura@hs-anhalt.de, is responsible for the Campus API, the content management system, editorial content, and the application and feedback system. Each entity is responsible for its respective area described here.

## Campus API and public content

When retrieving news, events, contacts, rooms, canteen menus, timetables and public calendar data, the app establishes an encrypted connection to the student body's Campus API. The technical data processed includes in particular the IP address, time and target of the request, transmitted query parameters such as date range, language or selected course group, and customary connection information. This is necessary to deliver the requested content, diagnose faults and protect the service against misuse and attacks. The legal basis is Article 6(1)(e) GDPR in conjunction with section 65(1) of the Higher Education Act of Saxony-Anhalt. The Campus API has no user accounts, uses no advertising, analytics or tracking services, and creates no user profiles.

## Retention in the Campus backend

Technical connection data may be processed temporarily while a request is being handled. The server-side application logs of the containers use size-based rotation. Under the current standard configuration, each container retains no more than five log files of up to 10 MB each. Once this limit is reached, the oldest file is overwritten. There is therefore no fixed calendar-based retention period; the actual period depends on the volume of log data generated. Data relating to a specific security incident may be retained until its investigation and mitigation are complete and for longer where required by law. The campus, editorial and synchronisation data held in the backend does not constitute user profiles. It is not combined with data stored locally by the app.

## Hosting by Hostinger

The Campus backend runs on a VPS in Germany. The student body's hosting provider and processor is Hostinger International Ltd., 61 Lordou Vironos Street, 6023 Larnaca, Cyprus. The primary server location is therefore within the European Union. The student body and Hostinger have entered into a data processing agreement under Article 28 GDPR. Hostinger processes hosting data on the student body's instructions and may engage sub-processors for this purpose. Where data is transferred outside the European Economic Area to a country for which the European Commission has not adopted an adequacy decision, the data processing agreement provides for the Standard Contractual Clauses under Commission Implementing Decision (EU) 2021/914 as an appropriate safeguard. Information about the sub-processors used, possible transfers and the safeguards is available at https://www.hostinger.com/legal/dpa.

## Local data on your device

The app stores settings for language and appearance, selected channels, calendars and course group, canteen settings and favourites, saved events, tasks you create, and cached public content solely on your device. This storage is necessary to provide the app functions and offline use you request (section 25(2)(2) TDDDG). Where personal data is processed in this context, the legal basis is Article 6(1)(b) GDPR, as the processing is necessary to provide the app functions you expressly request. The app's own functions and the Campus backend do not use cookies. Technically necessary session cookies may be used when signing in directly to the exam portals. They are held temporarily in memory only and deleted after the request has been completed. There are no advertising identifiers or cross-device tracking. Settings and local content remain stored until you delete or reset them in the app. Credentials and personal caches have their own deletion controls in the respective features; use these before uninstalling because operating systems handle deletion of securely stored keys upon uninstall differently.

## Student email

When you use the student email feature, your device connects directly over TLS to the Hochschule Anhalt mail server (mail.hs-anhalt.de). The app uses IMAP and SMTP and, solely for recipient suggestions, Exchange `ResolveNames`; your search term is sent directly to the university's Exchange directory. The Campus API, Strapi and worker are not involved and receive neither your credentials, email nor directory search terms. Your email address and password are stored only in your device's secure keystore. For offline use, the app stores email headers, message contents, involved addresses and, if enabled, attachments in an encrypted cache on this device. Deleting an individual message moves or removes it on the university server. After a successful “Remove account”, the credentials, local cache and its encryption key are removed from the device; removing the account does not alter your email on the university server.

## Grades

When you use grades, the app connects directly and securely to the Hochschule Anhalt exam portal identified for your account: HIS-QIS at service.ssc.hs-anhalt.de or HISinOne at sscportal.ssc.hs-anhalt.de. There is no intermediary server: neither the Campus backend nor Hostinger receives your credentials or grades. Your username, password and portal choice are stored only in your device's secure keystore; grades are cached locally and encrypted with a key held on the device. An automatic fetch occurs at most once every 24 hours, plus manually at your request. “Delete credentials and local grades” removes credentials, portal choice, grades and encryption key from the device. Hochschule Anhalt is responsible for processing on the exam portals.

## Moodle

When you connect Moodle, the app communicates directly and securely with moodle.hs-anhalt.de. Your password is used only to sign in and is not stored. The session token issued by Moodle, your Moodle user ID, courses, materials, assignments, announcements and deadlines are stored securely or encrypted on your device. The Campus backend and Hostinger do not receive this data. “Remove Moodle connection” deletes the token, user ID, cache and associated local synchronisation data. Hochschule Anhalt is responsible for processing on Moodle.

## Funding applications and feedback

When you submit a funding application or feedback, the app sends the information directly and securely to the student body's application portal at https://antrag.sturahsa.de. Funding applications include in particular the location, title, applicant's name, application document, a copy of the student ID and optional attachments; feedback includes the selected area, the text and—only if supplied—the name. The Campus API is not involved in this transfer and does not receive this data. Drafts, attachments, idempotency data and secret status and document links are encrypted on the device. Local draft attachments are removed after a successful submission; submitted cases remain locally until you delete them. The portal's privacy information governs the processing, server-side retention and deletion of submitted data. The student body is responsible for that processing.

## Notifications

Notifications are created entirely on this device. The app asks for the operating system's permission only after you have explicitly enabled them, and it evaluates only locally known data – events, timetable, Moodle deadlines, canteen menus, your favourites and the device-confirmed arrival of new email. A new-mail notice contains neither sender nor subject. There is no push service, device identifier, notification account or recipient: no data leaves your device for the notification itself. You can change every category, including “New emails”, or turn everything off at any time under More → Settings → Notifications.

## Direct services and external links

For student email, grades and Moodle, the app only establishes the direct connection to Hochschule Anhalt systems; Hochschule Anhalt is responsible for server-side processing there. External websites, telephone links or email links are passed to the operating system only after you select them. The respective provider's information applies to its processing. The app contains no analytics, advertising or crash-reporting SDKs. Apple and Google may process data on their own responsibility when you download the app or use their app stores.

## Whether data is required

No registration is required for public content. Technical connection data is unavoidable for an online request. You provide credentials and other information for email, grades, Moodle, funding applications or feedback voluntarily; without it, the selected feature cannot be used or can be used only to a limited extent. There is no automated decision-making or profiling.

## Your rights

Where a controller processes personal data, you have, subject to the GDPR's conditions, rights including access, rectification, erasure, restriction of processing, data portability and objection. Send requests about the app to erik@leviora.studio and requests about the Campus backend, editorial content or application portal to stura@hs-anhalt.de. Under Article 77 GDPR, you may also lodge a complaint with a supervisory authority, in particular the Saxony-Anhalt Commissioner for Data Protection, Otto-von-Guericke-Straße 34a, 39104 Magdeburg, Germany, email: poststelle@lfd.sachsen-anhalt.de.

## Changes to this policy

This policy will be updated if features, recipients or legal requirements change. The version displayed in the app applies to the processing described there.

## Independence notice

Campus Köthen is not an official Hochschule Anhalt app. The app is independently developed and distributed through app stores by Erik Engler, trading as “Leviora Studio”. The Campus backend and editorial content are operated by the legally independent student body of Hochschule Anhalt. Hochschule Anhalt itself neither develops nor operates the app.
