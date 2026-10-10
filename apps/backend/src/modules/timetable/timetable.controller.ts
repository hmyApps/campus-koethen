import { Controller, Get, Inject, Param, Query } from '@nestjs/common';
import { ApiOkResponse, ApiOperation, ApiParam, ApiQuery, ApiTags } from '@nestjs/swagger';
import { z } from 'zod';
import { ApiResponse, buildMeta } from '../../common/dto/meta.dto';
import { LocaleResolution } from '../../common/locale/locale';
import { RequestLocale } from '../../common/locale/locale.decorator';
import { addCalendarDays, campusToday } from '../../common/time/campus-date';
import {
  isoDate,
  paginationSchema,
  parseWith,
  refineDateRange,
} from '../../common/validation/query';
import { ENV } from '../../config/app-config.module';
import { Env } from '../../config/env.schema';
import { TimetableService } from './timetable.service';
import { TIMETABLE_TIMEZONE } from './webuntis.schema';
import {
  TimetableGroupDto,
  TimetableGroupResponseDto,
  TimetableGroupsResponseDto,
  TimetableLessonInfoDto,
  TimetableLessonInfoResponseDto,
  TimetableModuleDto,
  TimetableModulesResponseDto,
  TimetablePeriodDto,
  TimetablePeriodsResponseDto,
  TimetableStatusDto,
  TimetableStatusResponseDto,
  TimetableWeekDto,
  TimetableWeekResponseDto,
} from './timetable.types';

/** A timetable window is bounded; an unbounded range is an availability risk. */
const MAX_RANGE_DAYS = 42;

const groupsQuerySchema = paginationSchema.extend({
  query: z.string().trim().max(100).optional(),
  department: z.string().trim().max(100).optional(),
});

const groupParamSchema = z.object({ groupId: z.uuid('must be a Campus group id') });

const lessonInfoQuerySchema = z.object({ groupId: z.uuid('must be a Campus group id') });

const weekQuerySchema = refineDateRange(
  z.object({ groupId: z.uuid('must be a Campus group id'), from: isoDate, to: isoDate }),
  MAX_RANGE_DAYS,
);

@ApiTags('timetable')
@Controller({ path: 'timetable', version: '1' })
export class TimetableController {
  constructor(
    private readonly timetable: TimetableService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /**
   * The timetable horizon advertised with the catalogue: from the campus day
   * (Europe/Berlin, not UTC) to the end of the configured look-ahead.
   */
  private horizon(): { from: string; to: string } {
    const from = campusToday();
    return { from, to: addCalendarDays(from, this.env.WEBUNTIS_LOOKAHEAD_DAYS) };
  }

  @Get('groups')
  @ApiOperation({
    summary: 'List selectable class groups.',
    description:
      'Comes from the synchronised catalogue, never from a live upstream call. Identifiers are Campus UUIDs; the source system id is never exposed.',
  })
  @ApiQuery({
    name: 'query',
    required: false,
    description: 'Searches short name, long name and department.',
  })
  @ApiQuery({ name: 'department', required: false })
  @ApiQuery({ name: 'page', required: false, type: Number })
  @ApiQuery({ name: 'pageSize', required: false, type: Number, description: 'Max 50.' })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: TimetableGroupsResponseDto })
  async groups(
    @RequestLocale() locale: LocaleResolution,
    @Query() query: Record<string, unknown>,
  ): Promise<ApiResponse<TimetableGroupDto[]>> {
    const filter = parseWith(groupsQuerySchema, query, locale.resolvedLocale);
    const result = await this.timetable.listGroups(locale, filter);

    return {
      data: result.data,
      meta: buildMeta({
        ...locale,
        // Group names are the source's own strings and are never translated.
        translationFallback: locale.resolvedLocale !== 'de',
        pagination: result.pagination,
        featureEnabled: this.timetable.featureEnabled,
        lastSuccessfulSyncAt: result.lastSyncAt?.toISOString() ?? null,
        dataStale: result.stale,
        ...this.horizon(),
      }),
    };
  }

  @Get('groups/:groupId')
  @ApiOperation({
    summary: 'Resolve one previously selected class group.',
    description:
      'Returns one group by its stable Campus UUID so clients can retain the selection and its public label offline without downloading the catalogue.',
  })
  @ApiParam({ name: 'groupId', format: 'uuid', description: 'Stable Campus UUID.' })
  @ApiOkResponse({ type: TimetableGroupResponseDto })
  async group(
    @RequestLocale() locale: LocaleResolution,
    @Param() params: Record<string, unknown>,
  ): Promise<ApiResponse<TimetableGroupDto>> {
    const { groupId } = parseWith(groupParamSchema, params, locale.resolvedLocale);
    const result = await this.timetable.getGroup(locale, groupId);

    return {
      data: result.data,
      meta: buildMeta({
        ...locale,
        translationFallback: locale.resolvedLocale !== 'de',
        featureEnabled: this.timetable.featureEnabled,
        lastSuccessfulSyncAt: result.lastSyncAt?.toISOString() ?? null,
        dataStale: result.stale,
        ...this.horizon(),
      }),
    };
  }

  @Get('periods')
  @ApiOperation({
    summary: 'List semester catalogues available to the timetable assistant.',
    description:
      'Contains Campus UUIDs only. WebUntis school-year and class identifiers remain server-internal.',
  })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: TimetablePeriodsResponseDto })
  async periods(
    @RequestLocale() locale: LocaleResolution,
  ): Promise<ApiResponse<TimetablePeriodDto[]>> {
    const result = await this.timetable.listPeriods();
    return {
      data: result.data,
      meta: buildMeta({
        ...locale,
        translationFallback: locale.resolvedLocale !== 'de',
        featureEnabled: this.timetable.featureEnabled,
        lastSuccessfulSyncAt: result.lastSyncAt?.toISOString() ?? null,
        dataStale: result.stale,
      }),
    };
  }

  @Get('lesson-info')
  @ApiOperation({
    summary: 'List exact lesson information texts for a selected timetable group.',
    description:
      'Reads the last successfully imported timetable window from the Campus database. No WebUntis request is triggered.',
  })
  @ApiQuery({ name: 'groupId', required: true, format: 'uuid' })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: TimetableLessonInfoResponseDto })
  async lessonInfo(
    @RequestLocale() locale: LocaleResolution,
    @Query() query: Record<string, unknown>,
  ): Promise<ApiResponse<TimetableLessonInfoDto>> {
    const { groupId } = parseWith(lessonInfoQuerySchema, query, locale.resolvedLocale);
    return {
      data: await this.timetable.listLessonInfo(groupId, locale),
      meta: buildMeta({ ...locale, translationFallback: locale.resolvedLocale !== 'de' }),
    };
  }

  @Get('modules')
  @ApiOperation({
    summary: 'List modules observed for one selectable study group.',
    description:
      'Reads retained Campus timetable rows only. Module names and codes are source-provided; no upstream identifiers or live request are exposed.',
  })
  @ApiQuery({ name: 'groupId', required: true, format: 'uuid' })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: TimetableModulesResponseDto })
  async modules(
    @RequestLocale() locale: LocaleResolution,
    @Query() query: Record<string, unknown>,
  ): Promise<ApiResponse<TimetableModuleDto[]>> {
    const { groupId } = parseWith(lessonInfoQuerySchema, query, locale.resolvedLocale);
    const result = await this.timetable.listModules(groupId, locale);
    return {
      data: result.data,
      meta: buildMeta({
        ...locale,
        translationFallback: locale.resolvedLocale !== 'de',
        featureEnabled: this.timetable.featureEnabled,
        lastSuccessfulSyncAt: result.lastSyncAt?.toISOString() ?? null,
        dataStale: result.stale,
      }),
    };
  }

  @Get('entries')
  @ApiOperation({
    summary: 'Fetch one group’s timetable for a date range.',
    description:
      'Every day of the range is returned, so a genuinely free day is distinguishable from a loading error. Range is capped at 42 days.',
  })
  @ApiQuery({ name: 'groupId', required: true, format: 'uuid' })
  @ApiQuery({ name: 'from', required: true, example: '2026-07-20' })
  @ApiQuery({ name: 'to', required: true, example: '2026-08-02' })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: TimetableWeekResponseDto })
  async entries(
    @RequestLocale() locale: LocaleResolution,
    @Query() query: Record<string, unknown>,
  ): Promise<ApiResponse<TimetableWeekDto>> {
    const range = parseWith(weekQuerySchema, query, locale.resolvedLocale);
    const result = await this.timetable.getWeek(locale, range.groupId, range);

    return {
      data: result.data,
      meta: buildMeta({
        ...locale,
        // Subjects, rooms and teachers stay in the source language.
        translationFallback: locale.resolvedLocale !== 'de',
        timezone: TIMETABLE_TIMEZONE,
        from: range.from,
        to: range.to,
        lastSuccessfulSyncAt: result.lastSyncAt?.toISOString() ?? null,
        dataStale: result.stale,
        dataState: result.dataState,
        featureEnabled: this.timetable.featureEnabled,
      }),
    };
  }

  @Get('status')
  @ApiOperation({
    summary: 'Public health of the timetable integration.',
    description: 'Deliberately thin: no upstream URLs, headers, external ids or error detail.',
  })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: TimetableStatusResponseDto })
  async status(
    @RequestLocale() locale: LocaleResolution,
  ): Promise<ApiResponse<TimetableStatusDto>> {
    return {
      data: await this.timetable.getStatus(),
      meta: buildMeta({ ...locale, translationFallback: false }),
    };
  }
}
