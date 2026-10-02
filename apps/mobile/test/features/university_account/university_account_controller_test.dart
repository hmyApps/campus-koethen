// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/university_account/application/university_account_controller.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

const UniversityIdentity _identity = UniversityIdentity(
  identifier: 'student-42@hs-anhalt.de',
  password: 'top-secret',
);

class _MemoryIdentityStore implements UniversityIdentityStore {
  UniversityIdentity? value;
  Object? writeError;
  Object? clearError;
  int writes = 0;
  int clears = 0;

  @override
  Future<UniversityIdentity?> read() async => value;

  @override
  Future<void> write(UniversityIdentity identity) async {
    if (writeError != null) throw writeError!;
    writes++;
    value = identity;
  }

  @override
  Future<void> clear() async {
    if (clearError != null) throw clearError!;
    clears++;
    value = null;
  }
}

void main() {
  test('identity normalizes identifiers and never prints the password', () {
    const UniversityIdentity identity = UniversityIdentity(
      identifier: '  student-42@hs-anhalt.de  ',
      password: 'top-secret',
    );

    expect(identity.normalized.identifier, 'student-42@hs-anhalt.de');
    expect(identity.toString(), isNot(contains('top-secret')));
    expect(identity.normalized.isValid, isTrue);
  });

  test('a bare username is just as valid as an email address', () {
    const UniversityIdentity identity = UniversityIdentity(
      identifier: 'student-42',
      password: 'top-secret',
    );

    expect(identity.isValid, isTrue);
  });

  test('public state never carries the password', () async {
    final _MemoryIdentityStore store = _MemoryIdentityStore()
      ..value = _identity;
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        universityIdentityStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    final UniversityAccountState state = await container.read(
      universityAccountControllerProvider.future,
    );

    expect(state.identifier, _identity.identifier);
    expect(state.toString(), isNot(contains(_identity.password)));
  });

  test(
    'verified identity can be retained and required only from secure store',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          universityIdentityStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      await container.read(universityAccountControllerProvider.future);

      await container
          .read(universityAccountControllerProvider.notifier)
          .retainVerified(_identity);

      expect(store.writes, 1);
      expect(
        await container
            .read(universityAccountControllerProvider.notifier)
            .requireIdentity(),
        _identity,
      );
    },
  );

  test(
    'invalid and missing identities are rejected with typed failures',
    () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          universityIdentityStoreProvider.overrideWithValue(
            _MemoryIdentityStore(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(universityAccountControllerProvider.future);

      await expectLater(
        container
            .read(universityAccountControllerProvider.notifier)
            .retainVerified(
              const UniversityIdentity(identifier: '', password: ''),
            ),
        throwsA(
          const UniversityAccountFailure(
            UniversityAccountFailureKind.invalidIdentity,
          ),
        ),
      );
      await expectLater(
        container
            .read(universityAccountControllerProvider.notifier)
            .requireIdentity(),
        throwsA(
          const UniversityAccountFailure(
            UniversityAccountFailureKind.identityMissing,
          ),
        ),
      );
    },
  );
}
