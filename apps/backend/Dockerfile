# Campus Köthen — Campus API and worker image
#
# Build context is the REPOSITORY ROOT, because this is a pnpm workspace:
#   docker build -f apps/backend/Dockerfile -t campus-app-backend:local .
#
# One image, two entrypoints:
#   API    -> node dist/main.js
#   Worker -> node dist/worker.js
#
# Published only for linux/amd64. Runs as a non-root user.

# ---------------------------------------------------------------------------
# Stage 1 — install workspace dependencies (cached on manifests alone)
# ---------------------------------------------------------------------------
FROM node:24.21.0-alpine AS deps

RUN corepack enable
WORKDIR /repo

# Only the manifests, so a source-only change does not bust the install cache.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY .node-version ./
COPY scripts/check-node-version.mjs scripts/
COPY patches/braces@3.0.3.patch patches/
COPY apps/backend/package.json apps/backend/
COPY apps/cms/package.json apps/cms/
COPY packages/openapi/package.json packages/openapi/
# Not a backend dependency, but apps/cms links to it — pnpm resolves the whole
# workspace, so the manifest has to exist or the install fails.
COPY packages/campus-map/package.json packages/campus-map/

RUN pnpm install --frozen-lockfile --filter @campus/backend...

# ---------------------------------------------------------------------------
# Stage 2 — generate the Prisma client and compile TypeScript
# ---------------------------------------------------------------------------
FROM deps AS build

COPY apps/backend apps/backend
COPY packages/campus-map packages/campus-map

# prisma.config.ts resolves env('DATABASE_URL') eagerly, so the variable has to
# be SET for `prisma generate` — but it is never CONNECTED to at build time.
# This obvious placeholder satisfies the config loader, lives only in this build
# stage, and never reaches the runtime image. The real URL comes from the
# environment at deploy time.
ENV DATABASE_URL=postgresql://placeholder:placeholder@127.0.0.1:5432/placeholder

RUN pnpm --filter @campus/backend exec prisma generate \
 && pnpm --filter @campus/backend exec nest build

# `pnpm deploy` resolves the workspace links into a self-contained directory
# with production dependencies only — no dev tooling ends up in the runtime.
RUN pnpm --filter @campus/backend deploy --prod --legacy /opt/deploy

# ---------------------------------------------------------------------------
# Stage 3 — runtime
# ---------------------------------------------------------------------------
FROM node:24.21.0-alpine AS runtime

# openssl is required by Prisma; tini gives us correct signal handling so the
# worker's SIGTERM shutdown path actually runs.
RUN apk add --no-cache openssl tini

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
    PORT=3000

WORKDIR /opt/app

# node:alpine already ships an unprivileged `node` user (uid 1000).
COPY --from=build --chown=node:node /opt/deploy/node_modules ./node_modules
COPY --from=build --chown=node:node /opt/deploy/dist ./dist
COPY --from=build --chown=node:node /opt/deploy/package.json ./package.json
# Migrations travel with the image so `prisma migrate deploy` can be run as a
# one-off task against the server database.
COPY --from=build --chown=node:node /opt/deploy/prisma ./prisma
COPY --from=build --chown=node:node /opt/deploy/prisma.config.ts ./prisma.config.ts

# A deployment image that carries migrations but cannot execute them is not a
# deployable artefact. Keep this assertion in the image build itself so the
# Images workflow fails before publishing a broken migration contract.
#
# Checking that the binary and the folder exist is NOT enough — that version of
# this test passed while the published image was in fact unusable: prisma.config.ts
# imports `dotenv/config`, dotenv sat in devDependencies, and `pnpm deploy --prod`
# dropped it. The migration gate then died on the server with
# "Cannot find module 'dotenv/config'".
#
# So the test now LOADS the config the way every real Prisma command does.
# `prisma validate` parses prisma.config.ts and the schema without opening a
# connection, so the placeholder URL below is never dialled — it exists only
# because the config resolves DATABASE_URL eagerly and would otherwise throw.
RUN test -x /opt/app/node_modules/.bin/prisma \
 && test -d /opt/app/prisma/migrations \
 && test -f /opt/app/dist/cli/seed-user-test-data.js \
 && node -e "require.resolve('dotenv/config')" \
 && DATABASE_URL='postgresql://placeholder:placeholder@127.0.0.1:5432/placeholder?schema=public' \
    /opt/app/node_modules/.bin/prisma validate \
 && echo 'migration runtime contract ok: prisma config loads and the schema validates'

USER node

EXPOSE 3000

# Liveness only — it must not fail because a dependency is down, otherwise a
# database outage would turn into a container restart loop.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/health/live').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/sbin/tini", "--"]

# Overridden with ["node","dist/worker.js"] for the worker container.
CMD ["node", "dist/main.js"]
