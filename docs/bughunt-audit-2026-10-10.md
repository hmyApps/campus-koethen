# Multi-Agent-Bughunt 2026-10-10

Acht parallele, ausschließlich lesende Prüf-Agenten haben das gesamte Repository rekursiv
abgesucht, jeweils mit eigenem Bereich. Gesucht wurde nach Logikfehlern, defekten Verbindungen,
verlorenen Features und Verstößen gegen `AGENTS.md`. Was das Audit vom 2026-10-07
(`docs/bughunt-audit-2026-10-07.md`) als behoben führt, wurde nachgeprüft und nur dann erneut
aufgenommen, wenn es weiterhin besteht (F-08, C-01 EWS-Teil).

Alle Funde stützen sich auf gelesenen Code. Im Zuge dieses Audits wurde **nichts behoben**, und
es wurden keine Tests ausgeführt. Funde mit dem Zusatz „nicht verifiziert“ oder „voraussichtlich“
beruhen auf Framework- bzw. Plugin-Verhalten und müssen vor dem Fix reproduziert werden.

## Überblick

| Bereich | hoch | mittel | niedrig |
|---|---|---|---|
| Kalender, Stundenplan, Todos | 2 | 4 | 7 |
| Backend und OpenAPI | 1 | 2 | 6 |
| Mail, HSA-GPT, Hochschulzugang | – | 4 | 7 |
| App-Kern, l10n, kleinere Features | – | 6 | 4 |
| CMS, Infrastruktur, CI, Skripte | – | 4 | 9 |
| Anträge, Dokumenten-Wallet, Kontakte | – | 3 | 10 |
| Benachrichtigungen und Moodle | – | 2 | 5 |
| Noten, Studienservice, Nextcloud | – | 1 | 9 |
| **Summe (86)** | **3** | **26** | **57** |

## Empfohlene Reihenfolge

1. **Hoch:** Stundenplan-Refresh lädt nicht neu (Pending-Pläne lösen sich nie auf);
   Zusatzgruppen jenseits der ersten 50 nicht abonnierbar; Unique-Konflikt bei `channelSlug`
   blockiert den Katalog-Sync der öffentlichen Kalender dauerhaft.
2. **Bezug zu AGENTS.md (Datenschutz/Sicherheit):** HSA-GPT trotz Deaktivierung über
   Navigationseinstellungen und Kontokarte erreichbar; fehlendes HAWKI-`/logout`; HAWKI-Token
   bleibt bei Fehler im Identitätsspeicher liegen; Anhang-Box mit `discardUnreadable: true`;
   EWS-Fehl-Logins nach Passwort-Ablehnung; `http://` für `REQUESTS_BASE_URL` nicht abgewiesen;
   fehlende `REVOKE CONNECT` in PROD-`db-init`; lokaler Worker ohne `STRAPI_BASE_URL`.
3. **Verlorene Features:** „In Google Kalender öffnen“, Standardgebäude in den Einstellungen,
   Quellenangabe/Info-Dialog der Karte, Moodle-„Im Browser öffnen“, Detail-Sheet nach Tap auf
   Termin-Erinnerung.
4. Übrige mittlere und niedrige Funde, Doku-Drift und ungenutzte ARB-Schlüssel.

### Kalender, Stundenplan, Todos

Bereich: `features/{calendar,timetable,todos}`, iOS- und Android-Widget, `docs/public-calendars.md`. Einen Verstoß gegen AGENTS §2 gibt es nicht: Exchange-Termine werden vor dem Widget-Payload herausgefiltert. Todos sind ohne neue Funde.

| Schwere | Ort | Problem | Lösungsvorschlag |
|---|---|---|---|
| hoch | `apps/mobile/lib/features/timetable/presentation/timetable_screen.dart:70-85` (mit `timetable_providers.dart:485-496`) | Refresh, Pull-to-Refresh und Pending-Poller invalidieren nur den Aggregat-Provider, nicht die zugrunde liegenden `timetableWeekProvider`-Einträge. Es gibt also keinen neuen Netzabruf, und ein Plan im Zustand „pending“ löst sich nie auf. | Vorher `timetableWeekProvider` für alle Gruppen-IDs der Woche invalidieren und einen Test ergänzen, der den Request zählt. |
| hoch | `apps/mobile/lib/features/timetable/presentation/timetable_subscriptions_sheet.dart:76-122` (mit `timetable_providers.dart:158-162`, `timetable_repository.dart:34-56`) | Das Sheet für Zusatzgruppen lädt nur Seite 1 (50 Gruppen) und filtert lokal. Alle weiteren Gruppen lassen sich weder finden noch abonnieren. | `timetableGroupSearchProvider` mit serverseitiger Suche und `loadMore` verwenden, wie im Gruppenpicker. |
| mittel | `apps/mobile/lib/features/calendar/application/calendar_providers.dart:421-426, 948-950` | Der Filter auf „Starttag ≥ heute“ lässt laufende mehrtägige Termine und Termine über Mitternacht in Liste und Widget weg. | Nach `lastDay ≥ heute` filtern und den Test erweitern. |
| mittel | `apps/mobile/lib/app/app_sync_host.dart:125-142` (mit `timetable_providers.dart:386-400, 445-469`) | `timetableRangeProvider` (Quelle für Liste und Widget) wird nie invalidiert; Ausfälle erscheinen erst nach einem Neustart. `timetableForegroundRefreshProvider` ist ungenutzt, stattdessen wird jedes Mal der Gruppenkatalog geladen. | Im Sync-Host `timetableRangeProvider` invalidieren und `timetableForegroundRefreshProvider` verwenden. |
| mittel | `apps/mobile/lib/features/calendar/application/public_calendar_providers.dart:113-116, 206-216` | Der Katalog wird per `.value` gelesen. Bei Fehler oder während des Ladens kommt still `[]` zurück, und Fehler- bzw. Ladebanner erscheinen nie. | `await ref.watch(publicCalendarsCatalogProvider.future)` verwenden. |
| mittel | `apps/mobile/lib/features/calendar/data/public_calendars_repository.dart:86-97`; `presentation/public_calendar_list.dart` | **Verlorenes Feature:** „Ausgewählte in Google Kalender öffnen“ (docs/public-calendars.md:171-173) fehlt seit Commit `749864a`. `fetchGoogleViewUrl`, `calendarOpenSelectedInGoogle` und `calendarGoogleCombinedNote` sind dadurch tot. | Den Button wiederherstellen oder Doku, Keys und Methode bewusst entfernen. |
| niedrig | `apps/mobile/lib/features/calendar/application/public_calendar_providers.dart:200-225` | Der Monatsabruf ignoriert `meta.truncated`, ein gekapptes Ergebnis wirkt vollständig. | Die Truncation-Logik von `_loadWindowEntries` übernehmen. |
| niedrig | `apps/mobile/lib/features/timetable/presentation/timetable_screen.dart:237-245` | Änderungshinweise werden nur für die Primärgruppe angezeigt; die Hinweise der Zusatzgruppen bleiben unsichtbar. | Nach allen ausgewählten Gruppen-IDs filtern und quittieren. |
| niedrig | `apps/mobile/lib/features/calendar/presentation/calendar_screen.dart:99-102` | `everythingVisible` ignoriert `hiddenCourses`, sodass das Filter-Icon trotz ausgeblendeter Kurse unmarkiert bleibt. | `&& lessonInfoFilter.hiddenCourses.isEmpty` ergänzen. |
| niedrig | `apps/mobile/lib/features/calendar/presentation/calendar_screen.dart:585-596`; `calendar_list_rows.dart:66` | Ganztagseinträge erscheinen ab Mitternacht als „vergangen“ gedimmt, und die Jetzt-Linie richtet sich nach ihrem UTC-Start aus. | Ganztagseinträge davon ausnehmen. |
| niedrig | `apps/mobile/lib/features/calendar/presentation/calendar_entry_sheet.dart:340` | Bei Exchange-Terminen zeigt das Detail-Sheet den Ort nur, wenn er sich als Campusraum auflösen lässt; „Online“ und externe Orte fehlen. | Eine generische Ortszeile ausgeben. |
| niedrig | `apps/mobile/lib/features/calendar/presentation/calendar_source_sheets.dart:346-350` (mit `timetable_group_picker_sheet.dart:55`) | Der Picker bekommt den Kontext eines bereits geschlossenen Sheets. Dadurch wird das Benachrichtigungs-Opt-in (Einstiegspunkt C) nie angeboten. | Den Screen-Kontext übergeben bzw. das Opt-in im Aufrufer auslösen. |
| niedrig | `apps/mobile/ios/CampusCalendarWidget/CampusCalendarWidget.swift:232` | Der Widget-Name ist als „Campus Koethen“ hartcodiert, nicht lokalisiert und weicht vom App-Namen ab (AGENTS §1). | Über `de.lproj`/`en.lproj` als „Campus Köthen“ lokalisieren. |

### Backend und OpenAPI

Bereich: `apps/backend` (src, Prisma, Migrationen), `packages/openapi`, `docs/api.md`. Schema, Migrationen, Modul-Registrierung und OpenAPI-Pfade passen zusammen.

| Schwere | Ort | Problem | Lösungsvorschlag |
|---|---|---|---|
| hoch | `apps/backend/src/modules/public-calendar/public-calendar-sync.service.ts:164-176, 184-191, 216` | `channelSlug` ist unique, wird aber in Katalogreihenfolge upsertet. Stillgelegte Kalender behalten ihren Slug. Wechselt ein Kanal den Kalender, scheitert die ganze Katalog-Transaktion bei jedem Lauf mit einem Unique-Fehler (falsch protokolliert als `strapiUnavailable`). Katalogänderungen greifen danach nicht mehr. | In der Transaktion zuerst die betroffenen bzw. stillgelegten Slugs auf `null` setzen, dann upserten. Fehlercodes trennen und einen Test für den Kanalwechsel ergänzen. |
| mittel | `apps/backend/src/modules/public-calendar/public-calendar-sync.service.ts:184-191` (mit `public-calendar.strapi.ts:68-80`) | Ein einzelner verworfener Strapi-Eintrag (z. B. ein vertippter Link) führt dazu, dass der Kalender im selben Lauf stillgelegt wird. Das widerspricht `docs/public-calendars.md` §5 und AGENTS §4. | Verworfene Slugs von der Stilllegung ausnehmen oder bei `rejected > 0` gar nicht stilllegen. |
| mittel | `apps/backend/src/modules/posts/posts.service.ts:344-348, 499-503` (vs. 622-626) | Mit explizitem `channels` filtern Feed und Events nur nach Slug, nicht nach `isActive`. Beiträge deaktivierter Kanäle erscheinen in der Liste, ihr Detail-Link liefert 404. | Im Kanalfilter `isActive: { $eq: true }` ergänzen und testen. |
| niedrig | `apps/backend/src/modules/public-calendar/public-calendar.controller.ts:443-445`; `posts/posts.controller.ts:44-46` | Ist nur `from` gesetzt, wird `to` als heute + maxDays berechnet statt `from` + Spanne. Ein `from` in der Vergangenheit ergibt 400 (latent, die App sendet beide Werte). | `to = raw.to ?? addCalendarDays(from, maxDays)`. |
| niedrig | `apps/backend/src/modules/public-calendar/public-calendar.controller.ts:471-476`; `posts/posts.service.ts:482-483` | `from`/`to` sind als Europe/Berlin-Tage dokumentiert, werden aber als UTC-Grenzen ausgewertet: Am Rand fehlen bis zu 2 Stunden oder es kommen 2 Stunden zu viel dazu. | Grenzen mit `zonedWallClockToUtc` in Berliner Zeit umrechnen. |
| niedrig | `apps/backend/src/modules/posts/posts.service.ts:145, 157`; `contacts/contacts.service.ts:291`; `rooms/rooms.service.ts:98` | Der Strapi-Envelope wird nicht mit Zod geprüft (AGENTS §4). Eine 200-Antwort ohne `data` wird als leere Liste gecacht und ausgeliefert. | Den Envelope per Zod prüfen und bei falscher Form `UPSTREAM_UNAVAILABLE` liefern. |
| niedrig | `apps/backend/src/common/validation/query.ts:32` | `page` hat keine Obergrenze (AGENTS §7). Riesige Werte enden als 500/503 statt 400. | `.max(10_000)` o. ä. |
| niedrig | `apps/backend/src/config/env.schema.ts:198-201`; `apps/backend/.env.example` | `PUBLIC_CALENDAR_USER_AGENT` fehlt in `.env.example`. Der Default nennt die veraltete Version 1.2.4 und die ungültige URL `https://dev.erikengler.campuskoethen`. | In `.env.example` aufnehmen und den Default korrigieren. |
| niedrig | `apps/backend/src/modules/timetable/timetable-sync.service.ts:1089-1094` | `windowFor` nutzt das UTC-Datum und wurde in Commit `7e03d36` nicht auf `campusToday()` umgestellt. Zwischen 00 und 02 Uhr verschiebt sich das Fenster um einen Tag. | `campusToday()` und `addCalendarDays` verwenden. |

### Mail, HSA-GPT, Hochschulzugang

Bereich: `features/{mail,hsa_ki,university_account}`.

| Schwere | Ort | Problem | Lösungsvorschlag |
|---|---|---|---|
| mittel | `apps/mobile/lib/features/mail/application/mail_search_controller.dart:127-134`; `presentation/mail_message_screen.dart:119-122` | Der Suchzustand ist weder `autoDispose` noch an den Ordner gebunden. Treffer aus der INBOX bleiben nach einem Ordnerwechsel stehen; ein Tipp öffnet bzw. löscht die UID im falschen Ordner, außerhalb der INBOX ohne UIDVALIDITY-Schutz. | `selectedMailboxProvider` watchen bzw. `autoDispose` setzen und `mailboxPath` in der Route mitgeben. |
| mittel | `apps/mobile/lib/features/hsa_ki/application/hsa_ki_account_controller.dart:108-110` | `disconnect()` liest die Identität außerhalb von try/catch. Wirft der Speicher einen Fehler, wird `store.clear()` nie erreicht und das HAWKI-Token bleibt liegen. | Den Identitäts-Read in das try/catch ziehen, damit der lokale Wipe immer läuft. |
| mittel | `apps/mobile/lib/features/mail/application/exchange_calendar_providers.dart:208-265` | Der EWS-Kalender ignoriert die Passwort-Ablehnung bzw. eine 401-Sperre und schickt pro Rebuild bis zu 3 parallele Fehl-Logins ans zentrale Konto. Das ist der EWS-Teil von C-01, der nicht umgesetzt wurde. | Rejection-Sperre prüfen und setzen, Fenster nacheinander abrufen und nach dem ersten 401 abbrechen. |
| mittel | `apps/mobile/lib/features/hsa_ki/data/hawki_gateway.dart:241-267, 283-297`; `domain/hsa_ki_profile.dart:22` | Verstoß gegen AGENTS §2: `/logout` wird nach dem Web-Login nie aufgerufen (`logoutUri` ist ungenutzt), sodass die Websitzung offen bleibt. `GET /profile` dient als CSRF-Quelle, steht aber nicht in der Allowlist. | Best-effort `/logout` im `finally` ausführen; `/profile` in AGENTS.md aufnehmen oder das CSRF-Token anders beziehen. |
| niedrig | `apps/mobile/lib/features/mail/application/mail_inbox_controller.dart:399, 432, 456-470`; `mail_folders.dart:27-40` | Nach einer Passwort-Ablehnung erzeugen `_markSeen`, die Ordnerliste und Nicht-INBOX-Ordner weiter IMAP-Fehl-Logins im Hintergrund. | Vor impliziten IMAP-Aufrufen `mailCredentialsRejectionProvider` prüfen. |
| niedrig | `apps/mobile/lib/features/university_account/application/university_service_connector.dart:359-360` | Bei einem Kontowechsel wird der Anzeigename des alten Kontos als `From`-Name übernommen. | Den Snapshot-Namen nur bei demselben Konto verwenden. |
| niedrig | `apps/mobile/lib/features/mail/application/mail_account_controller.dart:99` | Mail vergleicht die Adresse case-sensitiv, der Connector case-insensitiv. Eine Passwortänderung mit anderer Schreibweise der Kennung löscht den Offline-Cache. | Case-insensitiv vergleichen, wie im Connector. |
| niedrig | `apps/mobile/lib/features/mail/application/mail_sync_controller.dart:360-362` vs. `:485-492` | Ein manueller Refresh hebt die Sperre auf, die Live-Sync bleibt aber in `authRequired`, bis die App fortgesetzt wird. | Auf das Aufheben der Rejection hören und `start()` erneut aufrufen. |
| niedrig | `apps/mobile/lib/features/university_account/presentation/university_account_card.dart:260-293` (vgl. `app/app_modules.dart:283`) | HSA-GPT ist deaktiviert, trotzdem bieten Karte und Onboarding `+` an und erzeugen ein nutzloses HAWKI-Token. | Die Zeile ausblenden, solange `isTemporarilyUnavailable` gilt. |
| niedrig | `apps/mobile/lib/features/hsa_ki/presentation/hsa_ki_chat_screen.dart:186-204` | Das Modell-Dropdown hat kein Semantics-Label; `hsaKiModelLabel` ist ungenutzt. Ebenfalls tot: `hsaKiOpenChat`, `mailInboxTitle`, `mailRefresh`, `mailAttachmentOpen`, `mailAttachmentLoadImage`, `mailAttachmentNotDownloaded`, `mailMessageAttachmentsUnsupported`. | Label über `InputDecorator`/`Semantics` setzen, tote Schlüssel entfernen. |
| niedrig | `apps/mobile/lib/features/mail/presentation/mail_inbox_screen.dart:67-70` | Connector-Fehler (z. B. `operationBlocked`) werden mit `mailFailureMessage` übersetzt und ergeben nur einen generischen Text. | `universityAccountErrorMessage(l10n, DirectService.mail, error)` verwenden. |

### App-Kern, l10n, kleinere Features

Bereich: `main.dart`, `app/`, `core/`, ARB-Dateien, `features/{canteen,campusmap,news,events,onboarding,settings,about,more,legal}`. Ohne Befund: Routen ↔ Screens, ARB de = en (1456/1456), DTO-Felder Mensa/Räume/Posts, Hexwerte und Hardcode-Texte.

| Schwere | Ort | Problem | Lösungsvorschlag |
|---|---|---|---|
| mittel | `apps/mobile/lib/app/takt_navigation_bar.dart:120-128`; `features/more/presentation/more_screen.dart:83-92` | `Semantics(button: true, excludeSemantics: true)` verwirft die Tap-Aktion des `InkWell`. Navigations-Tabs und „Mehr“-Zeilen sind unter TalkBack/VoiceOver voraussichtlich nicht auslösbar (AGENTS §9; aus dem Framework-Verhalten abgeleitet, nicht am Gerät geprüft). | `onTap` direkt an `Semantics` übergeben und mit `hasTapAction: true` testen. |
| mittel | `apps/mobile/lib/core/prefs/settings_controller.dart:472-486` | `resetLocalPreferences` löscht die Widget-Schlüssel nur im Store, der Provider im Speicher bleibt `enabled`/`showDetails`. Das Homescreen-Widget zeigt bis zum Neustart weiter Titel und Orte. | `ref.invalidate(calendarHomeWidgetSettingsProvider)` aufrufen bzw. `setEnabled(false)`. |
| mittel | `apps/mobile/lib/features/settings/presentation/navigation_settings_screen.dart:161`; `app/app_modules.dart:283` | HSA-GPT ist deaktiviert, bleibt aber `pinnable`. Als Navigations-Tab öffnet es den Chat direkt und umgeht so die Sperre aus AGENTS §2. | Module mit `isTemporarilyUnavailable` in `_availableIn` und `NavigationConfig.of` ausfiltern. |
| mittel | `features/settings/presentation/settings_screen.dart` (fehlt); `features/onboarding/presentation/onboarding_steps.dart:319-370`; `features/campusmap/presentation/campus_map_screen.dart:291` | **Verlorenes Feature:** Das Standardgebäude lässt sich nur im Onboarding setzen. Der Hinweis „später in den Einstellungen“ läuft ins Leere, und `settingsDefaultBuilding*` ist ungenutzt. | Eine Kachel „Standardgebäude“ in den Einstellungen ergänzen. |
| mittel | `apps/mobile/lib/app/app_sync_host.dart:57, 112-118` | Der Auto-Refresh (alle 5 Minuten und bei jedem Resume) invalidiert den News-Feed: Ein weit gescrollter Feed springt auf Seite 1 zurück. | Nur Seite 1 abgleichen und einmischen oder bei `page > 1` den Auto-Refresh auslassen. |
| mittel | `apps/mobile/lib/features/campusmap/domain/map_catalog.dart:59-87`; `presentation/campus_map_screen.dart` | **Verlorenes Feature:** `sourceAttribution` („Plangrundlage …“) wird nie angezeigt. Der Schematisch-Hinweis steht nur deutsch im SVG, entgegen `docs/campus-map.md:436-437` (DE/EN-Hinweis plus Info-Dialog). | Info-Dialog mit `resolvedSourceAttribution(locale)` und lokalisiertem Hinweis aus ARB. |
| niedrig | `apps/mobile/lib/core/prefs/key_value_store.dart:94-100`; `settings_controller.dart:476-483` | `remove` schluckt Exceptions, sodass `settingsResetIncomplete` (SET-6) toter Code ist. | Erfolg zurückgeben bzw. weiterwerfen und im Reset auswerten. |
| niedrig | `apps/mobile/lib/core/cache/hive_content_cache.dart:97, 121-130` | Jeder `write` löst `prune()` aus, das alle bis zu 128 Einträge (bis 20 MB) per JSON dekodiert und so CPU und Akku kostet. | Nur Metadaten prüfen oder `prune` drosseln. |
| niedrig | `features/events/presentation/event_overview_screen.dart:100`; `features/canteen/presentation/canteen_screen.dart:104-116` | Ein werfendes `_refresh` (offline, ohne Cache) erzeugt einen unbehandelten Async-Fehler. | Den Fehler in `_refresh` fangen. |
| niedrig | `apps/mobile/lib/l10n/app_de.arb` / `app_en.arb` | 113 ungenutzte Schlüssel, u. a. die komplette `today*`- (Dashboard) und `search*`-Gruppe (globale Suche), `newsEvents*Empty/NotAvailable` und `campusMapLegendTitle`. Das deutet auf entfernte oder nie verdrahtete Features hin. | Bewusst entfernen bzw. wieder anbinden und einen CI-Check auf ungenutzte ARB-Schlüssel ergänzen. |

### CMS, Infrastruktur, CI, Skripte, Campus-Map

Bereich: `apps/cms`, `infrastructure/`, `scripts/`, `packages/campus-map`, `.github/workflows`, Root-Manifeste, Dockerfiles. Die CMS-Felder passen zu den Strapi-Abfragen des Backends, Compose und `.env.example` sind vollständig, Actions sind SHA-gepinnt und Postgres ist nirgends öffentlich gebunden.

| Schwere | Ort | Problem | Lösungsvorschlag |
|---|---|---|---|
| mittel | `apps/cms/src/index.ts:46`; `apps/cms/src/bootstrap/seed.ts:150-163, 166-185` | `ensureTags` überschreibt bei jedem Boot, auch in PROD, die Tags `news`/`event` (Name, `isActive: true`) und veröffentlicht sie. Redaktionelle Änderungen gehen verloren, und Entwürfe werden still veröffentlicht. | Nur anlegen, wenn der Tag fehlt; das Update nur bei `seedDemoContent` ausführen. Test ergänzen. |
| mittel | `apps/cms/config/server.ts:3-12` (vgl. `apps/cms/.env.example:10`, `infrastructure/vps/compose.yaml:196`) | `PUBLIC_URL` wird gesetzt, aber nie gelesen; es fehlen `url` und `proxy`. Strapi kennt hinter nginx weder seine HTTPS-URL noch `X-Forwarded-Proto` (betrifft absolute URLs und Secure-Cookies). | `url: env('PUBLIC_URL')` und `proxy: true` setzen und den Admin-Login hinter dem Proxy prüfen. |
| mittel | `infrastructure/local/compose.yaml:172-199` | Dem lokalen `worker` fehlen `STRAPI_BASE_URL`, `STRAPI_API_TOKEN` und `depends_on: cms`. Er nutzt deshalb `127.0.0.1:1337` (sich selbst), und der Katalog-Sync scheitert (verletzt AGENTS §2.4). | Die Variablen wie beim `api`-Dienst setzen und `depends_on: cms: service_healthy` ergänzen. |
| mittel | `infrastructure/vps/compose.yaml:139-176` (vgl. `infrastructure/local/initdb/10-create-databases.sh:44-64`) | Der PROD-`db-init` entzieht weder `CONNECT … FROM PUBLIC` noch die Rechte am `public`-Schema. App- und CMS-Rolle können jeweils die andere DB öffnen (AGENTS §2.3), lokal ist das strenger gelöst. | `REVOKE CONNECT … FROM PUBLIC`, `GRANT CONNECT … TO owner` und `REVOKE ALL ON SCHEMA public FROM PUBLIC` ergänzen, ebenso in `myaioffice-dev`. |
| niedrig | `apps/cms/src/catalog/room-guard.ts:87-104` | Der Raum-Guard ignoriert die Aktion `clone` (Admin „Duplizieren“). Ein Editor kann so Räume außerhalb von `rooms:sync` anlegen. | `clone` wie `create` abweisen und testen. |
| niedrig | `apps/cms/Dockerfile:96-105, 110`; `apps/backend/Dockerfile:86-92` | Der Code wird per `--chown=node:node` kopiert. Der Prozess kann seinen eigenen Code also ändern, entgegen dem Kommentar. | Code root-owned kopieren; nur `uploads` und `.tmp` dem Nutzer `node` geben. |
| niedrig | `scripts/smoke-test.sh:60, 87-88` | Die Prüfung von `isDemoContent` auf Kontaktbereichen ist veraltet (das Feld wurde entfernt). Außerdem erwartet der Test `/docs` = 200, obwohl die Docs lokal aus sind. | Die Assertion entfernen und `DOCS_ENABLED` setzen bzw. `/docs` nur optional prüfen. |
| niedrig | `.trivyignore` (deepmerge-ts, js-yaml, nanoid, brace-expansion) | Die Ausnahmen sind durch Overrides in `pnpm-workspace.yaml` überholt, verdecken aber künftige Regressionen. | Die Ausnahmen entfernen und Trivy neu laufen lassen. |
| niedrig | `.github/workflows/uptime.yml:142-149`; `scripts/smoke-test.sh:29` | `curl -w '%{http_code}' … \|\| echo "000"` ergibt `000000`; der Zweig „unreachable“ wird nie erreicht. | `\|\| true` verwenden bzw. den Exit-Code separat auswerten. |
| niedrig | `scripts/check-content-type-schemas.mjs:12`; `.github/workflows/ci.yml:172-192` | Das Node-Skript ist ungenutzt, während die CI dieselbe Prüfung inline in Python dupliziert. | Die CI auf das Node-Skript umstellen. |
| niedrig | `packages/campus-map/src/generate.mjs:355-381`; `apps/mobile/pubspec.yaml:116-120` | `check` erkennt weder verwaiste SVGs noch Gebäudeordner, die in `pubspec.yaml` fehlen. | Unerwartete Dateien und fehlende Asset-Einträge melden. |
| niedrig | `scripts/perf/seed-perf-dataset.ts:424-425` | Ohne `--profile` liefert `indexOf(-1)+1` das erste Argument, was zu „Unknown profile '--reset'“ führt. | `indexOf >= 0` prüfen. |
| niedrig | `apps/cms/src/admin/app.tsx:6-9` | Der Kommentar verweist auf die nicht vorhandene `vite.config.ts`. | Auf `scripts/inject-prism-shim.mjs` korrigieren. |

### Anträge, Dokumenten-Wallet, Kontakte

Bereich: `features/{requests,document_wallet,contacts}`. In `contacts` wurde nichts gefunden.

| Schwere | Ort | Problem | Lösungsvorschlag |
|---|---|---|---|
| mittel | `apps/mobile/lib/features/requests/application/requests_controller.dart:301-310`; `presentation/application_form_screen.dart:253`; `presentation/feedback_form_screen.dart:209` | Ein eingefrorener Entwurf bleibt nach einer eindeutigen 4xx-Ablehnung beim erneuten Senden (400/404/413/415) gesperrt. Die Aufforderung „andere Stelle wählen“ lässt sich nicht befolgen; es bleibt nur Löschen, und dabei gehen die Anhänge verloren. Dafür gibt es keinen Test. | Bei eindeutigem 4xx `unfreeze` anbieten oder automatisch ausführen und einen Test ergänzen. |
| mittel | `apps/mobile/lib/features/requests/data/encrypted_attachment_store.dart:31-38, 146` | Die Anhang-Box (enthält die Ausweiskopie) nutzt den Standard `discardUnreadable: true`: Eine Box, die sich nicht lesen lässt, wird still geleert. Das widerspricht `docs/requests.md` §8. `openRead` liest tolerant, sodass ein Lesefehler als feldbezogene Ablehnung erscheint. | `discardUnreadable: false` setzen; in `openRead` `readChecked` verwenden und Speicherfehler als eigenes Ergebnis melden. |
| mittel | `apps/mobile/lib/features/requests/presentation/submission_detail_screen.dart:116-118, 137-152` | `.value ?? []` setzt Laden bzw. Fehler mit „kein Vorgang“ gleich. `_refresh` wartet ohne try/catch auf `submissionsProvider.future`, sodass Polling und Pull-to-Refresh unbehandelte Fehler werfen. | Laden, Fehler und Daten wie in `RequestsScreen` unterscheiden und `_refresh` mit try/catch absichern. |
| niedrig | `apps/mobile/lib/features/requests/data/locations_repository.dart:31`; `feedback_areas_repository.dart:30`; `application/requests_providers.dart:101-115` | Es wird nur geprüft, ob die Adresse leer ist. Ein `http://`-Wert für `REQUESTS_BASE_URL` führt zu Abrufen über Klartext-HTTP (verletzt die HTTPS-Pflicht aus AGENTS §2). | Vorher `GremioOrigin.parse(baseUrl)` aufrufen; bei `null` „nicht angebunden“ melden. |
| niedrig | `apps/mobile/lib/features/requests/application/requests_local_data_wiper.dart:27-56` | Die Komplettlöschung ignoriert laufende Einreichungen. Ein Upload, der danach endet, schreibt Statuslink bzw. Entwurf wieder in den Speicher. | Löschen sperren, solange etwas gesendet wird, oder laufende Sendungen abbrechen und ihr Ergebnis verwerfen. |
| niedrig | `apps/mobile/lib/features/requests/application/requests_controller.dart:399-412`; `presentation/application_form_screen.dart:127-146` | „Als neuen Vorgang senden“ behält den alten Idempotenzschlüssel. Ist der Entwurf geändert und kennt der Server den Schlüssel noch, folgt ein 409 mit irreführender Meldung. | Beim Neuversand einen neuen Schlüssel erzeugen oder Kommentar und Doku an das tatsächliche Verhalten anpassen. |
| niedrig | `apps/mobile/lib/features/requests/data/gremio_request_gateway.dart:189-196` | Ein Abbruch vor `bind` ergibt „unbekannter Ausgang“ und friert den Entwurf ein, obwohl nichts gesendet wurde. | Ein eigenes Ergebnis „nichts gesendet“ ohne Einfrieren einführen. |
| niedrig | `requests/presentation/submission_detail_screen.dart:450`; `requests_screen.dart:439`; `application_form_screen.dart:188`; `feedback_form_screen.dart:160` | `RequestStoreUnavailable` aus `remove`, `delete` und `save` wird nicht abgefangen; die Nutzerin bekommt kein Feedback. | Fehler abfangen und per SnackBar mit lokalisiertem Text melden. |
| niedrig | `apps/mobile/lib/features/requests/domain/request_validation.dart:100, 107, 150` | Die Validierung zählt UTF-16-Einheiten, `TextField.maxLength` dagegen Grapheme: Emoji-Titel gelten fälschlich als zu lang. | Einheitlich zählen (`characters.length`), passend zur Zählweise des Servers. |
| niedrig | `apps/mobile/lib/features/requests/domain/case_status.dart:53` | Der fest kodierte Fallback `'dokument'` erscheint als Titel im UI (verletzt AGENTS §6). | `null` liefern und den Text in der Präsentationsschicht aus ARB setzen. |
| niedrig | `apps/mobile/lib/features/document_wallet/data/encrypted_document_wallet_store.dart:33, 75-79` | `readAll` und die Löschprüfung lesen tolerant: Ein Speicherfehler erscheint als leere Wallet, und eine Löschung gilt fälschlich als bestätigt. | `readChecked` verwenden und Fehler als `storageUnavailable` melden. |
| niedrig | `apps/mobile/lib/l10n/app_de.arb` / `app_en.arb` | 10 `requests*`-Schlüssel sind ungenutzt (`requestsKeyExpiredTitle`, `requestsFinanceTitle`, `requestsFeedbackTitle`, `requestsSlotRequired`, `requestsSlotOptional`, `requestsCategoryTravel/App/Campus`, `requestsAddAttachment`, `requestsNoAttachments`). | `requestsKeyExpiredTitle` als Bannertitel nutzen, die übrigen entfernen. |
| niedrig | `docs/requests.md:4, 18` | Die Doku spricht von „vier“ Direktanbindungen und nennt HIS-QIS; laut AGENTS §2 sind es sechs, mit HISinOne als Standardportal. | An AGENTS §2 angleichen. |

### Benachrichtigungen und Moodle

Bereich: `features/{notifications,moodle}`, `docs/notifications.md`, `docs/moodle.md`. Die als behoben geführten Funde des Audits vom 07.10. sind bestätigt behoben, außer F-08 (Zeile 1). Einen Verstoß gegen AGENTS §2 gibt es nicht.

| Schwere | Ort | Problem | Lösungsvorschlag |
|---|---|---|---|
| mittel | `apps/mobile/lib/features/notifications/presentation/notification_host.dart:339-342` (mit `app/campus_app.dart:63`, `calendar/presentation/calendar_entry_sheet.dart:35`) | Der `NotificationHost` sitzt im `MaterialApp.router`-Builder oberhalb des Navigators, es gibt keinen `navigatorKey`. `showModalBottomSheet` wirft deshalb, und ein Tap auf eine Termin-Erinnerung öffnet nie das Detail-Sheet. F-08 ist damit nur teilweise behoben. | Den GoRouter mit einem Root-`navigatorKey` versehen und dessen Kontext nutzen, oder das Sheet über einen Fokus-Provider im Kalender öffnen. Dazu ein Widget-Test mit echtem Router-Builder. |
| mittel | `apps/mobile/lib/features/moodle/data/moodle_repository_impl.dart:180-183, 347-350` | Ist die letzte offene Aufgabe abgegeben, liefert Moodle eine leere Liste. `_keepIfEmpty` behält dann den alten Bestand, und N4-Erinnerungen bzw. die N2-Zählung laufen für abgegebene Aufgaben weiter. | Beim Behalten nur künftige Einträge aktueller Kurse übernehmen oder den Bestand als „stale“ markieren und keine N4-Kandidaten daraus erzeugen. Test ergänzen. |
| niedrig | `apps/mobile/lib/features/notifications/data/device_time_zone.dart:66-71` | Die Ersatz-Zone `device-offset-<min>` wird als `timeZoneName` an die native Seite gereicht und ist dort voraussichtlich ungültig. Geplante Meldungen schlagen dann still fehl. Am Plugin-Code ist das nicht verifiziert. | Einen gültigen Namen verwenden (`Etc/GMT∓h` bzw. `+01:00`) und einen Gateway-Test ergänzen. |
| niedrig | `apps/mobile/lib/features/notifications/application/notification_tap_router.dart:581-582`; `moodle_deadline_candidates.dart:24-26`; ARB `notificationMoodleDeadlineBody` | Die N4-Frist-Meldung führt zur Moodle-Kursliste, die keine Fristen zeigt (Sackgasse). | Auf den Kalender am Fristtag routen oder in Moodle einen Abschnitt „Anstehende Fristen“ ergänzen. |
| niedrig | `apps/mobile/lib/features/moodle/data/moodle_repository_impl.dart:411-419` (mit `moodle_parsers.dart:302-306`) | `isLate` wird unabhängig vom Status gesetzt. Ein Entwurf nach Fristende zeigt widersprüchliche Chips. | `isLate` nur bei `state == submitted` setzen und testen. |
| niedrig | `apps/mobile/lib/features/moodle/domain/moodle_profile.dart:30`; `domain/moodle_assignment.dart:94`; ARB `moodleOpenInBrowser`, `moodleModuleUnsupported`, `moodleCourseProgress`, `moodleCoursesTitle` | **Verlorene Funktion:** Es gibt keinen „Im Browser öffnen“-Link, keinen Hinweis auf nicht unterstützte Module und keine Anzeige des Kursfortschritts, obwohl Felder und Keys dafür vorhanden sind. | Einen tokenfreien Web-Link über `SafeLinkLauncher` verdrahten oder Felder und Keys entfernen. |
| niedrig | `docs/notifications.md:22, 53, 169-171, 244, 304`; `docs/moodle.md:154`; `daily_summary_content.dart:302-303` | Die Doku ist veraltet: Sie nennt 4 statt 6 Kategorien, N4 statt n6 für Mail und noch die „24-h-Policy“. Ein Code-Kommentar widerspricht `hasRelevantEntry`. | Die Doku auf N1–N6 und die 1-h-Policy bringen, den Kommentar korrigieren. |

### Noten, Studienservice, Nextcloud

Bereich: `features/{grades,student_service,nextcloud}`, `docs/grades.md`, `docs/nextcloud.md`. Was das Audit vom 07.10. als behoben führt, ist bestätigt umgesetzt. Funde der Stufe „hoch“ gibt es nicht.

| Schwere | Ort | Problem | Lösungsvorschlag |
|---|---|---|---|
| mittel | `apps/mobile/lib/features/student_service/data/his_in_one_student_service_gateway.dart:236-246` | Der Submit „PDF erstellen“ (Studienverlaufsbescheinigung) folgt Redirects über `postForm` mit der allgemeinen Freigabeliste. Endet die Kette wie bei den Druck-Buttons auf `state=docdownload`, scheitert der 307 auf `untrust-sscportal` als `hostRejected`. Für diesen Erfolgspfad gibt es keinen Test. | Über `postFormStream` und `documentDownloadRoute` laufen lassen bzw. den Redirect an `_fetchDocument` übergeben. Gateway-Test ergänzen. |
| niedrig | `apps/mobile/lib/features/student_service/data/his_in_one_student_service_parser.dart:395-401` | Die Regex-Treffer für Select und Option sind nicht aneinander gebunden und setzen eine feste Attributreihenfolge voraus. Bei mehreren Selects wird geraten (verletzt AGENTS §2). | Per DOM parsen; mehrdeutige Fälle als `UnrecognisedJobConfiguration` melden. |
| niedrig | `apps/mobile/lib/features/student_service/data/his_in_one_student_service_gateway.dart:294-304` | `downloadCertificate` hat kein abschließendes `catch (_)`, sodass z. B. eine `FormatException` unklassifiziert entweicht. | `catch (_) → StudentServiceFailure(unknown)` wie in `fetchOverview`. |
| niedrig | `apps/mobile/lib/features/grades/application/grade_account_controller.dart:225-226` | Scheitert `_portalStore.write` nach dem Speichern der Zugangsdaten, wird ein Fehler gemeldet, das Konto bleibt aber gespeichert und wird später still mit HISinOne verbunden. | Bei einem Fehler die Zugangsdaten verifiziert zurückrollen oder die Portalwahl zuerst schreiben. |
| niedrig | `apps/mobile/lib/features/grades/data/his_in_one_grades_gateway.dart:80-81` | Im Fall `empty` fehlen die `examReports`, sodass „Übersicht fehlender Leistungen“ nicht erreichbar ist. | Auch im `empty`-Fall `findExamReports` ausführen. |
| niedrig | `apps/mobile/lib/features/grades/presentation/grade_setup_screen.dart:125-132` | Der Browser-Link führt vor der Einrichtung fest zu HIS-QIS, obwohl HISinOne Standard ist. | `hisInOneProfileProvider.portalUrl` verwenden oder beide Portale anbieten. |
| niedrig | `apps/mobile/lib/features/grades/presentation/grade_messages.dart:36-39` | Noten werden auf eine Nachkommastelle gerundet (2,37 → 2,4), obwohl die Doku sagt, die Werte würden „unverändert übernommen“. | Variable Nachkommastellen bzw. den Rohtext des Portals anzeigen. |
| niedrig | `apps/mobile/lib/features/nextcloud/application/nextcloud_account_controller.dart:56-61` | Ein Abbruch während `startLogin()` wird nicht geprüft, der Browser-Login öffnet sich trotzdem. | Vor `open()` die Abbruchanfrage bzw. Generation prüfen. |
| niedrig | `docs/grades.md:159, 447, 501, 522`; `apps/mobile/lib/features/grades/data/secure_grade_portal_store.dart:24` | Die Doku nennt `hisQisLegacy` als Fallback (der Code wechselt auf HISinOne) und die nicht vorhandene Funktion `allowsDocumentDownload`. | An den Code angleichen (`examReportDownloadRoute`). |
| niedrig | `apps/mobile/lib/l10n/app_de.arb:1305, 1327, 1463` (+ en) | `gradeSetupPortalLink`, `gradesReenter` und `studentServiceCertificateReady` sind ungenutzt. | Entfernen oder anbinden. |

