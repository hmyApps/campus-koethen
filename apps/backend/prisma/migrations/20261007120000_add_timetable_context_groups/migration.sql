-- Keep the semester catalogue relationship explicit so the client can offer
-- the next course without exposing WebUntis school-year or class identifiers.
CREATE TABLE "timetable_context_groups" (
    "contextId" TEXT NOT NULL,
    "groupId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "timetable_context_groups_pkey" PRIMARY KEY ("contextId", "groupId")
);

CREATE INDEX "timetable_context_groups_groupId_contextId_idx"
    ON "timetable_context_groups"("groupId", "contextId");

ALTER TABLE "timetable_context_groups"
    ADD CONSTRAINT "timetable_context_groups_contextId_fkey"
    FOREIGN KEY ("contextId") REFERENCES "timetable_contexts"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "timetable_context_groups"
    ADD CONSTRAINT "timetable_context_groups_groupId_fkey"
    FOREIGN KEY ("groupId") REFERENCES "timetable_groups"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
