// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/documents/app_document.dart';
import '../domain/moodle_downloader.dart';
import '../domain/moodle_failure.dart';
import '../domain/moodle_profile.dart';
import 'moodle_http_client.dart';

/// Downloads a single Moodle file on demand into memory.
///
/// Security policy, all central and non-bypassable:
///  * the file URL must be HTTPS on `moodle.hs-anhalt.de` — otherwise the
///    request is refused and the token is never sent;
///  * the token travels in the POST body, never in the URL;
///  * redirects are never followed with the token;
///  * a declared size or an actual stream exceeding [kMaxInMemoryPreviewBytes]
///    aborts with [MoodleFailureKind.fileTooLarge];
///  * a cancelled or failed transfer keeps no partial bytes (the buffer is
///    local and simply discarded — nothing is written to disk);
///  * a cancel aborts the request itself and ends with
///    [MoodleDownloadCancelled], never with a failure;
///  * the Moodle transport timeouts apply, so a hung connection ends with
///    [MoodleFailureKind.timeout] instead of waiting forever.
class MoodleFileDownloaderImpl implements MoodleFileDownloader {
  MoodleFileDownloaderImpl({
    Dio? dio,
    this.profile = const MoodleProfile(),
    this.maxBytes = kMaxInMemoryPreviewBytes,
    this.receiveTimeout = kMoodleReceiveTimeout,
  }) : _dio = dio ?? Dio();

  final Dio _dio;
  final MoodleProfile profile;
  final int maxBytes;
  final Duration receiveTimeout;

  @override
  Future<AppDocument> download({
    required String token,
    required String fileUrl,
    required String fileName,
    String? declaredMimeType,
    int? declaredSize,
    MoodleDownloadProgress? onProgress,
    MoodleDownloadCancel? cancel,
  }) async {
    final Uri? uri = Uri.tryParse(fileUrl);
    if (uri == null || !profile.allows(uri)) {
      // Wrong scheme or host: never attach the token, never send.
      throw const MoodleFailure(MoodleFailureKind.tlsOrHostRejected);
    }
    if (declaredSize != null && declaredSize > maxBytes) {
      throw const MoodleFailure(MoodleFailureKind.fileTooLarge);
    }
    if (cancel?.isCancelled ?? false) throw const MoodleDownloadCancelled();

    // Bound to the caller's handle so a cancel aborts the request itself,
    // whether it still waits for headers or its body has stopped arriving.
    final CancelToken cancelToken = CancelToken();
    unawaited(cancel?.whenCancelled.then((_) => cancelToken.cancel()));

    late final Response<ResponseBody> response;
    try {
      response = await _dio.postUri<ResponseBody>(
        uri,
        data: <String, String>{'token': token},
        // Pinned per request, like the redirect policy, so they also hold for
        // an injected Dio: without them a hung connection kept the file tile
        // locked indefinitely.
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (_) => true,
          connectTimeout: kMoodleConnectTimeout,
          sendTimeout: kMoodleSendTimeout,
          receiveTimeout: receiveTimeout,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      throw _classify(error, cancel);
    }

    final int status = response.statusCode ?? 0;
    if (status >= 300 && status < 400) {
      throw const MoodleFailure(MoodleFailureKind.tlsOrHostRejected);
    }
    if (status < 200 || status >= 300) {
      throw const MoodleFailure(MoodleFailureKind.downloadFailed);
    }

    final int? contentLength = int.tryParse(
      response.headers.value(Headers.contentLengthHeader) ?? '',
    );
    if (contentLength != null && contentLength > maxBytes) {
      throw const MoodleFailure(MoodleFailureKind.fileTooLarge);
    }

    final ResponseBody? body = response.data;
    if (body == null) {
      throw const MoodleFailure(MoodleFailureKind.downloadFailed);
    }

    final BytesBuilder builder = BytesBuilder(copy: false);
    try {
      await for (final Uint8List chunk in body.stream) {
        if (cancel?.isCancelled ?? false) {
          throw const MoodleDownloadCancelled();
        }
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw const MoodleFailure(MoodleFailureKind.fileTooLarge);
        }
        if (contentLength != null && contentLength > 0) {
          onProgress?.call(builder.length / contentLength);
        } else {
          onProgress?.call(null);
        }
      }
    } on MoodleFailure {
      rethrow;
    } on MoodleDownloadCancelled {
      rethrow;
    } catch (error) {
      // Any transport error mid-stream: discard the partial buffer.
      throw _classify(error, cancel);
    }
    if (cancel?.isCancelled ?? false) throw const MoodleDownloadCancelled();

    final Uint8List data = builder.takeBytes();
    return AppDocument(
      filename: fileName,
      mediaType: mediaTypeFor(fileName, declared: declaredMimeType),
      bytes: data,
      sizeBytes: data.length,
    );
  }

  /// A deliberate cancel stays a cancel even if the transport reports it as
  /// some other error; only real transport problems become failures.
  Exception _classify(Object error, MoodleDownloadCancel? cancel) {
    if ((cancel?.isCancelled ?? false) ||
        (error is DioException && error.type == DioExceptionType.cancel)) {
      return const MoodleDownloadCancelled();
    }
    if (error is DioException &&
        (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.receiveTimeout)) {
      return const MoodleFailure(MoodleFailureKind.timeout);
    }
    return const MoodleFailure(MoodleFailureKind.downloadFailed);
  }
}
