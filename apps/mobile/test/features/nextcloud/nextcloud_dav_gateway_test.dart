// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campus_koethen/features/nextcloud/data/nextcloud_dav_gateway.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_account.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_entry.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_failure.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_gateway.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const NextcloudCredential _credential = NextcloudCredential(
  server: 'https://cloud.hs-anhalt.de',
  loginName: 'student',
  userId: 'student-id',
  appPassword: 'app-password',
);

void main() {
  test('login flow pins both returned URLs to the configured origin', () async {
    final _Adapter adapter = _Adapter((RequestOptions request) {
      return _Response.json(<String, Object?>{
        'poll': <String, Object?>{
          'token': 'poll-secret',
          'endpoint': 'https://attacker.test/login/v2/poll',
        },
        'login': 'https://cloud.hs-anhalt.de/login/v2/flow/abc',
      });
    });

    await expectLater(
      _gateway(adapter).startLogin(),
      throwsA(const NextcloudFailure(NextcloudFailureKind.invalidResponse)),
    );
  });

  test(
    'polls login, resolves DAV uid through OCS and never leaks auth early',
    () async {
      var polls = 0;
      final _Adapter adapter = _Adapter((RequestOptions request) {
        if (request.uri.path == '/index.php/login/v2') {
          expect(request.headers['authorization'], isNull);
          return _Response.json(<String, Object?>{
            'poll': <String, Object?>{
              'token': 'poll-secret',
              'endpoint': 'https://cloud.hs-anhalt.de/login/v2/poll',
            },
            'login': 'https://cloud.hs-anhalt.de/login/v2/flow/abc',
          });
        }
        if (request.uri.path == '/login/v2/poll') {
          expect(request.headers['authorization'], isNull);
          polls++;
          if (polls == 1) return const _Response('', 404);
          return _Response.json(<String, Object?>{
            'server': 'https://cloud.hs-anhalt.de',
            'loginName': 'student-login',
            'appPassword': 'issued-secret',
          });
        }
        if (request.uri.path == '/ocs/v2.php/cloud/user') {
          expect(request.headers['authorization'], startsWith('Basic '));
          expect(request.headers['OCS-APIRequest'], 'true');
          return _Response.json(<String, Object?>{
            'ocs': <String, Object?>{
              'meta': <String, Object?>{'statuscode': 100},
              'data': <String, Object?>{'id': 'actual-dav-uid'},
            },
          });
        }
        throw StateError('Unexpected ${request.method} ${request.path}');
      });
      final NextcloudDavGateway gateway = _gateway(adapter);

      final start = await gateway.startLogin();
      final NextcloudCredential credential = await gateway.completeLogin(
        start,
        canceled: Completer<void>().future,
      );

      expect(credential.loginName, 'student-login');
      expect(credential.userId, 'actual-dav-uid');
      expect(credential.appPassword, 'issued-secret');
      expect(polls, 2);
    },
  );

  test('revokes an issued app password when uid resolution fails', () async {
    var revocations = 0;
    final _Adapter adapter = _Adapter((RequestOptions request) {
      if (request.uri.path == '/login/v2/poll') {
        return _Response.json(<String, Object?>{
          'server': 'https://cloud.hs-anhalt.de',
          'loginName': 'student-login',
          'appPassword': 'issued-secret',
        });
      }
      if (request.uri.path == '/ocs/v2.php/cloud/user') {
        return const _Response('', 503);
      }
      if (request.uri.path == '/ocs/v2.php/core/apppassword') {
        revocations++;
        expect(request.method, 'DELETE');
        expect(request.headers['authorization'], startsWith('Basic '));
        return _Response.json(<String, Object?>{
          'ocs': <String, Object?>{
            'meta': <String, Object?>{'statuscode': 100},
            'data': <String, Object?>{},
          },
        });
      }
      throw StateError('Unexpected ${request.method} ${request.path}');
    });
    final NextcloudDavGateway gateway = _gateway(adapter);

    await expectLater(
      gateway.completeLogin(
        NextcloudLoginStart(
          loginUri: Uri.parse('https://cloud.hs-anhalt.de/login/v2/flow/id'),
          pollUri: Uri.parse('https://cloud.hs-anhalt.de/login/v2/poll'),
          pollToken: 'poll-secret',
        ),
        canceled: Completer<void>().future,
      ),
      throwsA(const NextcloudFailure(NextcloudFailureKind.serviceUnavailable)),
    );
    expect(revocations, 1);
  });

  test('revokes an issued app password when the server field drifts', () async {
    var revocations = 0;
    final _Adapter adapter = _Adapter((RequestOptions request) {
      if (request.uri.path == '/login/v2/poll') {
        return _Response.json(<String, Object?>{
          'server': 'https://unexpected.example',
          'loginName': 'student-login',
          'appPassword': 'issued-secret',
        });
      }
      if (request.uri.path == '/ocs/v2.php/core/apppassword') {
        revocations++;
        return _Response.json(<String, Object?>{
          'ocs': <String, Object?>{
            'meta': <String, Object?>{'statuscode': 100},
            'data': <String, Object?>{},
          },
        });
      }
      throw StateError('Unexpected ${request.method} ${request.path}');
    });

    await expectLater(
      _gateway(adapter).completeLogin(
        NextcloudLoginStart(
          loginUri: Uri.parse('https://cloud.hs-anhalt.de/login/v2/flow/id'),
          pollUri: Uri.parse('https://cloud.hs-anhalt.de/login/v2/poll'),
          pollToken: 'poll-secret',
        ),
        canceled: Completer<void>().future,
      ),
      throwsA(const NextcloudFailure(NextcloudFailureKind.invalidResponse)),
    );
    expect(revocations, 1);
  });

  test('lists one folder and file through a Depth 1 PROPFIND', () async {
    final _Adapter adapter = _Adapter((RequestOptions request) {
      expect(request.method, 'PROPFIND');
      expect(request.headers['Depth'], '1');
      expect(request.headers['authorization'], startsWith('Basic '));
      return const _Response(_multistatus, 207, <String, List<String>>{
        'content-type': <String>['application/xml'],
      });
    });

    final entries = await _gateway(
      adapter,
    ).listFolder(_credential, '/Documents');

    expect(entries, hasLength(2));
    expect(entries.first.isDirectory, isTrue);
    expect(entries.first.path, '/Documents/Notes');
    expect(entries.last.name, 'Übung 1.pdf');
    expect(entries.last.sizeBytes, 42);
    expect(entries.last.modifiedAt, DateTime.utc(2026, 10, 4, 10));
  });

  test('does not consume properties from a failed DAV propstat', () async {
    final String body = _multistatus.replaceFirst(
      '<d:status>HTTP/1.1 200 OK</d:status></d:propstat>\n  </d:response>\n</d:multistatus>',
      '<d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>\n  </d:response>\n</d:multistatus>',
    );
    final _Adapter adapter = _Adapter(
      (_) => _Response(body, 207, const <String, List<String>>{
        'content-type': <String>['application/xml'],
      }),
    );

    await expectLater(
      _gateway(adapter).listFolder(_credential, '/Documents'),
      throwsA(const NextcloudFailure(NextcloudFailureKind.invalidResponse)),
    );
  });

  test('rejects malformed numeric DAV metadata instead of hiding it', () async {
    final String body = _multistatus.replaceFirst(
      '<d:getcontentlength>42</d:getcontentlength>',
      '<d:getcontentlength>not-a-number</d:getcontentlength>',
    );
    final _Adapter adapter = _Adapter(
      (_) => _Response(body, 207, const <String, List<String>>{
        'content-type': <String>['application/xml'],
      }),
    );

    await expectLater(
      _gateway(adapter).listFolder(_credential, '/Documents'),
      throwsA(const NextcloudFailure(NextcloudFailureKind.invalidResponse)),
    );
  });

  test('rejects malformed DAV timestamps instead of hiding them', () async {
    final String body = _multistatus.replaceFirst(
      'Sun, 04 Oct 2026 10:00:00 GMT',
      'definitely-not-a-date',
    );
    final _Adapter adapter = _Adapter(
      (_) => _Response(body, 207, const <String, List<String>>{
        'content-type': <String>['application/xml'],
      }),
    );

    await expectLater(
      _gateway(adapter).listFolder(_credential, '/Documents'),
      throwsA(const NextcloudFailure(NextcloudFailureKind.invalidResponse)),
    );
  });

  test('rejects a DAV response that escapes the user root', () async {
    final String body = _multistatus.replaceFirst(
      '/remote.php/dav/files/student-id/Documents/Notes/',
      '/remote.php/dav/files/another-user/private/',
    );
    final _Adapter adapter = _Adapter(
      (_) => _Response(body, 207, const <String, List<String>>{
        'content-type': <String>['application/xml'],
      }),
    );

    await expectLater(
      _gateway(adapter).listFolder(_credential, '/Documents'),
      throwsA(const NextcloudFailure(NextcloudFailureKind.invalidResponse)),
    );
  });

  test('rejects a multistatus body with a non-XML media type', () async {
    final _Adapter adapter = _Adapter(
      (_) => const _Response(_multistatus, 207, <String, List<String>>{
        'content-type': <String>['text/html'],
      }),
    );

    await expectLater(
      _gateway(adapter).listFolder(_credential, '/Documents'),
      throwsA(const NextcloudFailure(NextcloudFailureKind.invalidResponse)),
    );
  });

  test('rejects XML declarations that can expand custom entities', () async {
    final String body = _multistatus.replaceFirst(
      '<d:multistatus',
      '<!DOCTYPE d:multistatus [<!ENTITY x "content">]><d:multistatus',
    );
    final _Adapter adapter = _Adapter(
      (_) => _Response(body, 207, const <String, List<String>>{
        'content-type': <String>['application/xml'],
      }),
    );

    await expectLater(
      _gateway(adapter).listFolder(_credential, '/Documents'),
      throwsA(const NextcloudFailure(NextcloudFailureKind.invalidResponse)),
    );
  });

  test(
    'enforces the Login Flow lifetime independently of poll count',
    () async {
      var requests = 0;
      final _Adapter adapter = _Adapter((_) {
        requests++;
        return const _Response('', 404);
      });
      final Dio dio = Dio(
        BaseOptions(validateStatus: (_) => true, followRedirects: false),
      )..httpClientAdapter = adapter;
      final NextcloudDavGateway gateway = NextcloudDavGateway(
        dio: dio,
        profile: const NextcloudProfile(),
        pollInterval: Duration.zero,
        loginTimeout: Duration.zero,
      );

      await expectLater(
        gateway.completeLogin(
          NextcloudLoginStart(
            loginUri: Uri.parse('https://cloud.hs-anhalt.de/login/v2/flow/id'),
            pollUri: Uri.parse('https://cloud.hs-anhalt.de/login/v2/poll'),
            pollToken: 'poll-secret',
          ),
          canceled: Completer<void>().future,
        ),
        throwsA(const NextcloudFailure(NextcloudFailureKind.loginTimedOut)),
      );
      expect(requests, 0);
    },
  );

  test(
    'classifies TLS handshake failures separately from offline errors',
    () async {
      final _Adapter adapter = _Adapter((RequestOptions request) {
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
          error: const HandshakeException('certificate rejected'),
        );
      });

      await expectLater(
        _gateway(adapter).startLogin(),
        throwsA(const NextcloudFailure(NextcloudFailureKind.tlsOrHostRejected)),
      );
    },
  );

  test('rejects a declared download above the in-memory limit', () async {
    final _Adapter adapter = _Adapter(
      (_) => const _Response('ignored', 200, <String, List<String>>{
        'content-length': <String>['26214401'],
        'content-type': <String>['application/pdf'],
      }),
    );

    await expectLater(
      _gateway(adapter).downloadFile(
        _credential,
        const NextcloudEntry(
          path: '/large.pdf',
          name: 'large.pdf',
          isDirectory: false,
        ),
      ),
      throwsA(const NextcloudFailure(NextcloudFailureKind.fileTooLarge)),
    );
  });

  test('rejects a malformed declared download length', () async {
    final _Adapter adapter = _Adapter(
      (_) => const _Response('ignored', 200, <String, List<String>>{
        'content-length': <String>['not-a-number'],
        'content-type': <String>['application/pdf'],
      }),
    );

    await expectLater(
      _gateway(adapter).downloadFile(
        _credential,
        const NextcloudEntry(
          path: '/document.pdf',
          name: 'document.pdf',
          isDirectory: false,
        ),
      ),
      throwsA(const NextcloudFailure(NextcloudFailureKind.invalidResponse)),
    );
  });

  test('uploads a stream to the selected folder without overwriting', () async {
    late RequestOptions captured;
    final _Adapter adapter = _Adapter((RequestOptions request) {
      captured = request;
      return const _Response('', 201);
    });

    await _gateway(adapter).uploadFile(
      _credential,
      directoryPath: '/Documents',
      file: NextcloudUploadFile(
        filename: 'notes.txt',
        mediaType: 'text/plain',
        length: 5,
        openRead: () =>
            Stream<Uint8List>.value(Uint8List.fromList(utf8.encode('hello'))),
      ),
    );

    expect(captured.method, 'PUT');
    expect(
      captured.uri,
      Uri.parse(
        'https://cloud.hs-anhalt.de/remote.php/dav/files/student-id/Documents/notes.txt',
      ),
    );
    expect(captured.headers['If-None-Match'], '*');
    expect(captured.headers[Headers.contentLengthHeader], 5);
    expect(adapter.requestBytes, utf8.encode('hello'));
  });

  test(
    'classifies an existing upload destination without overwriting',
    () async {
      final _Adapter adapter = _Adapter((_) => const _Response('', 412));

      await expectLater(
        _gateway(adapter).uploadFile(
          _credential,
          directoryPath: '/',
          file: NextcloudUploadFile(
            filename: 'existing.txt',
            mediaType: 'text/plain',
            length: 0,
            openRead: () => const Stream<Uint8List>.empty(),
          ),
        ),
        throwsA(const NextcloudFailure(NextcloudFailureKind.alreadyExists)),
      );
    },
  );

  test('rejects an upload filename containing a path separator', () async {
    var requests = 0;
    final _Adapter adapter = _Adapter((_) {
      requests++;
      return const _Response('', 201);
    });

    await expectLater(
      _gateway(adapter).uploadFile(
        _credential,
        directoryPath: '/',
        file: NextcloudUploadFile(
          filename: '../private.txt',
          mediaType: 'text/plain',
          length: 0,
          openRead: () => const Stream<Uint8List>.empty(),
        ),
      ),
      throwsA(const NextcloudFailure(NextcloudFailureKind.invalidFileName)),
    );
    expect(requests, 0);
  });

  test('deletes exactly the selected DAV entry', () async {
    late RequestOptions captured;
    final _Adapter adapter = _Adapter((RequestOptions request) {
      captured = request;
      return const _Response('', 204);
    });

    await _gateway(adapter).deleteEntry(
      _credential,
      const NextcloudEntry(
        path: '/Documents/old.txt',
        name: 'old.txt',
        isDirectory: false,
      ),
    );

    expect(captured.method, 'DELETE');
    expect(
      captured.uri,
      Uri.parse(
        'https://cloud.hs-anhalt.de/remote.php/dav/files/student-id/Documents/old.txt',
      ),
    );
  });

  test(
    'creates a read-only public share and accepts only its pinned URL',
    () async {
      late RequestOptions captured;
      final _Adapter adapter = _Adapter((RequestOptions request) {
        captured = request;
        return _Response.json(<String, Object?>{
          'ocs': <String, Object?>{
            'meta': <String, Object?>{'statuscode': 100},
            'data': <String, Object?>{
              'url': 'https://cloud.hs-anhalt.de/s/safe-token',
            },
          },
        });
      });

      final Uri link = await _gateway(adapter).createPublicShare(
        _credential,
        const NextcloudEntry(
          path: '/Documents/notes.txt',
          name: 'notes.txt',
          isDirectory: false,
        ),
      );

      expect(link, Uri.parse('https://cloud.hs-anhalt.de/s/safe-token'));
      expect(captured.method, 'POST');
      expect(captured.uri.path, '/ocs/v2.php/apps/files_sharing/api/v1/shares');
      expect(captured.uri.queryParameters['format'], 'json');
      expect(captured.data, <String, String>{
        'path': '/Documents/notes.txt',
        'shareType': '3',
        'permissions': '1',
      });
    },
  );

  test(
    'rejects a public share URL outside the pinned Nextcloud origin',
    () async {
      final _Adapter adapter = _Adapter(
        (_) => _Response.json(<String, Object?>{
          'ocs': <String, Object?>{
            'meta': <String, Object?>{'statuscode': 100},
            'data': <String, Object?>{'url': 'https://attacker.test/s/token'},
          },
        }),
      );

      await expectLater(
        _gateway(adapter).createPublicShare(
          _credential,
          const NextcloudEntry(
            path: '/notes.txt',
            name: 'notes.txt',
            isDirectory: false,
          ),
        ),
        throwsA(const NextcloudFailure(NextcloudFailureKind.invalidResponse)),
      );
    },
  );
}

NextcloudDavGateway _gateway(_Adapter adapter) {
  final Dio dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  )..httpClientAdapter = adapter;
  return NextcloudDavGateway(
    dio: dio,
    profile: const NextcloudProfile(),
    pollInterval: Duration.zero,
    maxPollAttempts: 3,
  );
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final FutureOr<_Response> Function(RequestOptions request) handler;
  List<int> requestBytes = const <int>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final BytesBuilder bytes = BytesBuilder(copy: false);
    if (requestStream != null) {
      await for (final Uint8List chunk in requestStream) {
        bytes.add(chunk);
      }
    }
    requestBytes = bytes.takeBytes();
    final _Response response = await handler(options);
    return ResponseBody.fromBytes(
      utf8.encode(response.body),
      response.status,
      headers: response.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Response {
  const _Response(
    this.body,
    this.status, [
    this.headers = const <String, List<String>>{},
  ]);

  factory _Response.json(Object body, {int status = 200}) =>
      _Response(jsonEncode(body), status, const <String, List<String>>{
        'content-type': <String>['application/json'],
      });

  final String body;
  final int status;
  final Map<String, List<String>> headers;
}

const String _multistatus = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/remote.php/dav/files/student-id/Documents/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/remote.php/dav/files/student-id/Documents/Notes/</d:href>
    <d:propstat><d:prop><d:displayname>Notes</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/remote.php/dav/files/student-id/Documents/%C3%9Cbung%201.pdf</d:href>
    <d:propstat><d:prop><d:displayname>Übung 1.pdf</d:displayname><d:getcontentlength>42</d:getcontentlength><d:getcontenttype>application/pdf</d:getcontenttype><d:getlastmodified>Sun, 04 Oct 2026 10:00:00 GMT</d:getlastmodified><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';
