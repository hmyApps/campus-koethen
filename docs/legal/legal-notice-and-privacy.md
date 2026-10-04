# Legal notice

Last updated: 4 October 2026

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

Campus Köthen is not an official Hochschule Anhalt app. The app is distributed through app stores by Erik Engler. The Campus backend and editorial content are operated by the legally independent student body of Hochschule Anhalt. Hochschule Anhalt itself neither develops nor operates the app.

---

# Privacy

Last updated: 2 October 2026

## Scope and controllers

This privacy policy describes the processing of personal data in the “Campus Köthen” mobile app. Erik Engler, trading as “Leviora Studio”, Gartenstraße 29C, 06406 Bernburg, Germany, email: erik@leviora.studio, is responsible for providing the app and for processing on the device. The student body of Hochschule Anhalt, a public-law corporation represented by the spokespersons' council of the student council, Bernburger Straße 55, 06366 Köthen, Germany, email: stura@hs-anhalt.de, is responsible for the Campus API, the content management system, editorial content, and the application and feedback system. Each entity is responsible for its respective area described here.

## Campus API and public content

When retrieving news, events, contacts, rooms, canteen menus, timetables and public calendar data, the app establishes an encrypted connection to the student body's Campus API. The technical data processed includes in particular the IP address, time and target of the request, transmitted query parameters such as date range, language or selected course group, and customary connection information. This is necessary to deliver the requested content, diagnose faults and protect the service against misuse and attacks. The legal basis is Article 6(1)(e) GDPR in conjunction with section 65(1) of the Higher Education Act of Saxony-Anhalt. The public Campus API has no user accounts, uses no advertising, analytics or tracking services, and creates no user profiles. The separate CMS administration area uses accounts and technically necessary sessions for authorised editorial staff; public app requests do not require a CMS login.

## Retention in the Campus backend

Technical connection data may be processed temporarily while a request is being handled. The upstream web server may record the IP address, time, requested path including query parameters, response status and technical client information in access or error logs. According to the operator, the global host nginx configuration sets `error_log /dev/null` in the main context and `access_log off` and `error_log /dev/null` in the HTTP context. The versioned Campus configurations contain no different log destinations. Whether the effective configuration on the running server contains further overrides and whether nginx logs are stored for the Campus service has not yet been verified.

During security events, the IP address, time and technical characteristics of a connection or attack attempt may also appear in local system and security logs on the shared server. According to the operator, systemd-journald, the daily rotated rsyslog files and the Fail2ban log are normally retained locally for about 15 days. This is not a promise to delete every server log file by then. These data are used to diagnose faults and to detect, investigate and defend against attacks. For the student body, the legal basis is Article 6(1)(e) GDPR in conjunction with section 65(1) of the Higher Education Act of Saxony-Anhalt.

The VPS template provides for size-based rotation of server-side application logs: one active Docker log file per container with a rotation threshold of 4m (`max-file=1`, `max-size=4m`). When the threshold is reached, the previous file is discarded. In normal operation, this is on the order of up to about 5 MB per container; it is not a hard upper bound, as a single log entry can exceed the threshold. Whether this configuration is active on the running server and whether Docker logs are included in Hostinger backups has not yet been verified. There is no fixed calendar-based retention period; the actual period depends on the volume of log data generated. The approximately 15 days for local system and security logs do not apply to these container logs or generally to databases, CMS accounts or other services. Data relating to a specific security incident may be retained until its investigation and mitigation are complete and for longer where required by law. The campus, editorial and synchronisation data held in the backend does not constitute user profiles. It is not combined with data stored locally by the app.

## Hosting by Hostinger

The Campus backend runs on an Ubuntu 24 VPS in Germany. The student body's hosting provider and processor is Hostinger International Ltd., 61 Lordou Vironos Street, 6023 Larnaca, Cyprus. The primary server location is therefore within the European Union. The student body and Hostinger have entered into a data processing agreement under Article 28 GDPR. Hostinger processes hosting data on the student body's instructions and may engage sub-processors for this purpose. Where data is transferred outside the European Economic Area to a country for which the European Commission has not adopted an adequacy decision, the data processing agreement provides for the Standard Contractual Clauses under Commission Implementing Decision (EU) 2021/914 as an appropriate safeguard. Information about the sub-processors used, possible transfers and the safeguards is available at https://www.hostinger.com/legal/dpa.

According to the operator, Hostinger creates an automatic server backup every week on servers within the EU. Two backups are retained; the oldest is deleted when a new backup is created. A security log entry held locally for about 15 days may therefore remain in a backup for up to about 29 days after its creation, if included in that backup. This calculation applies only to such log entries, not to the retention of other backed-up data. Retention of Hostinger's own logs and any different rules for other backups have not been established.

## Local data on your device

The app stores settings for language and appearance, selected channels, calendars and course group, canteen settings and favourites, saved events, tasks you create, and cached public content solely on your device. This storage is necessary to provide the app functions and offline use you request (section 25(2)(2) TDDDG). Where personal data is processed in this context, the legal basis is Article 6(1)(b) GDPR, as the processing is necessary to provide the app functions you expressly request. The app's own functions and the Campus backend do not use cookies. Technically necessary session cookies may be used when signing in directly to the exam portals. They are held temporarily in memory only and deleted after the request has been completed. There are no advertising identifiers or cross-device tracking. Settings and local content remain stored until you delete or reset them in the app. Credentials and personal caches have their own deletion controls in the respective features; use these before uninstalling because operating systems handle deletion of securely stored keys upon uninstall differently.

## NFC canteen-card balance check

When you select “Check balance”, the app uses NFC solely to read the balance stored on a supported canteen card. On Android, presenting an ISO-DEP card while outside the app may also trigger the operating system's prompt to open Campus Köthen; only tapping that prompt opens the app and starts the read. On iOS, platform restrictions require the scan to be started manually inside the app. The app does not evaluate the card identifier. The card identifier, raw card response and balance are never stored, logged or transmitted to the Campus backend, the student body, Hochschule Anhalt or any third party. The displayed amount exists only temporarily in memory and is discarded when you close the view. There is no background scan. Processing is limited to providing the local function you request under Article 6(1)(b) GDPR and section 25(2)(2) TDDDG.

## Central university access

You can optionally store exactly one university identifier — a username or full university email address — and one password centrally. They are stored only after your explicit confirmation and after at least one of email, Moodle or grades has accepted them. Both values remain exclusively in the device-bound secure keystore. For email, the app locally expands an identifier without `@` to `<identifier>@hs-anhalt.de`; a full email address remains unchanged. Moodle and grades receive the identifier unchanged. If the retired three-field schema is detected, it is wiped completely and is not migrated automatically. The values are never sent to the Campus backend, Strapi or worker and are never placed in settings, caches, logs or public app state. The central access is only a local input aid, not a shared SSO session: only tapping `+` signs the selected service in separately and directly with the respective university system. `−` deletes only that service's session and local data; the central access remains available to other services. “Delete university access completely” disconnects every service first and deletes the central access last. If a service fails, the central access is retained for a retry. After a password change, “Update credentials” verifies the new values with a selected service before replacing the stored identity.

Nextcloud never receives this central identity and uses the browser-based Login Flow v2 instead.

## Student email

When you use the student email feature, your device connects directly to the Hochschule Anhalt mail server (mail.hs-anhalt.de) over a TLS-protected connection. The Campus API, Strapi and worker are not involved and receive neither your credentials nor your email. The service-specific email address and password are stored only in your device's secure keystore. For offline use, the app stores email headers, message contents, involved addresses and, if enabled, attachments in an encrypted cache on this device. After a successful “Delete email connection and local data”, the service-specific credentials, local cache and its encryption key are removed; an optional central university access is retained. Your email on the university server remains unchanged.

## Grades

When you use grades, the app connects directly and securely to the Hochschule Anhalt exam portal identified for your account: HIS-QIS at service.ssc.hs-anhalt.de or HISinOne at sscportal.ssc.hs-anhalt.de. There is no intermediary server: neither the Campus backend nor Hostinger receives your credentials or grades. The service-specific username, password and portal choice are stored only in your device's secure keystore; grades are cached locally and encrypted with a key held on the device. An automatic fetch occurs at most once every 24 hours, plus manually at your request. “Delete grades connection and local grades” removes the service-specific credentials, portal choice, grades and encryption key; an optional central university access is retained. Hochschule Anhalt is responsible for processing on the exam portals.

On HISinOne, the grade overview itself additionally offers up to three fixed certificate buttons (such as a transcript of passed modules and an overview of outstanding ones). Generating one sends the same overview page's own form directly to `sscportal.ssc.hs-anhalt.de` and fetches the result over the same narrowly scoped path `/qisserver/rds?state=docdownload` used by the Study Service certificates below. The document stays in memory only and is opened in the app or handed to your operating system's share action, never archived permanently on the device.

If your account is set up on HISinOne, the app's "HISinOne" module additionally offers read-only access to a "Study Service" page with several sections: your certificate overview with download, your personal and contact data, and your programme overview — over the same connection and the same credentials as grades, without a second sign-in. Portal pages, form actions and the one-time fetch of a generated certificate are all sent only to `sscportal.ssc.hs-anhalt.de`, the certificate fetch additionally narrowed to the path `/qisserver/rds?state=docdownload`. These functions do not modify university records; no exam registration, address change or other mutation is sent. Downloaded certificates are not archived permanently on the device; they are held in memory only and opened in the app or handed to your operating system's share action. The Study Service overview is cached locally in encrypted form. Deleting the grades connection waits for in-flight operations and removes this cache and its key as well as access to these functions.

## Moodle

When you connect Moodle, the app communicates directly and securely with moodle.hs-anhalt.de. The Moodle sign-in does not store your password in the Moodle account; after your explicit confirmation, the same password may optionally be stored separately in the central university access. The session token issued by Moodle, your Moodle user ID, courses, materials, assignments, announcements and deadlines are stored securely or encrypted on your device. The Campus backend and Hostinger do not receive this data. “Delete Moodle connection and local data” deletes the token, user ID, cache and associated local synchronisation data; an optional central university access is retained. Hochschule Anhalt is responsible for processing on Moodle.

## Nextcloud

When you connect Nextcloud, the app starts the official Login Flow v2 for `cloud.hs-anhalt.de` in the system browser. Your university password is entered only there and is not received by Campus Köthen. Nextcloud issues the app with a revocable app password; it, the login name and user ID remain exclusively in the device-bound secure keystore. The app reads folders and files you select directly over encrypted WebDAV below your own user root. Folder listings, file metadata and downloaded files are not cached permanently and are held only temporarily in memory. A file is passed to the operating system only after an explicit share/save action. When disconnecting, the app attempts to revoke the app password in Nextcloud and removes the local credential even if the server fails. The Campus backend, Strapi and Hostinger do not receive these data. Hochschule Anhalt is responsible for server-side processing in Nextcloud.

## Funding applications and feedback

When you submit a funding application or feedback, the app sends the information directly and securely to the student body's application portal at https://antrag.sturahsa.de. Funding applications include in particular the location, title, applicant's name, application document, a copy of the student ID and optional attachments; feedback includes the selected area, the text and—only if supplied—the name. The Campus API is not involved in this transfer and does not receive this data. Drafts, attachments, idempotency data and secret status and document links are encrypted on the device. Local draft attachments are removed after a successful submission; submitted cases remain locally until you delete them. The portal's privacy information governs the processing, server-side retention and deletion of submitted data. The student body is responsible for that processing.

## Notifications

Notifications are scheduled entirely on this device. The app asks for the operating system's permission only after you have explicitly enabled them, and it evaluates only data that is already stored locally – events, timetable, Moodle deadlines, canteen menus and your favourites. There is no push service, no device identifier, no user account and no recipient: no data ever leaves your device for this. You can change your settings or turn everything off again at any time under More → Settings → Notifications.

## Direct services and external links

For student email, grades, Moodle and Nextcloud, the app only establishes the direct connection to Hochschule Anhalt systems; Hochschule Anhalt is responsible for server-side processing there. External websites, telephone links or email links are passed to the operating system only after you select them. The respective provider's information applies to its processing. The app contains no analytics, advertising or crash-reporting SDKs. Apple and Google may process data on their own responsibility when you download the app or use their app stores.

## Whether data is required

No registration is required for public content. Technical connection data is unavoidable for an online request. You provide credentials and other information for email, grades, Moodle, Nextcloud, funding applications or feedback voluntarily; without it, the selected feature cannot be used or can be used only to a limited extent. There is no automated decision-making or profiling.

## Your rights

Where a controller processes personal data, you have, subject to the GDPR's conditions, rights including access, rectification, erasure, restriction of processing, data portability and objection. Send requests about the app to erik@leviora.studio and requests about the Campus backend, editorial content or application portal to stura@hs-anhalt.de. Under Article 77 GDPR, you may also lodge a complaint with a supervisory authority, in particular the Saxony-Anhalt Commissioner for Data Protection, Otto-von-Guericke-Straße 34a, 39104 Magdeburg, Germany, email: poststelle@lfd.sachsen-anhalt.de.

## Changes to this policy

This policy will be updated if features, recipients or legal requirements change. The version displayed in the app applies to the processing described there.

## Independence notice

Campus Köthen is not an official Hochschule Anhalt app. The app is distributed through app stores by Erik Engler. The Campus backend and editorial content are operated by the legally independent student body of Hochschule Anhalt. Hochschule Anhalt itself neither develops nor operates the app.
