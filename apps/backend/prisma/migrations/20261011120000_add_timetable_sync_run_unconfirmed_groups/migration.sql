-- AlterTable
-- Entry runs count the classes whose own response carried errors or no day
-- for them. Existing runs predate the counter and keep the default 0.
ALTER TABLE "timetable_sync_runs" ADD COLUMN     "groupsUnconfirmed" INTEGER NOT NULL DEFAULT 0;
