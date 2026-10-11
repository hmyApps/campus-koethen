// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:matrix/matrix.dart';

/// Answers the homeserver's re-authentication requests (user-interactive
/// authentication) for exactly one operation.
///
/// Setting up or resetting the encryption identity can make the server ask
/// for the account password. The SDK then waits until someone answers; an
/// unanswered request would hang forever. This answers once with the
/// password the user just typed for this operation, refuses any further or
/// unsupported request, and never keeps the password beyond [stop].
class UiaPasswordResponder {
  UiaPasswordResponder({
    required this._requests,
    required this._password,
    required this._userId,
  });

  final Stream<UiaRequest> _requests;
  String? _password;
  final String _userId;
  StreamSubscription<UiaRequest>? _subscription;
  bool _answered = false;

  /// The server asked for a password and none was given.
  bool passwordMissing = false;

  /// The server asked again after the password was given: it was wrong.
  bool passwordRejected = false;

  void start() {
    _subscription ??= _requests.listen(_answer);
  }

  Future<void> stop() async {
    _password = null;
    await _subscription?.cancel();
    _subscription = null;
  }

  void _answer(UiaRequest request) {
    if (request.state != UiaRequestState.waitForUser) return;
    final String? password = _password;
    if (_answered) {
      passwordRejected = true;
      request.cancel();
      return;
    }
    if (password == null ||
        !request.nextStages.contains(AuthenticationTypes.password)) {
      passwordMissing = password == null;
      request.cancel();
      return;
    }
    _answered = true;
    unawaited(
      request.completeStage(
        AuthenticationPassword(
          session: request.session,
          password: password,
          identifier: AuthenticationUserIdentifier(user: _userId),
        ),
      ),
    );
  }
}
