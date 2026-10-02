# Campus API and canteen worker

Campus Köthen App · `AGPL-3.0-only` · Copyright © 2026 Leviora Studio and Jona Loreen Sommer

NestJS service that is the **only** interface the mobile app talks to. It wraps
Strapi and the canteen source so the client never reaches either directly.

One codebase, two entrypoints:

| Entrypoint | Command               | Role                                     |
| ---------- | --------------------- | ---------------------------------------- |
| API        | `node dist/main.js`   | HTTP server on `0.0.0.0:3000`            |
| Worker     | `node dist/worker.js` | Canteen synchronisation, every two hours |

They run as **separate containers from the same image**, so a slow or failing
sync can never block the API or trigger its restart.

## Endpoints

|                                                                                                |                                                         |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `GET /health/live`                                                                             | Process only. Never fails because a dependency is down. |
| `GET /health/ready`                                                                            | Database and CMS, each with a bounded timeout.          |
| `GET /docs`, `GET /docs-json`                                                                  | Swagger UI and the OpenAPI document.                    |
| `GET /v1/posts/channels`, `/v1/posts/tags`, `/v1/posts/events`, `/v1/posts`, `/v1/posts/:slug` | Posts (Beiträge und Events)                             |
| `GET /v1/contact-areas`, `/v1/contact-areas/:slug`                                             | Contacts                                                |
| `GET /v1/canteens`, `/v1/canteens/:slug/menu`                                                  | Canteens                                                |

The binding contract is [`docs/api.md`](../../docs/api.md); the generated
artefact is [`packages/openapi/openapi.json`](../../packages/openapi/openapi.json),
and CI fails if the two drift apart.

## Local development

Local commands require the repository's exact Node.js pin, currently 24.21.0,
with pnpm supplied through Corepack. Run `pnpm node:check` from the repository
root before diagnosing toolchain-dependent failures.

```bash
cp .env.example .env
pnpm --filter @campus/backend prisma:generate
pnpm --filter @campus/backend prisma:migrate:dev
pnpm --filter @campus/backend start:dev
```

Requires the local database from
[`infrastructure/local`](../../infrastructure/local). Full walkthrough:
[`docs/local-development.md`](../../docs/local-development.md).

### Administrative commands

```bash
pnpm --filter @campus/backend seed:canteens        # idempotent
pnpm --filter @campus/backend sync:canteens        # against the live source
pnpm --filter @campus/backend sync:canteens -- --fixture  # against stored fixtures
pnpm --filter @campus/backend openapi:generate
```

Synchronisation is a **CLI command, not an HTTP endpoint**. An unauthenticated
sync route would let anyone drive load onto a third-party service.

## Tests

```bash
pnpm --filter @campus/backend lint
pnpm --filter @campus/backend typecheck
pnpm --filter @campus/backend test
```

The canteen tests run against a **real PostgreSQL**. The guarantee they protect
— that an empty, invalid or failed upstream response never deletes stored data —
is a statement about database state, so asserting it against a mock would prove
nothing.

## Design notes

- **Nothing from Strapi leaks.** `documentId`, `attributes`, `localizations` and
  `populate` metadata stop at the mappers. Public DTOs are written out field by
  field rather than spread, so a new upstream field cannot escape by accident.
- **German is the canonical locale.** The requested locale is overlaid on top of
  it, so an untranslated article keeps its German text and sets
  `translationFallback` instead of disappearing. Nothing is machine-translated.
- **Canteen text is never translated at all.** The source is German-only; meals
  carry `sourceLanguage: "de"` so the client can say so honestly.
- **Money is `Decimal`**, transported as a decimal string. No float arithmetic.
- **`food.image_url` is parsed and discarded.** No canteen images are stored or
  served, and there is no image column in the schema.
- **The timetable source is fully encapsulated.** WebUntis is reached only by the
  worker, only server-side, and its base URL, headers, school year id and class
  ids never appear in a public DTO or in the app. A client request never
  triggers an upstream call — otherwise the API would become an unthrottled
  proxy onto a third party.
- **The timetable ships dormant.** `WEBUNTIS_ENABLED` defaults to `false` until
  automated use of that source is cleared; the API then reports
  `featureEnabled: false` and `dataState: "unavailable"` rather than erroring.
- **Unknown content blocks are dropped server-side** and reported in
  `meta.droppedBlockTypes`, so a new CMS block type cannot break a detail screen.
- **Responses are compressed on the wire, not in content.** `br` or `gzip` from
  1 KiB upwards, whenever the client offers it; a client that offers nothing
  gets the identical bytes it got before. The media endpoint is excluded — its
  allowlist admits raster images only, and those are already compressed.

## Configuration

Every variable is validated once at boot by `src/config/env.schema.ts`. A bad
value fails the process immediately and reports the offending **key only** —
never the value, so a malformed `DATABASE_URL` cannot print a password into the
logs. See [`.env.example`](.env.example).
