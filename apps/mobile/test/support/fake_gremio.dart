// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Test doubles for the committee system.
///
/// Everything here uses **fake hosts and invented tokens**. No test in this
/// suite ever reaches the real API, and no real status link appears in a
/// fixture — a status link is a bearer credential, and a test file is the last
/// place one should be able to leak from.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_koethen/features/requests/domain/attachment_store.dart';
import 'package:campus_koethen/features/requests/domain/request_drafts.dart';
import 'package:campus_koethen/features/requests/domain/request_gateway.dart';
import 'package:campus_koethen/features/requests/domain/request_store.dart';
import 'package:campus_koethen/features/requests/domain/status_gateway.dart';
import 'package:campus_koethen/features/requests/domain/submitted_case.dart';
import 'package:dio/dio.dart';

/// The fake instance every test talks to.
const String kFakeBaseUrl = 'https://gremio.example';
const String kFakeStatusUrl = 'https://gremio.example/status/testtoken';
const String kFakeReceiptUrl = 'https://gremio.example/status/testtoken/pdf';
const String kFakeFeedbackStatusUrl =
    'https://gremio.example/feedback/status/testtoken';
const String kFakeFeedbackReceiptUrl =
    'https://gremio.example/feedback/status/testtoken/pdf';

/// A scripted adapter that can answer with headers and with raw bytes.
class FakeGremioAdapter implements HttpClientAdapter {
  FakeGremioAdapter(this.handler);

  final FutureOr<FakeGremioResponse> Function(RequestOptions options) handler;

  final List<RequestOptions> requests = <RequestOptions>[];

  /// The body dio actually serialised, per request.
  final List<String> bodies = <String>[];

  RequestOptions get lastRequest => requests.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final List<int> collected = <int>[];
      await for (final Uint8List chunk in requestStream) {
        collected.addAll(chunk);
      }
      bodies.add(utf8.decode(collected, allowMalformed: true));
    } else {
      bodies.add(options.data is String ? options.data as String : '');
    }

    final FakeGremioResponse response = await handler(options);
    if (response.throwsTransport) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'test-transport',
      );
    }

    final List<int> bytes =
        response.bytes ?? utf8.encode(jsonEncode(response.body));
    return ResponseBody.fromBytes(
      bytes,
      response.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[
          response.contentType ?? 'application/json; charset=utf-8',
        ],
        for (final MapEntry<String, String> entry in response.headers.entries)
          entry.key: <String>[entry.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class FakeGremioResponse {
  const FakeGremioResponse(
    this.body, {
    this.statusCode = 200,
    this.headers = const <String, String>{},
    this.bytes,
    this.contentType,
    this.throwsTransport = false,
  });

  /// A transport failure — the case the idempotency key exists for.
  const FakeGremioResponse.transportError()
    : body = null,
      statusCode = 0,
      headers = const <String, String>{},
      bytes = null,
      contentType = null,
      throwsTransport = true;

  final Object? body;
  final int statusCode;
  final Map<String, String> headers;
  final List<int>? bytes;
  final String? contentType;
  final bool throwsTransport;
}

Dio fakeGremioDio(FakeGremioAdapter adapter) {
  final Dio dio = Dio(
    BaseOptions(validateStatus: (int? s) => s != null && s < 500),
  );
  dio.httpClientAdapter = adapter;
  return dio;
}

/// An [AttachmentStore] that keeps bytes in a map.
class FakeAttachmentStore implements AttachmentStore, StreamingAttachmentStore {
  bool wipeSucceeds = true;
  int wipes = 0;

  @override
  Future<bool> wipeEverything() async {
    wipes++;
    if (wipeSucceeds) entries.clear();
    return wipeSucceeds;
  }

  final Map<String, Uint8List> entries = <String, Uint8List>{};
  int _next = 0;
  int wholeFileReads = 0;

  @override
  Future<RequestAttachment?> put(String fileName, Uint8List bytes) async {
    final String id = 'fake-${_next++}';
    entries[id] = bytes;
    return RequestAttachment(
      fileName: fileName,
      path: id,
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<Uint8List?> read(RequestAttachment attachment) async {
    wholeFileReads++;
    return entries[attachment.path];
  }

  @override
  Future<RequestAttachment?> putStream(
    String fileName,
    int expectedLength,
    Stream<List<int>> bytes,
  ) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in bytes) {
      builder.add(chunk);
    }
    final Uint8List materialized = builder.takeBytes();
    if (materialized.length != expectedLength) {
      throw const AttachmentLimitExceeded();
    }
    return put(fileName, materialized);
  }

  @override
  Future<StoredAttachmentStream?> openRead(RequestAttachment attachment) async {
    final Uint8List? bytes = entries[attachment.path];
    if (bytes == null) return null;
    return StoredAttachmentStream(
      length: bytes.length,
      open: () => Stream<List<int>>.value(bytes),
    );
  }

  @override
  Future<void> delete(RequestAttachment attachment) async =>
      entries.remove(attachment.path);

  @override
  Future<void> deleteAll(Iterable<RequestAttachment> attachments) async {
    for (final RequestAttachment a in attachments) {
      await delete(a);
    }
  }
}

/// A store whose writes can be made to fail, to exercise the path where a case
/// is accepted but cannot be recorded.
class FlakyRequestStore implements RequestStore {
  bool wipeSucceeds = true;
  int wipes = 0;

  @override
  Future<bool> wipeEverything() async {
    wipes++;
    if (wipeSucceeds) {
      drafts = const <RequestDraft>[];
      cases = const <SubmittedCase>[];
    }
    return wipeSucceeds;
  }

  FlakyRequestStore({this.failCaseWrites = false});

  bool failCaseWrites;
  bool failDraftWrites = false;

  /// Reads that throw, like a locked keystore or an undecodable list.
  bool failCaseReads = false;
  bool failDraftReads = false;

  /// Real asynchronous gaps, so concurrent callers genuinely interleave.
  Duration readDelay = Duration.zero;
  Duration writeDelay = Duration.zero;

  int caseWrites = 0;
  int draftWrites = 0;

  List<RequestDraft> drafts = <RequestDraft>[];
  List<SubmittedCase> cases = <SubmittedCase>[];

  @override
  Future<List<RequestDraft>> readDrafts() async {
    await Future<void>.delayed(readDelay);
    if (failDraftReads) throw const RequestStoreUnavailable();
    return List<RequestDraft>.of(drafts);
  }

  @override
  Future<void> writeDrafts(List<RequestDraft> next) async {
    draftWrites++;
    await Future<void>.delayed(writeDelay);
    if (failDraftWrites) throw const RequestStoreUnavailable();
    drafts = List<RequestDraft>.of(next);
  }

  @override
  Future<List<SubmittedCase>> readCases() async {
    await Future<void>.delayed(readDelay);
    if (failCaseReads) throw const RequestStoreUnavailable();
    return List<SubmittedCase>.of(cases);
  }

  @override
  Future<void> writeCases(List<SubmittedCase> next) async {
    caseWrites++;
    await Future<void>.delayed(writeDelay);
    if (failCaseWrites) throw Exception('storage refused');
    cases = List<SubmittedCase>.of(next);
  }
}

/// A gateway that answers with whatever the test set.
class ScriptedRequestGateway implements RequestGateway {
  ScriptedRequestGateway(this.result);

  SubmissionResult result;

  /// When set, every answer waits for it — an upload still in flight.
  Completer<void>? gate;

  /// When set, the gateway throws this instead of answering.
  Object? failure;

  final List<String> keysUsed = <String>[];
  final List<String> fingerprints = <String>[];

  Future<SubmissionResult> _answer(RequestDraft draft) async {
    keysUsed.add(draft.idempotencyKey);
    fingerprints.add(draft.payloadFingerprint);
    final Completer<void>? waiting = gate;
    if (waiting != null) await waiting.future;
    final Object? thrown = failure;
    if (thrown != null) throw thrown;
    return result;
  }

  @override
  Future<SubmissionResult> submitApplication(
    FinanceApplicationDraft draft, {
    SubmissionProgress? onProgress,
    SubmissionCancelToken? cancel,
  }) {
    // Reported so a test can assert the form actually shows progress.
    onProgress?.call(1, 1);
    return _answer(draft);
  }

  @override
  Future<SubmissionResult> submitFeedback(
    FeedbackDraft draft, {
    SubmissionProgress? onProgress,
    SubmissionCancelToken? cancel,
  }) {
    onProgress?.call(1, 1);
    return _answer(draft);
  }
}

/// A status gateway that counts calls, for single-flight tests.
class ScriptedStatusGateway implements StatusGateway {
  ScriptedStatusGateway(this.result, {this.delay = Duration.zero});

  StatusResult result;
  Duration delay;
  int calls = 0;
  final List<String> urls = <String>[];

  @override
  Future<StatusResult> fetch(String statusUrl) async {
    calls++;
    urls.add(statusUrl);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return result;
  }
}

/// A successful application status body, as the API documents it.
Map<String, dynamic> applicationStatusBody({
  String? name = 'In Bearbeitung',
  String? publicNote,
  bool archived = false,
  String? resubmittedAt,
  List<Map<String, dynamic>> documents = const <Map<String, dynamic>>[],
  bool canUpload = false,
  String? submitMode,
  String? number = 'A_0042_2026',
}) => <String, dynamic>{
  'type': 'application',
  'statusUrl': kFakeStatusUrl,
  'receiptPdfUrl': kFakeReceiptUrl,
  'number': number,
  'submittedAt': '2026-08-04T10:15:00.000Z',
  'updatedAt': '2026-08-05T08:30:00.000Z',
  'application': <String, dynamic>{
    'title': 'Grillabend am FB5',
    'applicant': 'Testperson',
  },
  'status': <String, dynamic>{
    'name': name,
    'resubmittedAt': resubmittedAt,
    'archived': archived,
  },
  'publicNote': publicNote,
  'documents': documents,
  'availableActions': <String, dynamic>{
    'canUploadDocuments': canUpload,
    'submitMode': submitMode,
  },
};

Map<String, dynamic> feedbackStatusBody({
  String? name = 'Eingegangen',
  String text = 'Die Öffnungszeiten sollten verlängert werden.',
  String submitterName = 'Anonym',
  String? publicNote,
}) => <String, dynamic>{
  'type': 'feedback',
  'statusUrl': kFakeFeedbackStatusUrl,
  'receiptPdfUrl': kFakeFeedbackReceiptUrl,
  'number': 'F_0042_2026',
  'submittedAt': '2026-08-04T10:15:00.000Z',
  'updatedAt': '2026-08-05T08:30:00.000Z',
  'feedback': <String, dynamic>{
    'area': 'Bibliothek',
    'submitterName': submitterName,
    'text': text,
  },
  'status': <String, dynamic>{'name': name},
  'publicNote': publicNote,
  'documents': <Map<String, dynamic>>[],
  'availableActions': <String, dynamic>{
    'canUploadDocuments': false,
    'submitMode': null,
  },
};
