# Campus Köthen — Strapi 5 CMS image
#
# Build context is the REPOSITORY ROOT (pnpm workspace):
#   docker build -f apps/cms/Dockerfile -t campus-app-cms:local .
#
# Contains the pre-built admin UI, listens on 0.0.0.0:1337 and exposes
# Strapi's /_health. Published only for linux/amd64. Runs as non-root.
#
# Base image: Debian slim rather than Alpine. Strapi's image pipeline (sharp)
# ships prebuilt glibc binaries; on musl it tries to compile from source and
# fails. Slim keeps the toolchain out of the runtime layer anyway.

# ---------------------------------------------------------------------------
# Stage 1 — install workspace dependencies
# ---------------------------------------------------------------------------
FROM node:24.21.0-slim AS deps

RUN corepack enable
WORKDIR /repo

# Only the manifests, so a source-only change does not bust the install cache.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY .node-version ./
COPY scripts/check-node-version.mjs scripts/
COPY apps/cms/package.json apps/cms/
COPY apps/backend/package.json apps/backend/
COPY packages/openapi/package.json packages/openapi/
COPY packages/campus-map/package.json packages/campus-map/

RUN pnpm install --frozen-lockfile --filter @campus/cms...

# ---------------------------------------------------------------------------
# Stage 2 — build the admin panel
# ---------------------------------------------------------------------------
FROM deps AS build

COPY apps/cms apps/cms
# The room sync imports @campus/map, and `strapi build` type-checks scripts/ —
# so the package content (not just its manifest) has to be present. It is a
# devDependency, so `pnpm deploy --prod` below keeps it out of the runtime image.
COPY packages/campus-map packages/campus-map

# `strapi build` compiles the admin UI. It reads configuration but needs no
# database and no real secret.
#
# The placeholders are passed INLINE to this one command rather than via ENV:
# that keeps them out of the image metadata entirely and avoids teaching anyone
# that secrets belong in a Dockerfile. Real values arrive from the environment
# at run time.
RUN NODE_ENV=production \
    APP_KEYS=build-only-placeholder-1,build-only-placeholder-2 \
    API_TOKEN_SALT=build-only-placeholder \
    ADMIN_JWT_SECRET=build-only-placeholder \
    TRANSFER_TOKEN_SALT=build-only-placeholder \
    ENCRYPTION_KEY=build-only-placeholder \
    pnpm --filter @campus/cms run build
# NOTE: the package script, not `exec strapi build` directly — the script also
# runs scripts/inject-prism-shim.mjs, without which the admin serves a blank page.

# `pnpm deploy` resolves workspace links into a self-contained directory with
# production dependencies only.
RUN pnpm --filter @campus/cms deploy --prod --legacy /opt/deploy

# ---------------------------------------------------------------------------
# Stage 3 — runtime
# ---------------------------------------------------------------------------
FROM node:24.21.0-slim AS runtime

# tini gives correct signal handling so Strapi shuts down cleanly.
RUN apt-get update \
 && apt-get install -y --no-install-recommends tini \
 && rm -rf /var/lib/apt/lists/*

# Remove npm, npx and corepack from the RUNTIME image.
#
# Nothing here runs them: the container starts with `node dist/...` (or Strapi's
# JS entry) and any local CLI is a plain node script. npm ships its own bundled
# dependency tree, which is where every HIGH/CRITICAL finding in the first Trivy
# scan came from (tar, sigstore, picomatch, brace-expansion) — none of them our
# code, none of them reachable, all of them real scanner noise we cannot patch
# from our lockfile. Deleting the package manager removes the whole class and
# shrinks the image.
RUN rm -rf /usr/local/lib/node_modules/npm \
           /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
           /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=1337

WORKDIR /opt/app

# The node:* images already ship an unprivileged `node` user (uid 1000).
COPY --from=build --chown=node:node /opt/deploy ./

# `pnpm deploy` packs the package the way `npm pack` would, so it skips
# git-ignored paths — which is exactly where `strapi build` puts its output.
# The compiled server (dist/, including the admin bundle in dist/build) and the
# Vite client entry (.strapi/client) are therefore copied explicitly. Without
# these the container would have no admin UI and would try to rebuild at
# startup.
COPY --from=build --chown=node:node /repo/apps/cms/dist ./dist
COPY --from=build --chown=node:node /repo/apps/cms/.strapi ./.strapi

# Uploads live on a persistent volume; the directory must exist and be owned by
# the runtime user before the volume is mounted over it.
#
# `.tmp` is created for the same reason: /opt/app itself stays root-owned so the
# application cannot rewrite its own code, but Strapi needs a scratch directory
# when it boots programmatically — which is exactly how `rooms-sync` starts it.
# Without this the documented production command dies with EACCES.
RUN mkdir -p /opt/app/public/uploads /opt/app/.tmp \
 && chown -R node:node /opt/app/public /opt/app/.tmp

# Room-sync runtime contract.
#
# `node dist/scripts/rooms-sync.js --dry-run` is the documented production
# command, so the image has to be able to run it. Two things went wrong before
# and are therefore asserted here rather than trusted:
#
#  1. @campus/map sat in devDependencies, so `pnpm deploy --prod` dropped it and
#     the sync would have died with MODULE_NOT_FOUND on the target host.
#  2. The compiled script reaches the package through require(), which also
#     needs the catalogue and the SVG to be part of the deployed files — a
#     manifest-only copy resolves but cannot load.
#
# Asserting it in the image build means a broken runtime contract fails here,
# before publishing, instead of on the server.
#
# What is asserted is that the catalogue LOADS and VALIDATES, not how large it
# happens to be. An exact room count once stood here and made every catalogue
# change — a new room, a new floor — fail the image build for a reason that had
# nothing to do with the packaging this check is about. How many rooms there
# are is the catalogue's business, and the package's own tests own that number.
RUN test -f dist/scripts/rooms-sync.js \
 && node -e "const m=require('@campus/map');const{catalog,problems}=m.loadCanonical();if(problems.length)throw new Error('catalogue invalid: '+problems.join('; '));if(!catalog.rooms.length)throw new Error('catalogue loaded but carries no rooms — the deployed copy is manifest-only');console.log('rooms-sync runtime contract ok: '+catalog.rooms.length+' rooms, mapVersion '+catalog.mapVersion)"

USER node

EXPOSE 1337

VOLUME ["/opt/app/public/uploads"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||1337)+'/_health').then(r=>process.exit(r.status<400?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--"]

# Invoke the package's real JS entry directly. `node_modules/.bin/strapi` is a
# shell wrapper, so `node node_modules/.bin/strapi` fails with a SyntaxError.
CMD ["node", "node_modules/@strapi/strapi/bin/strapi.js", "start"]
