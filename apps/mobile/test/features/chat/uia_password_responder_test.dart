// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:convert';

import 'package:campus_koethen/features/chat/data/uia_password_responder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// A request that needs the password stage, as Synapse asks for it.
MatrixException _needsPassword() => MatrixException(
  http.Response(
    jsonEncode(<String, Object?>{
      'flows': <Object?>[
        <String, Object?>{
          'stages': <String>['m.login.password'],
        },
      ],
      'session': 'demo-session',
      'params': <String, Object?>{},
    }),
    401,
  ),
);

void main() {
  const String userId = '@demo-user:matrix.example.test';
  late StreamController<UiaRequest> requests;
  final List<AuthenticationData?> seen = <AuthenticationData?>[];

  setUp(() {
    requests = StreamController<UiaRequest>.broadcast();
    seen.clear();
  });

  tearDown(() => requests.close());

  /// Runs one UIA-protected request the way the SDK does, accepting only
  /// [accepted] as password.
  Future<String> protectedRequest(String accepted) {
    final Completer<String> done = Completer<String>();
    late UiaRequest<String> uia;
    uia = UiaRequest<String>(
      request: (AuthenticationData? auth) async {
        seen.add(auth);
        if (auth is AuthenticationPassword && auth.password == accepted) {
          return 'done';
        }
        throw _needsPassword();
      },
      onUpdate: (UiaRequestState state) {
        if (state == UiaRequestState.done) {
          // The SDK reports `done` before it stores `result`.
          done.complete('done');
        } else if (state == UiaRequestState.fail) {
          done.completeError(uia.error ?? StateError('failed'));
        } else {
          requests.add(uia);
        }
      },
    );
    return done.future;
  }

  test('answers once with the given password for the own account', () async {
    final UiaPasswordResponder responder = UiaPasswordResponder(
      requests: requests.stream,
      password: 'demo-password',
      userId: userId,
    )..start();
    addTearDown(responder.stop);

    expect(await protectedRequest('demo-password'), 'done');
    final AuthenticationPassword auth = seen.last! as AuthenticationPassword;
    expect(auth.session, 'demo-session');
    expect((auth.identifier as AuthenticationUserIdentifier).user, userId);
    expect(responder.passwordMissing, isFalse);
    expect(responder.passwordRejected, isFalse);
  });

  test('without a password it refuses instead of leaving the request '
      'hanging', () async {
    final UiaPasswordResponder responder = UiaPasswordResponder(
      requests: requests.stream,
      password: null,
      userId: userId,
    )..start();
    addTearDown(responder.stop);

    await expectLater(
      protectedRequest('demo-password').timeout(const Duration(seconds: 5)),
      throwsA(isNot(isA<TimeoutException>())),
    );
    expect(responder.passwordMissing, isTrue);
  });

  test('a wrong password is not tried twice', () async {
    final UiaPasswordResponder responder = UiaPasswordResponder(
      requests: requests.stream,
      password: 'wrong',
      userId: userId,
    )..start();
    addTearDown(responder.stop);

    await expectLater(
      protectedRequest('demo-password').timeout(const Duration(seconds: 5)),
      throwsA(isNot(isA<TimeoutException>())),
    );
    expect(responder.passwordRejected, isTrue);
    expect(seen.whereType<AuthenticationPassword>(), hasLength(1));
  });
}
