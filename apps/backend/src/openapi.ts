import type { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';

/**
 * Shared OpenAPI metadata, used both by the running server (/docs) and by the
 * generator that writes packages/openapi/openapi.json, so the published
 * contract and the live documentation cannot drift apart.
 */
export function buildOpenApiConfig(builder: DocumentBuilder) {
  return builder
    .setTitle('Campus Köthen API')
    .setDescription(
      [
        'Public read-only API of the Campus Köthen app.',
        '',
        'Campus Köthen is an independent, unofficial campus app. It is neither developed',
        'nor operated by Hochschule Anhalt, nor is it officially endorsed by the university.',
        '',
        'All content endpoints accept `locale=de|en` (default `de`) and report',
        '`requestedLocale`, `resolvedLocale` and `translationFallback` in their metadata.',
        'Canteen dish text comes from a German-only source and is never machine-translated.',
      ].join('\n'),
    )
    .setVersion('1.2.4')
    .setLicense('AGPL-3.0-only', 'https://www.gnu.org/licenses/agpl-3.0.html')
    .setContact('Campus Köthen App', 'https://github.com/Leviora-Studio/campus-koethen', '')
    .addTag('health', 'Liveness and readiness probes')
    .addTag('environment', 'Public deployment disclosure flags')
    .addTag('posts', 'Posts (news and events), channels, and tags')
    .addTag('contacts', 'Contact areas and persons')
    .addTag('canteens', 'Canteens and menus')
    .addTag('public-calendars', 'Public Google calendars (read-only, synced via public ICS)')
    .build();
}

/**
 * Mounts Swagger UI at `/docs` and the document at `/docs-json` — or does not.
 *
 * `enabled` is the resolved DOCS_ENABLED, which defaults to off in production.
 * The page is real HTML on the same origin the media endpoint serves bytes
 * from, and it deliberately runs under a looser CSP than the API
 * (DOCS_CONTENT_SECURITY_POLICY). Since the contract is already published and
 * versioned in packages/openapi/openapi.json, serving it live is worth being a
 * decision rather than a default.
 *
 * @returns whether the routes were mounted.
 */
export function setupOpenApiDocs(app: INestApplication, enabled: boolean): boolean {
  if (!enabled) {
    return false;
  }
  const document = SwaggerModule.createDocument(app, buildOpenApiConfig(new DocumentBuilder()));
  SwaggerModule.setup('docs', app, document, { jsonDocumentUrl: 'docs-json' });
  return true;
}
