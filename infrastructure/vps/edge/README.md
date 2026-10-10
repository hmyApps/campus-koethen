# Nginx for test and production

This directory contains complete Nginx profiles for the `erikspace.eu` test
deployment and the `sturahsa.de` production deployment. Both use the same
capacity contract for an audience of 3,000 students, including clients that
share a public campus NAT address. Each profile contains no placeholders and
can be installed unchanged on its dedicated Debian/Ubuntu VPS.

## Files

- `campus-shared-capacity.conf` — shared-NAT-aware rate and connection zones,
  upstream keepalive pools and the public media edge cache;
- `nginx.conf` — complete main configuration with automatic workers, 16,384
  connections per worker, reusable client connections and TLS session cache;
- `nginx-systemd-limits.conf` — systemd file-descriptor ceiling matching the
  Nginx worker limit.

Choose exactly one of these environment-specific sets:

| Profile    | ACME bootstrap                          | Final API VHost                       | Final CMS VHost                     | Certificate name            |
| ---------- | --------------------------------------- | ------------------------------------- | ----------------------------------- | --------------------------- |
| Test       | `campus-test-acme-bootstrap.conf`       | `campus-test-api.erikspace.eu.conf`   | `campus-test-cms.erikspace.eu.conf` | `campus-koethen-test`       |
| Production | `campus-production-acme-bootstrap.conf` | `campus-koethen-api.sturahsa.de.conf` | `koethen-cms.sturahsa.de.conf`      | `campus-koethen-production` |

The test VHosts belong with `../campus-test-api.example`; the production
VHosts belong with `../campus-production.example`. Both sets reuse
`campus-shared-capacity.conf`, `nginx.conf` and
`nginx-systemd-limits.conf`. Do not mix domains, certificates or VHosts between
profiles.

Do not install the bootstrap and final files at the same time. They define the
same port-80 server names.

Remove an older installed `campus-api.conf` before enabling the final API file.
The repository no longer contains that placeholder-based predecessor.

The limits are generous enough not to treat a campus NAT address as one app
user. They also impose a separate global ceiling so an extreme burst is
smoothed before it reaches the single backend process. These are conservative
operating assumptions, not measured capacity: a later load test is still
required before claiming a guaranteed request rate.

## Prerequisites

Before requesting the certificate:

1. both domains of the selected profile must resolve directly to that VPS;
2. TCP ports 80 and 443 must be reachable;
3. ports 3020, 3021 and 5432 must remain private. Compose binds CMS and API to
   `127.0.0.1` already;
4. install Nginx and Certbot with the distribution packages;
5. create the persistent ACME webroot and media-cache directory;
6. confirm that no other file in `conf.d` defines one of the `campus_*` zones or
   upstream names.

```bash
sudo install -d -o root -g root -m 0755 /var/www/letsencrypt
sudo install -d -o www-data -g www-data -m 0750 /var/cache/nginx/campus-media
```

The configuration assumes direct DNS. If another reverse proxy such as
Cloudflare is placed in front of Nginx, configure and verify trusted real-IP
handling before relying on the per-client rate limits.

## Host capacity configuration

Back up the host configuration before replacing it. The supplied main file
keeps both standard Debian/Ubuntu include directories, but an existing VPS may
contain additional local directives that must be retained deliberately.

```bash
sudo cp -a /etc/nginx/nginx.conf /etc/nginx/nginx.conf.before-campus
sudo install -o root -g root -m 0644 nginx.conf /etc/nginx/nginx.conf
sudo install -d -o root -g root -m 0755 /etc/systemd/system/nginx.service.d
sudo install -o root -g root -m 0644 \
  nginx-systemd-limits.conf \
  /etc/systemd/system/nginx.service.d/campus-limits.conf
sudo systemctl daemon-reload
```

`worker_processes auto` uses the available CPU cores. Each worker accepts up to
16,384 connections; proxied client and upstream sockets both count. The service
and worker open-file limits are raised to 65,535 so the connection setting is
not silently capped by the operating system.

## First certificate and installation

The commands below show the test profile. For production, use the matching
filenames and certificate name from the profile table. The exact production
Certbot command is included immediately afterwards.

Install only the bootstrap virtual host first:

```bash
sudo install -o root -g root -m 0644 \
  campus-test-acme-bootstrap.conf \
  /etc/nginx/conf.d/campus-test-acme-bootstrap.conf
sudo nginx -t
sudo systemctl restart nginx
```

Obtain one certificate containing both test domains under the predictable
certificate name used by both final virtual hosts:

```bash
sudo certbot certonly \
  --webroot \
  --webroot-path /var/www/letsencrypt \
  --cert-name campus-koethen-test \
  -d campus-test-api.erikspace.eu \
  -d campus-test-cms.erikspace.eu
```

The certificate must now exist at:

```text
/etc/letsencrypt/live/campus-koethen-test/fullchain.pem
/etc/letsencrypt/live/campus-koethen-test/privkey.pem
```

For production, install `campus-production-acme-bootstrap.conf` and obtain the
shared production certificate with:

```bash
sudo certbot certonly \
  --webroot \
  --webroot-path /var/www/letsencrypt \
  --cert-name campus-koethen-production \
  -d campus-koethen-api.sturahsa.de \
  -d koethen-cms.sturahsa.de
```

The two production VHosts expect the certificate at:

```text
/etc/letsencrypt/live/campus-koethen-production/fullchain.pem
/etc/letsencrypt/live/campus-koethen-production/privkey.pem
```

Replace the bootstrap with the shared capacity contract and final virtual
hosts:

```bash
sudo rm /etc/nginx/conf.d/campus-test-acme-bootstrap.conf
sudo install -o root -g root -m 0644 \
  campus-shared-capacity.conf \
  /etc/nginx/conf.d/campus-shared-capacity.conf
sudo install -o root -g root -m 0644 \
  campus-test-api.erikspace.eu.conf \
  /etc/nginx/conf.d/campus-test-api.erikspace.eu.conf
sudo install -o root -g root -m 0644 \
  campus-test-cms.erikspace.eu.conf \
  /etc/nginx/conf.d/campus-test-cms.erikspace.eu.conf
sudo nginx -t
sudo systemctl reload nginx
sudo certbot renew --dry-run
```

The port-80 blocks in the final files keep the ACME webroot reachable for
automatic renewal and redirect all other requests to HTTPS.

For later application deployments, copy the shared capacity file and the two
final hosts only when their contents changed. Changes to `nginx.conf` or the
systemd limit require `systemctl daemon-reload` and an Nginx restart; ordinary
VHost changes need only `nginx -t` followed by a reload. A normal container
rollout does not require an Nginx reload because ports and domains remain
stable.

## API edge contract

The API is public and unauthenticated, so its final host applies these limits
before a request reaches Node:

| Promise                   | Value                                                        |
| ------------------------- | ------------------------------------------------------------ |
| Public paths              | `/v1/`, `/health/live`, `/health/ready`, `/docs*`            |
| Every other path          | `404`                                                        |
| General, campus NAT       | 1,200 requests/s, burst 12,000                               |
| General, whole API        | 600 requests/s, burst 6,000; delayed after first 1,200       |
| Media, campus NAT         | 120 requests/s, burst 1,000                                  |
| Media, whole API          | 60 requests/s, burst 600; delayed after first 120            |
| Documentation, campus NAT | 100 requests/s, burst 500                                    |
| Documentation, whole API  | 50 requests/s, burst 250; delayed after first 50             |
| Health probes, source NAT | 20 requests/s, burst 100                                     |
| Health probes, whole API  | 50 requests/s, burst 200                                     |
| General connections       | 3,000 per NAT and 4,000 globally                             |
| Media connections         | 500 per NAT and 750 globally                                 |
| Public media cache        | 5 GiB maximum, 7 d inactive; only 200 (24 h) and 404 (1 min) |
| Request body              | maximum 1 KiB; the public API is read-only                   |
| Allowed methods           | `GET`, `HEAD`, `OPTIONS`                                     |
| Upstream                  | keepalive pool to `127.0.0.1:3021`                           |

The media cache ignores the upstream `Cache-Control` and `Expires` headers
(`proxy_ignore_headers`): nginx would otherwise prefer them over
`proxy_cache_valid`, and a single error answer carrying a long `max-age` was
kept for a day. The API marks every error answer `no-store` as well.

`/docs` and `/docs-json` are intentionally public because the API is a public
read-only contract. `DOCS_ENABLED=true` in the deployment environment must
remain aligned with that edge decision.

## CMS edge contract

The CMS host forwards to `http://127.0.0.1:3020`. It deliberately adds no HTTP
Basic Auth: Strapi Admin provides its own login, and the Strapi content API has
no anonymous public role. The backend does not use the public CMS domain; it
connects over the internal Compose network with its server-side read-only
token.

Nginx accepts at most 30 MiB per request, leaving multipart overhead for the
CMS limit `UPLOAD_SIZE_LIMIT_BYTES=26214400` (25 MiB). Larger uploads are
rejected at the edge before they reach Strapi. The CMS ceiling is 100
requests/s per NAT and 200 requests/s globally, with generous bursts; its
global simultaneous connection ceiling is 750. App users never access this
host.

## Verification

After the containers and Nginx are running:

```bash
curl -I http://campus-test-api.erikspace.eu/health/ready
curl -I http://campus-test-cms.erikspace.eu/_health
curl -i https://campus-test-api.erikspace.eu/health/ready
curl -i https://campus-test-cms.erikspace.eu/_health
curl -i https://campus-test-api.erikspace.eu/
```

Expected results:

- both HTTP requests redirect to HTTPS;
- API readiness returns `200`;
- CMS health returns `204`;
- the API root returns `404` because it is not on the allowlist.

Finally, confirm that the capacity zones, upstream pools and cache were loaded:

```bash
sudo nginx -T 2>&1 | grep -E \
  'campus_api_global|campus_media_cache|campus_api_backend|worker_connections 16384'
systemctl show nginx --property=LimitNOFILE
```

The output must show the global request zone, media cache, API upstream,
16,384-worker connection setting and `LimitNOFILE=65535`. This verifies the
loaded contract without intentionally creating load. Operational logs include
request time, upstream time, cache status and rate-limit status; monitor them
for unexpected `429`, `5xx` or increasing response times.
