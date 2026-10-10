// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer
//
// The Moodle file downloader carries the token, so its host/size/cancel policy
// is security-critical. No real network, no real token.

import 'dart:async';
import 'dart:typed_data';

import 'package:campus_koethen/core/documents/app_document.dart';
import 'package:campus_koethen/features/moodle/data/moodle_file_downloader.dart';
import 'package:campus_koethen/features/moodle/data/moodle_http_client.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_downloader.dart';
import 'package:campus_koethen/features/moodle/domain/moodle_failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_bytes_adapter.dart';

const String _moodleFile =
    'https://moodle.hs-anhalt.de/webservice/pluginfile.php/1/mod_resource/content/1/uebung1.pdf';

MoodleFileDownloaderImpl downloaderWith(FakeBytesAdapter adapter) {
  final Dio dio = Dio();
  dio.httpClientAdapter = adapter;
  return MoodleFileDownloaderImpl(dio: dio);
}

Uint8List bytes(int n) => Uint8List.fromList(List<int>.filled(n, 65));

void main() {
  test('downloads a file, attaching the token in the POST body only', () async {
    final FakeBytesAdapter adapter = FakeBytesAdapter(
      (RequestOptions o) =>
          FakeBytes.single(bytes(64), contentType: 'application/pdf'),
    );
    final AppDocument doc = await downloaderWith(adapter).download(
      token: 'tok-secret',
      fileUrl: _moodleFile,
      fileName: 'uebung1.pdf',
      declaredMimeType: 'application/pdf',
    );

    expect(doc.filename, 'uebung1.pdf');
    expect(doc.isPdf, isTrue);
    expect(doc.bytes, hasLength(64));

    final RequestOptions req = adapter.requests.single;
    expect(req.uri.host, 'moodle.hs-anhalt.de');
    // Token must never appear in the URL.
    expect(req.uri.toString(), isNot(contains('tok-secret')));
    expect(req.uri.query, isEmpty);
    final Map<String, dynamic> data = req.data as Map<String, dynamic>;
    expect(data['token'], 'tok-secret');
  });

  test('refuses a non-moodle host and never sends the token', () async {
    final FakeBytesAdapter adapter = FakeBytesAdapter(
      (RequestOptions o) => FakeBytes.single(bytes(8)),
    );
    await expectLater(
      downloaderWith(adapter).download(
        token: 'tok',
        fileUrl: 'https://evil.example.com/file.pdf',
        fileName: 'file.pdf',
      ),
      throwsA(const MoodleFailure(MoodleFailureKind.tlsOrHostRejected)),
    );
    expect(adapter.requests, isEmpty);
  });

  test('refuses a non-https url', () async {
    final FakeBytesAdapter adapter = FakeBytesAdapter(
      (RequestOptions o) => FakeBytes.single(bytes(8)),
    );
    await expectLater(
      downloaderWith(adapter).download(
        token: 'tok',
        fileUrl: 'http://moodle.hs-anhalt.de/file.pdf',
        fileName: 'file.pdf',
      ),
      throwsA(const MoodleFailure(MoodleFailureKind.tlsOrHostRejected)),
    );
    expect(adapter.requests, isEmpty);
  });

  test('refuses a malformed URL without throwing a raw parser error', () async {
    final FakeBytesAdapter adapter = FakeBytesAdapter(
      (RequestOptions o) => FakeBytes.single(bytes(8)),
    );
    await expectLater(
      downloaderWith(adapter).download(
        token: 'tok',
        fileUrl: 'https://[broken/file.pdf',
        fileName: 'file.pdf',
      ),
      throwsA(const MoodleFailure(MoodleFailureKind.tlsOrHostRejected)),
    );
    expect(adapter.requests, isEmpty);
  });

  test(
    'rejects a declared size over the in-memory cap before downloading',
    () async {
      final FakeBytesAdapter adapter = FakeBytesAdapter(
        (RequestOptions o) => FakeBytes.single(bytes(8)),
      );
      await expectLater(
        downloaderWith(adapter).download(
          token: 'tok',
          fileUrl: _moodleFile,
          fileName: 'huge.bin',
          declaredSize: kMaxInMemoryPreviewBytes + 1,
        ),
        throwsA(const MoodleFailure(MoodleFailureKind.fileTooLarge)),
      );
      expect(adapter.requests, isEmpty);
    },
  );

  test('aborts when the stream exceeds the cap, keeping no bytes', () async {
    // Server lies: content-length small, but streams more than the cap.
    final FakeBytesAdapter adapter = FakeBytesAdapter(
      (RequestOptions o) => FakeBytes(<Uint8List>[
        bytes(kMaxInMemoryPreviewBytes ~/ 2),
        bytes(kMaxInMemoryPreviewBytes),
      ], contentLength: 10),
    );
    await expectLater(
      downloaderWith(
        adapter,
      ).download(token: 'tok', fileUrl: _moodleFile, fileName: 'liar.bin'),
      throwsA(const MoodleFailure(MoodleFailureKind.fileTooLarge)),
    );
  });

  test('a redirect is refused and the token is not replayed', () async {
    final FakeBytesAdapter adapter = FakeBytesAdapter(
      (RequestOptions o) => FakeBytes.redirect('https://evil.example.com/x'),
    );
    await expectLater(
      downloaderWith(
        adapter,
      ).download(token: 'tok', fileUrl: _moodleFile, fileName: 'r.bin'),
      throwsA(const MoodleFailure(MoodleFailureKind.tlsOrHostRejected)),
    );
    expect(adapter.requests, hasLength(1));
  });

  test(
    'cancellation discards the download as a cancel, not a failure',
    () async {
      final MoodleDownloadCancel cancel = MoodleDownloadCancel()..cancel();
      final FakeBytesAdapter adapter = FakeBytesAdapter(
        (RequestOptions o) => FakeBytes.single(bytes(64)),
      );
      await expectLater(
        downloaderWith(adapter).download(
          token: 'tok',
          fileUrl: _moodleFile,
          fileName: 'c.bin',
          cancel: cancel,
        ),
        throwsA(isA<MoodleDownloadCancelled>()),
      );
      expect(adapter.requests, isEmpty);
    },
  );

  test('every request carries the Moodle transport timeouts', () async {
    // Pinned per request, so they hold even for an injected Dio without them.
    final FakeBytesAdapter adapter = FakeBytesAdapter(
      (RequestOptions o) => FakeBytes.single(bytes(8)),
    );
    await downloaderWith(
      adapter,
    ).download(token: 'tok', fileUrl: _moodleFile, fileName: 't.bin');

    final RequestOptions req = adapter.requests.single;
    expect(req.connectTimeout, kMoodleConnectTimeout);
    expect(req.sendTimeout, kMoodleSendTimeout);
    expect(req.receiveTimeout, kMoodleReceiveTimeout);
    expect(req.followRedirects, isFalse);
  });

  test('cancel aborts a request that is still waiting for headers', () async {
    final Completer<void> requested = Completer<void>();
    final _ScriptedAdapter adapter = _ScriptedAdapter((RequestOptions o) {
      requested.complete();
      // The server never answers.
      return Completer<ResponseBody>().future;
    });
    final MoodleDownloadCancel cancel = MoodleDownloadCancel();

    final Future<AppDocument> download = _downloader(adapter).download(
      token: 'tok',
      fileUrl: _moodleFile,
      fileName: 'h.bin',
      cancel: cancel,
    );
    await requested.future;
    cancel.cancel();

    await expectLater(
      download.timeout(const Duration(seconds: 5)),
      throwsA(isA<MoodleDownloadCancelled>()),
    );
  });

  test('cancel aborts a body that has stopped arriving', () async {
    final StreamController<Uint8List> body = StreamController<Uint8List>();
    addTearDown(() => unawaited(body.close()));
    final _ScriptedAdapter adapter = _ScriptedAdapter((RequestOptions o) {
      // One chunk, then silence: the connection hangs mid-body.
      body.add(bytes(16));
      return ResponseBody(
        body.stream,
        200,
        headers: <String, List<String>>{
          Headers.contentLengthHeader: <String>['64'],
        },
      );
    });
    final MoodleDownloadCancel cancel = MoodleDownloadCancel();
    final Completer<void> started = Completer<void>();

    final Future<AppDocument> download = _downloader(adapter).download(
      token: 'tok',
      fileUrl: _moodleFile,
      fileName: 's.bin',
      cancel: cancel,
      onProgress: (_) {
        if (!started.isCompleted) started.complete();
      },
    );
    await started.future;
    cancel.cancel();

    await expectLater(
      download.timeout(const Duration(seconds: 5)),
      throwsA(isA<MoodleDownloadCancelled>()),
    );
  });

  test('a body that stops arriving times out as a timeout', () async {
    final StreamController<Uint8List> body = StreamController<Uint8List>();
    addTearDown(() => unawaited(body.close()));
    final _ScriptedAdapter adapter = _ScriptedAdapter((RequestOptions o) {
      body.add(bytes(16));
      return ResponseBody(body.stream, 200);
    });

    await expectLater(
      _downloader(adapter, receiveTimeout: const Duration(milliseconds: 50))
          .download(token: 'tok', fileUrl: _moodleFile, fileName: 'x.bin')
          .timeout(const Duration(seconds: 5)),
      throwsA(const MoodleFailure(MoodleFailureKind.timeout)),
    );
  });
}

MoodleFileDownloaderImpl _downloader(
  HttpClientAdapter adapter, {
  Duration receiveTimeout = kMoodleReceiveTimeout,
}) {
  final Dio dio = Dio()..httpClientAdapter = adapter;
  return MoodleFileDownloaderImpl(dio: dio, receiveTimeout: receiveTimeout);
}

/// An adapter whose answer is fully scripted, including never answering.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responder);

  final FutureOr<ResponseBody> Function(RequestOptions options) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => responder(options);

  @override
  void close({bool force = false}) {}
}
