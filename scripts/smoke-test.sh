#!/usr/bin/env bash
#
# Campus Köthen — end-to-end smoke test against a running local stack.
#
#   docker compose -f infrastructure/local/compose.yaml --profile full up -d
#   ./scripts/smoke-test.sh
#
# Checks the real HTTP contract, not mocks: health probes, the locale contract,
# input bounds, and the guarantees that no Strapi internals and no canteen image
# ever reach a client.
#
# Exits non-zero on the first genuine failure.

set -uo pipefail

API="${API_BASE_URL:-http://127.0.0.1:3021}"
CMS="${CMS_BASE_URL:-http://127.0.0.1:3020}"
# The API serves /docs only when DOCS_ENABLED is true, which is off by default
# under NODE_ENV=production (every compose stack). Set EXPECT_DOCS=true or
# EXPECT_DOCS=false to assert either state; left unset, /docs is not checked.
EXPECT_DOCS="${EXPECT_DOCS:-}"

pass=0
fail=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail + 1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# expect_status <label> <url> <expected>
expect_status() {
  local label="$1" url="$2" expected="$3" status
  # curl already writes 000 via -w when the host is unreachable; `|| echo`
  # would append a second 000. Only fill in when nothing was written at all.
  status=$(curl -sS -o /dev/null -m 15 -w '%{http_code}' "$url" 2>/dev/null) || true
  status="${status:-000}"
  if [ "$status" = "$expected" ]; then
    ok "$label (HTTP $status)"
  else
    bad "$label — expected HTTP $expected, got $status  [$url]"
  fi
}

# expect_json <label> <url> <python-expression over `d`>
expect_json() {
  local label="$1" url="$2" expr="$3" body
  body=$(curl -sS -m 15 "$url" 2>/dev/null)
  if [ -z "$body" ]; then
    bad "$label — empty response  [$url]"
    return
  fi
  if printf '%s' "$body" | python3 -c "
import json,sys
d = json.load(sys.stdin)
sys.exit(0 if ($expr) else 1)
" 2>/dev/null; then
    ok "$label"
  else
    bad "$label — assertion failed: $expr  [$url]"
  fi
}

head_ "Health"
expect_status "CMS  /_health"      "$CMS/_health"       204
expect_status "API  /health/live"  "$API/health/live"   200
expect_status "API  /health/ready" "$API/health/ready"  200
case "$EXPECT_DOCS" in
  true)  expect_status "API  /docs (DOCS_ENABLED)"  "$API/docs" 200 ;;
  false) expect_status "API  /docs is disabled"     "$API/docs" 404 ;;
esac
expect_json   "readiness reports the database as ok" \
              "$API/health/ready" "d['checks']['database']['status'] == 'ok'"

head_ "Channels are dynamic and both defaults are subscribed"
expect_json "campus-news and fb5-news are present" "$API/v1/posts/channels" \
  "{'campus-news','fb5-news'} <= {c['slug'] for c in d['data']}"
expect_json "both start channels have defaultSubscribed = true" "$API/v1/posts/channels" \
  "all(c['defaultSubscribed'] for c in d['data'] if c['slug'] in ('campus-news','fb5-news'))"

head_ "Locale contract"
expect_json "de is the default"          "$API/v1/posts/channels"           "d['meta']['resolvedLocale'] == 'de'"
expect_json "?locale=en is honoured"     "$API/v1/posts/channels?locale=en" "d['meta']['resolvedLocale'] == 'en'"
expect_json "English differs from German" "$API/v1/posts/channels?locale=en" \
  "any('News from' in (c['description'] or '') for c in d['data'])"
expect_status "unsupported ?locale=fr is rejected" "$API/v1/posts/channels?locale=fr" 400

head_ "Tags & Events"
expect_json "news and event tags are present" "$API/v1/posts/tags" \
  "{'news','event'} <= {t['slug'] for t in d['data']}"
expect_json "events endpoint answers" "$API/v1/posts/events" \
  "'data' in d and 'meta' in d"

head_ "Contacts"
expect_json "areas are returned"                  "$API/v1/contact-areas" "len(d['data']) > 0"
expect_json "an area without persons stays valid" "$API/v1/contact-areas" \
  "any(a['personCount'] == 0 for a in d['data'])"
expect_status "unknown area is a 404" "$API/v1/contact-areas/does-not-exist" 404

head_ "Canteens"
expect_json "both canteens are served from the backend" "$API/v1/canteens" \
  "{'koethen-fasanerieallee','koethen-lohmannstrasse'} <= {c['slug'] for c in d['data']}"
expect_json "freshness metadata is present" "$API/v1/canteens" \
  "all('lastSuccessfulSyncAt' in c and 'dataStale' in c for c in d['data'])"
expect_json "every day of the range is returned" \
  "$API/v1/canteens/koethen-fasanerieallee/menu?from=2026-07-20&to=2026-07-22" \
  "len(d['data']['days']) == 3"
expect_json "meals carry all price groups the source provided" \
  "$API/v1/canteens/koethen-fasanerieallee/menu?from=2026-07-20&to=2026-07-22" \
  "all(len(m['prices']) >= 1 for day in d['data']['days'] for m in day['meals'])"
expect_json "the student price group is exposed" \
  "$API/v1/canteens/koethen-fasanerieallee/menu?from=2026-07-20&to=2026-07-22" \
  "all(any(p['group'] == 'student' for p in m['prices']) for day in d['data']['days'] for m in day['meals'])"
expect_json "dish text is marked as untranslated German" \
  "$API/v1/canteens/koethen-fasanerieallee/menu?locale=en&from=2026-07-20&to=2026-07-22" \
  "all(m['sourceLanguage'] == 'de' for day in d['data']['days'] for m in day['meals'])"
expect_status "unknown canteen is a 404"          "$API/v1/canteens/nope/menu" 404
expect_status "an over-wide date range is rejected" \
  "$API/v1/canteens/koethen-fasanerieallee/menu?from=2026-01-01&to=2026-12-31" 400
expect_status "pageSize above the cap is rejected" "$API/v1/posts?pageSize=999" 400

head_ "Contract guarantees"
for endpoint in /v1/posts/channels /v1/contact-areas /v1/canteens; do
  body=$(curl -sS -m 15 "$API$endpoint" 2>/dev/null)
  if printf '%s' "$body" | grep -qE '"(documentId|attributes|localizations|populate)"'; then
    bad "no Strapi internals leak from $endpoint"
  else
    ok "no Strapi internals leak from $endpoint"
  fi
done

body=$(curl -sS -m 15 "$API/v1/canteens/koethen-fasanerieallee/menu?from=2026-07-20&to=2026-07-22" 2>/dev/null)
if printf '%s' "$body" | grep -qiE '"image|imageUrl|mediathek'; then
  bad "no canteen image is served"
else
  ok "no canteen image is served"
fi

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
