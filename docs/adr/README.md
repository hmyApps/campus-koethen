# Architecture Decision Records

Campus Köthen App · `AGPL-3.0-only` · Copyright © 2026 Leviora Studio and Jona Loreen Sommer

Hier liegen langlebige oder schwer umkehrbare Architekturentscheidungen. Alles, was sich ohne
Migration wieder ändern lässt, gehört **nicht** hierher, sondern in
[`../architecture.md`](../architecture.md) oder in das Dokument des betroffenen Bereichs.

## Konvention

- Dateiname: `NNNN-kurzer-titel.md`, fortlaufend, nie neu vergeben.
- Jedes ADR beginnt mit einer Kopftabelle: Status, Datum, Autor, Ticket, Ersetzt/Ersetzt durch.
- Status: **Vorgeschlagen** · **Angenommen** · **Abgelöst** · **Verworfen**.
- Ein angenommenes ADR wird **nicht rückwirkend geändert**. Eine neue Entscheidung bekommt ein
  neues ADR und verlinkt das abgelöste.
- Korrekturen an Tippfehlern, Links und Formatierung sind davon ausgenommen.

## Index

| ADR                                     | Titel                                                            | Status     |
| --------------------------------------- | ---------------------------------------------------------------- | ---------- |
| [0001](0001-push-benachrichtigungen.md) | Benachrichtigungen aus lokal vorhandenen Daten, ohne Push-Server | Angenommen |
| [0002](0002-hintergrund-abgleich.md)    | Periodischer Hintergrund-Abgleich auf dem Gerät                  | Angenommen |
