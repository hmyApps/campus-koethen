// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/hsa_ki/application/hsa_ki_chat_controller.dart';
import 'package:campus_koethen/features/hsa_ki/application/hsa_ki_providers.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_account.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_chat.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_failure.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_gateway.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const HsaKiCredential _credential = HsaKiCredential(
  token: 'tok-1',
  tokenId: '7',
  username: 'mmustermann',
);

const List<HsaKiModel> _models = <HsaKiModel>[
  HsaKiModel(modelId: 'inactive-model', label: 'Alt', active: false),
  HsaKiModel(modelId: 'gpt-4', label: 'GPT-4', active: true),
];

void main() {
  test('with no stored credential, no model list is fetched', () async {
    final _Gateway gateway = _Gateway();
    final ProviderContainer container = _container(
      store: _MemoryCredentialStore(),
      gateway: gateway,
    );
    addTearDown(container.dispose);

    final HsaKiChatState state = await container.read(
      hsaKiChatControllerProvider.future,
    );

    expect(state.messages, isEmpty);
    expect(state.models, isEmpty);
    expect(gateway.listModelsCalls, 0);
  });

  test('build loads models and defaults to the active one', () async {
    final _Gateway gateway = _Gateway(models: _models);
    final ProviderContainer container = _container(
      store: _MemoryCredentialStore()..value = _credential,
      gateway: gateway,
    );
    addTearDown(container.dispose);

    final HsaKiChatState state = await container.read(
      hsaKiChatControllerProvider.future,
    );

    expect(state.models, _models);
    expect(state.selectedModelId, 'gpt-4');
  });

  test('a failed model list must not block opening the chat', () async {
    final _Gateway gateway = _Gateway(listModelsFails: true);
    final ProviderContainer container = _container(
      store: _MemoryCredentialStore()..value = _credential,
      gateway: gateway,
    );
    addTearDown(container.dispose);

    final HsaKiChatState state = await container.read(
      hsaKiChatControllerProvider.future,
    );

    expect(state.models, isEmpty);
    expect(state.selectedModelId, isNull);
  });

  test('sending without any available model is refused before a message is '
      'sent', () async {
    final _Gateway gateway = _Gateway();
    final ProviderContainer container = _container(
      store: _MemoryCredentialStore()..value = _credential,
      gateway: gateway,
    );
    addTearDown(container.dispose);
    await container.read(hsaKiChatControllerProvider.future);

    await container.read(hsaKiChatControllerProvider.notifier).send('Hallo');

    final HsaKiChatState state = container
        .read(hsaKiChatControllerProvider)
        .value!;
    expect(state.messages, isEmpty);
    expect(state.lastError, HsaKiFailureKind.portalStructureChanged);
    expect(gateway.sendMessageCalls, 0);
  });

  test('send appends the user turn optimistically, then the reply once it '
      'arrives', () async {
    final _Gateway gateway = _Gateway(models: _models, reply: 'Moin!');
    final ProviderContainer container = _container(
      store: _MemoryCredentialStore()..value = _credential,
      gateway: gateway,
    );
    addTearDown(container.dispose);
    await container.read(hsaKiChatControllerProvider.future);

    await container.read(hsaKiChatControllerProvider.notifier).send('Hallo');

    final HsaKiChatState state = container
        .read(hsaKiChatControllerProvider)
        .value!;
    expect(state.messages, hasLength(2));
    expect(state.messages[0].role, HsaKiMessageRole.user);
    expect(state.messages[0].text, 'Hallo');
    expect(state.messages[1].role, HsaKiMessageRole.assistant);
    expect(state.messages[1].text, 'Moin!');
    expect(state.isSending, isFalse);
  });

  test('a reply that arrives after the session generation advanced (e.g. the '
      'user disconnected mid-send) is discarded, never appended', () async {
    final _Gateway gateway = _Gateway(models: _models, blockSend: true);
    final ProviderContainer container = _container(
      store: _MemoryCredentialStore()..value = _credential,
      gateway: gateway,
    );
    addTearDown(container.dispose);
    await container.read(hsaKiChatControllerProvider.future);

    final Future<void> sending = container
        .read(hsaKiChatControllerProvider.notifier)
        .send('Hallo');
    await gateway.sendEntered.future;
    container.read(hsaKiSessionGenerationProvider.notifier).advance();
    gateway.releaseSend.complete();
    await sending;

    final HsaKiChatState state = container
        .read(hsaKiChatControllerProvider)
        .value!;
    expect(state.messages, hasLength(1));
    expect(state.messages.single.role, HsaKiMessageRole.user);
  });

  group('chat lifecycle (D-03)', () {
    test('a new HSA-GPT session starts with an empty chat and never sends the '
        'previous history', () async {
      final _Gateway gateway = _Gateway(models: _models, reply: 'Moin!');
      final ProviderContainer container = _container(
        store: _MemoryCredentialStore()..value = _credential,
        gateway: gateway,
      );
      addTearDown(container.dispose);
      await container.read(hsaKiChatControllerProvider.future);
      await container.read(hsaKiChatControllerProvider.notifier).send('A');
      expect(
        container.read(hsaKiChatControllerProvider).value!.messages,
        hasLength(2),
      );

      // Disconnect and reconnect (possibly another account) both advance
      // the session generation.
      container.read(hsaKiSessionGenerationProvider.notifier).advance();
      final HsaKiChatState fresh = await container.read(
        hsaKiChatControllerProvider.future,
      );
      expect(fresh.messages, isEmpty);

      await container.read(hsaKiChatControllerProvider.notifier).send('B');
      expect(gateway.sentHistories.last, hasLength(1));
      expect(gateway.sentHistories.last.single.text, 'B');
    });

    test('disconnecting mid-send never leaves the composer locked', () async {
      final _Gateway gateway = _Gateway(models: _models, blockSend: true);
      final ProviderContainer container = _container(
        store: _MemoryCredentialStore()..value = _credential,
        gateway: gateway,
      );
      addTearDown(container.dispose);
      await container.read(hsaKiChatControllerProvider.future);

      final Future<void> sending = container
          .read(hsaKiChatControllerProvider.notifier)
          .send('Hallo');
      await gateway.sendEntered.future;
      container.read(hsaKiSessionGenerationProvider.notifier).advance();
      gateway.releaseSend.complete();
      await sending;

      final HsaKiChatState state = await container.read(
        hsaKiChatControllerProvider.future,
      );
      expect(state.isSending, isFalse);
      expect(state.messages, isEmpty);
    });

    test('a failed model list is retried by the next send', () async {
      final _Gateway gateway = _Gateway(
        models: _models,
        failingModelLists: 1,
        reply: 'Moin!',
      );
      final ProviderContainer container = _container(
        store: _MemoryCredentialStore()..value = _credential,
        gateway: gateway,
      );
      addTearDown(container.dispose);
      final HsaKiChatState opened = await container.read(
        hsaKiChatControllerProvider.future,
      );
      expect(opened.models, isEmpty);

      await container.read(hsaKiChatControllerProvider.notifier).send('Hallo');

      final HsaKiChatState state = container
          .read(hsaKiChatControllerProvider)
          .value!;
      expect(gateway.listModelsCalls, 2);
      expect(state.selectedModelId, 'gpt-4');
      expect(state.messages, hasLength(2));
      expect(state.lastError, isNull);
    });

    test(
      'an unavailable keystore while opening does not brick the chat',
      () async {
        final _Gateway gateway = _Gateway(models: _models, reply: 'Moin!');
        final ProviderContainer container = _container(
          store: _MemoryCredentialStore()
            ..value = _credential
            ..failingReads = 1,
          gateway: gateway,
        );
        addTearDown(container.dispose);
        // Let the first build finish, but not Riverpod's delayed automatic
        // retry: the open chat itself has to stay usable.
        await pumpEventQueue();
        expect(container.read(hsaKiChatControllerProvider).hasValue, isTrue);

        await container
            .read(hsaKiChatControllerProvider.notifier)
            .send('Hallo');

        final HsaKiChatState state = container
            .read(hsaKiChatControllerProvider)
            .value!;
        expect(state.messages, hasLength(2));
        expect(state.isSending, isFalse);
      },
    );

    test('the history is discarded once no chat screen shows it', () async {
      final _Gateway gateway = _Gateway(models: _models, reply: 'Moin!');
      final ProviderContainer container = ProviderContainer(
        overrides: [
          hsaKiCredentialStoreProvider.overrideWithValue(
            _MemoryCredentialStore()..value = _credential,
          ),
          hsaKiGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final ProviderSubscription<AsyncValue<HsaKiChatState>> screen = container
          .listen<AsyncValue<HsaKiChatState>>(
            hsaKiChatControllerProvider,
            (_, _) {},
          );
      await container.read(hsaKiChatControllerProvider.future);
      await container.read(hsaKiChatControllerProvider.notifier).send('Hallo');

      screen.close();
      await container.pump();

      container.listen<AsyncValue<HsaKiChatState>>(
        hsaKiChatControllerProvider,
        (_, _) {},
      );
      final HsaKiChatState reopened = await container.read(
        hsaKiChatControllerProvider.future,
      );
      expect(reopened.messages, isEmpty);
    });
  });
}

/// The chat is auto-disposed; like the open chat screen, every test keeps
/// one listener on it.
ProviderContainer _container({
  required _MemoryCredentialStore store,
  required _Gateway gateway,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      hsaKiCredentialStoreProvider.overrideWithValue(store),
      hsaKiGatewayProvider.overrideWithValue(gateway),
    ],
  );
  container.listen<AsyncValue<HsaKiChatState>>(
    hsaKiChatControllerProvider,
    (_, _) {},
  );
  return container;
}

class _MemoryCredentialStore implements HsaKiCredentialStore {
  HsaKiCredential? value;

  /// The next n reads fail like an unavailable keystore.
  int failingReads = 0;

  @override
  Future<HsaKiCredential?> read() async {
    if (failingReads > 0) {
      failingReads--;
      throw const HsaKiFailure(HsaKiFailureKind.secureStorageUnavailable);
    }
    return value;
  }

  @override
  Future<void> write(HsaKiCredential credential) async => value = credential;

  @override
  Future<void> clear() async => value = null;
}

class _Gateway implements HsaKiGateway {
  _Gateway({
    this.models = const <HsaKiModel>[],
    this.listModelsFails = false,
    this.failingModelLists = 0,
    this.reply = '',
    this.blockSend = false,
  });

  final List<HsaKiModel> models;
  final bool listModelsFails;

  /// Only the first n model lists fail.
  int failingModelLists;
  final List<List<HsaKiMessage>> sentHistories = <List<HsaKiMessage>>[];
  final String reply;
  final bool blockSend;
  final Completer<void> sendEntered = Completer<void>();
  final Completer<void> releaseSend = Completer<void>();
  var listModelsCalls = 0;
  var sendMessageCalls = 0;

  @override
  Future<HsaKiCredential> connect({
    required String username,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<void> revoke(
    HsaKiCredential credential, {
    required String password,
  }) async {}

  @override
  Future<List<HsaKiModel>> listModels(HsaKiCredential credential) async {
    listModelsCalls++;
    if (listModelsFails) throw StateError('unavailable');
    if (failingModelLists > 0) {
      failingModelLists--;
      throw const HsaKiFailure(HsaKiFailureKind.portalUnavailable);
    }
    return models;
  }

  @override
  Future<String> sendMessage(
    HsaKiCredential credential, {
    required String modelId,
    required List<HsaKiMessage> messages,
  }) async {
    sendMessageCalls++;
    sentHistories.add(List<HsaKiMessage>.of(messages));
    if (!sendEntered.isCompleted) sendEntered.complete();
    if (blockSend) await releaseSend.future;
    return reply;
  }
}
