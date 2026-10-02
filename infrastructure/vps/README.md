# Portable VPS deployment

This directory is the source-checkout-free deployment contract for Campus
Koethen. The target server pulls immutable CMS and backend images from GitHub
Container Registry (`ghcr.io/leviora-studio/campus-koethen/...`);
it does not build images and does not need a clone of this repository.

GitHub Actions builds and scans the images after every CI gate passes on `main`
or a version tag. It publishes only images that pass the blocking Trivy scan;
deployments remain manual. See `docs/architecture.md` §7.1.

## Files needed on the VPS

Only two files are required for the Compose application runtime:

```text
compose.yaml
.env
```

The database bootstrap is embedded in `compose.yaml`. PostgreSQL data and
Strapi uploads live in named Docker volumes. Nginx and TLS termination remain
outside Docker and forward to the loopback ports configured in `.env`.

The host additionally needs the directly installable Nginx bundle in
[`edge/`](edge/README.md): main process and file-descriptor tuning, shared-NAT
and global capacity limits, upstream keepalive, a media cache, the two final
virtual hosts and the temporary ACME bootstrap. It is sized as a conservative
configuration for 3,000 students, including many devices behind the same campus
NAT address. Nginx remains a manual host-level deployment; Compose does not
install or reload it.

`generate-env-secrets.sh` is an optional first-install helper. It fills only
empty credential assignments in `.env`, never prints their values and never
overwrites an existing value. The running stack does not need the script.

`manage-user-test-data.sh` is an optional, guarded helper for a controlled user
test. It previews, refreshes or removes only the synthetic Mensa and
timetable rows owned by the `user-test` source. The app discloses the test
environment globally; individual cards keep natural labels.

## Environment profiles

Every committed environment file is a non-secret template. Copy exactly one to
`.env` on its target VPS and fill its empty credentials there:

| Template                    | Purpose                                                      |
| --------------------------- | ------------------------------------------------------------ |
| `.env.example`              | Generic installation with placeholder domains and safe gates |
| `campus-test-api.example`   | User-test deployment on the two `erikspace.eu` test domains  |
| `campus-production.example` | Production on the two `sturahsa.de` domains                  |

The test template enables the guarded synthetic user-test dataset. The
production template enables canteen synchronization, public calendars and API
documentation, but keeps `USER_TEST_DATA_ENABLED=false`. Both templates keep
real WebUntis requests disabled until the documented organisational release
gate has been cleared. The production addresses are
`https://campus-koethen-api.sturahsa.de` for the backend and
`https://koethen-cms.sturahsa.de` for Strapi.

News, contacts and rooms are always served from Strapi and have no separate
enable switch. Mail, grades, Moodle and requests remain direct device
integrations by design and therefore have no VPS feature flag.
`SEED_DEMO_CONTENT` stays off in both concrete templates because sample-content
seeding is not a product feature and is forbidden in the production-mode CMS
container.

Both concrete templates contain the public source configuration used by the
worker:

- `https://meine-mensa.de/api/food_plans`, with the two versioned Koethen
  location IDs 7 (Fasanerieallee) and 22 (Lohmannstrasse);
- `https://hsa.webuntis.com/WebUntis/api/rest/view/v1`, with the anonymous
  Hochschule Anhalt school identifier `hsa`;
- public Google calendar share URLs maintained in Strapi. Their fixed public
  ICS feed URLs are constructed server-side and are deliberately not an
  environment variable.

`WEBUNTIS_ENABLED=true` performs real automated requests to the public-view
interface. Its use must be organizationally cleared for the selected
deployment. A template is not proof of the effective value on a host: before a
release, operators must check the deployed environment and verify
`GET /v1/timetable/status`. Until approval, that response must report
`featureEnabled: false` in production. The synthetic test profile may still
report the feature as available because `USER_TEST_DATA_ENABLED=true`, without
contacting WebUntis.

## Download the test profile without cloning the repository

Create an empty deployment directory on the VPS and download the two runtime
files, the optional non-secret helpers and the complete Nginx setup:

```bash
mkdir -p /root/test/docker/campus
cd /root/test/docker/campus
mkdir -p edge
curl -fsSLO https://raw.githubusercontent.com/Leviora-Studio/campus-koethen/main/infrastructure/vps/compose.yaml
curl -fsSL https://raw.githubusercontent.com/Leviora-Studio/campus-koethen/main/infrastructure/vps/campus-test-api.example -o .env
curl -fsSLO https://raw.githubusercontent.com/Leviora-Studio/campus-koethen/main/infrastructure/vps/generate-env-secrets.sh
curl -fsSLO https://raw.githubusercontent.com/Leviora-Studio/campus-koethen/main/infrastructure/vps/manage-user-test-data.sh
curl -fsSL https://raw.githubusercontent.com/Leviora-Studio/campus-koethen/main/infrastructure/vps/edge/README.md -o edge/README.md
curl -fsSL https://raw.githubusercontent.com/Leviora-Studio/campus-koethen/main/infrastructure/vps/edge/campus-test-acme-bootstrap.conf -o edge/campus-test-acme-bootstrap.conf
curl -fsSL https://raw.githubusercontent.com/Leviora-Studio/campus-koethen/main/infrastructure/vps/edge/campus-shared-capacity.conf -o edge/campus-shared-capacity.conf
curl -fsSL https://raw.githubusercontent.com/Leviora-Studio/campus-koethen/main/infrastructure/vps/edge/campus-test-api.erikspace.eu.conf -o edge/campus-test-api.erikspace.eu.conf
curl -fsSL https://raw.githubusercontent.com/Leviora-Studio/campus-koethen/main/infrastructure/vps/edge/campus-test-cms.erikspace.eu.conf -o edge/campus-test-cms.erikspace.eu.conf
curl -fsSL https://raw.githubusercontent.com/Leviora-Studio/campus-koethen/main/infrastructure/vps/edge/nginx.conf -o edge/nginx.conf
curl -fsSL https://raw.githubusercontent.com/Leviora-Studio/campus-koethen/main/infrastructure/vps/edge/nginx-systemd-limits.conf -o edge/nginx-systemd-limits.conf
chmod 600 .env
chmod 700 generate-env-secrets.sh
chmod 700 manage-user-test-data.sh
```

These commands intentionally download the `erikspace.eu` test profile. For the
production VPS, use `campus-production.example` as `.env` and the production
Nginx files listed in [`edge/README.md`](edge/README.md); do not mix files from
the two profiles.

If the repository is private, copy the files over an authenticated channel
instead (for example with `gh`, `scp`, or curl with a private token header). Do
not place a GitHub token in a public URL or shell history.

Before the public verification, prepare DNS, ports 80/443, Nginx and the first
TLS certificate exactly as described in [`edge/README.md`](edge/README.md).
That is a one-time host setup. Start with the ACME bootstrap file and replace it
with the two final virtual hosts after Certbot has issued the shared
certificate.

Generate all first-install database and Strapi credentials locally on the VPS:

```bash
./generate-env-secrets.sh .env
```

The command is safe to repeat: non-empty values are preserved, and the script
does not generate the later Strapi read-only API token. Edit `.env` and set
`CAMPUS_IMAGE_TAG` to the immutable
`sha-<full commit SHA>` tag from a successful GitHub Actions run. CMS and
backend must use the same tag. Leave `STRAPI_API_TOKEN` empty until the first
CMS start.

Validate interpolation without printing the resolved secret-bearing config:

```bash
docker compose config --quiet
```

If the GHCR packages are private, authenticate Docker to `ghcr.io` once on the
VPS using a dedicated personal access token (classic) with only the
`read:packages` scope. GitHub currently requires a classic token for GitHub
Packages authentication; authorize it for the organization as well if SSO is
enforced. See GitHub's
[Container registry authentication documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic).

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin
```

This stores the credentials safely in `~/.docker/config.json` on the server
without checking them into `.env` or any repository files. Public images need no
login.

## First start

Start PostgreSQL, its idempotent bootstrap, and Strapi:

```bash
docker compose pull db db-init cms
docker compose up -d db cms
docker compose ps --all
```

Create the first Strapi administrator at the configured CMS URL. Then create a
server-side read-only API token, put it into `STRAPI_API_TOKEN` in `.env`, and
keep Strapi content unavailable without an API token.

## Room catalogue bootstrap

The CMS image already contains the validated technical room catalogue from
`packages/campus-map`. Compose does not write that catalogue into Strapi during
startup: changing a live editorial database remains an explicit, reviewable
operation. The secret helper and `db-init` do not perform this sync either.

Once `docker compose ps --all` reports the CMS as healthy, preview the exact
changes without writing anything:

```bash
docker compose exec cms node dist/scripts/rooms-sync.js --dry-run
```

Review the reported create, update and deactivate counts. If the plan is
correct, apply it and immediately verify idempotency with another dry run:

```bash
docker compose exec cms node dist/scripts/rooms-sync.js
docker compose exec cms node dist/scripts/rooms-sync.js --dry-run
```

The final dry run should report zero creates, updates and deactivations. The
sync creates new catalogue rooms, refreshes catalogue-managed labels and
deactivates rooms that disappeared; it never deletes rooms and never overwrites
editorial display names, descriptions, visibility or contact relations. An
invalid catalogue aborts before any CMS write.

The map geometry remains bundled in the mobile app independently of this
operation. Without the Strapi sync, the map can still render, but `/v1/rooms`,
room search and room/contact links have no room rows to expose. Repeat the
review-and-apply sequence after deploying an image whose campus-map catalogue
changed.

Apply the committed application migrations and start API and worker:

```bash
docker compose pull api worker migrate
docker compose --profile migrate run --rm migrate
docker compose up -d api worker
```

The host reverse proxy should now forward the configured public CMS URL to
`CMS_BIND_ADDRESS:CMS_HOST_PORT` and the public API URL to
`API_BIND_ADDRESS:API_HOST_PORT`.

All worker cron expressions are evaluated in `WORKER_TIME_ZONE`. The generic
configuration uses `UTC`; the erikspace.eu test configuration deliberately uses
`Europe/Berlin`, including its daylight-saving transitions. Invalid IANA zone
names make the backend fail configuration validation instead of silently using
the host timezone.

## Verify

With the erikspace.eu test profile:

```bash
curl -i http://127.0.0.1:3020/_health
curl -i http://127.0.0.1:3021/health/live
curl -i http://127.0.0.1:3021/health/ready
curl -i https://campus-test-cms.erikspace.eu/_health
curl -i https://campus-test-api.erikspace.eu/health/ready
docker compose ps --all
docker compose logs --since=10m --tail=200 cms api worker
```

Expected HTTP statuses are 204 for the CMS health endpoint and 200 for both API
health endpoints. `db-init` should be exited with status 0; it is a successful
one-off service, not a daemon.

For production, use the same commands with
`https://koethen-cms.sturahsa.de/_health` and
`https://campus-koethen-api.sturahsa.de/health/ready`.

## Controlled user-test dataset (test environment only)

Set `USER_TEST_DATA_ENABLED=true` only on the temporary deployment used for the
user test. The erikspace.eu test example already opts in. The flag both unlocks
the write operation and makes `GET /v1/environment` advertise the deployment,
which displays the global bilingual disclosure in the app.

After migrations and the API image are current, preview and seed the rolling
dataset:

```bash
./manage-user-test-data.sh --dry-run
./manage-user-test-data.sh --seed
```

The operation is idempotent. Repeating `--seed` moves the menu window to today
and the timetable window to the current week, updates existing records and
removes older rows from this seed only. It creates meals for both configured
Köthen canteens and one selectable timetable group whose room references come
from the current canonical fictional building catalogue. It does not create a
Google calendar; configure the separate public test calendar in Strapi.

To end the user test, remove the rows first and only then set
`USER_TEST_DATA_ENABLED=false` and recreate API and worker:

```bash
./manage-user-test-data.sh --remove
docker compose up -d --force-recreate api worker
```

The environment endpoint continues disclosing synthetic content while seeded
rows remain, even if the flag is disabled too early.

## Normal rollout

Make a database and uploads backup first. Then change the single
`CAMPUS_IMAGE_TAG` value in `.env` and run:

```bash
docker compose config --quiet
docker compose pull cms api worker migrate
docker compose stop api worker
docker compose --profile migrate run --rm migrate
docker compose up -d cms
# Wait until the CMS is healthy, then review before applying.
docker compose exec cms node dist/scripts/rooms-sync.js --dry-run
docker compose exec cms node dist/scripts/rooms-sync.js
docker compose exec cms node dist/scripts/rooms-sync.js --dry-run
docker compose up -d api worker
docker compose ps --all
```

Nginx needs no deployment change because the host ports remain stable. An image
rollback uses the previous immutable tag, but it does not undo a database
migration.

## Persistence and secrets

Compose creates two named volumes under `COMPOSE_PROJECT_NAME`:

- `postgres_data` contains both isolated databases;
- `strapi_uploads` contains uploaded CMS files.

Back up both before upgrades and keep offsite backups with tested restores.
Never run `docker compose down --volumes` for an installation whose data must be
retained.

The committed `*.example` files contain no credentials. The filled `.env` is
ignored by Git and must exist only on the target server or in an appropriate
secret manager.
