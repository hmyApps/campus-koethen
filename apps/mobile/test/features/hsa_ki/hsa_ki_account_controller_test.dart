// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/hsa_ki/application/hsa_ki_account_controller.dart';
import 'package:campus_koethen/features/hsa_ki/application/hsa_ki_providers.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_account.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_chat.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_gateway.dart';
import 'package:campus_koethen/features/university_account/application/university_account_controller.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const HsaKiCredential _credential = HsaKiCredential(
  token: 'tok-1',
  tokenId: '7',
  username: 'mmustermann',
);

const UniversityIdentity _identity = UniversityIdentity(
  identifier: 'mmustermann',
  password: 'secret',
);

void main() {
  test('connect mints a token and stores only the credential', () async {
    final _MemoryCredentialStore store = _MemoryCredentialStore();
    final _Gateway gateway = _Gateway();
    final ProviderContainer container = _container(store: store, gateway: gateway);
    addTearDown(container.dispose);
    await container.read(hsaKiAccountControllerProvider.future);
    final int generationBefore = container.read(hsaKiSessionGenerationProvider);

    await container
        .read(hsaKiAccountControllerProvider.notifier)
        .connect(username: 'mmustermann', password: 'secret');

    expect(store.value, _credential);
    expect(
      container.read(hsaKiAccountControllerProvider).value,
      const HsaKiAccount(username: 'mmustermann'),
    );
    expect(gateway.connectCalls, 1);
    expect(
      container.read(hsaKiSessionGenerationProvider),
      greaterThan(generationBefore),
    );
  });

  test(
    'a failed secure-storage write revokes the just-minted token and leaves '
    'no local credential behind',
    () async {
      final _MemoryCredentialStore store = _MemoryCredentialStore(
        writeFails: true,
      );
      final _Gateway gateway = _Gateway();
      final ProviderContainer container = _container(
        store: store,
        gateway: gateway,
      );
      addTearDown(container.dispose);
      await container.read(hsaKiAccountControllerProvider.future);

      await container
          .read(hsaKiAccountControllerProvider.notifier)
          .connect(username: 'mmustermann', password: 'secret');

      expect(store.value, isNull);
      expect(gateway.revokeCalls, 1);
      expect(
        container.read(hsaKiAccountControllerProvider).hasError,
        isTrue,
      );
    },
  );

  test(
    'disconnect clears the local token even when the remote revoke fails',
    () async {
      final _MemoryCredentialStore store = _MemoryCredentialStore()
        ..value = _credential;
      final _Gateway gateway = _Gateway(revokeFails: true);
      final _MemoryIdentityStore identityStore = _MemoryIdentityStore()
        ..value = _identity;
      final ProviderContainer container = _container(
        store: store,
        gateway: gateway,
        identityStore: identityStore,
      );
      addTearDown(container.dispose);
      await container.read(hsaKiAccountControllerProvider.future);

      await container
          .read(hsaKiAccountControllerProvider.notifier)
          .disconnect();

      expect(gateway.revokeCalls, 1);
      expect(store.value, isNull);
      expect(container.read(hsaKiAccountControllerProvider).value, isNull);
    },
  );

  test(
    'disconnect with no central identity stored skips the remote revoke but '
    'still wipes the local token',
    () async {
      final _MemoryCredentialStore store = _MemoryCredentialStore()
        ..value = _credential;
      final _Gateway gateway = _Gateway();
      final ProviderContainer container = _container(
        store: store,
        gateway: gateway,
      );
      addTearDown(container.dispose);
      await container.read(hsaKiAccountControllerProvider.future);

      await container
          .read(hsaKiAccountControllerProvider.notifier)
          .disconnect();

      expect(gateway.revokeCalls, 0);
      expect(store.value, isNull);
    },
  );
}

ProviderContainer _container({
  required _MemoryCredentialStore store,
  required _Gateway gateway,
  _MemoryIdentityStore? identityStore,
}) => ProviderContainer(
  overrides: [
    hsaKiCredentialStoreProvider.overrideWithValue(store),
    hsaKiGatewayProvider.overrideWithValue(gateway),
    universityIdentityStoreProvider.overrideWithValue(
      identityStore ?? _MemoryIdentityStore(),
    ),
  ],
);

class _MemoryCredentialStore implements HsaKiCredentialStore {
  _MemoryCredentialStore({this.writeFails = false});

  final bool writeFails;
  HsaKiCredential? value;

  @override
  Future<HsaKiCredential?> read() async => value;

  @override
  Future<void> write(HsaKiCredential credential) async {
    if (writeFails) throw StateError('secure store unavailable');
    value = credential;
  }

  @override
  Future<void> clear() async => value = null;
}

class _MemoryIdentityStore implements UniversityIdentityStore {
  UniversityIdentity? value;

  @override
  Future<UniversityIdentity?> read() async => value;

  @override
  Future<void> write(UniversityIdentity identity) async => value = identity;

  @override
  Future<void> clear() async => value = null;
}

class _Gateway implements HsaKiGateway {
  _Gateway({this.revokeFails = false});

  final bool revokeFails;
  var connectCalls = 0;
  var revokeCalls = 0;

  @override
  Future<HsaKiCredential> connect({
    required String username,
    required String password,
  }) async {
    connectCalls++;
    return _credential;
  }

  @override
  Future<void> revoke(HsaKiCredential credential, {required String password}) async {
    revokeCalls++;
    if (revokeFails) throw StateError('remote unavailable');
  }

  @override
  Future<List<HsaKiModel>> listModels(HsaKiCredential credential) async =>
      const <HsaKiModel>[];

  @override
  Future<String> sendMessage(
    HsaKiCredential credential, {
    required String modelId,
    required List<HsaKiMessage> messages,
  }) async => '';
}
