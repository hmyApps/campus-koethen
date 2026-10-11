// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/chat/application/chat_providers.dart';
import 'package:campus_koethen/features/chat/domain/chat_models.dart';
import 'package:campus_koethen/features/chat/domain/matrix_failure.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_matrix_gateway.dart';

void main() {
  late FakeMatrixGateway gateway;

  ProviderContainer containerFor() {
    final ProviderContainer container = ProviderContainer(
      overrides: [matrixGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => gateway = FakeMatrixGateway());

  const ChatRoomSummary demoRoom = ChatRoomSummary(
    id: '!demo:matrix.example.test',
    title: 'Demo-Gruppe',
    isDirect: false,
    isEncrypted: true,
    isInvite: false,
    unreadCount: 1,
  );

  test('restores the stored session when first read', () async {
    gateway.stored = FakeMatrixGateway.demoAccount;
    final ProviderContainer container = containerFor();

    expect(
      await container.read(chatSessionControllerProvider.future),
      FakeMatrixGateway.demoAccount,
    );
  });

  test('a failed restore is an error, not "signed out"', () async {
    gateway.restoreFailure = const MatrixFailure(
      MatrixFailureKind.databaseUnavailable,
    );
    final ProviderContainer container = containerFor();

    await expectLater(
      container.read(chatSessionControllerProvider.future),
      throwsA(isA<MatrixFailure>()),
    );
    expect(container.read(chatSessionControllerProvider).hasError, isTrue);
  });

  test('login stores the account in state, the password nowhere', () async {
    final ProviderContainer container = containerFor();
    await container.read(chatSessionControllerProvider.future);

    await container
        .read(chatSessionControllerProvider.notifier)
        .login(username: 'demo-user', password: 'demo-password');

    expect(
      container.read(chatSessionControllerProvider).value,
      FakeMatrixGateway.demoAccount,
    );
    expect(
      container.read(chatSessionControllerProvider).value.toString(),
      isNot(contains('demo-password')),
    );
  });

  test('a failed login is reported in state and stays signed out', () async {
    gateway.loginFailure = const MatrixFailure(
      MatrixFailureKind.invalidCredentials,
    );
    final ProviderContainer container = containerFor();
    await container.read(chatSessionControllerProvider.future);

    await container
        .read(chatSessionControllerProvider.notifier)
        .login(username: 'demo-user', password: 'wrong');

    final AsyncValue<MatrixAccount?> state = container.read(
      chatSessionControllerProvider,
    );
    expect(
      state.error,
      const MatrixFailure(MatrixFailureKind.invalidCredentials),
    );
    expect(gateway.stored, isNull);
  });

  test('a second login while one runs is ignored', () async {
    gateway.loginGate = Completer<void>();
    final ProviderContainer container = containerFor();
    await container.read(chatSessionControllerProvider.future);
    final ChatSessionController controller = container.read(
      chatSessionControllerProvider.notifier,
    );

    final Future<void> first = controller.login(
      username: 'demo-user',
      password: 'demo-password',
    );
    await controller.login(username: 'demo-user', password: 'demo-password');
    gateway.loginGate!.complete();
    await first;

    expect(gateway.logins, hasLength(1));
  });

  test('logout signs out and ends signed out', () async {
    gateway.stored = FakeMatrixGateway.demoAccount;
    final ProviderContainer container = containerFor();
    await container.read(chatSessionControllerProvider.future);

    await container.read(chatSessionControllerProvider.notifier).logout();

    expect(gateway.logouts, 1);
    expect(container.read(chatSessionControllerProvider).value, isNull);
  });

  test('a logout whose local wipe failed is reported and retryable', () async {
    gateway.stored = FakeMatrixGateway.demoAccount;
    gateway.logoutFailure = const MatrixFailure(
      MatrixFailureKind.secureStorageUnavailable,
    );
    final ProviderContainer container = containerFor();
    await container.read(chatSessionControllerProvider.future);

    await expectLater(
      container.read(chatSessionControllerProvider.notifier).logout(),
      throwsA(isA<MatrixFailure>()),
    );
    expect(container.read(chatSessionControllerProvider).hasError, isTrue);
  });

  test('a session the server ended is wiped and explained', () async {
    gateway.stored = FakeMatrixGateway.demoAccount;
    final ProviderContainer container = containerFor();
    final ProviderSubscription<AsyncValue<MatrixAccount?>> session = container
        .listen(chatSessionControllerProvider, (_, _) {});
    addTearDown(session.close);
    await container.read(chatSessionControllerProvider.future);

    gateway.stored = null;
    gateway.emitChange();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(gateway.logouts, 1);
    expect(
      session.read().error,
      const MatrixFailure(MatrixFailureKind.sessionEnded),
    );
  });

  test('its own logout is not mistaken for an ended session', () async {
    gateway.stored = FakeMatrixGateway.demoAccount;
    final ProviderContainer container = containerFor();
    await container.read(chatSessionControllerProvider.future);

    await container.read(chatSessionControllerProvider.notifier).logout();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.logouts, 1);
    expect(container.read(chatSessionControllerProvider).value, isNull);
    expect(container.read(chatSessionControllerProvider).hasError, isFalse);
  });

  test('the room list follows the gateway', () async {
    gateway.stored = FakeMatrixGateway.demoAccount;
    final ProviderContainer container = containerFor();
    final ProviderSubscription<AsyncValue<List<ChatRoomSummary>>> rooms =
        container.listen(chatRoomsProvider, (_, _) {});
    addTearDown(rooms.close);

    expect(await container.read(chatRoomsProvider.future), isEmpty);

    gateway.roomList = <ChatRoomSummary>[demoRoom];
    gateway.emitChange();
    await Future<void>.delayed(Duration.zero);

    expect(rooms.read().value, <ChatRoomSummary>[demoRoom]);
  });

  test('the room list is empty while signed out', () async {
    gateway.roomList = <ChatRoomSummary>[demoRoom];
    final ProviderContainer container = containerFor();
    final ProviderSubscription<AsyncValue<List<ChatRoomSummary>>> rooms =
        container.listen(chatRoomsProvider, (_, _) {});
    addTearDown(rooms.close);

    expect(await container.read(chatRoomsProvider.future), isEmpty);
  });
}
