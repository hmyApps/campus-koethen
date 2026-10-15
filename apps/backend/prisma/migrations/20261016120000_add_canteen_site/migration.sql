-- AlterTable
-- Which campus site a canteen belongs to. Existing rows are the Köthen canteens;
-- the seed sets the right site for every canteen on its next run.
ALTER TABLE "canteens" ADD COLUMN     "siteKey" TEXT NOT NULL DEFAULT 'koethen';
