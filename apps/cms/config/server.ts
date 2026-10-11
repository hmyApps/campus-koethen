import type { Core } from '@strapi/strapi';

/**
 * `url` and `proxy` come only from the environment (AGENTS.md §2.5).
 *
 * Behind the nginx edge Strapi must know its public HTTPS origin (absolute
 * URLs, admin panel) and must trust `X-Forwarded-Proto`/`X-Forwarded-For`, or
 * Koa sees plain HTTP and Secure cookies break. Strapi 5 reads the Koa proxy
 * flag from `server.proxy.koa` — a bare `proxy: true` is silently ignored.
 *
 * Proxy headers are trusted by default only when PUBLIC_URL is set, i.e. when
 * the CMS is deployed behind the edge. Locally, where clients connect directly,
 * forged forwarding headers are not trusted. IS_PROXIED overrides either way.
 */
const config = ({ env }: Core.Config.Shared.ConfigParams): Core.Config.Server => {
  const publicUrl = env('PUBLIC_URL', '');

  return {
    host: env('HOST', '0.0.0.0'),
    port: env.int('PORT', 1337),
    url: publicUrl,
    proxy: {
      koa: env.bool('IS_PROXIED', publicUrl !== ''),
    },
    app: {
      keys: env.array('APP_KEYS')!,
    },
    webhooks: {
      populateRelations: env.bool('WEBHOOKS_POPULATE_RELATIONS', false),
    },
  };
};

export default config;
