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

| Datum      | Arbeit                                                             | Ergebnis                                                                               |
| ---------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| 2026-10-07 | Rekursiver Mehragenten-Bughunt (4 Runden, 19 Agenten, nur Analyse) | `docs/bughunt-audit-2026-10-07.md`: 94 validierte Bugs (9 hoch, 40 mittel, 45 niedrig) |

## Offene To-dos (Priorität absteigend)

Fixes laut Audit, jeweils TDD (AGENTS §8); Fix-Gruppen aus Audit §5 gemeinsam umsetzen.

- [ ] Hoch: A-01, A-02 (Stundenplan-Sync, Backend)
- [ ] Hoch: B-01 (öffentliche Kalender – Flags ohne Wirkung)
- [ ] Hoch: C-01 + VC-N01 (IDLE-Reconnect-Schleife, Empfängervorschläge)
- [ ] Hoch: D-02 + D-03 + VD-N01 + R3-2-N01 (HSA-GPT connect/Consent/Chat-State)
- [ ] Hoch: E-03 + G-02 (Verlust der Antrags-Statuslinks über EncryptedBox)
- [ ] Hoch: F-02 (Moodle-Erinnerung nach Fristende)
- [ ] Mittel: Fix-Gruppen D-01+D-05, E-01+VE-N01+VE-N02+E-04, danach übrige Mittel-Funde
- [ ] Niedrig: nach Kapazität; Doku-Drift (A-07, A-08, D-10, D-11, E-13, G-07, VA-N02) per Maintainer-Entscheidung
- [ ] Offen zu verifizieren: F-06 (EWS-Ganztag) und VF-N01 (Strapi-Datepicker) live; B-02/VB-N02 gegen echtes Google-ETag-Verhalten
