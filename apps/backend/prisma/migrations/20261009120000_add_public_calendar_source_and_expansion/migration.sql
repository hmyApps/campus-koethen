-- AlterTable
ALTER TABLE "public_calendars" ADD COLUMN     "lastExpandedTo" TIMESTAMP(3),
ADD COLUMN     "source" TEXT NOT NULL DEFAULT 'strapi';

-- Rows the synthetic user-test seed already wrote before this column existed.
-- Both markers the seed always sets must match, so an editor's calendar can
-- never be reclassified: the reserved slug prefix AND a calendar id under the
-- reserved `.invalid` TLD, which no real Google calendar can carry.
UPDATE "public_calendars"
SET "source" = 'user-test'
WHERE "slug" LIKE 'user-test-%'
  AND "googleCalendarId" LIKE '%@user-test.invalid';
