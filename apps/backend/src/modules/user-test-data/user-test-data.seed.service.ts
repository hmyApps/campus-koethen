import catalog from '@campus/map/catalog';
import { Inject, Injectable } from '@nestjs/common';
import { ENV } from '../../config/app-config.module';
import { Env } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import { CanteenSyncService } from '../canteen/canteen-sync.service';
import { CANTEENS } from '../canteen/canteens.config';
import {
  buildUserTestDataset,
  UserTestDataset,
  UserTestMapCatalog,
} from './user-test-data.dataset';
import { USER_TEST_CALENDAR_PREFIX, USER_TEST_SOURCE } from './user-test-data.constants';

export interface UserTestSeedSummary {
  from: string;
  to: string;
  canteens: number;
  meals: number;
  timetableGroups: number;
  timetableEntries: number;
  calendars: number;
  calendarEvents: number;
}

export interface UserTestRemovalSummary {
  syncRuns: number;
  meals: number;
  timetableSyncRuns: number;
  timetableEntries: number;
  timetableGroups: number;
  timetableContexts: number;
  calendars: number;
  calendarEvents: number;
}

@Injectable()
export class UserTestDataSeedService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly canteens: CanteenSyncService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  preview(now = new Date()): UserTestSeedSummary {
    return this.toSummary(this.dataset(now));
  }

  async seed(now = new Date()): Promise<UserTestSeedSummary> {
    if (!this.env.USER_TEST_DATA_ENABLED) {
      throw new Error(
        'Synthetic user-test data is disabled. Set USER_TEST_DATA_ENABLED=true before seeding.',
      );
    }

    const dataset = this.dataset(now);
    await this.canteens.seedCanteens();

    const canteens = await this.prisma.canteen.findMany({
      where: { slug: { in: CANTEENS.filter((item) => item.active).map((item) => item.slug) } },
      select: { id: true, slug: true },
    });
    const canteenIdBySlug = new Map(canteens.map((item) => [item.slug, item.id]));
    if (canteens.length !== CANTEENS.filter((item) => item.active).length) {
      throw new Error('Not every configured canteen was available after the idempotent seed.');
    }

    const seededAt = new Date();
    await this.prisma.$transaction(
      async (tx) => {
        for (const definition of dataset.ingredientDefinitions) {
          await tx.ingredientDefinition.upsert({
            where: { code: definition.code },
            create: definition,
            update: { labelDe: definition.labelDe, kind: definition.kind },
          });
        }

        for (const meal of dataset.meals) {
          const canteenId = canteenIdBySlug.get(meal.canteenSlug);
          if (!canteenId) throw new Error(`Unknown canteen slug: ${meal.canteenSlug}`);

          const data = {
            source: USER_TEST_SOURCE,
            sourceFoodId: null,
            canteenId,
            date: dateOnly(meal.date),
            counterId: meal.counterId,
            isSprint: meal.isSprint,
            name: meal.name,
            subtitle: meal.subtitle,
            extras: meal.extras,
            ingredientCodes: meal.ingredientCodes,
            sourceUpdatedAt: seededAt,
          };
          const stored = await tx.meal.upsert({
            where: { sourcePlanId: meal.sourcePlanId },
            create: { sourcePlanId: meal.sourcePlanId, ...data },
            update: data,
          });
          await tx.mealPrice.deleteMany({ where: { mealId: stored.id } });
          await tx.mealPrice.createMany({
            data: meal.prices.map((price) => ({ mealId: stored.id, ...price })),
          });
        }
        await tx.meal.deleteMany({
          where: {
            source: USER_TEST_SOURCE,
            sourcePlanId: { notIn: dataset.meals.map((meal) => meal.sourcePlanId) },
          },
        });

        const context = dataset.timetable.context;
        const storedContext = await tx.timetableContext.upsert({
          where: {
            source_externalId: { source: USER_TEST_SOURCE, externalId: context.externalId },
          },
          create: {
            source: USER_TEST_SOURCE,
            externalId: context.externalId,
            name: context.name,
            validFrom: dateOnly(context.validFrom),
            validTo: dateOnly(context.validTo),
            lastSeenAt: seededAt,
          },
          update: {
            name: context.name,
            validFrom: dateOnly(context.validFrom),
            validTo: dateOnly(context.validTo),
            active: true,
            lastSeenAt: seededAt,
          },
        });

        const group = dataset.timetable.group;
        const storedGroup = await tx.timetableGroup.upsert({
          where: {
            source_externalId: { source: USER_TEST_SOURCE, externalId: group.externalId },
          },
          create: { source: USER_TEST_SOURCE, ...group, lastSeenAt: seededAt },
          update: {
            shortName: group.shortName,
            longName: group.longName,
            department: group.department,
            active: true,
            lastSeenAt: seededAt,
          },
        });
        await tx.timetableContextGroup.upsert({
          where: {
            contextId_groupId: {
              contextId: storedContext.id,
              groupId: storedGroup.id,
            },
          },
          create: { contextId: storedContext.id, groupId: storedGroup.id },
          update: {},
        });

        for (const entry of dataset.timetable.entries) {
          const stored = await tx.timetableEntry.upsert({
            where: {
              source_externalKey: { source: USER_TEST_SOURCE, externalKey: entry.externalKey },
            },
            create: {
              source: USER_TEST_SOURCE,
              externalKey: entry.externalKey,
              startsAt: entry.startsAt,
              endsAt: entry.endsAt,
              date: dateOnly(entry.date),
              title: entry.title,
              subjectCode: entry.subjectCode,
              type: entry.type,
              status: entry.status,
              sourceStatus: null,
              teachers: entry.teachers,
              rooms: entry.rooms,
              note: entry.note,
              lastSeenAt: seededAt,
            },
            update: {
              startsAt: entry.startsAt,
              endsAt: entry.endsAt,
              date: dateOnly(entry.date),
              title: entry.title,
              subjectCode: entry.subjectCode,
              type: entry.type,
              status: entry.status,
              sourceStatus: null,
              teachers: entry.teachers,
              rooms: entry.rooms,
              note: entry.note,
              lastSeenAt: seededAt,
            },
          });
          await tx.timetableEntryGroup.upsert({
            where: { entryId_groupId: { entryId: stored.id, groupId: storedGroup.id } },
            create: { entryId: stored.id, groupId: storedGroup.id },
            update: {},
          });
        }

        await tx.timetableEntry.deleteMany({
          where: {
            source: USER_TEST_SOURCE,
            externalKey: {
              notIn: dataset.timetable.entries.map((entry) => entry.externalKey),
            },
          },
        });
        await tx.timetableGroup.deleteMany({
          where: { source: USER_TEST_SOURCE, externalId: { not: group.externalId } },
        });
        await tx.timetableContext.deleteMany({
          where: { source: USER_TEST_SOURCE, externalId: { not: context.externalId } },
        });

        // Public calendars. Normally the worker fills these from a Google feed;
        // here they are written directly so the calendar screens have something
        // to show without any network access. `operationalStatus` and the sync
        // timestamp are set to what a successful run would leave behind —
        // otherwise the API would serve them as permanently stale.
        for (const calendar of dataset.calendars) {
          const calendarData = {
            googleCalendarId: `${calendar.slug}@user-test.invalid`,
            nameDe: calendar.nameDe,
            nameEn: calendar.nameEn,
            colorHex: calendar.colorHex,
            sortOrder: calendar.sortOrder,
            isActive: true,
            defaultSubscribed: calendar.defaultSubscribed,
            includeEventDescription: calendar.includeEventDescription,
            includeEventLocation: calendar.includeEventLocation,
            operationalStatus: 'ready',
            lastSuccessfulSyncAt: seededAt,
          };
          const storedCalendar = await tx.publicCalendar.upsert({
            where: { slug: calendar.slug },
            create: { slug: calendar.slug, ...calendarData },
            update: calendarData,
          });

          for (const event of calendar.events) {
            const eventData = {
              uid: event.uid,
              recurrenceId: null,
              sequence: null,
              title: event.title,
              description: calendar.includeEventDescription ? event.description : null,
              location: calendar.includeEventLocation ? event.location : null,
              startsAt: event.startsAt,
              endsAt: event.endsAt,
              allDay: event.allDay,
              status: event.status,
              sourceUpdatedAt: seededAt,
              lastSeenAt: seededAt,
            };
            await tx.publicCalendarEvent.upsert({
              where: {
                calendarId_occurrenceKey: {
                  calendarId: storedCalendar.id,
                  occurrenceKey: event.occurrenceKey,
                },
              },
              create: {
                calendarId: storedCalendar.id,
                occurrenceKey: event.occurrenceKey,
                ...eventData,
              },
              update: eventData,
            });
          }

          await tx.publicCalendarEvent.deleteMany({
            where: {
              calendarId: storedCalendar.id,
              occurrenceKey: { notIn: calendar.events.map((event) => event.occurrenceKey) },
            },
          });
        }

        await tx.publicCalendarSyncRun.deleteMany({
          where: { calendarSlug: { in: dataset.calendars.map((calendar) => calendar.slug) } },
        });
        await tx.publicCalendarSyncRun.createMany({
          data: dataset.calendars.map((calendar) => ({
            calendarSlug: calendar.slug,
            kind: 'events',
            status: 'success',
            startedAt: seededAt,
            finishedAt: seededAt,
            eventsReceived: calendar.events.length,
            eventsExpanded: calendar.events.length,
            recordsAccepted: calendar.events.length,
          })),
        });

        await tx.syncRun.deleteMany({ where: { source: USER_TEST_SOURCE } });
        await tx.syncRun.createMany({
          data: canteens.map((item) => ({
            source: USER_TEST_SOURCE,
            canteenId: item.id,
            startedAt: seededAt,
            finishedAt: seededAt,
            status: 'success',
            recordsReceived: dataset.meals.filter((meal) => meal.canteenSlug === item.slug).length,
            recordsUpserted: dataset.meals.filter((meal) => meal.canteenSlug === item.slug).length,
          })),
        });

        await tx.timetableSyncRun.deleteMany({ where: { source: USER_TEST_SOURCE } });
        await tx.timetableSyncRun.createMany({
          data: [
            {
              source: USER_TEST_SOURCE,
              kind: 'groups',
              startedAt: seededAt,
              finishedAt: seededAt,
              status: 'success',
              recordsReceived: 1,
              recordsAccepted: 1,
              recordsWritten: 1,
            },
            {
              source: USER_TEST_SOURCE,
              kind: 'entries',
              startedAt: seededAt,
              finishedAt: seededAt,
              status: 'success',
              rangeFrom: dateOnly(context.validFrom),
              rangeTo: dateOnly(context.validTo),
              groupsRequested: 1,
              recordsReceived: dataset.timetable.entries.length,
              recordsAccepted: dataset.timetable.entries.length,
              recordsWritten: dataset.timetable.entries.length,
            },
          ],
        });
      },
      { timeout: 120_000, maxWait: 10_000 },
    );

    return this.toSummary(dataset);
  }

  async remove(): Promise<UserTestRemovalSummary> {
    return this.prisma.$transaction(async (tx) => {
      const syncRuns = await tx.syncRun.deleteMany({ where: { source: USER_TEST_SOURCE } });
      const meals = await tx.meal.deleteMany({ where: { source: USER_TEST_SOURCE } });
      const timetableSyncRuns = await tx.timetableSyncRun.deleteMany({
        where: { source: USER_TEST_SOURCE },
      });
      const timetableEntries = await tx.timetableEntry.deleteMany({
        where: { source: USER_TEST_SOURCE },
      });
      const timetableGroups = await tx.timetableGroup.deleteMany({
        where: { source: USER_TEST_SOURCE },
      });
      const timetableContexts = await tx.timetableContext.deleteMany({
        where: { source: USER_TEST_SOURCE },
      });
      // Cascade removes the events with their calendar.
      const calendarEvents = await tx.publicCalendarEvent.deleteMany({
        where: { calendar: { slug: { startsWith: USER_TEST_CALENDAR_PREFIX } } },
      });
      await tx.publicCalendarSyncRun.deleteMany({
        where: { calendarSlug: { startsWith: USER_TEST_CALENDAR_PREFIX } },
      });
      const calendars = await tx.publicCalendar.deleteMany({
        where: { slug: { startsWith: USER_TEST_CALENDAR_PREFIX } },
      });
      return {
        syncRuns: syncRuns.count,
        meals: meals.count,
        timetableSyncRuns: timetableSyncRuns.count,
        timetableEntries: timetableEntries.count,
        timetableGroups: timetableGroups.count,
        timetableContexts: timetableContexts.count,
        calendars: calendars.count,
        calendarEvents: calendarEvents.count,
      };
    });
  }

  private dataset(now: Date): UserTestDataset {
    return buildUserTestDataset({
      anchor: calendarDateInTimeZone(now, this.env.WORKER_TIME_ZONE),
      catalog: catalog as UserTestMapCatalog,
      canteenSlugs: CANTEENS.filter((item) => item.active).map((item) => item.slug),
    });
  }

  private toSummary(dataset: UserTestDataset): UserTestSeedSummary {
    return {
      from: dataset.from,
      to: dataset.to,
      canteens: new Set(dataset.meals.map((meal) => meal.canteenSlug)).size,
      meals: dataset.meals.length,
      timetableGroups: 1,
      timetableEntries: dataset.timetable.entries.length,
      calendars: dataset.calendars.length,
      calendarEvents: dataset.calendars.reduce(
        (total, calendar) => total + calendar.events.length,
        0,
      ),
    };
  }
}

function dateOnly(value: string): Date {
  return new Date(`${value}T00:00:00.000Z`);
}

function calendarDateInTimeZone(now: Date, timeZone: string): Date {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const get = (type: string): string => parts.find((part) => part.type === type)?.value ?? '00';
  return new Date(`${get('year')}-${get('month')}-${get('day')}T12:00:00.000Z`);
}
