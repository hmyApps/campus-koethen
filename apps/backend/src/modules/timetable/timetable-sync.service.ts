import { Inject, Injectable, Logger } from '@nestjs/common';
import { ENV } from '../../config/app-config.module';
import { Env } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import { WebUntisClient, WebUntisError } from './webuntis.client';
import {
  EntriesResponse,
  FilterResponse,
  normalizeEntryStatus,
  normalizeEntryType,
  pickAllPositions,
  toUtc,
} from './webuntis.schema';

/**
 * Timetable synchronisation.
 *
 * The governing rule, identical to the canteen importer: a failed, invalid or
 * unexpectedly empty upstream response must NEVER remove data that is already
 * stored. Stale but real beats empty, and the API tells the client how old the
 * data is instead of pretending it is fresh.
 *
 * The source requires exactly one class per entry request. A whole window is
 * read before any write, so one failed class keeps the last complete result.
 */

export type SyncKind = 'context' | 'groups' | 'entries';
export type SyncStatus = 'success' | 'empty' | 'partial' | 'failed' | 'disabled';

export interface SyncOutcome {
  kind: SyncKind;
  status: SyncStatus;
  received: number;
  accepted: number;
  rejected: number;
  written: number;
  removed: number;
  errorCode?: string;
}

interface NormalizedEntry {
  externalKey: string;
  startsAt: Date;
  endsAt: Date;
  date: Date;
  title: string;
  subjectCode: string | null;
  type: string;
  status: string;
  sourceStatus: string | null;
  teachers: Array<{ shortName: string; displayName: string | null }>;
  rooms: Array<{ shortName: string; longName: string | null }>;
  note: string | null;
  lessonInfo: string | null;
  /**
   * The classes attending this lesson.
   *
   * A `Set` rather than an array because the only operation performed on it is
   * "add this class if it is not already there": the same lesson is delivered
   * once per attending class, so an array meant rebuilding the whole collection
   * on every occurrence just to keep it unique.
   */
  groupExternalIds: Set<string>;
}

@Injectable()
export class TimetableSyncService {
  private readonly logger = new Logger(TimetableSyncService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly client: WebUntisClient,
    @Inject(ENV) private readonly env: Env,
  ) {}

  private async startRun(kind: SyncKind) {
    return this.prisma.timetableSyncRun.create({ data: { kind, status: 'running' } });
  }

  private async failRun(
    runId: string,
    kind: SyncKind,
    error: unknown,
    extra: Partial<SyncOutcome> = {},
  ): Promise<SyncOutcome> {
    const code = error instanceof WebUntisError ? error.kind : 'unexpected';
    const status: SyncStatus = code === 'disabled' ? 'disabled' : 'failed';

    await this.prisma.timetableSyncRun.update({
      where: { id: runId },
      data: {
        status,
        finishedAt: new Date(),
        errorCode: code,
        // Classification only — the client's message is already scrubbed of
        // host, headers and payload.
        errorMessage: error instanceof Error ? error.message.slice(0, 300) : 'unknown error',
      },
    });

    // Deliberately no delete anywhere on this path.
    if (status === 'failed') {
      this.logger.warn(`Timetable ${kind} sync failed (${code}); existing data kept`);
    }

    return {
      kind,
      status,
      received: 0,
      accepted: 0,
      rejected: 0,
      written: 0,
      removed: 0,
      errorCode: code,
      ...extra,
    };
  }

  /** Resolves and stores the current school year. Everything else needs its id. */
  async syncContext(): Promise<SyncOutcome & { externalId?: string }> {
    const run = await this.startRun('context');

    try {
      const data = await this.client.fetchAppData();
      const years = await this.client.fetchSchoolYears();
      const year = data.currentSchoolYear;
      const externalId = String(year.id);

      for (const candidate of years) {
        if (candidate.id === year.id) continue;
        const id = String(candidate.id);
        await this.prisma.timetableContext.upsert({
          where: { source_externalId: { source: 'webuntis', externalId: id } },
          create: {
            externalId: id,
            name: candidate.name,
            validFrom: new Date(`${candidate.dateRange.start}T00:00:00.000Z`),
            validTo: new Date(`${candidate.dateRange.end}T00:00:00.000Z`),
            active: false,
          },
          update: {
            name: candidate.name,
            validFrom: new Date(`${candidate.dateRange.start}T00:00:00.000Z`),
            validTo: new Date(`${candidate.dateRange.end}T00:00:00.000Z`),
            lastSeenAt: new Date(),
          },
        });
      }

      await this.prisma.timetableContext.upsert({
        where: { source_externalId: { source: 'webuntis', externalId } },
        create: {
          externalId,
          name: year.name,
          validFrom: new Date(`${year.dateRange.start}T00:00:00.000Z`),
          validTo: new Date(`${year.dateRange.end}T00:00:00.000Z`),
        },
        update: {
          name: year.name,
          validFrom: new Date(`${year.dateRange.start}T00:00:00.000Z`),
          validTo: new Date(`${year.dateRange.end}T00:00:00.000Z`),
          active: true,
          lastSeenAt: new Date(),
        },
      });

      // Any other context is no longer current.
      await this.prisma.timetableContext.updateMany({
        where: { source: 'webuntis', externalId: { not: externalId } },
        data: { active: false },
      });

      await this.prisma.timetableSyncRun.update({
        where: { id: run.id },
        data: { status: 'success', finishedAt: new Date(), recordsWritten: 1, recordsAccepted: 1 },
      });

      return {
        kind: 'context',
        status: 'success',
        received: 1,
        accepted: 1,
        rejected: 0,
        written: 1,
        removed: 0,
        externalId,
      };
    } catch (error) {
      return this.failRun(run.id, 'context', error);
    }
  }

  private async contextsFor(
    from: string,
    to: string,
  ): Promise<Array<{ id: number; storageId: string; from: string; to: string }>> {
    const contexts = await this.prisma.timetableContext.findMany({
      where: {
        source: 'webuntis',
        validFrom: { lte: new Date(`${to}T00:00:00.000Z`) },
        validTo: { gte: new Date(`${from}T00:00:00.000Z`) },
      },
      orderBy: { validFrom: 'asc' },
      select: { id: true, externalId: true, validFrom: true, validTo: true },
    });
    return contexts.flatMap((context) => {
      const id = Number(context.externalId);
      if (!Number.isSafeInteger(id)) return [];
      const start = context.validFrom.toISOString().slice(0, 10);
      const end = context.validTo.toISOString().slice(0, 10);
      return [
        {
          id,
          storageId: context.id,
          from: start > from ? start : from,
          to: end < to ? end : to,
        },
      ];
    });
  }

  /** Full class catalogue. Rare, complete, and the only thing allowed to deactivate a group. */
  async syncGroups(asOf = new Date()): Promise<SyncOutcome> {
    const run = await this.startRun('groups');

    try {
      const window = this.windowFor(asOf);
      const contexts = await this.contextsFor(window.from, window.to);
      if (contexts.length === 0) {
        throw new WebUntisError('malformed', 'No timetable context covers the sync window.');
      }

      const catalogues: Array<{ contextId: string; catalogue: FilterResponse }> = [];
      for (const context of contexts) {
        catalogues.push({
          contextId: context.storageId,
          catalogue: await this.client.fetchClasses(context.id),
        });
      }
      // One empty semester catalogue is suspect. Updating the other semester
      // while retiring the empty one's groups would violate the same
      // last-good-data rule as an entirely empty response.
      if (catalogues.some(({ catalogue }) => catalogue.classes.length === 0)) {
        await this.prisma.timetableSyncRun.update({
          where: { id: run.id },
          data: {
            status: 'empty',
            finishedAt: new Date(),
            errorMessage: 'one or more semester catalogues empty; existing groups kept',
          },
        });
        return {
          kind: 'groups',
          status: 'empty',
          received: 0,
          accepted: 0,
          rejected: 0,
          written: 0,
          removed: 0,
        };
      }

      const classes = catalogues.flatMap(({ catalogue }) => catalogue.classes);
      const received = classes.length;

      const seen = classes
        .map((item) => ({
          externalId: String(item.class.id),
          shortName: item.class.shortName.trim(),
          longName: (item.class.longName ?? item.class.shortName).trim(),
          department: item.department?.shortName?.trim() || null,
        }))
        .filter((group) => group.externalId && group.shortName);

      // An empty catalogue is treated as suspect, not as "everything closed".
      // Deactivating 270 groups because of one odd response would empty the
      // picker for every user.
      if (seen.length === 0) {
        await this.prisma.timetableSyncRun.update({
          where: { id: run.id },
          data: {
            status: 'empty',
            finishedAt: new Date(),
            recordsReceived: received,
            errorMessage: 'empty catalogue; existing groups kept',
          },
        });
        this.logger.warn('Timetable catalogue came back empty; existing groups kept');
        return {
          kind: 'groups',
          status: 'empty',
          received,
          accepted: 0,
          rejected: received,
          written: 0,
          removed: 0,
        };
      }

      const now = new Date();
      // A repeated externalId would collide on the unique constraint once the
      // writes are batched, where the sequential loop simply wrote twice. Last
      // one wins, exactly as it did before.
      const uniqueGroups = [...new Map(seen.map((group) => [group.externalId, group])).values()];

      const externalIdsByContext = new Map<string, string[]>(
        catalogues.map(({ contextId, catalogue }) => [
          contextId,
          [
            ...new Set(
              catalogue.classes
                .filter((item) => item.class.shortName.trim().length > 0)
                .map((item) => String(item.class.id))
                .filter((externalId) => externalId.length > 0),
            ),
          ],
        ]),
      );

      await this.prisma.$transaction(
        async (tx) => {
          // Read once, write only the differences. A class catalogue changes
          // once a semester; rewriting all ~270 rows every run was work spent
          // to record nothing.
          const stored = await tx.timetableGroup.findMany({
            where: {
              source: 'webuntis',
              externalId: { in: uniqueGroups.map((group) => group.externalId) },
            },
            select: {
              id: true,
              externalId: true,
              shortName: true,
              longName: true,
              department: true,
              active: true,
            },
          });
          const storedByExternalId = new Map(stored.map((row) => [row.externalId, row]));

          const toCreate: typeof uniqueGroups = [];
          const toUpdate: typeof uniqueGroups = [];
          const unchangedIds: string[] = [];

          for (const group of uniqueGroups) {
            const row = storedByExternalId.get(group.externalId);
            if (!row) {
              toCreate.push(group);
              continue;
            }
            // `active: true` was part of the update, so a retired group that
            // upstream offers again has to count as changed and be revived.
            if (
              !row.active ||
              row.shortName !== group.shortName ||
              row.longName !== group.longName ||
              row.department !== group.department
            ) {
              toUpdate.push(group);
            } else {
              unchangedIds.push(row.id);
            }
          }

          if (toCreate.length > 0) {
            await tx.timetableGroup.createMany({
              data: toCreate.map((group) => ({ ...group, lastSeenAt: now })),
            });
          }
          for (const group of toUpdate) {
            await tx.timetableGroup.update({
              where: { source_externalId: { source: 'webuntis', externalId: group.externalId } },
              data: { ...group, active: true, lastSeenAt: now },
            });
          }
          // Everything the catalogue confirmed was seen now, changed or not.
          if (unchangedIds.length > 0) {
            await tx.timetableGroup.updateMany({
              where: { id: { in: unchangedIds } },
              data: { lastSeenAt: now },
            });
          }

          const linkedGroups = await tx.timetableGroup.findMany({
            where: {
              source: 'webuntis',
              externalId: { in: uniqueGroups.map((group) => group.externalId) },
            },
            select: { id: true, externalId: true },
          });
          const groupIdByExternal = new Map(
            linkedGroups.map((group) => [group.externalId, group.id]),
          );
          for (const [contextId, externalIds] of externalIdsByContext) {
            const groupIds = externalIds
              .map((externalId) => groupIdByExternal.get(externalId))
              .filter((groupId): groupId is string => groupId !== undefined);
            // A catalogue is complete only if every accepted upstream class can
            // be resolved to its persisted row. Fail the transaction closed;
            // otherwise an unexpected partial write could erase valid semester
            // links and make a period look empty to clients.
            if (groupIds.length !== externalIds.length) {
              throw new WebUntisError(
                'malformed',
                'Not every timetable group could be linked to its semester.',
              );
            }
            await tx.timetableContextGroup.createMany({
              data: groupIds.map((groupId) => ({ contextId, groupId })),
              skipDuplicates: true,
            });
            await tx.timetableContextGroup.deleteMany({
              where: {
                contextId,
                groupId: { notIn: groupIds },
              },
            });
          }
        },
        // Headroom rather than a surprise P2028 later. It is reserve now, not a
        // necessity: a run without changes is one read and one stamp.
        { timeout: 120_000, maxWait: 10_000 },
      );

      // Only now — after a COMPLETE, non-empty, successful import — may a group
      // that upstream no longer offers be retired. It is deactivated, never
      // deleted, so its historical entries stay intact.
      const retired = await this.prisma.timetableGroup.updateMany({
        where: {
          source: 'webuntis',
          active: true,
          externalId: { notIn: seen.map((group) => group.externalId) },
        },
        data: { active: false },
      });

      await this.prisma.timetableSyncRun.update({
        where: { id: run.id },
        data: {
          status: 'success',
          finishedAt: new Date(),
          recordsReceived: received,
          recordsAccepted: seen.length,
          recordsRejected: received - seen.length,
          recordsWritten: seen.length,
          recordsRemoved: retired.count,
        },
      });

      this.logger.log(
        `Timetable groups: ${seen.length} upserted, ${retired.count} retired, ${received - seen.length} rejected`,
      );

      return {
        kind: 'groups',
        status: 'success',
        received,
        accepted: seen.length,
        rejected: received - seen.length,
        written: seen.length,
        removed: retired.count,
      };
    } catch (error) {
      return this.failRun(run.id, 'groups', error);
    }
  }

  /** Converts one upstream response into entries keyed by a stable source key. */
  private normalize(response: EntriesResponse): {
    entries: Map<string, NormalizedEntry>;
    rejected: number;
    groupExternalIds: Set<string>;
  } {
    const entries = new Map<string, NormalizedEntry>();
    const groupExternalIds = new Set<string>();
    let rejected = 0;

    for (const day of response.days) {
      groupExternalIds.add(String(day.resource.id));

      for (const raw of day.gridEntries) {
        try {
          // `ids` is the source's own key. Sorted and joined so a reordering
          // upstream cannot masquerade as a different lesson.
          const externalKey = [...raw.ids].sort((a, b) => a - b).join('-');

          const { subjects, teachers, rooms, infos } = pickAllPositions(raw);

          const title =
            subjects[0]?.longName?.trim() ||
            subjects[0]?.shortName?.trim() ||
            raw.name?.trim() ||
            infos[0]?.shortName?.trim() ||
            '';

          if (!title) {
            rejected += 1;
            continue;
          }

          const startsAt = toUtc(raw.duration.start);
          const endsAt = toUtc(raw.duration.end);

          const existing = entries.get(externalKey);
          const entry: NormalizedEntry = existing ?? {
            externalKey,
            startsAt,
            endsAt,
            date: new Date(`${day.date}T00:00:00.000Z`),
            title,
            subjectCode: subjects[0]?.shortName?.trim() || null,
            type: normalizeEntryType(raw.type),
            status: normalizeEntryStatus(raw.status),
            sourceStatus: raw.status ?? null,
            teachers: teachers.map((t) => ({
              shortName: t.shortName,
              displayName: t.displayName ?? t.longName ?? null,
            })),
            rooms: rooms.map((r) => ({ shortName: r.shortName, longName: r.longName ?? null })),
            note: raw.lessonText?.trim() || raw.substitutionText?.trim() || null,
            lessonInfo: raw.lessonInfo?.trim() ? raw.lessonInfo : null,
            groupExternalIds: new Set<string>(),
          };

          // The same lesson appears once per attending class. Union the groups
          // rather than letting the last occurrence win.
          if (existing && !existing.lessonInfo) {
            existing.lessonInfo = raw.lessonInfo?.trim() ? raw.lessonInfo : null;
          }
          entry.groupExternalIds.add(String(day.resource.id));

          entries.set(externalKey, entry);
        } catch {
          // A single unparseable lesson must not discard the whole window.
          rejected += 1;
        }
      }
    }

    return { entries, rejected, groupExternalIds };
  }

  /**
   * Compares a stored reference list against the normalised one.
   *
   * Deliberately field by field rather than by serialising both sides: the
   * columns are `jsonb`, and PostgreSQL does not preserve object key order, so
   * a string comparison would report a change on every single run and undo the
   * point of the diff.
   */
  private static refsChanged(
    stored: unknown,
    next: Array<Record<string, string | null>>,
    fields: readonly string[],
  ): boolean {
    if (!Array.isArray(stored) || stored.length !== next.length) {
      return true;
    }
    for (let index = 0; index < next.length; index += 1) {
      const storedRef: unknown = stored[index];
      if (typeof storedRef !== 'object' || storedRef === null) {
        return true;
      }
      const record = storedRef as Record<string, unknown>;
      for (const field of fields) {
        if ((record[field] ?? null) !== (next[index]![field] ?? null)) {
          return true;
        }
      }
    }
    return false;
  }

  /** True when the response carries anything the stored row does not already say. */
  private static entryChanged(
    stored: {
      startsAt: Date;
      endsAt: Date;
      date: Date;
      title: string;
      subjectCode: string | null;
      type: string;
      status: string;
      sourceStatus: string | null;
      teachers: unknown;
      rooms: unknown;
      note: string | null;
      lessonInfo: string | null;
    },
    next: NormalizedEntry,
  ): boolean {
    return (
      stored.startsAt.getTime() !== next.startsAt.getTime() ||
      stored.endsAt.getTime() !== next.endsAt.getTime() ||
      stored.date.getTime() !== next.date.getTime() ||
      stored.title !== next.title ||
      stored.subjectCode !== next.subjectCode ||
      stored.type !== next.type ||
      stored.status !== next.status ||
      stored.sourceStatus !== next.sourceStatus ||
      stored.note !== next.note ||
      stored.lessonInfo !== next.lessonInfo ||
      TimetableSyncService.refsChanged(stored.teachers, next.teachers, [
        'shortName',
        'displayName',
      ]) ||
      TimetableSyncService.refsChanged(stored.rooms, next.rooms, ['shortName', 'longName'])
    );
  }

  /**
   * Entries for every class in every school year covering the requested window.
   *
   * Removal is limited to the confirmed window AND the confirmed groups, and
   * only ever runs after a successful, non-empty response.
   */
  async syncEntries(from: string, to: string): Promise<SyncOutcome> {
    const run = await this.prisma.timetableSyncRun.create({
      data: {
        kind: 'entries',
        status: 'running',
        rangeFrom: new Date(`${from}T00:00:00.000Z`),
        rangeTo: new Date(`${to}T00:00:00.000Z`),
      },
    });

    try {
      const contexts = await this.contextsFor(from, to);
      if (contexts.length === 0) {
        throw new WebUntisError('malformed', 'No timetable context covers the sync window.');
      }

      const days: EntriesResponse['days'] = [];
      const requestedGroupIds = new Set<string>();
      for (const context of contexts) {
        const catalogue = await this.client.fetchClasses(context.id);
        if (catalogue.classes.length === 0) {
          throw new WebUntisError('malformed', 'A timetable class catalogue was empty.');
        }
        for (const item of catalogue.classes) {
          const classId = item.class.id;
          requestedGroupIds.add(String(classId));
          const classEntries = await this.client.fetchEntries(
            context.id,
            context.from,
            context.to,
            classId,
          );
          days.push(...classEntries.days);
        }
      }
      const response: EntriesResponse = { days };
      const { entries, rejected, groupExternalIds } = this.normalize(response);
      for (const id of requestedGroupIds) groupExternalIds.add(id);
      const received = response.days.reduce((sum, day) => sum + day.gridEntries.length, 0);

      if (entries.size === 0) {
        // A genuinely empty window is possible (semester break), but it is not
        // worth destroying a good dataset over. The API reports the age, so a
        // stale-but-real plan is visibly stale rather than silently gone.
        await this.prisma.timetableSyncRun.update({
          where: { id: run.id },
          data: {
            status: 'empty',
            finishedAt: new Date(),
            recordsReceived: received,
            recordsRejected: rejected,
            groupsRequested: groupExternalIds.size,
            errorMessage: 'empty window; existing entries kept',
          },
        });
        this.logger.warn(`Timetable entries ${from}..${to} came back empty; existing data kept`);
        return {
          kind: 'entries',
          status: 'empty',
          received,
          accepted: 0,
          rejected,
          written: 0,
          removed: 0,
        };
      }

      const groups = await this.prisma.timetableGroup.findMany({
        where: { source: 'webuntis', externalId: { in: [...groupExternalIds] } },
        select: { id: true, externalId: true },
      });
      const groupIdByExternal = new Map(groups.map((group) => [group.externalId, group.id]));

      const rangeStart = new Date(`${from}T00:00:00.000Z`);
      const rangeEnd = new Date(`${to}T00:00:00.000Z`);
      const confirmedGroupIds = [...groupIdByExternal.values()];

      const removed = await this.prisma.$transaction(
        async (tx) => {
          const keptKeys = [...entries.keys()];
          const now = new Date();

          // Read the window's current state once, then write only what the
          // response actually changed. The job covers the whole catalogue every
          // hour, and between two runs a handful of lessons move at most — the
          // unconditional upsert loop this replaces spent ~800 sequential
          // round-trips and ~800 row updates to record a few dozen real changes,
          // while holding the transaction's locks the whole time. That is what
          // forced the timeout below up from Prisma's 5s default.
          const stored = await tx.timetableEntry.findMany({
            where: { source: 'webuntis', externalKey: { in: keptKeys } },
            select: {
              id: true,
              externalKey: true,
              startsAt: true,
              endsAt: true,
              date: true,
              title: true,
              subjectCode: true,
              type: true,
              status: true,
              sourceStatus: true,
              teachers: true,
              rooms: true,
              note: true,
              lessonInfo: true,
            },
          });
          const storedByKey = new Map(stored.map((row) => [row.externalKey, row]));

          const idByKey = new Map<string, string>();
          const toCreate: NormalizedEntry[] = [];
          const toUpdate: NormalizedEntry[] = [];
          const unchangedIds: string[] = [];

          for (const entry of entries.values()) {
            const row = storedByKey.get(entry.externalKey);
            if (!row) {
              toCreate.push(entry);
              continue;
            }
            idByKey.set(entry.externalKey, row.id);
            if (TimetableSyncService.entryChanged(row, entry)) {
              toUpdate.push(entry);
            } else {
              unchangedIds.push(row.id);
            }
          }

          if (toCreate.length > 0) {
            const created = await tx.timetableEntry.createManyAndReturn({
              data: toCreate.map((entry) => ({
                externalKey: entry.externalKey,
                startsAt: entry.startsAt,
                endsAt: entry.endsAt,
                date: entry.date,
                title: entry.title,
                subjectCode: entry.subjectCode,
                type: entry.type,
                status: entry.status,
                sourceStatus: entry.sourceStatus,
                teachers: entry.teachers,
                rooms: entry.rooms,
                note: entry.note,
                lessonInfo: entry.lessonInfo,
              })),
              select: { id: true, externalKey: true },
            });
            for (const row of created) {
              idByKey.set(row.externalKey, row.id);
            }
          }

          for (const entry of toUpdate) {
            await tx.timetableEntry.update({
              where: { source_externalKey: { source: 'webuntis', externalKey: entry.externalKey } },
              data: {
                startsAt: entry.startsAt,
                endsAt: entry.endsAt,
                date: entry.date,
                title: entry.title,
                subjectCode: entry.subjectCode,
                type: entry.type,
                status: entry.status,
                sourceStatus: entry.sourceStatus,
                teachers: entry.teachers,
                rooms: entry.rooms,
                note: entry.note,
                lessonInfo: entry.lessonInfo,
                lastSeenAt: now,
              },
            });
          }

          // Everything the response confirmed was seen now, changed or not —
          // the same stamp the upsert loop wrote, in one statement.
          if (unchangedIds.length > 0) {
            await tx.timetableEntry.updateMany({
              where: { id: { in: unchangedIds } },
              data: { lastSeenAt: now },
            });
          }

          const links: Array<{ entryId: string; groupId: string }> = [];
          for (const entry of entries.values()) {
            const entryId = idByKey.get(entry.externalKey);
            if (!entryId) {
              continue;
            }
            for (const externalId of entry.groupExternalIds) {
              const groupId = groupIdByExternal.get(externalId);
              if (groupId) {
                links.push({ entryId, groupId });
              }
            }
          }

          // One bulk insert instead of a per-link upsert. Links are only ever
          // ADDED (the join table has no updatable columns), and skipDuplicates
          // handles a re-run against the composite primary key — so this is
          // behaviour-identical to the previous upsert loop, minus ~one
          // round-trip per link. That is what took the write phase past Prisma's
          // 5s interactive-transaction limit on real data (~800 entries): the
          // fixtures were far too small to reveal it.
          if (links.length > 0) {
            await tx.timetableEntryGroup.createMany({ data: links, skipDuplicates: true });
          }

          // Withdraw links only inside the confirmed window and only for groups
          // this response actually covered. An entry attended by a group outside
          // the confirmed set keeps that link.
          const withdrawn = await tx.timetableEntryGroup.deleteMany({
            where: {
              groupId: { in: confirmedGroupIds },
              entry: {
                source: 'webuntis',
                date: { gte: rangeStart, lte: rangeEnd },
                externalKey: { notIn: keptKeys },
              },
            },
          });

          // Only entries that now belong to NOBODY are cleaned up. A lesson still
          // attended by another group survives.
          const orphans = await tx.timetableEntry.deleteMany({
            where: {
              source: 'webuntis',
              date: { gte: rangeStart, lte: rangeEnd },
              groups: { none: {} },
            },
          });

          return withdrawn.count + orphans.count;
        },
        // Generous ceiling for the whole-catalogue write. The worker owns these
        // tables exclusively and runs hourly, so holding one transaction for a
        // few seconds costs nothing; the default 5s was simply too tight for a
        // real timetable.
        { timeout: 120_000, maxWait: 10_000 },
      );

      await this.prisma.timetableSyncRun.update({
        where: { id: run.id },
        data: {
          status: 'success',
          finishedAt: new Date(),
          recordsReceived: received,
          recordsAccepted: entries.size,
          recordsRejected: rejected,
          recordsWritten: entries.size,
          recordsRemoved: removed,
          groupsRequested: groupExternalIds.size,
        },
      });

      this.logger.log(
        `Timetable entries ${from}..${to}: ${entries.size} written across ${groupExternalIds.size} group(s), ${rejected} rejected, ${removed} withdrawn`,
      );

      return {
        kind: 'entries',
        status: 'success',
        received,
        accepted: entries.size,
        rejected,
        written: entries.size,
        removed,
      };
    } catch (error) {
      return this.failRun(run.id, 'entries', error);
    }
  }

  /** The window the scheduled job covers. */
  windowFor(today = new Date()): { from: string; to: string } {
    const day = 86_400_000;
    const from = new Date(today.getTime() - this.env.WEBUNTIS_LOOKBACK_DAYS * day);
    const to = new Date(today.getTime() + this.env.WEBUNTIS_LOOKAHEAD_DAYS * day);
    return { from: from.toISOString().slice(0, 10), to: to.toISOString().slice(0, 10) };
  }

  async lastSuccessfulAt(kind: SyncKind): Promise<Date | null> {
    const run = await this.prisma.timetableSyncRun.findFirst({
      where: { kind, status: 'success', finishedAt: { not: null } },
      orderBy: { finishedAt: 'desc' },
      select: { finishedAt: true },
    });
    return run?.finishedAt ?? null;
  }
}
