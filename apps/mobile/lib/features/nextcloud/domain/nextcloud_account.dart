// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

/// The credential returned by Nextcloud Login Flow v2.
///
/// It may only exist at the gateway/secure-store boundary. In particular, the
/// app password must never be put into Riverpod state or an exception.
@immutable
class NextcloudCredential {
  const NextcloudCredential({
    required this.server,
    required this.loginName,
    required this.userId,
    required this.appPassword,
  });

  final String server;
  final String loginName;
  final String userId;
  final String appPassword;

  NextcloudAccount toAccount() =>
      NextcloudAccount(loginName: loginName, userId: userId);

  @override
  String toString() => 'NextcloudCredential(«redacted»)';

  @override
  bool operator ==(Object other) =>
      other is NextcloudCredential &&
      other.server == server &&
      other.loginName == loginName &&
      other.userId == userId &&
      other.appPassword == appPassword;

  @override
  int get hashCode => Object.hash(server, loginName, userId, appPassword);
}

/// Public account state. Contains no bearer credential.
@immutable
class NextcloudAccount {
  const NextcloudAccount({required this.loginName, required this.userId});

  final String loginName;
  final String userId;

  @override
  String toString() => 'NextcloudAccount(«redacted»)';

  @override
  bool operator ==(Object other) =>
      other is NextcloudAccount &&
      other.loginName == loginName &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(loginName, userId);
}

abstract interface class NextcloudCredentialStore {
  Future<NextcloudCredential?> read();
  Future<void> write(NextcloudCredential credential);
  Future<void> clear();
}
