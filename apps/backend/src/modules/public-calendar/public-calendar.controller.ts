import { Controller, Get, Inject, Param, Query } from '@nestjs/common';
import { ApiOkResponse, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { z } from 'zod';
import { ApiResponse, buildMeta } from '../../common/dto/meta.dto';
import { ApiError } from '../../common/errors/api-error';
import { Locale, LocaleResolution } from '../../common/locale/locale';
import { RequestLocale } from '../../common/locale/locale.decorator';
import { isoDate, parseWith, refineDateRange } from '../../common/validation/query';
import { ENV } from '../../config/app-config.module';
import { addCalendarDays, campusToday } from '../../common/time/campus-date';
import { Env } from '../../config/env.schema';
import { PublicCalendarService } from './public-calendar.service';
import {
  GoogleViewUrlDataDto,
  GoogleViewUrlResponseDto,
  PublicCalendarDto,
  PublicCalendarEventDto,
  PublicCalendarEventsResponseDto,
  PublicCalendarListResponseDto,
} from './public-calendar.types';

const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

@ApiTags('public-calendars')
@Controller({ path: 'calendars', version: '1' })
export class PublicCalendarController {
  /**
   * Built once, not per request.
   *
   * The schema depends on nothing but `PUBLIC_CALENDAR_API_MAX_RANGE_DAYS`, an
   * environment value that is fixed for the life of the process — but it used
   * to be constructed inside the request path, so every call to
   * `/v1/calendars/events` and `/v1/calendars/:slug/events` paid for building a
   * regex, three refinements and a transform before it validated anything.
   * Measured over 20.000 runs: 151,5 µs to build and parse against 2,5 µs to
   * parse alone. Every other query schema in this codebase is already a
   * constant; this one was the exception.
   */
  private readonly dateRange: ReturnType<typeof PublicCalendarController.buildDateRangeSchema>;

  constructor(
    private readonly calendars: PublicCalendarService,
    @Inject(ENV) private readonly env: Env,
  ) {
    this.dateRange = PublicCalendarController.buildDateRangeSchema(
      env.PUBLIC_CALENDAR_API_MAX_RANGE_DAYS,
    );
  }

  private static buildDateRangeSchema(maxDays: number) {
    return refineDateRange(
      z.object({ from: isoDate.optional(), to: isoDate.optional() }).transform((raw) => {
        // Resolved at parse time, not at build time: the default window is
        // relative to "now", so it has to move with the clock.
        const today = campusToday();
        const from = raw.from ?? today;
        const to = raw.to ?? addCalendarDays(today, maxDays);
        return { from, to };
      }),
      maxDays,
    );
  }

  private parseCalendars(raw: unknown, locale: Locale): string[] {
    const values = Array.isArray(raw) ? raw : raw === undefined ? [] : [raw];
    const slugs: string[] = [];
    for (const v of values) {
      const s = String(v).trim();
      if (!SLUG_PATTERN.test(s)) {
        throw new ApiError('VALIDATION_FAILED', locale, [
          `calendar: invalid slug "${s.slice(0, 40)}"`,
        ]);
      }
      slugs.push(s);
    }
    const unique = [...new Set(slugs)];
    if (unique.length > this.env.PUBLIC_CALENDAR_API_MAX_CALENDARS) {
      throw new ApiError('VALIDATION_FAILED', locale, ['calendar: too many calendars requested']);
    }
    return unique;
  }

  private range(query: Record<string, unknown>, locale: Locale): { from: Date; to: Date } {
    const parsed = parseWith(this.dateRange, query, locale);
    return {
      from: new Date(`${parsed.from}T00:00:00.000Z`),
      to: new Date(`${parsed.to}T23:59:59.999Z`),
    };
  }

  @Get()
  @ApiOperation({
    summary: 'List public calendars (read-only, synced from their public ICS feed).',
    description:
      'Only active, validated calendars that have synced at least once. The Google calendar id and feed URL are never exposed; each item carries a safe googleOpenUrl.',
  })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: PublicCalendarListResponseDto })
  async list(@RequestLocale() locale: LocaleResolution): Promise<ApiResponse<PublicCalendarDto[]>> {
    const { data, translationFallback } = await this.calendars.listCalendars(locale);
    const today = campusToday();
    return {
      data,
      meta: buildMeta({
        ...locale,
        translationFallback,
        featureEnabled: this.env.PUBLIC_CALENDAR_ENABLED,
        from: today,
        to: addCalendarDays(today, this.env.PUBLIC_CALENDAR_LOOKAHEAD_DAYS),
        maxRangeDays: this.env.PUBLIC_CALENDAR_API_MAX_RANGE_DAYS,
      }),
    };
  }

  @Get('events')
  @ApiOperation({
    summary: 'Aggregated events across several selected public calendars.',
    description:
      'Pass one `calendar` slug per selected calendar. An empty selection returns an empty list (never "all calendars"). Each event carries calendarId and calendarSlug. The result is capped server-side; `meta.truncated` reports a cut list rather than presenting it as complete.',
  })
  @ApiQuery({ name: 'calendar', required: false, isArray: true, type: String })
  @ApiQuery({ name: 'from', required: false, description: 'YYYY-MM-DD' })
  @ApiQuery({ name: 'to', required: false, description: 'YYYY-MM-DD' })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: PublicCalendarEventsResponseDto })
  async aggregated(
    @RequestLocale() locale: LocaleResolution,
    @Query() query: Record<string, unknown>,
  ): Promise<ApiResponse<PublicCalendarEventDto[]>> {
    const slugs = this.parseCalendars(query.calendar, locale.resolvedLocale);
    const range = this.range(query, locale.resolvedLocale);
    const { events, truncated } = await this.calendars.getAggregatedEvents(
      slugs,
      range.from,
      range.to,
    );
    return {
      data: events,
      meta: buildMeta({
        ...locale,
        translationFallback: false,
        from: range.from.toISOString().slice(0, 10),
        to: range.to.toISOString().slice(0, 10),
        truncated,
      }),
    };
  }

  @Get('google-view-url')
  @ApiOperation({
    summary: 'A combined calendar.google.com embed URL for the selected calendars.',
    description:
      "Server-constructed HTTPS URL (one src per calendar). This is a shared VIEW only — it never adds anything to a user's personal Google account.",
  })
  @ApiQuery({ name: 'calendar', required: true, isArray: true, type: String })
  @ApiOkResponse({ type: GoogleViewUrlResponseDto })
  async googleViewUrl(
    @RequestLocale() locale: LocaleResolution,
    @Query() query: Record<string, unknown>,
  ): Promise<ApiResponse<GoogleViewUrlDataDto>> {
    const slugs = this.parseCalendars(query.calendar, locale.resolvedLocale);
    const url = await this.calendars.buildGoogleViewUrl(slugs, locale.resolvedLocale);
    return { data: { url }, meta: buildMeta({ ...locale, translationFallback: false }) };
  }

  @Get(':slug/events')
  @ApiOperation({
    summary: 'Events of a single public calendar in a date range.',
    description:
      'The result is capped server-side; `meta.truncated` reports a cut list rather than presenting it as complete.',
  })
  @ApiQuery({ name: 'from', required: false, description: 'YYYY-MM-DD' })
  @ApiQuery({ name: 'to', required: false, description: 'YYYY-MM-DD' })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: PublicCalendarEventsResponseDto })
  async single(
    @RequestLocale() locale: LocaleResolution,
    @Param('slug') slug: string,
    @Query() query: Record<string, unknown>,
  ): Promise<ApiResponse<PublicCalendarEventDto[]>> {
    if (!SLUG_PATTERN.test(slug))
      throw new ApiError('PUBLIC_CALENDAR_NOT_FOUND', locale.resolvedLocale);
    const range = this.range(query, locale.resolvedLocale);
    const result = await this.calendars.getCalendarEvents(slug, range.from, range.to);
    if (!result) throw new ApiError('PUBLIC_CALENDAR_NOT_FOUND', locale.resolvedLocale);
    return {
      data: result.events,
      meta: buildMeta({
        ...locale,
        translationFallback: false,
        from: range.from.toISOString().slice(0, 10),
        to: range.to.toISOString().slice(0, 10),
        lastSuccessfulSyncAt: result.calendar.lastSuccessfulSyncAt,
        dataStale: result.calendar.dataStale,
        truncated: result.truncated,
      }),
    };
  }
}
