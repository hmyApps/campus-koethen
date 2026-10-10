import { Controller, Get, Header, Headers, Param, Res } from '@nestjs/common';
import { ApiHeader, ApiOperation, ApiParam, ApiResponse, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import { ApiError } from '../../common/errors/api-error';
import { MediaError, MediaService } from './media.service';

/**
 * Freshness of a delivered image.
 *
 * Set by the handler on a 200 or 304 only — deliberately NOT through
 * `@Header()`, which Nest applies before the handler runs, so a 404 or a 503
 * left with it too and the edge cache kept the failure for a day. Error
 * answers are marked `no-store` by the global exception filter.
 */
const IMAGE_CACHE_CONTROL = 'public, max-age=86400';

/**
 * Serves editorial images.
 *
 * The one endpoint of this API that answers with bytes rather than JSON, and
 * the reason the app never has to know Strapi's address: contact photos and
 * news banners are published as `/v1/media/uploads/…` and fetched from the
 * Campus API like everything else (AGENTS.md §2.1).
 */
@ApiTags('media')
@Controller({ path: 'media', version: '1' })
export class MediaController {
  constructor(private readonly media: MediaService) {}

  @Get('uploads/:filename')
  @ApiOperation({
    summary: 'An editorial image from the CMS.',
    description:
      'Images only, from the CMS upload directory only. The path is validated against a strict ' +
      'allowlist before anything is fetched, so it cannot be pointed at another target. Cached ' +
      'for a day: editorial images are replaced by uploading a new file, which changes the name. ' +
      'Send the ETag back as `If-None-Match` to revalidate: a still-current image answers 304 ' +
      'without a body instead of being transferred again.',
  })
  @ApiParam({ name: 'filename', example: 'foto_5a141d3978.jpeg' })
  @ApiHeader({
    name: 'If-None-Match',
    required: false,
    description: 'Entity tag from a previous response. A match answers 304 without a body.',
    example: 'W/"1f-18c2b4d1e20"',
  })
  @ApiResponse({ status: 200, description: 'The image bytes.' })
  @ApiResponse({ status: 304, description: 'The client copy is still current. No body.' })
  // Belt and braces for a byte-serving endpoint: nothing here should ever be
  // interpreted as a document by a client that guesses at content types.
  @Header('X-Content-Type-Options', 'nosniff')
  @Header('Content-Disposition', 'inline')
  async get(
    @Param('filename') filename: string,
    @Headers('if-none-match') ifNoneMatch: string | undefined,
    @Res() response: Response,
  ): Promise<void> {
    try {
      const result = await this.media.fetch(`/uploads/${filename}`, { ifNoneMatch });
      response.setHeader('Cache-Control', IMAGE_CACHE_CONTROL);
      if (result.etag) {
        response.setHeader('ETag', result.etag);
      }
      if (result.kind === 'not-modified') {
        // A 304 carries no body and no Content-Type. Cache-Control and the
        // header guards above still apply — they are what the client keeps.
        response.status(304).end();
        return;
      }
      response.setHeader('Content-Type', result.contentType);
      response.send(result.body);
    } catch (error) {
      throw MediaController.toApiError(error);
    }
  }

  private static toApiError(error: unknown): ApiError {
    if (!(error instanceof MediaError)) {
      return new ApiError('UPSTREAM_UNAVAILABLE');
    }
    switch (error.kind) {
      case 'not-found':
      case 'unsupported':
        // Deliberately the same answer: whether a path is outside the
        // allowlist, holds a PDF or simply does not exist is nobody's
        // business, and distinguishing them would map out the upload
        // directory for anyone who asks often enough.
        return new ApiError('MEDIA_NOT_FOUND');
      case 'too-large':
      case 'unavailable':
        return new ApiError('UPSTREAM_UNAVAILABLE');
    }
  }
}
