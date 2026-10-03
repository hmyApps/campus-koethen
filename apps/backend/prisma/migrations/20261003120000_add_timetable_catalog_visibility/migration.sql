ALTER TABLE "timetable_groups"
ADD COLUMN "catalogVisible" BOOLEAN NOT NULL DEFAULT true;

DROP INDEX IF EXISTS "timetable_groups_active_shortName_idx";

CREATE INDEX "timetable_groups_active_catalogVisible_shortName_idx"
ON "timetable_groups"("active", "catalogVisible", "shortName");
