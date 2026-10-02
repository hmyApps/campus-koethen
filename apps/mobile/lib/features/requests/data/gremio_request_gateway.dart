// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../domain/application_files.dart';
import '../domain/attachment_store.dart';
import '../domain/gremio_origin.dart';
import '../domain/request_drafts.dart';
import '../domain/request_gateway.dart';
import '../domain/request_validation.dart';
import 'requests_api_config.dart';

/// Submits applications and feedback straight from the device.
///
/// Direct on purpose: an application carries the applicant's name and a copy of
/// their student card, and AGENTS.md §2 lists this among the integrations that
/// must not pass through a Campus Köthen backend. Nothing about the request or
/// its answer is proxied, cached server-side or logged.
///
/// **The status link in the answer is a secret.** It is put into the returned
/// [SubmissionAccepted] and nowhere else — never into a log line, never into a
/// failure reason, and only after it has been checked against the configured
/// origin: a link pointing somewhere else is not a case this app can track, it
/// is somebody else's host being handed a token.
class GremioRequestGateway implements RequestGateway {
  GremioRequestGateway({
    required Dio dio,
    required String baseUrl,
    required AttachmentStore attachments,
  }) : this._(
         dio,
         attachments,
         RequestsApiConfig.stripTrailingSlash(baseUrl.trim()),
         GremioOrigin.parse(baseUrl),
       );

  GremioRequestGateway._(
    this._dio,
    this._attachments,
    this._base,
    this._origin,
  );

  final Dio _dio;
  final AttachmentStore _attachments;
  final String _base;
  final GremioOrigin? _origin;

  @override
  Future<SubmissionResult> submitApplication(
    FinanceApplicationDraft draft, {
    SubmissionProgress? onProgress,
    SubmissionCancelToken? cancel,
  }) async {
    if (_origin == null) return const SubmissionNotConnected();

    final RequestValidation validation = RequestValidation.validate(draft);
    if (!validation.isValid) {
      // Sending a body that cannot succeed wastes the user's data allowance
      // and burns a rate-limit slot for an answer we already know.
      return SubmissionRejected(
        fieldErrors: <RequestField, String>{
          for (final RequestField field in validation.errors.keys) field: '',
        },
      );
    }

    final FormData form = FormData();
    form.fields
      ..add(MapEntry<String, String>('locationId', '${draft.locationId}'))
      ..add(MapEntry<String, String>('title', draft.title.trim()))
      ..add(MapEntry<String, String>('applicant', draft.applicant.trim()));

    int totalBytes = 0;
    int fileCount = 0;
    for (final ApplicationFileSlot slot in ApplicationFileSlot.values) {
      final RequestAttachment? file = draft.fileFor(slot);
      if (file == null) continue;
      fileCount++;
      final int? declaredSize = file.sizeBytes;
      if (fileCount > ApplicationFileLimits.maxFiles ||
          (declaredSize != null &&
              !ApplicationFileLimits.acceptsFile(declaredSize))) {
        return SubmissionRejected(
          fieldErrors: <RequestField, String>{RequestField.forSlot(slot): ''},
        );
      }

      final StoredAttachmentStream? source = switch (_attachments) {
        final StreamingAttachmentStore streaming => await streaming.openRead(
          file,
        ),
        _ => await _wholeFileSource(file),
      };
      if (source == null ||
          (declaredSize != null && source.length != declaredSize) ||
          !ApplicationFileLimits.acceptsFile(source.length)) {
        return SubmissionRejected(
          fieldErrors: <RequestField, String>{RequestField.forSlot(slot): ''},
        );
      }
      totalBytes += source.length;
      if (!ApplicationFileLimits.acceptsTotal(totalBytes)) {
        return const SubmissionTooLarge();
      }
      final String? contentType = slot.contentTypeFor(file.fileName);
      form.files.add(
        MapEntry<String, MultipartFile>(
          slot.field,
          MultipartFile.fromStream(
            source.open,
            source.length,
            filename: file.fileName,
            contentType: contentType == null
                ? null
                : MediaType.parse(contentType),
          ),
        ),
      );
    }

    return _send(
      path: RequestsApiConfig.applicationsPath,
      body: form,
      idempotencyKey: draft.idempotencyKey,
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  Future<StoredAttachmentStream?> _wholeFileSource(
    RequestAttachment attachment,
  ) async {
    final bytes = await _attachments.read(attachment);
    if (bytes == null) return null;
    return StoredAttachmentStream(
      length: bytes.length,
      open: () => Stream<List<int>>.value(bytes),
    );
  }

  @override
  Future<SubmissionResult> submitFeedback(
    FeedbackDraft draft, {
    SubmissionProgress? onProgress,
    SubmissionCancelToken? cancel,
  }) async {
    if (_origin == null) return const SubmissionNotConnected();

    final RequestValidation validation = RequestValidation.validate(draft);
    if (!validation.isValid) {
      return SubmissionRejected(
        fieldErrors: <RequestField, String>{
          for (final RequestField field in validation.errors.keys) field: '',
        },
      );
    }

    final String? name = draft.wireSubmitterName;
    return _send(
      path: RequestsApiConfig.feedbackPath,
      body: <String, dynamic>{
        'areaId': draft.areaId,
        // Left out entirely when blank. The committee records such feedback as
        // anonymous itself; sending that word would put it in the user's mouth
        // and, per the contract, is the same request for idempotency anyway.
        'submitterName': ?name,
        'feedback': draft.feedback.trim(),
      },
      idempotencyKey: draft.idempotencyKey,
      contentType: Headers.jsonContentType,
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  Future<SubmissionResult> _send({
    required String path,
    required Object body,
    required String idempotencyKey,
    String? contentType,
    SubmissionProgress? onProgress,
    SubmissionCancelToken? cancel,
  }) async {
    // Translated at the edge, so nothing above this layer knows about Dio.
    final CancelToken? token = cancel == null ? null : CancelToken();
    if (cancel != null && token != null) {
      cancel.bind(() => token.cancel('cancelled by the user'));
      // A token cancelled before the request went out must not still send.
      if (cancel.isCancelled) {
        return const SubmissionOutcomeUnknown('cancelled');
      }
    }
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '$_base$path',
        data: body,
        cancelToken: token,
        onSendProgress: onProgress == null
            ? null
            : (int sent, int total) => onProgress(sent, total),
        options: Options(
          // Enforced on the sensitive request itself as well as on the shared
          // Dio instance, so an injected/test client cannot weaken the rule.
          followRedirects: false,
          headers: <String, String>{
            'Idempotency-Key': idempotencyKey,
            'Accept': 'application/json',
          },
          contentType: contentType,
          sendTimeout: RequestsApiConfig.sendTimeout,
          receiveTimeout: RequestsApiConfig.receiveTimeout,
          // Every documented status below 500 is a result, not an exception.
          // A 5xx is left to throw: its outcome is genuinely unknown.
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );
      return _readResponse(response);
    } on DioException catch (error) {
      // A cancelled upload is an UNKNOWN outcome, never a clean failure: the
      // bytes may already have reached the endpoint, so the draft has to
      // freeze and a retry has to replay under the same key.
      if (CancelToken.isCancel(error)) {
        return const SubmissionOutcomeUnknown('cancelled');
      }
      return _readTransportError(error);
    }
  }

  SubmissionResult _readResponse(Response<dynamic> response) {
    final int status = response.statusCode ?? 0;
    final dynamic data = response.data;
    final Map<String, dynamic> json = data is Map<String, dynamic>
        ? data
        : const <String, dynamic>{};

    if (status == 200 || status == 201) return _readAccepted(response, json);

    final Object? error = json['error'];
    final String message = error is String ? error : '';

    return switch (status) {
      400 => _readRejected(message, json),
      404 => SubmissionTargetGone(message: message),
      409 => const SubmissionConflict(),
      413 => const SubmissionTooLarge(),
      415 => const SubmissionUnsupportedMedia(),
      429 => SubmissionRateLimited(
        retryAfter: _retryAfter(response.headers.value('Retry-After')),
      ),
      // Anything else below 500 the contract does not describe. Unknown, not
      // failed: we cannot tell whether the case was filed.
      _ => SubmissionOutcomeUnknown('http-$status'),
    };
  }

  SubmissionResult _readAccepted(
    Response<dynamic> response,
    Map<String, dynamic> json,
  ) {
    final Object? statusUrl = json['statusUrl'];
    final Object? receipt = json['receiptPdfUrl'];
    // Without the link there is no way back to this case. Calling that a
    // success would strand it.
    if (statusUrl is! String || !_origin!.allows(statusUrl)) {
      return const SubmissionFailed('accepted-without-usable-status-url');
    }
    if (receipt is! String || !_origin.allows(receipt)) {
      return const SubmissionFailed('accepted-without-usable-receipt-url');
    }
    final Object? number = json['number'];
    return SubmissionAccepted(
      statusUrl: statusUrl,
      receiptPdfUrl: receipt,
      number: number is String && number.trim().isNotEmpty ? number : null,
      wasReplay:
          response.statusCode == 200 ||
          response.headers.value('Idempotency-Replayed') == 'true',
    );
  }

  /// Maps the endpoint's field-level issues onto the real form fields.
  ///
  /// An issue naming something this build does not know is kept as general
  /// text rather than dropped: an unmapped message is still information, and
  /// silently losing it would leave the user with a form that looks fine and
  /// a submission that keeps failing.
  static SubmissionRejected _readRejected(
    String message,
    Map<String, dynamic> json,
  ) {
    final Map<RequestField, String> fields = <RequestField, String>{};
    final List<String> general = <String>[];

    final Object? issues = json['issues'];
    if (issues is List) {
      for (final Object? issue in issues) {
        if (issue is! Map<String, dynamic>) continue;
        final Object? field = issue['field'];
        final Object? text = issue['message'];
        if (text is! String || text.trim().isEmpty) continue;
        final RequestField? mapped = RequestField.fromWire(
          field is String ? field : null,
        );
        if (mapped == null) {
          general.add(text);
        } else {
          fields[mapped] = text;
        }
      }
    }

    return SubmissionRejected(
      message: message,
      fieldErrors: fields,
      generalIssues: general,
    );
  }

  static Duration? _retryAfter(String? header) {
    final int? seconds = int.tryParse(header?.trim() ?? '');
    return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
  }

  /// Every transport failure and every 5xx is an **unknown** outcome.
  ///
  /// The request may have been processed and only the answer lost. Reporting
  /// it as a plain failure would invite a fresh submission and a duplicate
  /// case; reporting it as unknown is what freezes the draft and keeps the
  /// key for an identical retry.
  static SubmissionResult _readTransportError(DioException error) {
    final int? status = error.response?.statusCode;
    if (status != null && status >= 500) {
      return SubmissionOutcomeUnknown('http-$status');
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => const SubmissionOutcomeUnknown(
        'transport',
      ),
      DioExceptionType.unknown when error.error is SocketException =>
        const SubmissionOutcomeUnknown('transport'),
      // The reason is a type name, never the body, a name or a URL.
      _ => SubmissionOutcomeUnknown('dio-${error.type.name}'),
    };
  }
}
