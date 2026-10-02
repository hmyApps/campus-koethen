import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { CronJob } from 'cron';
import { WorkerModule } from './worker.module';
import { JsonLogger } from './common/logger/json-logger.service';
import { ENV } from './config/app-config.module';
import { Env } from './config/env.schema';
import { CanteenSyncService } from './modules/canteen/canteen-sync.service';
import { PublicCalendarSyncService } from './modules/public-calendar/public-calendar-sync.service';
import { TimetableSyncService } from './modules/timetable/timetable-sync.service';
import { createWorkerCronJob } from './worker-cron';

/**
 * Background worker — the second entrypoint of the same image.
 *
 * Runs in its own container so a slow or failing sync cannot affect the API's
 * availability or trigger API restarts.
 *
 * Each data source is an INDEPENDENT job with its own schedule and its own
 * overlap guard. A failing canteen sync must never stop the timetable sync, and
 * vice versa: they share nothing but the process.
 */

/** One scheduled job with an overlap guard and its own error containment. */
class WorkerJob {
  private running = false;
  private job?: CronJob;

  constructor(
    private readonly name: string,
    private readonly cron: string,
    private readonly timeZone: string,
    private readonly logger: Logger,
    private readonly run: (trigger: string) => Promise<void>,
  ) {}

  async trigger(reason: string): Promise<void> {
    // A slow run must not be joined by the next tick.
    if (this.running) {
      this.logger.warn(`[${this.name}] skipping ${reason} run — still in progress`);
      return;
    }
    this.running = true;
    try {
      await this.run(reason);
    } catch (error) {
      // Contained here on purpose: an exception must not escape into the other
      // job's schedule or kill the process and lose every timer.
      this.logger.error(
        `[${this.name}] ${reason} run aborted: ${
          error instanceof Error ? error.message : 'unknown error'
        }`,
      );
    } finally {
      this.running = false;
    }
  }

  start(): void {
    this.job = createWorkerCronJob(this.cron, this.timeZone, () => {
      void this.trigger('scheduled');
    });
    this.job.start();
    this.logger.log(`[${this.name}] scheduled with "${this.cron}" in "${this.timeZone}"`);
  }

  stop(): void {
    void this.job?.stop();
  }
}

async function bootstrap(): Promise<void> {
  const app = await NestFactory.createApplicationContext(WorkerModule, {
    logger: new JsonLogger(),
  });
  app.enableShutdownHooks();

  const env = app.get<Env>(ENV);
  const logger = new Logger('Worker');
  const jobs: WorkerJob[] = [];

  // --- Canteen -------------------------------------------------------------
  const canteen = app.get(CanteenSyncService);
  await canteen.seedCanteens();

  const canteenJob = new WorkerJob(
    'canteen',
    env.CANTEEN_SYNC_CRON,
    env.WORKER_TIME_ZONE,
    logger,
    async (trigger) => {
      const outcomes = await canteen.syncAll();
      for (const outcome of outcomes) {
        logger.log(
          `[canteen:${trigger}] ${outcome.canteenSlug}: ${outcome.status} ` +
            `(received=${outcome.recordsReceived} upserted=${outcome.recordsUpserted} ` +
            `rejected=${outcome.recordsRejected} withdrawn=${outcome.recordsRemoved})`,
        );
      }
    },
  );
  jobs.push(canteenJob);

  // --- Timetable -----------------------------------------------------------
  const timetable = app.get(TimetableSyncService);

  // Separate jobs keep catalogue and entry failures isolated. Their daily
  // defaults are staggered because entry sync now requests each class.
  const groupJob = new WorkerJob(
    'timetable-groups',
    env.WEBUNTIS_GROUP_SYNC_CRON,
    env.WORKER_TIME_ZONE,
    logger,
    async (trigger) => {
      const context = await timetable.syncContext();
      logger.log(`[timetable-groups:${trigger}] context: ${context.status}`);
      if (context.status !== 'success') {
        // Without a school year id no catalogue request can be made.
        return;
      }
      const groups = await timetable.syncGroups();
      logger.log(
        `[timetable-groups:${trigger}] ${groups.status} ` +
          `(received=${groups.received} written=${groups.written} retired=${groups.removed})`,
      );
    },
  );

  const entryJob = new WorkerJob(
    'timetable-entries',
    env.WEBUNTIS_ENTRY_SYNC_CRON,
    env.WORKER_TIME_ZONE,
    logger,
    async (trigger) => {
      const window = timetable.windowFor();
      const outcome = await timetable.syncEntries(window.from, window.to);
      logger.log(
        `[timetable-entries:${trigger}] ${outcome.status} ${window.from}..${window.to} ` +
          `(received=${outcome.received} written=${outcome.written} ` +
          `rejected=${outcome.rejected} withdrawn=${outcome.removed})`,
      );
    },
  );

  if (env.WEBUNTIS_ENABLED) {
    jobs.push(groupJob, entryJob);
  } else {
    // Not an error state: the integration ships dormant until its use is
    // cleared. Saying so once at boot beats silent absence.
    logger.log('[timetable] disabled by configuration (WEBUNTIS_ENABLED=false); no jobs scheduled');
  }

  // --- Public calendars ----------------------------------------------------
  const publicCalendar = app.get(PublicCalendarSyncService);

  const catalogJob = new WorkerJob(
    'public-calendar-catalog',
    env.PUBLIC_CALENDAR_CATALOG_SYNC_CRON,
    env.WORKER_TIME_ZONE,
    logger,
    async (trigger) => {
      const outcome = await publicCalendar.syncCatalog();
      logger.log(
        `[public-calendar-catalog:${trigger}] ${outcome.status} ` +
          `(written=${outcome.written} deactivated=${outcome.deactivated} rejected=${outcome.rejected})`,
      );
    },
  );

  const calendarEventsJob = new WorkerJob(
    'public-calendar-events',
    env.PUBLIC_CALENDAR_EVENT_SYNC_CRON,
    env.WORKER_TIME_ZONE,
    logger,
    async (trigger) => {
      const outcomes = await publicCalendar.syncEvents();
      logger.log('Public-calendar event sync completed', {
        event: 'publicCalendar.batchSync',
        trigger,
        feeds: outcomes.length,
        successful: outcomes.filter((outcome) =>
          ['success', 'notModified', 'empty'].includes(outcome.status),
        ).length,
        degraded: outcomes.filter((outcome) =>
          ['stale', 'revoked', 'failed'].includes(outcome.status),
        ).length,
        written: outcomes.reduce((sum, outcome) => sum + outcome.written, 0),
        removed: outcomes.reduce((sum, outcome) => sum + outcome.removed, 0),
      });
    },
  );

  if (env.PUBLIC_CALENDAR_ENABLED) {
    jobs.push(catalogJob, calendarEventsJob);
  } else {
    logger.log(
      '[public-calendar] disabled by configuration (PUBLIC_CALENDAR_ENABLED=false); no jobs scheduled',
    );
  }

  for (const job of jobs) {
    job.start();
  }

  if (env.CANTEEN_SYNC_ON_BOOT) {
    await canteenJob.trigger('boot');
  }
  if (env.WEBUNTIS_ENABLED && env.WEBUNTIS_SYNC_ON_BOOT) {
    await groupJob.trigger('boot');
    await entryJob.trigger('boot');
  }
  if (env.PUBLIC_CALENDAR_ENABLED && env.PUBLIC_CALENDAR_SYNC_ON_BOOT) {
    await catalogJob.trigger('boot');
    await calendarEventsJob.trigger('boot');
  }

  const shutdown = (signal: string): void => {
    logger.log(`Received ${signal}, stopping the worker`);
    for (const job of jobs) {
      job.stop();
    }
    // Both outcomes must terminate: without a rejection handler a failing
    // close() would leave the container hanging until it is killed.
    void app.close().then(
      () => process.exit(0),
      () => process.exit(1),
    );
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

void bootstrap();
