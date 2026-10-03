import { Inject, Injectable } from '@nestjs/common';
import { ApiError } from '../../common/errors/api-error';
import { PaginationMetaDto } from '../../common/dto/meta.dto';
import { LocaleResolution } from '../../common/locale/locale';
import { ENV } from '../../config/app-config.module';
import { Env } from '../../config/env.schema';
import { PrismaService } from '../../prisma/prisma.service';
import { TIMETABLE_TIMEZONE } from './webuntis.schema';
import {
  TimetableDayDto,
  TimetableEntryDto,
  TimetableGroupDto,
  TimetableLessonInfoDto,
  TimetableRoomDto,
  TimetableStatusDto,
  TimetableTeacherDto,
  TimetableWeekDto,
} from './timetable.types';

/**
 * Read model for /v1/timetable*.
 *
 * Reads only from our own database. A client request never triggers an
 * upstream call — that is the worker's job, and keeping it that way is what
 * stops the API from becoming an unthrottled proxy onto a third party.
 *
 * Nothing here is translated: subjects, rooms, teachers and group names are
 * the source's own strings.
 */

type StoredRef = { shortName?: unknown; longName?: unknown; displayName?: unknown };

@Injectable()
export class TimetableService {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  get featureEnabled(): boolean {
    return this.env.WEBUNTIS_ENABLED || this.env.USER_TEST_DATA_ENABLED;
  }

  private isStale(at: Date | null): boolean {
    if (!at) {
      return true;
    }
    return (Date.now() - at.getTime()) / 60_000 > this.env.WEBUNTIS_STALE_AFTER_MINUTES;
  }

  /**
   * Freshness of the newest completed run of one kind.
   *
   * `listGroups`, `getWeek` and `getStatus` all ask this on every request, and
   * all three want nothing but the timestamp. Selecting the whole row would
   * carry the counters and the error classification along for no reader, so the
   * projection is deliberate rather than incidental.
   */
  private async lastSuccessful(kind: 'groups' | 'entries'): Promise<Date | null> {
    const run = await this.prisma.timetableSyncRun.findFirst({
      where: { kind, status: 'success', finishedAt: { not: null } },
      orderBy: { finishedAt: 'desc' },
      select: { finishedAt: true },
    });
    return run?.finishedAt ?? null;
  }

  /**
   * The newest completed entry run, as far as /v1/timetable/status needs it.
   *
   * Freshness and the covered window come from the same row, so they are read
   * as one query. That is sound because both are properties of one run: every
   * writer that sets `status: 'success'` sets `finishedAt` in the same update,
   * so "newest successful run" and "newest finished successful run" cannot
   * disagree. An unfinished or failed run is excluded by the same filter that
   * `lastSuccessful` uses, which is what keeps a run in flight from blanking
   * the window the last good run confirmed.
   */
  private async lastEntryRun(): Promise<{
    finishedAt: Date | null;
    rangeFrom: Date | null;
    rangeTo: Date | null;
  } | null> {
    return this.prisma.timetableSyncRun.findFirst({
      where: { kind: 'entries', status: 'success', finishedAt: { not: null } },
      orderBy: { finishedAt: 'desc' },
      select: { finishedAt: true, rangeFrom: true, rangeTo: true },
    });
  }

  private static mapGroup(group: {
    id: string;
    shortName: string;
    longName: string;
    department: string | null;
  }): TimetableGroupDto {
    // Written out field by field: spreading would eventually leak externalId.
    return {
      id: group.id,
      shortName: group.shortName,
      longName: group.longName,
      department: group.department,
    };
  }

  private static mapRefs<T>(value: unknown, map: (ref: StoredRef) => T | null): T[] {
    if (!Array.isArray(value)) {
      return [];
    }
    return value
      .map((item) => (typeof item === 'object' && item !== null ? map(item as StoredRef) : null))
      .filter((item): item is T => item !== null);
  }

  async listGroups(
    locale: LocaleResolution,
    filter: { page: number; pageSize: number; query?: string; department?: string },
  ): Promise<{
    data: TimetableGroupDto[];
    pagination: PaginationMetaDto;
    lastSyncAt: Date | null;
    stale: boolean;
  }> {
    if (!this.featureEnabled) {
      const lastSyncAt = await this.lastSuccessful('groups');
      return {
        data: [],
        pagination: { page: filter.page, pageSize: filter.pageSize, total: 0, totalPages: 0 },
        lastSyncAt,
        stale: true,
      };
    }

    const query = filter.query?.trim();
    const where = {
      active: true,
      catalogVisible: true,
      ...(filter.department ? { department: filter.department } : {}),
      ...(query
        ? {
            OR: [
              { shortName: { contains: query, mode: 'insensitive' as const } },
              { longName: { contains: query, mode: 'insensitive' as const } },
              { department: { contains: query, mode: 'insensitive' as const } },
            ],
          }
        : {}),
    };
    const [lastSyncAt, total, groups] = await Promise.all([
      this.lastSuccessful('groups'),
      this.prisma.timetableGroup.count({ where }),
      this.prisma.timetableGroup.findMany({
        where,
        orderBy: [{ shortName: 'asc' }, { longName: 'asc' }, { department: 'asc' }, { id: 'asc' }],
        select: { id: true, shortName: true, longName: true, department: true },
        skip: (filter.page - 1) * filter.pageSize,
        take: filter.pageSize,
      }),
    ]);

    void locale;
    return {
      data: groups.map((group) => TimetableService.mapGroup(group)),
      pagination: {
        page: filter.page,
        pageSize: filter.pageSize,
        total,
        totalPages: Math.ceil(total / filter.pageSize),
      },
      lastSyncAt,
      stale: this.isStale(lastSyncAt),
    };
  }

  /** Resolve one stored Campus UUID without downloading the catalogue. */
  async getGroup(
    locale: LocaleResolution,
    groupId: string,
  ): Promise<{ data: TimetableGroupDto; lastSyncAt: Date | null; stale: boolean }> {
    const select = {
      id: true,
      shortName: true,
      longName: true,
      department: true,
      catalogVisible: true,
    } as const;
    const [group, lastSyncAt] = await Promise.all([
      this.prisma.timetableGroup.findFirst({
        where: { id: groupId },
        select,
      }),
      this.lastSuccessful('groups'),
    ]);
    if (!group) {
      throw new ApiError('TIMETABLE_GROUP_NOT_FOUND', locale.resolvedLocale);
    }
    const publicGroup = group.catalogVisible
      ? group
      : ((await this.prisma.timetableGroup.findFirst({
          where: {
            active: true,
            catalogVisible: true,
            shortName: group.shortName,
            longName: group.longName,
            department: group.department,
          },
          orderBy: { id: 'asc' },
          select,
        })) ?? group);
    return {
      data: TimetableService.mapGroup(publicGroup),
      lastSyncAt,
      stale: this.isStale(lastSyncAt),
    };
  }

  /** Exact source strings available in the last successfully covered window. */
  async listLessonInfo(groupId: string, locale: LocaleResolution): Promise<TimetableLessonInfoDto> {
    const [group, run] = await Promise.all([
      this.prisma.timetableGroup.findFirst({ where: { id: groupId }, select: { id: true } }),
      this.lastEntryRun(),
    ]);
    if (!group) {
      throw new ApiError('TIMETABLE_GROUP_NOT_FOUND', locale.resolvedLocale);
    }
    if (!this.featureEnabled || !run?.rangeFrom || !run.rangeTo) {
      return { values: [], hasWithoutInfo: false };
    }

    const links = await this.prisma.timetableEntryGroup.findMany({
      where: {
        groupId,
        entry: { date: { gte: run.rangeFrom, lte: run.rangeTo } },
      },
      select: { entry: { select: { lessonInfo: true } } },
    });
    const values = new Set<string>();
    let hasWithoutInfo = false;
    for (const link of links) {
      const value = link.entry.lessonInfo;
      if (value == null || value.trim().length === 0) {
        hasWithoutInfo = true;
      } else {
        values.add(value);
      }
    }
    return { values: [...values].sort(), hasWithoutInfo };
  }

  async getWeek(
    locale: LocaleResolution,
    groupId: string,
    range: { from: string; to: string },
  ): Promise<{
    data: TimetableWeekDto;
    lastSyncAt: Date | null;
    stale: boolean;
    dataState: 'ready' | 'pending' | 'unavailable';
  }> {
    const [group, lastSyncAt] = await Promise.all([
      this.prisma.timetableGroup.findFirst({
        where: { id: groupId },
        select: { id: true, shortName: true, longName: true, department: true },
      }),
      this.lastSuccessful('entries'),
    ]);
    if (!group) {
      throw new ApiError('TIMETABLE_GROUP_NOT_FOUND', locale.resolvedLocale);
    }

    const rangeStart = new Date(`${range.from}T00:00:00.000Z`);
    const rangeEnd = new Date(`${range.to}T00:00:00.000Z`);

    // Every day of the range is present, so the client can tell a genuinely
    // free day from a loading failure — the same rule the canteen menu uses.
    const byDate = new Map<string, TimetableEntryDto[]>();
    for (let cursor = rangeStart.getTime(); cursor <= rangeEnd.getTime(); cursor += 86_400_000) {
      byDate.set(new Date(cursor).toISOString().slice(0, 10), []);
    }

    if (this.featureEnabled) {
      const links = await this.prisma.timetableEntryGroup.findMany({
        where: { groupId: group.id, entry: { date: { gte: rangeStart, lte: rangeEnd } } },
        select: {
          entry: {
            select: {
              id: true,
              date: true,
              startsAt: true,
              endsAt: true,
              title: true,
              subjectCode: true,
              type: true,
              status: true,
              teachers: true,
              rooms: true,
              note: true,
              lessonInfo: true,
              groups: {
                select: {
                  group: {
                    select: { id: true, shortName: true, longName: true, department: true },
                  },
                },
              },
            },
          },
        },
        orderBy: { entry: { startsAt: 'asc' } },
      });

      for (const link of links) {
        const entry = link.entry;
        const date = entry.date.toISOString().slice(0, 10);

        byDate.get(date)?.push({
          id: entry.id,
          start: entry.startsAt.toISOString(),
          end: entry.endsAt.toISOString(),
          timezone: TIMETABLE_TIMEZONE,
          title: entry.title,
          subjectCode: entry.subjectCode,
          type: entry.type,
          status: entry.status,
          teachers: TimetableService.mapRefs<TimetableTeacherDto>(entry.teachers, (ref) =>
            typeof ref.shortName === 'string'
              ? {
                  shortName: ref.shortName,
                  displayName: typeof ref.displayName === 'string' ? ref.displayName : null,
                }
              : null,
          ),
          rooms: TimetableService.mapRefs<TimetableRoomDto>(entry.rooms, (ref) =>
            typeof ref.shortName === 'string'
              ? {
                  shortName: ref.shortName,
                  longName: typeof ref.longName === 'string' ? ref.longName : null,
                }
              : null,
          ),
          groups: entry.groups.map((entryGroup) => TimetableService.mapGroup(entryGroup.group)),
          note: entry.note,
          lessonInfo: entry.lessonInfo,
        });
      }
    }

    const hasAny = [...byDate.values()].some((entries) => entries.length > 0);
    const dataState: 'ready' | 'pending' | 'unavailable' = !this.featureEnabled
      ? 'unavailable'
      : lastSyncAt
        ? 'ready'
        : // Enabled but never synchronised: the worker has simply not run yet.
          // That is a temporary state the client can retry, not an error.
          hasAny
          ? 'ready'
          : 'pending';

    return {
      data: {
        group: TimetableService.mapGroup(group),
        days: [...byDate.entries()].map(([date, entries]): TimetableDayDto => ({ date, entries })),
      },
      lastSyncAt,
      stale: this.isStale(lastSyncAt),
      dataState,
    };
  }

  async getStatus(): Promise<TimetableStatusDto> {
    const [groupCount, lastGroupSyncAt, lastEntryRun] = await Promise.all([
      this.prisma.timetableGroup.count({
        where: { active: true, catalogVisible: true },
      }),
      this.lastSuccessful('groups'),
      this.lastEntryRun(),
    ]);

    const lastEntrySyncAt = lastEntryRun?.finishedAt ?? null;

    return {
      featureEnabled: this.featureEnabled,
      groupCount,
      lastGroupSyncAt: lastGroupSyncAt?.toISOString() ?? null,
      lastEntrySyncAt: lastEntrySyncAt?.toISOString() ?? null,
      dataStale: this.isStale(lastEntrySyncAt),
      coveredFrom: lastEntryRun?.rangeFrom?.toISOString().slice(0, 10) ?? null,
      coveredTo: lastEntryRun?.rangeTo?.toISOString().slice(0, 10) ?? null,
    };
  }
}
