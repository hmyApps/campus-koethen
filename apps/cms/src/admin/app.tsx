import type { StrapiApp } from '@strapi/strapi/admin';

/**
 * Admin panel customisation.
 *
 * The prismjs global that the content-manager bundle depends on is injected
 * into the built admin bundle by `scripts/inject-prism-shim.mjs` (run by the
 * package's `build` script), not here: this module is evaluated too late to
 * help, and putting the shim in the obvious-looking place would only make it
 * look fixed. See the explanation there and
 * https://github.com/strapi/strapi/issues/25070.
 */
export default {
  config: {
    // The admin interface keeps Strapi's default locale set. Editorial CONTENT
    // is maintained in de and en, which is a content-type concern rather than
    // an admin UI language setting.
    locales: [],
  },
  bootstrap(_app: StrapiApp) {},
};
