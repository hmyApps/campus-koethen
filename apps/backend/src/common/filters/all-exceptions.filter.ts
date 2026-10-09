import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { Request, Response } from 'express';
import { ApiError, ApiErrorCode, messageFor } from '../errors/api-error';
import { DEFAULT_LOCALE, Locale, isSupportedLocale } from '../locale/locale';
import { asString } from '../util/coerce';

/**
 * Translates every escaping error into the documented public error shape.
 *
 * An unexpected exception is logged with a correlation id and answered with a
 * generic message. Internal details never reach the client, but the id makes
 * the log entry findable.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();
    const requestId = randomUUID();

    // Best-effort locale so the error message matches the rest of the response.
    // asString rather than String(): `?locale[]=x` arrives as an array and
    // String() would turn it into text that could never match a locale.
    const rawLocale = asString(request.query?.['locale']).toLowerCase();
    const locale: Locale = isSupportedLocale(rawLocale) ? rawLocale : DEFAULT_LOCALE;

    // An error answer is never worth keeping — not by a client, not by the
    // edge cache. This also overrides a long-lived Cache-Control a route set
    // before it failed: Nest applies @Header() decorators BEFORE the handler
    // runs, so a 404 or 503 would otherwise leave with the success header.
    response.setHeader('Cache-Control', 'no-store');

    if (exception instanceof ApiError) {
      const body = exception.getResponse() as { error: Record<string, unknown> };
      response.status(exception.getStatus()).json({
        error: { ...body.error, requestId },
      });
      return;
    }

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const original = exception.getResponse();
      // Nest's built-in validation errors carry a useful `message` array.
      const details =
        typeof original === 'object' && original !== null && 'message' in original
          ? original.message
          : undefined;

      // The code follows the STATUS. Reporting a 503 from a framework guard as
      // VALIDATION_FAILED tells a client the request was wrong when it was not,
      // and sends whoever reads the log looking in the wrong place.
      const code = AllExceptionsFilter.codeForStatus(status);

      response.status(status).json({
        error: {
          status,
          code,
          message: messageFor(code, locale),
          ...(Array.isArray(details) ? { details } : {}),
          requestId,
        },
      });
      return;
    }

    // The Error itself, never `exception.stack` as text: a string is free text
    // to the logger, so its production rule for errors (name and code only —
    // no message, no stack) would not apply, and a stack starts with the
    // message. A thrown non-Error is described by its type alone for the same
    // reason.
    this.logger.error(
      `Unhandled exception on ${request.method} ${request.path} (requestId=${requestId})`,
      exception instanceof Error ? exception : { thrownType: typeof exception },
    );

    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      error: {
        status: HttpStatus.INTERNAL_SERVER_ERROR,
        code: 'INTERNAL_ERROR',
        message: messageFor('INTERNAL_ERROR', locale),
        requestId,
      },
    });
  }

  /**
   * The published code for a framework-raised status.
   *
   * A 404 is answered NEUTRALLY: whether a route, an image or a slug was
   * missing is not a statement about posts, and the resource-specific codes are
   * raised deliberately by the handlers that know what was looked up.
   */
  private static codeForStatus(status: number): ApiErrorCode {
    if (status === Number(HttpStatus.NOT_FOUND)) return 'NOT_FOUND';
    if (status >= 500) return 'INTERNAL_ERROR';
    return 'VALIDATION_FAILED';
  }
}
