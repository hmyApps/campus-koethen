// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:campus_koethen/features/chat/data/encrypted_matrix_database.dart';
import 'package:campus_koethen/features/chat/data/sdk_matrix_gateway.dart';
import 'package:campus_koethen/features/chat/data/secure_matrix_database_key_store.dart';
import 'package:campus_koethen/features/chat/domain/matrix_failure.dart';
import 'package:campus_koethen/features/chat/domain/matrix_homeserver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test/support/fake_matrix.dart';

/// Manual device check for the chat (docs/matrix.md §6), run on a device or
/// emulator with the build's homeserver:
///
/// `flutter test integration_test/matrix_device_check_test.dart
///   --dart-define=MATRIX_HOMESERVER_URL=https://…`
///
/// Uses a temporary directory and an in-memory key store, so it never touches
/// the app's own chat data, and no real account: the login it sends is for a
/// made-up user with a random password and must be refused.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final MatrixHomeserver? homeserver = MatrixConfig.homeserver;
  final String? skip = homeserver == null
      ? 'needs --dart-define=MATRIX_HOMESERVER_URL'
      : null;

  late Directory directory;
  late MemorySecureStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('campus_chat_check');
    storage = MemorySecureStorage();
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  EncryptedMatrixDatabase database() => EncryptedMatrixDatabase(
    keyStore: SecureMatrixDatabaseKeyStore(storage),
    directory: () async => directory,
  );

  testWidgets('vodozemac loads on this device', (WidgetTester tester) async {
    await initVodozemac();
  }, skip: skip != null);

  testWidgets('the database is written encrypted on this device', (
    WidgetTester tester,
  ) async {
    final EncryptedMatrixDatabase db = database();
    final Database opened = await db.open();
    await opened.execute('CREATE TABLE probe (value TEXT)');
    await opened.insert('probe', <String, Object?>{'value': 'device check'});
    await opened.close();

    final List<int> bytes = await File(
      '${directory.path}/${EncryptedMatrixDatabase.fileName}',
    ).readAsBytes();
    expect(
      ascii.decode(bytes.take(15).toList(), allowInvalid: true),
      isNot('SQLite format 3'),
    );
    expect(latin1.decode(bytes), isNot(contains('device check')));

    await db.wipe();
    expect(storage.values, isEmpty);
  }, skip: skip != null);

  testWidgets('the homeserver refuses a made-up login, and nothing stays', (
    WidgetTester tester,
  ) async {
    final SdkMatrixGateway gateway = SdkMatrixGateway(
      homeserver: homeserver,
      database: database(),
    );
    addTearDown(gateway.dispose);
    final Random random = Random.secure();
    final String password = base64Url.encode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );

    await expectLater(
      gateway.login(
        username: 'campus-koethen-device-check-${random.nextInt(1 << 32)}',
        password: password,
      ),
      throwsA(
        isA<MatrixFailure>().having(
          (MatrixFailure f) => f.kind,
          'kind',
          MatrixFailureKind.invalidCredentials,
        ),
      ),
    );
    expect(storage.values, isEmpty);
    expect(
      await File(
        '${directory.path}/${EncryptedMatrixDatabase.fileName}',
      ).exists(),
      isFalse,
    );
  }, skip: skip != null);
}
