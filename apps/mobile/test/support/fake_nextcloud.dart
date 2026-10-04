// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/core/documents/app_document.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_account.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_entry.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_gateway.dart';

class InMemoryNextcloudCredentialStore implements NextcloudCredentialStore {
  NextcloudCredential? value;
  int clears = 0;

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }

  @override
  Future<NextcloudCredential?> read() async => value;

  @override
  Future<void> write(NextcloudCredential credential) async {
    value = credential;
  }
}

class FakeNextcloudGateway implements NextcloudGateway {
  var revokeCalls = 0;
  Object? revokeError;
  List<NextcloudEntry> entries = const <NextcloudEntry>[];
  AppDocument? document;
  NextcloudCredential? loginCredential;
  final List<String> listedPaths = <String>[];

  @override
  Future<NextcloudLoginStart> startLogin() async => NextcloudLoginStart(
    loginUri: Uri.parse('https://cloud.hs-anhalt.de/login/v2/flow/test'),
    pollUri: Uri.parse('https://cloud.hs-anhalt.de/login/v2/poll'),
    pollToken: 'fake-poll-token',
  );

  @override
  Future<NextcloudCredential> completeLogin(
    NextcloudLoginStart start, {
    required Future<void> canceled,
  }) async => loginCredential ?? (throw StateError('No fake login configured'));

  @override
  Future<void> revoke(NextcloudCredential credential) async {
    revokeCalls++;
    if (revokeError != null) throw revokeError!;
  }

  @override
  Future<List<NextcloudEntry>> listFolder(
    NextcloudCredential credential,
    String path,
  ) async {
    listedPaths.add(path);
    return entries;
  }

  @override
  Future<AppDocument> downloadFile(
    NextcloudCredential credential,
    NextcloudEntry entry,
  ) async => document ?? (throw StateError('No fake document configured'));
}
