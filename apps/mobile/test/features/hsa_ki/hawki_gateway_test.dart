// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:campus_koethen/features/hsa_ki/data/hawki_gateway.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_account.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_chat.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_html_adapter.dart';

const String _loginPageHtml = '''
  <html><body>
    <form id="hawkiLoginForm" method="POST" action="/req/login">
      <input type="hidden" name="_token" value="login-csrf">
    </form>
  </body></html>
''';

const String _profilePageHtml = '''
  <html><head><meta name="csrf-token" content="profile-csrf"></head>
  <body></body></html>
''';

FakeHtmlResponse _json(Object body, {int statusCode = 200}) =>
    FakeHtmlResponse(
      jsonEncode(body),
      statusCode: statusCode,
      contentType: 'application/json',
    );

/// A scripted happy path for the whole login → mint-token round trip.
FakeHtmlResponse _connectScript(
  RequestOptions o, {
  Object? createTokenResponse,
}) {
  final String path = o.uri.path;
  if (path == '/login' && o.method == 'GET') {
    return const FakeHtmlResponse(_loginPageHtml);
  }
  if (path == '/req/login' && o.method == 'POST') {
    return _json(<String, dynamic>{
      'success': true,
      'redirectUri': '/handshake',
    });
  }
  if (path == '/profile' && o.method == 'GET') {
    return const FakeHtmlResponse(_profilePageHtml);
  }
  if (path == '/req/profile/create-token' && o.method == 'POST') {
    return _json(
      createTokenResponse ??
          <String, dynamic>{
            'success': true,
            'token': 'plain-text-token',
            'id': 7,
            'name': 'Campus Köthen',
          },
    );
  }
  return const FakeHtmlResponse('not found', statusCode: 404);
}

void main() {
  group('connect', () {
    test(
      'logs in then mints a token, reading a fresh CSRF token from /profile',
      () async {
        final FakeHtmlAdapter adapter = FakeHtmlAdapter(_connectScript);
        final HawkiGateway gateway = HawkiGateway(adapter);

        final HsaKiCredential credential = await gateway.connect(
          username: 'mmustermann',
          password: 'secret',
        );

        expect(credential.token, 'plain-text-token');
        expect(credential.tokenId, '7');
        expect(credential.username, 'mmustermann');

        final RequestOptions login = adapter.requests.firstWhere(
          (RequestOptions o) => o.uri.path == '/req/login',
        );
        expect(login.headers['X-CSRF-TOKEN'], 'login-csrf');

        final RequestOptions createToken = adapter.requests.firstWhere(
          (RequestOptions o) => o.uri.path == '/req/profile/create-token',
        );
        expect(createToken.headers['X-CSRF-TOKEN'], 'profile-csrf');
        expect(createToken.data, <String, dynamic>{'name': 'Campus Köthen'});
      },
    );

    test('rejects invalid credentials without minting a token', () async {
      final FakeHtmlAdapter adapter = FakeHtmlAdapter((RequestOptions o) {
        if (o.uri.path == '/login' && o.method == 'GET') {
          return const FakeHtmlResponse(_loginPageHtml);
        }
        if (o.uri.path == '/req/login') {
          return _json(<String, dynamic>{}, statusCode: 401);
        }
        return const FakeHtmlResponse('not found', statusCode: 404);
      });

      await expectLater(
        HawkiGateway(adapter).connect(username: 'x', password: 'wrong'),
        throwsA(
          isA<HsaKiFailure>().having(
            (HsaKiFailure e) => e.kind,
            'kind',
            HsaKiFailureKind.invalidCredentials,
          ),
        ),
      );
      expect(
        adapter.urls.any(
          (String u) => u.contains('/req/profile/create-token'),
        ),
        isFalse,
      );
    });

    test(
      'treats a redirectUri of /register as not-yet-registered, never '
      'minting a token for a session the login endpoint never actually '
      'authenticated',
      () async {
        final FakeHtmlAdapter adapter = FakeHtmlAdapter((RequestOptions o) {
          if (o.uri.path == '/login' && o.method == 'GET') {
            return const FakeHtmlResponse(_loginPageHtml);
          }
          if (o.uri.path == '/req/login') {
            return _json(<String, dynamic>{
              'success': true,
              'redirectUri': '/register',
            });
          }
          return const FakeHtmlResponse('not found', statusCode: 404);
        });

        await expectLater(
          HawkiGateway(adapter).connect(username: 'new-student', password: 'y'),
          throwsA(
            isA<HsaKiFailure>().having(
              (HsaKiFailure e) => e.kind,
              'kind',
              HsaKiFailureKind.notRegistered,
            ),
          ),
        );
        expect(
          adapter.urls.any(
            (String u) => u.contains('/req/profile/create-token'),
          ),
          isFalse,
        );
      },
    );

    test(
      'reports portalStructureChanged when the token response has no token',
      () async {
        final FakeHtmlAdapter adapter = FakeHtmlAdapter(
          (RequestOptions o) => _connectScript(
            o,
            createTokenResponse: <String, dynamic>{'success': true},
          ),
        );

        await expectLater(
          HawkiGateway(adapter).connect(username: 'x', password: 'y'),
          throwsA(
            isA<HsaKiFailure>().having(
              (HsaKiFailure e) => e.kind,
              'kind',
              HsaKiFailureKind.portalStructureChanged,
            ),
          ),
        );
      },
    );

    test('maps a connection error to networkUnavailable', () async {
      final FakeHtmlAdapter adapter = FakeHtmlAdapter((RequestOptions o) {
        if (o.uri.path == '/login') return const FakeHtmlResponse(_loginPageHtml);
        throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        );
      });

      await expectLater(
        HawkiGateway(adapter).connect(username: 'x', password: 'y'),
        throwsA(
          isA<HsaKiFailure>().having(
            (HsaKiFailure e) => e.kind,
            'kind',
            HsaKiFailureKind.networkUnavailable,
          ),
        ),
      );
    });
  });

  group('revoke', () {
    const HsaKiCredential credential = HsaKiCredential(
      token: 'tok',
      tokenId: '7',
      username: 'mmustermann',
    );

    test('logs in again and revokes the token by its numeric id', () async {
      final FakeHtmlAdapter adapter = FakeHtmlAdapter((RequestOptions o) {
        final String path = o.uri.path;
        if (path == '/login' && o.method == 'GET') {
          return const FakeHtmlResponse(_loginPageHtml);
        }
        if (path == '/req/login') {
          return _json(<String, dynamic>{'success': true});
        }
        if (path == '/profile' && o.method == 'GET') {
          return const FakeHtmlResponse(_profilePageHtml);
        }
        if (path == '/req/profile/revoke-token') {
          return _json(<String, dynamic>{'success': true});
        }
        return const FakeHtmlResponse('not found', statusCode: 404);
      });

      await HawkiGateway(adapter).revoke(credential, password: 'secret');

      final RequestOptions revoke = adapter.requests.firstWhere(
        (RequestOptions o) => o.uri.path == '/req/profile/revoke-token',
      );
      expect(revoke.data, <String, dynamic>{'tokenId': 7});
    });

    test('a network failure during revoke is classified, not rethrown raw', () async {
      final FakeHtmlAdapter adapter = FakeHtmlAdapter((RequestOptions o) {
        if (o.uri.path == '/login') return const FakeHtmlResponse(_loginPageHtml);
        throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        );
      });

      await expectLater(
        HawkiGateway(adapter).revoke(credential, password: 'secret'),
        throwsA(isA<HsaKiFailure>()),
      );
    });
  });

  group('listModels', () {
    const HsaKiCredential credential = HsaKiCredential(
      token: 'bearer-tok',
      tokenId: '7',
      username: 'mmustermann',
    );

    test('parses the JSON:API attributes, skipping malformed entries', () async {
      final FakeHtmlAdapter adapter = FakeHtmlAdapter((RequestOptions o) {
        expect(o.headers['Authorization'], 'Bearer bearer-tok');
        return _json(<String, dynamic>{
          'data': <dynamic>[
            <String, dynamic>{
              'attributes': <String, dynamic>{
                'model_id': 'gpt-4',
                'label': 'GPT-4',
                'active': true,
              },
            },
            <String, dynamic>{
              'attributes': <String, dynamic>{
                'model_id': 'gpt-3',
                'active': false,
              },
            },
            <String, dynamic>{'attributes': <String, dynamic>{}},
          ],
        });
      });

      final List<HsaKiModel> models = await HawkiGateway(
        adapter,
      ).listModels(credential);

      expect(models, hasLength(2));
      expect(models[0].modelId, 'gpt-4');
      expect(models[0].label, 'GPT-4');
      expect(models[0].active, isTrue);
      // No label in the fixture: the model id itself is the fallback label.
      expect(models[1].label, 'gpt-3');
      expect(models[1].active, isFalse);
    });

    test('maps a 401 to notConnected', () async {
      final FakeHtmlAdapter adapter = FakeHtmlAdapter(
        (RequestOptions o) => _json(<String, dynamic>{}, statusCode: 401),
      );
      await expectLater(
        HawkiGateway(adapter).listModels(credential),
        throwsA(
          isA<HsaKiFailure>().having(
            (HsaKiFailure e) => e.kind,
            'kind',
            HsaKiFailureKind.notConnected,
          ),
        ),
      );
    });

    test(
      'maps a 403 to externalAccessDisabled (HSA-side ExtAppConfig toggle)',
      () async {
        final FakeHtmlAdapter adapter = FakeHtmlAdapter(
          (RequestOptions o) => _json(<String, dynamic>{}, statusCode: 403),
        );
        await expectLater(
          HawkiGateway(adapter).listModels(credential),
          throwsA(
            isA<HsaKiFailure>().having(
              (HsaKiFailure e) => e.kind,
              'kind',
              HsaKiFailureKind.externalAccessDisabled,
            ),
          ),
        );
      },
    );
  });

  group('sendMessage', () {
    const HsaKiCredential credential = HsaKiCredential(
      token: 'bearer-tok',
      tokenId: '7',
      username: 'mmustermann',
    );

    test('posts the stateless payload shape and returns the reply text', () async {
      final FakeHtmlAdapter adapter = FakeHtmlAdapter((RequestOptions o) {
        // Confirmed 2026-10-06 against the real, currently deployed
        // instance: `ai-req` is NOT under the JSON:API `/hawki/v1` prefix
        // (that prefix only exists for `ai-models` and similar JSON:API
        // resources) — `/api/hawki/v1/ai-req` 404s for real, `/api/ai-req`
        // answers 401 Unauthenticated (route exists, needs a token).
        expect(o.uri.path, '/api/ai-req');
        expect(o.data, <String, dynamic>{
          'payload': <String, dynamic>{
            'model': 'gpt-4',
            'messages': <dynamic>[
              <String, dynamic>{
                'role': 'user',
                'content': <String, dynamic>{'text': 'Hallo'},
              },
            ],
          },
        });
        return _json(<String, dynamic>{'success': true, 'content': 'Moin!'});
      });

      final String reply = await HawkiGateway(adapter).sendMessage(
        credential,
        modelId: 'gpt-4',
        messages: const <HsaKiMessage>[
          HsaKiMessage(role: HsaKiMessageRole.user, text: 'Hallo'),
        ],
      );

      expect(reply, 'Moin!');
    });

    test('reports portalStructureChanged when success is not true', () async {
      final FakeHtmlAdapter adapter = FakeHtmlAdapter(
        (RequestOptions o) =>
            _json(<String, dynamic>{'success': false, 'content': ''}),
      );
      await expectLater(
        HawkiGateway(adapter).sendMessage(
          credential,
          modelId: 'gpt-4',
          messages: const <HsaKiMessage>[],
        ),
        throwsA(
          isA<HsaKiFailure>().having(
            (HsaKiFailure e) => e.kind,
            'kind',
            HsaKiFailureKind.portalStructureChanged,
          ),
        ),
      );
    });
  });
}
