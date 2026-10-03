import type { Core } from '@strapi/strapi';

/**
 * MIME types the media library accepts.
 *
 * `plugin::upload.security` IS enforced server-side in the installed Strapi
 * (5.56.0): `@strapi/upload` sniffs the first 4100 bytes with `file-type` and
 * refuses anything whose DETECTED type is outside this list — an extension or a
 * declared `Content-Type` cannot override it. Verified against the installed
 * version by `test/upload-security.test.ts`, which drives the plugin's own
 * validator with exactly this configuration.
 */
const allowedMediaTypes = [
  'image/*',
  'video/*',
  'audio/*',
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.*',
  'text/plain',
  'text/csv',
];

/**
 * Refused regardless of the allow list — `deniedTypes` is checked first.
 *
 * SVG is here, not merely absent, because `image/*` MATCHES `image/svg+xml`:
 * the allow list is a wildcard regex, and the plugin even carries an explicit
 * "trust a .svg extension when image/svg+xml is allowed" branch. An SVG is a
 * script-carrying document, and uploads are served by `strapi::public` from the
 * SAME ORIGIN as the admin panel. Helmet's default CSP makes that hard to
 * exploit today — but a CSP is not the control that should be carrying this.
 * (The Campus API is unaffected either way: `media.path.ts` has never listed
 * SVG among its allowed types.)
 */
const deniedExecutableTypes = [
  'image/svg+xml',
  'application/vnd.microsoft.portable-executable',
  'application/x-msdownload',
  'application/x-msdos-program',
  'application/x-executable',
  'application/x-dosexec',
  'application/x-sh',
  'text/x-shellscript',
  'application/x-mach-binary',
];

/**
 * Largest single upload, in bytes.
 *
 * Not a preference: unset means the plugin default of 1 GB per file against
 * `strapi_uploads`, a volume with no quota. The editor role — the LOWER of the
 * two — could fill the VPS disk and take down the CMS and the shared PostgreSQL
 * with it. 25 MB comfortably covers the photographs and PDFs the editorial
 * workflow actually uses.
 */
const UPLOAD_SIZE_LIMIT_BYTES = 25 * 1024 * 1024;
const MAX_UPLOAD_SIZE_LIMIT_BYTES = 100 * 1024 * 1024;

/** Keeps an environment override from silently disabling the disk guard. */
function validatedUploadSizeLimit(value: number): number {
  if (!Number.isSafeInteger(value) || value <= 0 || value > MAX_UPLOAD_SIZE_LIMIT_BYTES) {
    throw new Error(
      `UPLOAD_SIZE_LIMIT_BYTES must be between 1 and ${MAX_UPLOAD_SIZE_LIMIT_BYTES}.`,
    );
  }
  return value;
}

const config = ({ env }: Core.Config.Shared.ConfigParams): Core.Config.Plugin => ({
  upload: {
    config: {
      sizeLimit: validatedUploadSizeLimit(
        env.int('UPLOAD_SIZE_LIMIT_BYTES', UPLOAD_SIZE_LIMIT_BYTES),
      ),
      security: {
        allowedTypes: allowedMediaTypes,
        deniedTypes: deniedExecutableTypes,
      },
    },
  },
});

export {
  MAX_UPLOAD_SIZE_LIMIT_BYTES,
  UPLOAD_SIZE_LIMIT_BYTES,
  allowedMediaTypes,
  deniedExecutableTypes,
  validatedUploadSizeLimit,
};
export default config;
