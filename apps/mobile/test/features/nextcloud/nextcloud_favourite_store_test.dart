// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/nextcloud/data/secure_nextcloud_favourite_store.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_account.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_failure.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const NextcloudAccount _account = NextcloudAccount(
  loginName: 'student',
  userId: 'student-id',
);

void main() {
  test('round-trips a bounded account-scoped favourite set', () async {
    final _MemoryStorage storage = _MemoryStorage();
    final SecureNextcloudFavouriteStore store = SecureNextcloudFavouriteStore(
      storage,
    );

    await store.write(_account, const <String>{'/B.pdf', '/A'});

    expect(await store.read(_account), const <String>{'/A', '/B.pdf'});
    expect(storage.values.values.single, isNot(contains('student-login')));
  });

  test('does not expose another account favourites', () async {
    final SecureNextcloudFavouriteStore store = SecureNextcloudFavouriteStore(
      _MemoryStorage(),
    );
    await store.write(_account, const <String>{'/private.pdf'});

    expect(
      await store.read(
        const NextcloudAccount(loginName: 'other', userId: 'other-id'),
      ),
      isEmpty,
    );
  });

  test('rejects traversal and an unbounded favourite set', () async {
    final SecureNextcloudFavouriteStore store = SecureNextcloudFavouriteStore(
      _MemoryStorage(),
    );

    await expectLater(
      store.write(_account, const <String>{'/../secret'}),
      throwsA(const NextcloudFailure(NextcloudFailureKind.invalidResponse)),
    );
    await expectLater(
      store.write(_account, <String>{
        for (
          var index = 0;
          index <= SecureNextcloudFavouriteStore.maximumFavourites;
          index++
        )
          '/file-$index',
      }),
      throwsA(
        const NextcloudFailure(NextcloudFailureKind.favouriteLimitReached),
      ),
    );
  });

  test('verified clear reports a value that survives deletion', () async {
    final _MemoryStorage storage = _MemoryStorage(dropDelete: true);
    final SecureNextcloudFavouriteStore store = SecureNextcloudFavouriteStore(
      storage,
    );
    await store.write(_account, const <String>{'/A'});

    await expectLater(
      store.clear(),
      throwsA(
        const NextcloudFailure(NextcloudFailureKind.secureStorageUnavailable),
      ),
    );
  });
}

class _MemoryStorage extends FlutterSecureStorage {
  _MemoryStorage({this.dropDelete = false});

  final bool dropDelete;
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (!dropDelete) values.remove(key);
  }
}
