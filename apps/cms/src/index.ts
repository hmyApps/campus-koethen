import type { Core } from '@strapi/strapi';
import { ensureLocales } from './bootstrap/locales';
import { ensureRoomAdminConfiguration } from './bootstrap/room-admin-configuration';
import { ensureTags, seedDemoContent } from './bootstrap/seed';
import { createRoomGuard } from './catalog/room-guard';
import { createEditorialGuard } from './editorial/post-guard';

export default {
  /**
   * Runs before the application is initialised.
   *
   * Installs guards into the document-service middleware chain:
   *  1. Room guard: protects catalogue-managed technical fields
   *  2. Editorial guard: enforces post requirements, reserved slugs, primary channels, and event times
   */
  register({ strapi }: { strapi: Core.Strapi }) {
    const roomGuard = createRoomGuard({
      warn: (message: string) => strapi.log.warn(`[rooms] ${message}`),
    });
    const editorialGuard = createEditorialGuard(strapi);

    strapi.documents.use((context, next) => roomGuard(context as never, next as never));
    strapi.documents.use((context, next) => editorialGuard(context as never, next as never));
  },

  /**
   * Runs before the application starts serving.
   *
   * Idempotent steps:
   *  1. Keep room labels readable in existing Content Manager layouts.
   *  2. Ensure the `de` and `en` locales exist, with German as the default.
   *  3. Create the essential tags `news` and `event` if they are missing;
   *     existing tags are never overwritten or republished.
   *  4. Optionally seed neutral demo content, gated behind SEED_DEMO_CONTENT
   *     so a production boot never writes placeholder records.
   *
   * There is deliberately no G5 role check here any more. It used to query
   * `plugin::users-permissions.role`, and that plugin is no longer installed —
   * the query resolved to nothing but a warning on every boot, so the check
   * read as active while verifying nothing. Without the plugin there is no
   * public role to misconfigure at all: `/api/*` answers 401 without a valid
   * API token. `test/no-public-role-plugin.test.ts` keeps that premise honest.
   */
  async bootstrap({ strapi }: { strapi: Core.Strapi }) {
    await ensureRoomAdminConfiguration(strapi);
    await ensureLocales(strapi);
    await ensureTags(strapi);

    if (process.env.SEED_DEMO_CONTENT === 'true') {
      await seedDemoContent({ strapi });
    }
  },
};
