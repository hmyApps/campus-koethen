// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/documents/app_document.dart';
import '../domain/case_status.dart';
import '../domain/gremio_origin.dart';
import 'requests_api_config.dart';

/// What came back from fetching one of a case's documents.
sealed class DocumentResult {
  const DocumentResult();
}

class DocumentLoaded extends DocumentResult {
  const DocumentLoaded(this.document);

  final AppDocument document;
}

/// The link did not point at the configured instance, or was not HTTPS.
///
/// Never fetched. Every one of these URLs carries the case's secret token, and
/// following one to another host is precisely how that token would leak.
class DocumentRefused extends DocumentResult {
  const DocumentRefused();
}

/// Larger than the in-app viewer can hold. Not downloaded — reading 200 MB
/// into memory to then refuse to render it helps nobody.
class DocumentTooLarge extends DocumentResult {
  const DocumentTooLarge();
}

class DocumentUnavailable extends DocumentResult {
  const DocumentUnavailable(this.reason);

  /// A short technical reason. Never the URL.
  final String reason;
}

/// Downloads a case's public documents for the in-app viewer.
///
/// Three rules hold throughout:
///
/// * **Same origin, HTTPS, no credentials.** Checked before the request. Every
///   redirect is refused rather than following a token-bearing URL to a target
///   the original response could choose.
/// * **Nothing is written to disk.** The bytes go to the viewer in memory and
///   are gone when it closes; a downloaded receipt is not left lying around
///   unencrypted.
/// * **No URL is ever logged**, not in an error, not in a reason string.
class CaseDocumentDownloader {
  CaseDocumentDownloader({required Dio dio, required String baseUrl})
    : this._(dio, GremioOrigin.parse(baseUrl));

  CaseDocumentDownloader._(this._dio, this._origin);

  final Dio _dio;
  final GremioOrigin? _origin;

  /// Fetches one document of a case.
  Future<DocumentResult> fetch({
    required String url,
    required String filename,
    required String mimeType,
  }) async {
    final GremioOrigin? origin = _origin;
    if (origin == null || !origin.allows(url)) return const DocumentRefused();

    try {
      final Response<ResponseBody> response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          // Keep the response as a stream. ResponseType.bytes would buffer the
          // entire body before the limit below can inspect it, making the limit
          // ineffective against a dishonest or missing Content-Length.
          responseType: ResponseType.stream,
          receiveTimeout: RequestsApiConfig.receiveTimeout,
          // Redirects are handled here rather than by dio, so none can replay
          // the token-bearing URL to a server-selected target.
          followRedirects: false,
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      final int status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        // A redirect could be legitimate, but we cannot verify where it leads
        // without following it. Refusing is the safe answer for a request that
        // carries a token.
        return const DocumentRefused();
      }
      if (status != 200) return DocumentUnavailable('http-$status');

      final int? declaredLength = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (declaredLength != null && declaredLength > kMaxInMemoryPreviewBytes) {
        return const DocumentTooLarge();
      }

      final ResponseBody? body = response.data;
      if (body == null) {
        return const DocumentUnavailable('empty-body');
      }

      final BytesBuilder builder = BytesBuilder(copy: false);
      try {
        await for (final Uint8List chunk in body.stream) {
          if (builder.length + chunk.length > kMaxInMemoryPreviewBytes) {
            // Returning from an await-for cancels the subscription, so no later
            // chunk is pulled and no over-limit body is accumulated in memory.
            return const DocumentTooLarge();
          }
          builder.add(chunk);
        }
      } catch (_) {
        return const DocumentUnavailable('stream');
      }

      final Uint8List bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        return const DocumentUnavailable('empty-body');
      }

      return DocumentLoaded(
        AppDocument(
          filename: filename,
          mediaType: mediaTypeFor(filename, declared: mimeType),
          bytes: bytes,
          sizeBytes: bytes.length,
        ),
      );
    } on DioException catch (error) {
      // A type name, never the URL.
      return DocumentUnavailable('dio-${error.type.name}');
    }
  }

  /// Convenience for a document listed in a status response.
  ///
  /// [fallbackFilename] is the localized name used when the server sent none.
  Future<DocumentResult> fetchDocument(
    StatusDocument document, {
    required String fallbackFilename,
  }) => fetch(
    url: document.downloadUrl,
    filename: document.filename ?? fallbackFilename,
    mimeType: document.mimeType,
  );
}
