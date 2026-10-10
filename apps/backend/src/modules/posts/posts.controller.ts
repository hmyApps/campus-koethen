// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import { Controller, Get, Inject, Param, Query } from '@nestjs/common';
import { ApiOkResponse, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { ApiResponse, buildMeta } from '../../common/dto/meta.dto';
import { RequestLocale } from '../../common/locale/locale.decorator';
import { LocaleResolution } from '../../common/locale/locale';
import {
  isoDate,
  paginationSchema,
  parseChannels,
  parseTags,
  parseWith,
  refineDateRange,
} from '../../common/validation/query';
import { ENV } from '../../config/app-config.module';
import { Env } from '../../config/env.schema';
import { addCalendarDays, campusToday } from '../../common/time/campus-date';
import { PostsService } from './posts.service';
import {
  ChannelDto,
  ChannelsResponseDto,
  PostDetailDto,
  PostDetailResponseDto,
  PostListItemDto,
  PostListResponseDto,
  TagDto,
  TagsResponseDto,
} from './posts.types';
import { z } from 'zod';

@ApiTags('posts')
@Controller({ path: 'posts', version: '1' })
export class PostsController {
  constructor(
    private readonly posts: PostsService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  private dateRangeSchema() {
    const maxDays = this.env.PUBLIC_CALENDAR_API_MAX_RANGE_DAYS;

    return refineDateRange(
      z.object({ from: isoDate.optional(), to: isoDate.optional() }).transform((raw) => {
        const today = campusToday();
        const from = raw.from ?? today;
        const to = raw.to ?? addCalendarDays(today, maxDays);
        return { from, to };
      }),
      maxDays,
    );
  }

  @Get('channels')
  @ApiOperation({
    summary: 'List active channels.',
    description:
      'Channels are fully dynamic. A channel added in the CMS appears here — and therefore in the app — without any code change.',
  })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({
    description: 'Active channels ordered by sortOrder, then name.',
    type: ChannelsResponseDto,
  })
  async channels(@RequestLocale() locale: LocaleResolution): Promise<ApiResponse<ChannelDto[]>> {
    const result = await this.posts.getChannels(locale);
    return {
      data: result.data,
      meta: buildMeta({ ...locale, translationFallback: result.translationFallback }),
    };
  }

  @Get('tags')
  @ApiOperation({
    summary: 'List active tags.',
    description:
      'Tags are fully dynamic. A tag added in the CMS appears here — and therefore in the app — without any code change.',
  })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({
    description: 'Active tags ordered by sortOrder, then name.',
    type: TagsResponseDto,
  })
  async tags(@RequestLocale() locale: LocaleResolution): Promise<ApiResponse<TagDto[]>> {
    const result = await this.posts.getTags(locale);
    return {
      data: result.data,
      meta: buildMeta({ ...locale, translationFallback: result.translationFallback }),
    };
  }

  @Get('events')
  @ApiOperation({
    summary: 'List event posts within a time range.',
    description:
      'Filter for posts with tag "event". Accepts optional `from` and `to` date bounds and channel filters. Interval overlap: eventStart <= to AND (eventEnd ?? eventStart) >= from. Sorted deterministically by eventStart asc, slug asc.',
  })
  @ApiQuery({ name: 'from', required: false, description: 'YYYY-MM-DD' })
  @ApiQuery({ name: 'to', required: false, description: 'YYYY-MM-DD' })
  @ApiQuery({
    name: 'channels',
    required: false,
    description: 'Comma-separated channel slugs. At most 25, each at most 100 characters.',
  })
  @ApiQuery({ name: 'page', required: false, type: Number })
  @ApiQuery({ name: 'pageSize', required: false, type: Number, description: 'Max 50.' })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: PostListResponseDto })
  async events(
    @RequestLocale() locale: LocaleResolution,
    @Query() query: Record<string, unknown>,
  ): Promise<ApiResponse<PostListItemDto[]>> {
    const { page, pageSize } = parseWith(paginationSchema, query, locale.resolvedLocale);
    const range = parseWith(this.dateRangeSchema(), query, locale.resolvedLocale);
    const { channels, channelsParamPresent } = parseChannels(
      query['channels'],
      locale.resolvedLocale,
    );

    const result = await this.posts.getEvents(locale, {
      from: range.from,
      to: range.to,
      channels,
      channelsParamPresent,
      page,
      pageSize,
    });

    return {
      data: result.data,
      meta: buildMeta({
        ...locale,
        from: range.from,
        to: range.to,
        translationFallback: result.translationFallback,
        pagination: result.pagination,
        droppedBlockTypes: result.droppedBlockTypes,
      }),
    };
  }

  @Get(':slug')
  @ApiOperation({
    summary: 'Fetch one post by its stable slug.',
    description:
      'Unknown content block types are removed server-side and reported in meta.droppedBlockTypes, so a new CMS block type can never break the detail screen.',
  })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: PostDetailResponseDto })
  async detail(
    @RequestLocale() locale: LocaleResolution,
    @Param('slug') slug: string,
  ): Promise<ApiResponse<PostDetailDto>> {
    const result = await this.posts.getPostBySlug(locale, slug);
    return {
      data: result.data,
      meta: buildMeta({
        ...locale,
        translationFallback: result.translationFallback,
        droppedBlockTypes: result.droppedBlockTypes,
      }),
    };
  }

  @Get()
  @ApiOperation({
    summary: 'List published posts.',
    description:
      'An absent `channels` parameter means all active channels; a present but empty `channels=` means the user deselected everything and yields an empty list. An absent `tags` parameter applies no tag filter; a present but empty `tags=` yields an empty list. Both filters combine with AND. Each entry carries its sanitised `content`, so a feed can render posts inline without a request per card; unknown block types are removed server-side and reported once in `meta.droppedBlockTypes`.',
  })
  @ApiQuery({
    name: 'channels',
    required: false,
    description: 'Comma-separated channel slugs. At most 25, each at most 100 characters.',
  })
  @ApiQuery({
    name: 'tags',
    required: false,
    description: 'Comma-separated tag slugs. At most 25, each at most 100 characters.',
  })
  @ApiQuery({ name: 'page', required: false, type: Number })
  @ApiQuery({ name: 'pageSize', required: false, type: Number, description: 'Max 50.' })
  @ApiQuery({ name: 'locale', required: false, enum: ['de', 'en'] })
  @ApiOkResponse({ type: PostListResponseDto })
  async list(
    @RequestLocale() locale: LocaleResolution,
    @Query() query: Record<string, unknown>,
  ): Promise<ApiResponse<PostListItemDto[]>> {
    const { page, pageSize } = parseWith(paginationSchema, query, locale.resolvedLocale);
    const { channels, channelsParamPresent } = parseChannels(
      query['channels'],
      locale.resolvedLocale,
    );
    const { tags, tagsParamPresent } = parseTags(query['tags'], locale.resolvedLocale);

    const result = await this.posts.getPosts(locale, {
      channels,
      channelsParamPresent,
      tags,
      tagsParamPresent,
      page,
      pageSize,
    });

    return {
      data: result.data,
      meta: buildMeta({
        ...locale,
        translationFallback: result.translationFallback,
        pagination: result.pagination,
        droppedBlockTypes: result.droppedBlockTypes,
      }),
    };
  }
}
