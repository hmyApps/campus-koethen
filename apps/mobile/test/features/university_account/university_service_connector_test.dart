// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/settings/domain/direct_service.dart';
import 'package:campus_koethen/features/grades/application/grades_providers.dart';
import 'package:campus_koethen/features/grades/domain/grade_portal.dart';
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

class _MemoryIdentityStore implements UniversityIdentityStore {
  UniversityIdentity? value;
  int writes = 0;
  int clears = 0;

  @override
  Future<UniversityIdentity?> read() async => value;
  @override
  Future<void> write(UniversityIdentity identity) async {
    writes++;
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
  int disconnects = 0;
  Object? connectError;
  Object? disconnectError;

  @override
  Future<void> connect(
    UniversityIdentity identity, {
    String? displayName,
  }) async {
    if (connectError != null) throw connectError!;
    connectedWith = identity;
    connectedWithDisplayName = displayName;
  }

  @override
  Future<void> disconnect() async {
    if (disconnectError != null) throw disconnectError!;
    disconnects++;
  }
}

ProviderContainer _container(
  _MemoryIdentityStore store,
  Map<DirectService, _RecordingAdapter> adapters,
) => ProviderContainer(
  overrides: <Override>[
    universityIdentityStoreProvider.overrideWithValue(store),
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
