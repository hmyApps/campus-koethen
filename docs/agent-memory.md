# Agenten-Gedächtnis: Campus Köthen

Arbeitsnotizen für KI-gestützte Sessions, damit eine spätere Session nahtlos fortsetzen kann
(„continue“ → an der letzten offenen Stelle weitermachen). Verbindliche Regeln stehen
ausschließlich in `AGENTS.md`; diese Datei ergänzt sie nur um Fortschritt und To-dos.

## Projekt-Eckdaten

- Monorepo: `apps/backend` (NestJS, Prisma, Node 24), `apps/cms` (Strapi 5), `apps/mobile` (Flutter, Riverpod, go_router, dio, hive_ce), `packages/campus-map`, `packages/openapi`.
- Aktuelle App-Version: `2.0.0+10` (`apps/mobile/pubspec.yaml`). Vor jedem Release-Build Versionsnummer erhöhen.
- Smoke-Check je Änderung: Release-Build (Flutter) bzw. die Gates aus `README.md`.
- In Cloud-Sessions ist Flutter/Dart nicht installiert; Backend-Gates laufen nach `pnpm install --frozen-lockfile`.

## Verlauf

| Datum      | Arbeit                                                             | Ergebnis                                                                                       |
| ---------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| 2026-10-07 | Rekursiver Mehragenten-Bughunt (4 Runden, 19 Agenten, nur Analyse) | `docs/bughunt-audit-2026-10-07.md`: 94 validierte Bugs (9 hoch, 40 mittel, 45 niedrig)         |
| 2026-10-10 | Mehragenten-Bugfix-Lauf (12 Arbeitspakete, je ein Worktree, TDD)   | Branch `fix/bughunt-2026-10-07`: 85 von 94 Funden behoben, 9 offen als Maintainer-Entscheidung |

## Stand nach dem Bugfix-Lauf (2026-10-10)

Behoben (alle mit vorher real rotem Test): alle 9 „hoch“, alle 40 „mittel“, 36 von 45 „niedrig“.
Zusätzlich behoben, nicht im Audit: `ical.js` verknüpfte Overrides UID-übergreifend (doppelter
`occurrenceKey`, Feed-Sync-Abbruch); `meta.truncated` im Kalender-Abgleich gemerkter Events;
48-dp-Ziel des Sterns in `meal_card.dart`; Race beim parallelen Schreiben von Antragsvorgängen.

Gates auf dem Endstand (lokal, Windows, Flutter 3.44.7, Node 24.11.0):

- Mobile: `gen-l10n`, `analyze --fatal-infos --fatal-warnings`, `dart format --set-exit-if-changed`
  grün; `flutter test` 3087/3087.
- Backend: `typecheck`, `lint` grün; Unit-Tests (`src/`) 44/44 Suites, 639/639.
- **Nicht ausgeführt:** alle DB-Integration-Specs (kein PostgreSQL/Docker), inkl. der neuen Fälle
  aus WP1/WP2, und die Migration `20261009120000_add_public_calendar_source_and_expansion`.

## Offene To-dos (Priorität absteigend)

- [ ] DB-Integration-Specs und neue Migration gegen eine isolierte temporäre PostgreSQL ausführen
      (AGENTS §8); Gates mit der gepinnten Node-Version 24.21.0 wiederholen (lokal 24.11.0, Root-`preinstall` scheitert).
- [ ] Maintainer-Entscheidungen: A-07 (Mensa-IDs im DTO), A-08 (`STRAPI_BASE_URL`-Default), VA-N02 (Speiseplan
      `to` = from+14 vs. Doku +13), B-11 (`workflow_dispatch` in `images.yml`), D-10 (`/api/ai-req` vs. AGENTS),
      D-11 (ungenutztes HAWKI-E2EE-Modul), E-13 (Moodle-Auto-Sync stündlich vs. Doku 24 h), G-07 (App-IDs),
      G-08 (Quellcode-Link im About, braucht Release-URL).
- [ ] Bewusste Abweichungen bestätigen: B-10 `.invalid`-Kalender im Perf-Seed bleiben aktiv; D-06 fehlende Portalwahl
      fällt weiter auf HIS-QIS zurück (1.x-Migration); HSA-GPT wird bei Kontowechsel ohne erneute Zustimmung neu
      verbunden; jedes HSA-GPT-Neuverbinden rotiert das Token.
- [ ] Folgefixes: regulärer 10-min-Mail-Sync loggt nach abgelehntem Passwort weiter ein (Rest von C-01);
      „heute“ per UTC noch in `posts.controller.ts`, `public-calendar.controller.ts`, `canteen-sync.service.ts`
      (Helper `common/time/campus-date.ts` nutzen); Aufbewahrungsfrist für `public_calendar_events` festlegen (B-02);
      vor dem Update gemerkte Ganztags-Event-Posts migrieren (VF-N01); Mail-Tests mit echter Uhr laufen ab ~01/2027 ab;
      Stundenplan-Lauf bleibt `success`, wenn einzelne Klassen unbestätigt sind (nur `errorMessage`).
- [ ] Live/real zu verifizieren: F-06 (EWS-Ganztag), C-02 (Teilabruf ohne Anhänge, echtes Postfach), D-08 (Overlay-IDs
      HISinOne), E-12 (Moodle-`wsaccessuser*`-Codes), F-08 (Gerätematrix #20), B-05/B-08 (Strapi `channels.isActive`,
      `documentId` in Relationen), B-06 (nginx `proxy_ignore_headers`), B-02/VB-N02 (Google-ETag-Verhalten).
