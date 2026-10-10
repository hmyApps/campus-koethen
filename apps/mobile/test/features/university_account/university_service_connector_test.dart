// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/settings/application/sign_out_everywhere_controller.dart';
import 'package:campus_koethen/features/settings/domain/direct_service.dart';
import 'package:campus_koethen/features/grades/application/grades_providers.dart';
import 'package:campus_koethen/features/grades/domain/grade_portal.dart';
import 'package:campus_koethen/features/hsa_ki/application/hsa_ki_consent.dart';
import 'package:campus_koethen/features/hsa_ki/application/hsa_ki_providers.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_account.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_chat.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_failure.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_gateway.dart';
import 'package:campus_koethen/features/mail/application/mail_providers.dart';
import 'package:campus_koethen/features/moodle/application/moodle_providers.dart';
import 'package:campus_koethen/features/university_account/application/university_account_controller.dart';
import 'package:campus_koethen/features/university_account/application/university_service_connector.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity.dart';
import 'package:campus_koethen/features/university_account/domain/university_identity_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grades.dart' as grades;
import '../../support/fake_mail.dart';
import '../../support/fake_moodle.dart' as moodle;

const UniversityIdentity _identity = UniversityIdentity(
  identifier: 'student@hs-anhalt.de',
  password: 'secret',
);
const UniversityIdentity _replacementIdentity = UniversityIdentity(
  identifier: 'replacement@hs-anhalt.de',
  password: 'new-secret',
);

class _MemoryIdentityStore implements UniversityIdentityStore {
  UniversityIdentity? value;
  Object? writeError;
  Object? nextWriteError;
  int writes = 0;
  int clears = 0;

  @override
  Future<UniversityIdentity?> read() async => value;
  @override
  Future<void> write(UniversityIdentity identity) async {
    writes++;
    if (nextWriteError case final Object error) {
      nextWriteError = null;
      throw error;
    }
    if (writeError != null) throw writeError!;
    value = identity;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

class _RecordingAdapter implements UniversityServiceAdapter {
  UniversityIdentity? connectedWith;
  String? connectedWithDisplayName;
  final List<UniversityIdentity> connections = <UniversityIdentity>[];
  int disconnects = 0;
  Object? connectError;
  Object? disconnectError;
  final Set<String> rejectedIdentifiers = <String>{};
  Completer<void>? connectStarted;
  Completer<void>? connectGate;

  @override
  Future<void> connect(
    UniversityIdentity identity, {
    String? displayName,
  }) async {
    connectStarted?.complete();
    final Future<void>? pending = connectGate?.future;
    if (pending != null) await pending;
    if (connectError != null ||
        rejectedIdentifiers.contains(identity.identifier)) {
      throw connectError ?? StateError('rejected');
    }
    connections.add(identity);
    connectedWith = identity;
    connectedWithDisplayName = displayName;
  }

  @override
  Future<void> disconnect() async {
    if (disconnectError != null) throw disconnectError!;
    disconnects++;
    connectedWith = null;
    connectedWithDisplayName = null;
  }
}

const HsaKiCredential _hsaKiCredential = HsaKiCredential(
  token: 'tok-1',
  tokenId: '7',
  username: 'student@hs-anhalt.de',
);

class _MemoryHsaKiCredentialStore implements HsaKiCredentialStore {
  HsaKiCredential? value;

  @override
  Future<HsaKiCredential?> read() async => value;

  @override
  Future<void> write(HsaKiCredential credential) async => value = credential;

  @override
  Future<void> clear() async => value = null;
}

/// HAWKI as seen by the real HSA-GPT controller: it either rejects every
/// login or mints [_hsaKiCredential].
class _HsaKiGateway implements HsaKiGateway {
  _HsaKiGateway({this.rejectLogin = false});

  final bool rejectLogin;
  int connectCalls = 0;

  @override
  Future<HsaKiCredential> connect({
    required String username,
    required String password,
  }) async {
    connectCalls++;
    if (rejectLogin) {
      throw const HsaKiFailure(HsaKiFailureKind.invalidCredentials);
    }
    return _hsaKiCredential;
  }

  @override
  Future<void> revoke(
    HsaKiCredential credential, {
    required String password,
  }) async {}

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

ProviderContainer _container(
  _MemoryIdentityStore store,
  Map<DirectService, _RecordingAdapter> adapters, {
  UniversityServiceConnectionSnapshot? snapshot,
  List<Override> extraOverrides = const <Override>[],
}) => ProviderContainer(
  overrides: <Override>[
    ...extraOverrides,
    universityIdentityStoreProvider.overrideWithValue(store),
    if (snapshot != null)
      universityServiceConnectionSnapshotProvider.overrideWithValue(snapshot),
    for (final MapEntry<DirectService, _RecordingAdapter> entry
        in adapters.entries)
      universityServiceAdapterProvider(
        entry.key,
      ).overrideWithValue(entry.value),
  ],
);

void main() {
  test(
    'operation gate deterministically drains work and blocks the deletion race',
    () async {
      final UniversityServiceOperationGate gate =
          UniversityServiceOperationGate();
      final Completer<void> operationStarted = Completer<void>();
      final Completer<void> releaseOperation = Completer<void>();
      final Completer<void> deletionAcquired = Completer<void>();
      final List<String> events = <String>[];

      final Future<void> operation = gate.run<void>(() async {
        events.add('operation-started');
        operationStarted.complete();
        await releaseOperation.future;
        events.add('operation-finished');
      });
      await operationStarted.future;

      final Future<void> deletion = gate.beginCompleteDeletion().then((_) {
        events.add('deletion-acquired');
        deletionAcquired.complete();
      });

      var blockedOperationInvoked = false;
      await expectLater(
        gate.run<void>(() async {
          blockedOperationInvoked = true;
        }),
        throwsA(
          isA<UniversityAccountFailure>().having(
            (UniversityAccountFailure failure) => failure.kind,
            'kind',
            UniversityAccountFailureKind.operationBlocked,
          ),
        ),
      );
      expect(blockedOperationInvoked, isFalse);
      expect(deletionAcquired.isCompleted, isFalse);

      releaseOperation.complete();
      await operation;
      await deletion;
      expect(events, <String>[
        'operation-started',
        'operation-finished',
        'deletion-acquired',
      ]);

      await expectLater(
        gate.run<void>(() async {
          blockedOperationInvoked = true;
        }),
        throwsA(
          isA<UniversityAccountFailure>().having(
            (UniversityAccountFailure failure) => failure.kind,
            'kind',
            UniversityAccountFailureKind.operationBlocked,
          ),
        ),
      );
      expect(blockedOperationInvoked, isFalse);

      gate.finishCompleteDeletion();
      await gate.run<void>(() async {
        events.add('post-deletion-operation');
      });
      expect(events.last, 'post-deletion-operation');
    },
  );

  test(
    'first connection validates before retaining the shared identity',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore();
      final _RecordingAdapter mail = _RecordingAdapter();
      final ProviderContainer container = _container(
        store,
        <DirectService, _RecordingAdapter>{DirectService.mail: mail},
      );
      addTearDown(container.dispose);

      await container
          .read(universityServiceConnectorProvider)
          .connectAndRetain(DirectService.mail, _identity);

      expect(mail.connectedWith, _identity);
      expect(store.value, _identity);
      expect(store.writes, 1);
    },
  );

  test('a supplied identity can connect without being retained', () async {
    final _MemoryIdentityStore store = _MemoryIdentityStore();
    final _RecordingAdapter mail = _RecordingAdapter();
    final ProviderContainer container = _container(
      store,
      <DirectService, _RecordingAdapter>{DirectService.mail: mail},
    );
    addTearDown(container.dispose);

    await container
        .read(universityServiceConnectorProvider)
        .connectWithIdentity(DirectService.mail, _identity);

    expect(mail.connectedWith, _identity);
    expect(store.value, isNull);
    expect(store.writes, 0);
  });

  test(
    'changing the retained identity wipes every service and reconnects the previously linked ones',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..value = _identity;
      final Map<DirectService, _RecordingAdapter> adapters =
          <DirectService, _RecordingAdapter>{
            for (final DirectService service in DirectService.values)
              service: _RecordingAdapter(),
          };
      final ProviderContainer container = _container(
        store,
        adapters,
        snapshot: const UniversityServiceConnectionSnapshot(
          connected: <DirectService>{DirectService.mail, DirectService.moodle},
          mailDisplayName: 'Max Mustermensch',
        ),
      );
      addTearDown(container.dispose);

      final UniversityServiceConnectionResult result = await container
          .read(universityServiceConnectorProvider)
          .replaceIdentityAndReconnect(
            DirectService.grades,
            _replacementIdentity,
          );

      expect(store.value, _replacementIdentity);
      expect(result.identityChanged, isTrue);
      expect(result.failedReconnections, isEmpty);
      expect(result.reconnectedServices, <DirectService>{
        DirectService.mail,
        DirectService.moodle,
      });
      expect(adapters[DirectService.mail]!.disconnects, 1);
      expect(adapters[DirectService.moodle]!.disconnects, 1);
      expect(adapters[DirectService.grades]!.disconnects, 0);
      expect(adapters[DirectService.grades]!.connections, <UniversityIdentity>[
        _replacementIdentity,
      ]);
      expect(
        adapters[DirectService.mail]!.connectedWithDisplayName,
        'Max Mustermensch',
      );
      expect(adapters[DirectService.mail]!.connectedWith, _replacementIdentity);
      expect(
        adapters[DirectService.moodle]!.connectedWith,
        _replacementIdentity,
      );
    },
  );

  test(
    'a failed reconnect is returned per service and never revives its old connection',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..value = _identity;
      final Map<DirectService, _RecordingAdapter> adapters =
          <DirectService, _RecordingAdapter>{
            for (final DirectService service in DirectService.values)
              service: _RecordingAdapter(),
          };
      adapters[DirectService.moodle]!.rejectedIdentifiers.add(
        _replacementIdentity.identifier,
      );
      final ProviderContainer container = _container(
        store,
        adapters,
        snapshot: const UniversityServiceConnectionSnapshot(
          connected: <DirectService>{DirectService.mail, DirectService.moodle},
        ),
      );
      addTearDown(container.dispose);

      final UniversityServiceConnectionResult result = await container
          .read(universityServiceConnectorProvider)
          .replaceIdentityAndReconnect(
            DirectService.grades,
            _replacementIdentity,
          );

      expect(store.value, _replacementIdentity);
      expect(result.reconnectedServices, <DirectService>{DirectService.mail});
      expect(result.failedReconnections, <DirectService>{DirectService.moodle});
      expect(adapters[DirectService.moodle]!.connections, isEmpty);
      expect(adapters[DirectService.moodle]!.connectedWith, isNull);
      expect(adapters[DirectService.moodle]!.disconnects, 1);
    },
  );

  test(
    'revalidating the unchanged identity never wipes other services',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..value = _identity;
      final Map<DirectService, _RecordingAdapter> adapters =
          <DirectService, _RecordingAdapter>{
            for (final DirectService service in DirectService.values)
              service: _RecordingAdapter(),
          };
      final ProviderContainer container = _container(
        store,
        adapters,
        snapshot: const UniversityServiceConnectionSnapshot(
          connected: <DirectService>{DirectService.mail, DirectService.moodle},
        ),
      );
      addTearDown(container.dispose);

      final UniversityServiceConnectionResult result = await container
          .read(universityServiceConnectorProvider)
          .replaceIdentityAndReconnect(DirectService.grades, _identity);

      expect(result.identityChanged, isFalse);
      expect(store.writes, 0);
      expect(adapters[DirectService.grades]!.connectedWith, _identity);
      for (final _RecordingAdapter adapter in adapters.values) {
        expect(adapter.disconnects, 0);
      }
    },
  );

  test(
    'rejected replacement credentials leave the old identity and services untouched',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..value = _identity;
      final Map<DirectService, _RecordingAdapter> adapters =
          <DirectService, _RecordingAdapter>{
            for (final DirectService service in DirectService.values)
              service: _RecordingAdapter(),
          };
      adapters[DirectService.grades]!.rejectedIdentifiers.add(
        _replacementIdentity.identifier,
      );
      final ProviderContainer container = _container(
        store,
        adapters,
        snapshot: const UniversityServiceConnectionSnapshot(
          connected: <DirectService>{DirectService.mail, DirectService.moodle},
        ),
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(universityServiceConnectorProvider)
            .replaceIdentityAndReconnect(
              DirectService.grades,
              _replacementIdentity,
            ),
        throwsStateError,
      );

      expect(store.value, _identity);
      expect(store.writes, 0);
      for (final _RecordingAdapter adapter in adapters.values) {
        expect(adapter.disconnects, 0);
      }
    },
  );

  test(
    'a cleanup failure restores the old service snapshot and keeps the old identity',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..value = _identity;
      final Map<DirectService, _RecordingAdapter> adapters =
          <DirectService, _RecordingAdapter>{
            for (final DirectService service in DirectService.values)
              service: _RecordingAdapter(),
          };
      adapters[DirectService.moodle]!.disconnectError = StateError(
        'wipe failed',
      );
      final ProviderContainer container = _container(
        store,
        adapters,
        snapshot: const UniversityServiceConnectionSnapshot(
          connected: <DirectService>{DirectService.mail, DirectService.moodle},
        ),
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(universityServiceConnectorProvider)
            .replaceIdentityAndReconnect(
              DirectService.grades,
              _replacementIdentity,
            ),
        throwsA(
          isA<UniversityAccountFailure>().having(
            (UniversityAccountFailure failure) => failure.kind,
            'kind',
            UniversityAccountFailureKind.accountChangeCleanupIncomplete,
          ),
        ),
      );

      expect(store.value, _identity);
      expect(adapters[DirectService.grades]!.disconnects, 1);
      expect(adapters[DirectService.mail]!.connectedWith, _identity);
      expect(adapters[DirectService.moodle]!.connectedWith, _identity);
    },
  );

  test(
    'a failed central replacement restores both central identity and old services',
    () async {
      final StateError retentionError = StateError('transient write failure');
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..value = _identity
        ..nextWriteError = retentionError;
      final Map<DirectService, _RecordingAdapter> adapters =
          <DirectService, _RecordingAdapter>{
            for (final DirectService service in DirectService.values)
              service: _RecordingAdapter(),
          };
      final ProviderContainer container = _container(
        store,
        adapters,
        snapshot: const UniversityServiceConnectionSnapshot(
          connected: <DirectService>{DirectService.mail},
        ),
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(universityServiceConnectorProvider)
            .replaceIdentityAndReconnect(
              DirectService.grades,
              _replacementIdentity,
            ),
        throwsA(same(retentionError)),
      );

      expect(store.value, _identity);
      expect(store.writes, 2, reason: 'failed replacement plus old restore');
      expect(adapters[DirectService.grades]!.disconnects, 1);
      expect(adapters[DirectService.mail]!.connectedWith, _identity);
    },
  );

  test(
    'failed central retention compensates through the canonical disconnect',
    () async {
      final StateError retentionError = StateError('secure store unavailable');
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..writeError = retentionError;
      final _RecordingAdapter mail = _RecordingAdapter();
      final ProviderContainer container = _container(
        store,
        <DirectService, _RecordingAdapter>{DirectService.mail: mail},
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(universityServiceConnectorProvider)
            .connectAndRetain(DirectService.mail, _identity),
        throwsA(same(retentionError)),
      );

      expect(mail.disconnects, 1);
      expect(store.value, isNull);
    },
  );

  test('a failed compensation is reported as an incomplete rollback', () async {
    final _MemoryIdentityStore store = _MemoryIdentityStore()
      ..writeError = StateError('secure store unavailable');
    final _RecordingAdapter mail = _RecordingAdapter()
      ..disconnectError = StateError('wipe failed');
    final ProviderContainer container = _container(
      store,
      <DirectService, _RecordingAdapter>{DirectService.mail: mail},
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(universityServiceConnectorProvider)
          .connectAndRetain(DirectService.mail, _identity),
      throwsA(
        isA<UniversityAccountFailure>().having(
          (UniversityAccountFailure failure) => failure.kind,
          'kind',
          UniversityAccountFailureKind.connectionRollbackIncomplete,
        ),
      ),
    );
  });

  for (final DirectService service in DirectService.values) {
    test(
      'complete deletion waits for manual ${service.name} setup and wipes every service',
      () async {
        final Completer<void> connectStarted = Completer<void>();
        final Completer<void> releaseConnect = Completer<void>();
        final _MemoryIdentityStore store = _MemoryIdentityStore();
        final Map<DirectService, _RecordingAdapter> adapters =
            <DirectService, _RecordingAdapter>{
              for (final DirectService candidate in DirectService.values)
                candidate: _RecordingAdapter(),
            };
        adapters[service]!
          ..connectStarted = connectStarted
          ..connectGate = releaseConnect;
        final ProviderContainer container = _container(store, adapters);
        addTearDown(container.dispose);

        final Future<void> connecting = container
            .read(universityServiceConnectorProvider)
            .connectAndRetain(service, _identity);
        await connectStarted.future;
        final Future<SignOutEverywhereResult> deleting = container
            .read(signOutEverywhereServiceProvider)
            .signOutAll();

        releaseConnect.complete();
        await connecting;
        final SignOutEverywhereResult result = await deleting;

        expect(result.isFullSuccess, isTrue);
        expect(store.value, isNull);
        for (final _RecordingAdapter adapter in adapters.values) {
          expect(adapter.disconnects, 1);
        }
      },
    );
  }

  test('a password HAWKI rejects is never retained through the real HSA-GPT '
      'controller', () async {
    final _MemoryIdentityStore store = _MemoryIdentityStore();
    final _HsaKiGateway gateway = _HsaKiGateway(rejectLogin: true);
    final _MemoryHsaKiCredentialStore hsaKiStore =
        _MemoryHsaKiCredentialStore();
    final ProviderContainer container = _container(
      store,
      const <DirectService, _RecordingAdapter>{},
      extraOverrides: <Override>[
        hsaKiGatewayProvider.overrideWithValue(gateway),
        hsaKiCredentialStoreProvider.overrideWithValue(hsaKiStore),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(hsaKiConsentGateProvider)
          .runWithConsent(
            () => container
                .read(universityServiceConnectorProvider)
                .connectAndRetain(DirectService.hsaKi, _identity),
          ),
      throwsA(const HsaKiFailure(HsaKiFailureKind.invalidCredentials)),
    );

    expect(gateway.connectCalls, 1);
    expect(store.value, isNull);
    expect(store.writes, 0);
    expect(hsaKiStore.value, isNull);
  });

  test(
    'an already connected HSA-GPT never vouches for an unchecked replacement '
    'identity',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..value = _identity;
      final Map<DirectService, _RecordingAdapter> adapters =
          <DirectService, _RecordingAdapter>{
            DirectService.mail: _RecordingAdapter(),
            DirectService.moodle: _RecordingAdapter(),
            DirectService.grades: _RecordingAdapter(),
            DirectService.nextcloud: _RecordingAdapter(),
          };
      final _HsaKiGateway gateway = _HsaKiGateway(rejectLogin: true);
      final _MemoryHsaKiCredentialStore hsaKiStore =
          _MemoryHsaKiCredentialStore()..value = _hsaKiCredential;
      final ProviderContainer container = _container(
        store,
        adapters,
        snapshot: const UniversityServiceConnectionSnapshot(
          connected: <DirectService>{
            DirectService.mail,
            DirectService.grades,
            DirectService.hsaKi,
          },
        ),
        extraOverrides: <Override>[
          hsaKiGatewayProvider.overrideWithValue(gateway),
          hsaKiCredentialStoreProvider.overrideWithValue(hsaKiStore),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(hsaKiConsentGateProvider)
            .runWithConsent(
              () => container
                  .read(universityServiceConnectorProvider)
                  .replaceIdentityAndReconnect(
                    DirectService.hsaKi,
                    _replacementIdentity,
                  ),
            ),
        throwsA(const HsaKiFailure(HsaKiFailureKind.invalidCredentials)),
      );

      expect(gateway.connectCalls, 1);
      expect(store.value, _identity);
      expect(store.writes, 0);
      expect(hsaKiStore.value, same(_hsaKiCredential));
      for (final _RecordingAdapter adapter in adapters.values) {
        expect(adapter.disconnects, 0);
      }
    },
  );

  test(
    'HSA-GPT never mints a token without its dedicated consent, even through '
    'the generic connector',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore();
      final _HsaKiGateway gateway = _HsaKiGateway();
      final _MemoryHsaKiCredentialStore hsaKiStore =
          _MemoryHsaKiCredentialStore();
      final ProviderContainer container = _container(
        store,
        const <DirectService, _RecordingAdapter>{},
        extraOverrides: <Override>[
          hsaKiGatewayProvider.overrideWithValue(gateway),
          hsaKiCredentialStoreProvider.overrideWithValue(hsaKiStore),
        ],
      );
      addTearDown(container.dispose);
      final UniversityServiceConnector connector = container.read(
        universityServiceConnectorProvider,
      );

      await expectLater(
        connector.connectAndRetain(DirectService.hsaKi, _identity),
        throwsA(const HsaKiFailure(HsaKiFailureKind.consentRequired)),
      );
      expect(gateway.connectCalls, 0);
      expect(store.writes, 0);
      expect(hsaKiStore.value, isNull);

      await container
          .read(hsaKiConsentGateProvider)
          .runWithConsent(
            () => connector.connectAndRetain(DirectService.hsaKi, _identity),
          );
      expect(gateway.connectCalls, 1);
      expect(store.value, _identity);
      expect(hsaKiStore.value, same(_hsaKiCredential));
      expect(container.read(hsaKiConsentGateProvider).isGranted, isFalse);
    },
  );

  test('an account update re-establishes an already consented HSA-GPT link '
      'without a new consent prompt', () async {
    final _MemoryIdentityStore store = _MemoryIdentityStore()
      ..value = _identity;
    final Map<DirectService, _RecordingAdapter> adapters =
        <DirectService, _RecordingAdapter>{
          DirectService.mail: _RecordingAdapter(),
          DirectService.moodle: _RecordingAdapter(),
          DirectService.grades: _RecordingAdapter(),
          DirectService.nextcloud: _RecordingAdapter(),
        };
    final _HsaKiGateway gateway = _HsaKiGateway();
    final _MemoryHsaKiCredentialStore hsaKiStore = _MemoryHsaKiCredentialStore()
      ..value = _hsaKiCredential;
    final ProviderContainer container = _container(
      store,
      adapters,
      snapshot: const UniversityServiceConnectionSnapshot(
        connected: <DirectService>{DirectService.hsaKi},
      ),
      extraOverrides: <Override>[
        hsaKiGatewayProvider.overrideWithValue(gateway),
        hsaKiCredentialStoreProvider.overrideWithValue(hsaKiStore),
      ],
    );
    addTearDown(container.dispose);

    final UniversityServiceConnectionResult result = await container
        .read(universityServiceConnectorProvider)
        .replaceIdentityAndReconnect(
          DirectService.grades,
          _replacementIdentity,
        );

    expect(result.failedReconnections, isEmpty);
    expect(result.reconnectedServices, <DirectService>{DirectService.hsaKi});
    expect(gateway.connectCalls, 1);
    expect(hsaKiStore.value, isNotNull);
    expect(container.read(hsaKiConsentGateProvider).isGranted, isFalse);
  });

  test('failed validation never stores the central password', () async {
    final _MemoryIdentityStore store = _MemoryIdentityStore();
    final _RecordingAdapter grades = _RecordingAdapter()
      ..connectError = StateError('rejected');
    final ProviderContainer container = _container(
      store,
      <DirectService, _RecordingAdapter>{DirectService.grades: grades},
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(universityServiceConnectorProvider)
          .connectAndRetain(DirectService.grades, _identity),
      throwsStateError,
    );
    expect(store.value, isNull);
    expect(store.writes, 0);
  });

  test(
    '+ reads the password just in time and creates only that service session',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..value = _identity;
      final _RecordingAdapter moodle = _RecordingAdapter();
      final ProviderContainer container = _container(
        store,
        <DirectService, _RecordingAdapter>{DirectService.moodle: moodle},
      );
      addTearDown(container.dispose);

      await container
          .read(universityServiceConnectorProvider)
          .connect(DirectService.moodle);

      expect(moodle.connectedWith, _identity);
      expect(store.value, _identity);
    },
  );

  test(
    '− disconnects only the selected service and retains central identity',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..value = _identity;
      final _RecordingAdapter mail = _RecordingAdapter();
      final _RecordingAdapter grades = _RecordingAdapter();
      final ProviderContainer container = _container(
        store,
        <DirectService, _RecordingAdapter>{
          DirectService.mail: mail,
          DirectService.grades: grades,
        },
      );
      addTearDown(container.dispose);

      await container
          .read(universityServiceConnectorProvider)
          .disconnect(DirectService.mail);

      expect(mail.disconnects, 1);
      expect(grades.disconnects, 0);
      expect(store.value, _identity);
      expect(store.clears, 0);
    },
  );

  test(
    'production adapters map the identity to all three canonical login paths',
    () async {
      final _MemoryIdentityStore identityStore = _MemoryIdentityStore()
        ..value = _identity;
      final InMemoryMailCredentialStore mailStore =
          InMemoryMailCredentialStore();
      final FakeMailGateway mailGateway = FakeMailGateway();
      final moodle.InMemoryMoodleTokenStore moodleTokens =
          moodle.InMemoryMoodleTokenStore();
      final grades.InMemoryGradeCredentialStore gradeStore =
          grades.InMemoryGradeCredentialStore();
      final grades.InMemoryGradePortalStore portalStore =
          grades.InMemoryGradePortalStore();
      final grades.FakeGradesGateway gradeGateway = grades.FakeGradesGateway(
        report: grades.sampleReport(),
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          universityIdentityStoreProvider.overrideWithValue(identityStore),
          mailCredentialStoreProvider.overrideWithValue(mailStore),
          mailGatewayProvider.overrideWithValue(mailGateway),
          moodleApiClientProvider.overrideWithValue(
            moodle.FakeMoodleApiClient(),
          ),
          moodleTokenStoreProvider.overrideWithValue(moodleTokens),
          moodleCacheStoreProvider.overrideWithValue(
            moodle.InMemoryMoodleCacheStore(),
          ),
          legacyQisGatewayProvider.overrideWithValue(gradeGateway),
          hisInOneGatewayProvider.overrideWithValue(gradeGateway),
          gradeCredentialStoreProvider.overrideWithValue(gradeStore),
          gradePortalStoreProvider.overrideWithValue(portalStore),
          gradeCacheStoreProvider.overrideWithValue(
            grades.InMemoryGradeCacheStore(),
          ),
          gradeClockProvider.overrideWithValue(
            grades.MutableClock(DateTime.utc(2026, 10, 1)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final UniversityServiceConnector connector = container.read(
        universityServiceConnectorProvider,
      );

      await connector.connect(DirectService.mail);
      await connector.connect(DirectService.moodle);
      await connector.connect(DirectService.grades);

      expect(mailGateway.verifyCalls, 1);
      expect(mailStore.lastWritten?.emailAddress, _identity.identifier);
      expect(mailStore.lastWritten?.password, _identity.password);
      expect(moodleTokens.token, isNotNull);
      expect(gradeStore.lastWritten?.username, _identity.identifier);
      expect(gradeStore.lastWritten?.password, _identity.password);
      expect(portalStore.lastWritten, GradePortal.hisInOne);
      expect(identityStore.value, _identity);
    },
  );

  test(
    'the mail adapter expands a bare university username to its address',
    () async {
      const UniversityIdentity byUsername = UniversityIdentity(
        identifier: 'student42',
        password: 'secret',
      );
      final _MemoryIdentityStore identityStore = _MemoryIdentityStore()
        ..value = byUsername;
      final InMemoryMailCredentialStore mailStore =
          InMemoryMailCredentialStore();
      final FakeMailGateway mailGateway = FakeMailGateway();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          universityIdentityStoreProvider.overrideWithValue(identityStore),
          mailCredentialStoreProvider.overrideWithValue(mailStore),
          mailGatewayProvider.overrideWithValue(mailGateway),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(universityServiceConnectorProvider)
          .connect(DirectService.mail);

      expect(mailGateway.verifyCalls, 1);
      expect(mailStore.lastWritten?.emailAddress, 'student42@hs-anhalt.de');
      expect(mailStore.lastWritten?.password, byUsername.password);
    },
  );

  test(
    'connect forwards an optional display name to the adapter, unmodified',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore()
        ..value = _identity;
      final _RecordingAdapter mail = _RecordingAdapter();
      final ProviderContainer container = _container(
        store,
        <DirectService, _RecordingAdapter>{DirectService.mail: mail},
      );
      addTearDown(container.dispose);

      await container
          .read(universityServiceConnectorProvider)
          .connect(DirectService.mail, displayName: 'Max Mustermensch');

      expect(mail.connectedWithDisplayName, 'Max Mustermensch');
    },
  );

  test(
    'connectAndRetain forwards an optional display name to the adapter',
    () async {
      final _MemoryIdentityStore store = _MemoryIdentityStore();
      final _RecordingAdapter mail = _RecordingAdapter();
      final ProviderContainer container = _container(
        store,
        <DirectService, _RecordingAdapter>{DirectService.mail: mail},
      );
      addTearDown(container.dispose);

      await container
          .read(universityServiceConnectorProvider)
          .connectAndRetain(
            DirectService.mail,
            _identity,
            displayName: 'Max Mustermensch',
          );

      expect(mail.connectedWithDisplayName, 'Max Mustermensch');
      expect(store.value, _identity);
    },
  );

  test(
    'the mail adapter passes a supplied display name through to its own sign-in',
    () async {
      final _MemoryIdentityStore identityStore = _MemoryIdentityStore()
        ..value = _identity;
      final InMemoryMailCredentialStore mailStore =
          InMemoryMailCredentialStore();
      final FakeMailGateway mailGateway = FakeMailGateway();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          universityIdentityStoreProvider.overrideWithValue(identityStore),
          mailCredentialStoreProvider.overrideWithValue(mailStore),
          mailGatewayProvider.overrideWithValue(mailGateway),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(universityServiceConnectorProvider)
          .connect(DirectService.mail, displayName: 'Max Mustermensch');

      expect(mailStore.lastWritten?.displayName, 'Max Mustermensch');
    },
  );
}
