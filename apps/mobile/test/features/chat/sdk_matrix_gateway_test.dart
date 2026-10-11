// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';

import 'package:campus_koethen/features/chat/data/encrypted_matrix_database.dart';
import 'package:campus_koethen/features/chat/data/sdk_matrix_gateway.dart';
import 'package:campus_koethen/features/chat/data/secure_matrix_database_key_store.dart';
import 'package:campus_koethen/features/chat/domain/chat_key_backup.dart';
import 'package:campus_koethen/features/chat/domain/chat_models.dart';
import 'package:campus_koethen/features/chat/domain/matrix_failure.dart';
import 'package:campus_koethen/features/chat/domain/matrix_gateway.dart';
import 'package:campus_koethen/features/chat/domain/matrix_homeserver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_homeserver.dart';
import '../../support/fake_matrix.dart';

void main() {
  late Directory directory;
  late MemorySecureStorage storage;
  late FakeHomeserver server;
  final List<SdkMatrixGateway> opened = <SdkMatrixGateway>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('campus_chat_gateway');
    storage = MemorySecureStorage();
    server = FakeHomeserver();
  });

  tearDown(() async {
    for (final SdkMatrixGateway gateway in opened) {
      await gateway.dispose();
    }
    opened.clear();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  SdkMatrixGateway gatewayFor({
    String homeserver = 'https://matrix.example.test',
  }) {
    final SdkMatrixGateway gateway = SdkMatrixGateway(
      homeserver: MatrixHomeserver.parse(homeserver),
      database: EncryptedMatrixDatabase(
        keyStore: SecureMatrixDatabaseKeyStore(storage),
        factory: databaseFactoryFfiNoIsolate,
        directory: () async => directory,
      ),
      httpClient: server,
      // The host test runner has no vodozemac build; E2EE runs on devices.
      initEncryption: null,
    );
    opened.add(gateway);
    return gateway;
  }

  File databaseFile() =>
      File('${directory.path}/${EncryptedMatrixDatabase.fileName}');

  Matcher failure(MatrixFailureKind kind) => throwsA(
    isA<MatrixFailure>().having((MatrixFailure f) => f.kind, 'kind', kind),
  );

  Future<MatrixAccount> signIn(MatrixGateway gateway) => gateway.login(
    username: FakeHomeserver.demoUser,
    password: FakeHomeserver.demoPassword,
  );

  Future<void> untilRooms(MatrixGateway gateway, int count) async {
    for (var i = 0; i < 200 && gateway.rooms.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(gateway.rooms, hasLength(count));
  }

  group('without a configured homeserver', () {
    test('login is refused and nothing is touched', () async {
      final SdkMatrixGateway gateway = gatewayFor(homeserver: '');

      await expectLater(
        signIn(gateway),
        failure(MatrixFailureKind.notConfigured),
      );
      expect(await gateway.restore(), isNull);
      expect(server.requests, isEmpty);
      expect(storage.values, isEmpty);
    });
  });

  group('login', () {
    test('signs in with the password flow at exactly the configured origin, '
        'without .well-known discovery', () async {
      final SdkMatrixGateway gateway = gatewayFor();

      final MatrixAccount account = await signIn(gateway);

      expect(account.userId, FakeHomeserver.userId);
      expect(
        server.requests.map((FakeHomeserverRequest r) => r.url.origin).toSet(),
        <String>{'https://matrix.example.test'},
      );
      expect(
        server.requests.where(
          (FakeHomeserverRequest r) => r.url.path.contains('.well-known'),
        ),
        isEmpty,
      );
      final Map<String, Object?> body =
          jsonDecode(server.called('POST', '/v3/login').single.body)
              as Map<String, Object?>;
      expect(body['type'], 'm.login.password');
      expect(body['password'], FakeHomeserver.demoPassword);
    });

    test('keeps only the database key in the keystore — never the password '
        'or the token', () async {
      await signIn(gatewayFor());

      expect(storage.values.keys, <String>[
        SecureMatrixDatabaseKeyStore.databaseKeyKey,
      ]);
      final String stored = storage.values.values.join();
      expect(stored, isNot(contains(FakeHomeserver.demoPassword)));
      expect(stored, isNot(contains('demo-access-token')));
      final String file = latin1.decode(await databaseFile().readAsBytes());
      expect(file, isNot(contains('demo-access-token')));
    });

    test('a wrong password is reported and leaves nothing behind', () async {
      final SdkMatrixGateway gateway = gatewayFor();

      await expectLater(
        gateway.login(username: FakeHomeserver.demoUser, password: 'wrong'),
        failure(MatrixFailureKind.invalidCredentials),
      );
      expect(storage.values, isEmpty);
      expect(await databaseFile().exists(), isFalse);
    });

    test('is classified when the network is down', () async {
      server.offline = true;

      await expectLater(
        signIn(gatewayFor()),
        failure(MatrixFailureKind.networkUnavailable),
      );
      expect(storage.values, isEmpty);
    });

    test('is classified when the server rate-limits', () async {
      server.loginError = (429, 'M_LIMIT_EXCEEDED');

      await expectLater(
        signIn(gatewayFor()),
        failure(MatrixFailureKind.rateLimited),
      );
    });

    test('refuses a server without password login', () async {
      server.loginFlows = <String>['m.login.sso'];

      await expectLater(
        signIn(gatewayFor()),
        failure(MatrixFailureKind.unsupportedServer),
      );
      expect(server.called('POST', '/v3/login'), isEmpty);
    });
  });

  group('restore', () {
    test('is null and does not create a database when signed out', () async {
      expect(await gatewayFor().restore(), isNull);
      expect(storage.values, isEmpty);
      expect(await databaseFile().exists(), isFalse);
      expect(server.requests, isEmpty);
    });

    test('brings back the stored session without a new login', () async {
      final SdkMatrixGateway first = gatewayFor();
      await signIn(first);
      await first.dispose();

      final MatrixAccount? restored = await gatewayFor().restore();

      expect(restored?.userId, FakeHomeserver.userId);
      expect(server.called('POST', '/v3/login'), hasLength(1));
    });

    test('drops a session that belongs to another homeserver', () async {
      final SdkMatrixGateway first = gatewayFor();
      await signIn(first);
      await first.dispose();
      final int before = server.requests.length;

      final MatrixAccount? restored = await gatewayFor(
        homeserver: 'https://other.example.test',
      ).restore();

      expect(restored, isNull);
      expect(storage.values, isEmpty);
      expect(await databaseFile().exists(), isFalse);
      expect(server.requests.length, before);
    });
  });

  group('rooms and messages', () {
    test('summarises joined rooms and invites', () async {
      server.firstSyncRooms = server.demoRooms;
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);
      await untilRooms(gateway, 3);

      final ChatRoomSummary group = gateway.rooms.singleWhere(
        (ChatRoomSummary r) => r.id == FakeHomeserver.groupRoomId,
      );
      expect(group.title, 'Demo-Gruppe');
      expect(group.isInvite, isFalse);
      expect(group.isEncrypted, isFalse);
      expect(group.unreadCount, 2);
      expect(group.lastMessage?.kind, ChatMessageKind.text);
      expect(group.lastMessage?.body, 'Demo-Nachricht');
      expect(group.lastMessage?.senderName, 'Demo-Kontakt');
      expect(group.lastMessage?.isMine, isFalse);

      final ChatRoomSummary encrypted = gateway.rooms.singleWhere(
        (ChatRoomSummary r) => r.id == FakeHomeserver.encryptedRoomId,
      );
      expect(encrypted.isEncrypted, isTrue);
      expect(encrypted.lastMessage?.kind, ChatMessageKind.undecryptable);
      expect(encrypted.lastMessage?.body, isEmpty);

      final ChatRoomSummary invite = gateway.rooms.singleWhere(
        (ChatRoomSummary r) => r.id == FakeHomeserver.inviteRoomId,
      );
      expect(invite.isInvite, isTrue);
      expect(invite.title, 'Demo-Einladung');
    });

    test('the timeline shows messages only, newest first', () async {
      server.firstSyncRooms = server.demoRooms;
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);
      await untilRooms(gateway, 3);

      final ChatRoomTimeline timeline = await gateway.openTimeline(
        FakeHomeserver.groupRoomId,
      );
      addTearDown(timeline.close);

      expect(timeline.messages.map((ChatMessage m) => m.body), <String>[
        'Demo-Nachricht',
      ]);
    });

    test('sends text to the room', () async {
      server.firstSyncRooms = server.demoRooms;
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);
      await untilRooms(gateway, 3);

      await gateway.sendText(FakeHomeserver.groupRoomId, 'Demo-Antwort');

      final FakeHomeserverRequest sent = server.requests.singleWhere(
        (FakeHomeserverRequest r) =>
            r.method == 'PUT' && r.path.contains('/send/m.room.message/'),
      );
      expect(
        sent.path,
        startsWith(
          '/v3/rooms/${Uri.encodeComponent(FakeHomeserver.groupRoomId)}/',
        ),
      );
      expect(
        (jsonDecode(sent.body) as Map<String, Object?>)['body'],
        'Demo-Antwort',
      );
    });

    test('an unknown room is reported, not guessed', () async {
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);

      await expectLater(
        gateway.sendText('!missing:matrix.example.test', 'x'),
        failure(MatrixFailureKind.roomUnavailable),
      );
      await expectLater(
        gateway.openTimeline('!missing:matrix.example.test'),
        failure(MatrixFailureKind.roomUnavailable),
      );
    });
  });

  group('logout', () {
    test('signs the device out and wipes database and key', () async {
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);

      await gateway.logout();

      expect(server.called('POST', '/v3/logout'), hasLength(1));
      expect(storage.values, isEmpty);
      expect(await databaseFile().exists(), isFalse);
      expect(gateway.rooms, isEmpty);
    });

    test('wipes locally even when the server cannot be reached', () async {
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);
      server.offline = true;

      await gateway.logout();

      expect(storage.values, isEmpty);
      expect(await databaseFile().exists(), isFalse);
    });

    test('also signs out a session that was never restored', () async {
      final SdkMatrixGateway first = gatewayFor();
      await signIn(first);
      await first.dispose();

      await gatewayFor().logout();

      expect(server.called('POST', '/v3/logout'), hasLength(1));
      expect(storage.values, isEmpty);
      expect(await databaseFile().exists(), isFalse);
    });
  });

  group('new conversations', () {
    Map<String, Object?> createRequest() =>
        jsonDecode(server.called('POST', '/v3/createRoom').single.body)
            as Map<String, Object?>;

    bool asksForEncryption(Map<String, Object?> request) =>
        ((request['initial_state'] as List<Object?>?) ?? <Object?>[]).any(
          (Object? e) =>
              e is Map &&
              e['type'] == 'm.room.encryption' &&
              (e['content'] as Map)['algorithm'] == 'm.megolm.v1.aes-sha2',
        );

    test(
      'starts an encrypted direct chat and waits until it is there',
      () async {
        final SdkMatrixGateway gateway = gatewayFor();
        await signIn(gateway);

        final String roomId = await gateway.startDirectChat(
          FakeHomeserver.peerId,
        );

        final Map<String, Object?> request = createRequest();
        expect(request['is_direct'], isTrue);
        expect(request['invite'], <String>[FakeHomeserver.peerId]);
        expect(asksForEncryption(request), isTrue);
        expect(
          gateway.rooms.map((ChatRoomSummary r) => r.id),
          contains(roomId),
        );
      },
    );

    test('creates an encrypted, private group', () async {
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);

      final String roomId = await gateway.createGroupChat(
        name: 'Demo-Lerngruppe',
        invite: <String>[FakeHomeserver.peerId],
      );

      final Map<String, Object?> request = createRequest();
      expect(request['name'], 'Demo-Lerngruppe');
      expect(request['invite'], <String>[FakeHomeserver.peerId]);
      expect(request['preset'], 'private_chat');
      expect(asksForEncryption(request), isTrue);
      expect(
        gateway.rooms.singleWhere((ChatRoomSummary r) => r.id == roomId).title,
        'Demo-Lerngruppe',
      );
    });

    test('refuses an invalid Matrix ID before asking the server', () async {
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);

      await expectLater(
        gateway.startDirectChat('demo peer'),
        failure(MatrixFailureKind.invalidUserId),
      );
      await expectLater(
        gateway.createGroupChat(name: 'x', invite: <String>['@:x']),
        failure(MatrixFailureKind.invalidUserId),
      );
      expect(server.called('POST', '/v3/createRoom'), isEmpty);
    });

    test('a refusal is "not allowed", not a wrong password', () async {
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);
      server.createRoomError = (403, 'M_FORBIDDEN');

      await expectLater(
        gateway.startDirectChat(FakeHomeserver.peerId),
        failure(MatrixFailureKind.notAllowed),
      );
    });

    test('an unknown person is reported as such', () async {
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);
      server.createRoomError = (404, 'M_NOT_FOUND');

      await expectLater(
        gateway.startDirectChat(FakeHomeserver.peerId),
        failure(MatrixFailureKind.notFound),
      );
    });
  });

  group('key backup without end-to-end encryption', () {
    // The host has no vodozemac build; on devices the chat never runs
    // without it. Here the gateway must say so, not pretend.
    test('reports it as unavailable', () async {
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);

      expect(await gateway.keyBackupState(), ChatKeyBackupState.unavailable);
    });

    test('refuses set-up, unlock and reset before asking the server', () async {
      final SdkMatrixGateway gateway = gatewayFor();
      await signIn(gateway);
      final int before = server.requests.length;

      await expectLater(
        gateway.setUpKeyBackup(),
        failure(MatrixFailureKind.encryptionUnavailable),
      );
      await expectLater(
        gateway.unlockKeyBackup('EsTd emoD'),
        failure(MatrixFailureKind.encryptionUnavailable),
      );
      await expectLater(
        gateway.resetKeyBackup(password: FakeHomeserver.demoPassword),
        failure(MatrixFailureKind.encryptionUnavailable),
      );
      expect(
        server.requests
            .skip(before)
            .where((FakeHomeserverRequest r) => r.path != '/v3/sync'),
        isEmpty,
      );
    });
  });

  test('a session the server ended is reported as signed out', () async {
    final SdkMatrixGateway gateway = gatewayFor();
    await signIn(gateway);
    expect(gateway.account?.userId, FakeHomeserver.userId);

    final Future<void> changed = gateway.changes.firstWhere(
      (_) => gateway.account == null,
    );
    server.revokeToken = true;
    await changed.timeout(const Duration(seconds: 10));

    expect(gateway.account, isNull);
    expect(gateway.rooms, isEmpty);
  });

  test('stops syncing while in the background', () async {
    final SdkMatrixGateway gateway = gatewayFor();
    await signIn(gateway);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.called('GET', '/v3/sync').length, greaterThan(1));

    gateway.setSyncActive(false);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final int paused = server.called('GET', '/v3/sync').length;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(server.called('GET', '/v3/sync').length, paused);

    gateway.setSyncActive(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.called('GET', '/v3/sync').length, greaterThan(paused));
  });
}
