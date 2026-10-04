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

  test('sending without a selected model is refused before any gateway call', () async {
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

  test(
    'send appends the user turn optimistically, then the reply once it '
    'arrives',
    () async {
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
    },
  );

  test(
    'a reply that arrives after the session generation advanced (e.g. the '
    'user disconnected mid-send) is discarded, never appended',
    () async {
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
    },
  );
}

ProviderContainer _container({
  required _MemoryCredentialStore store,
  required _Gateway gateway,
}) => ProviderContainer(
  overrides: [
    hsaKiCredentialStoreProvider.overrideWithValue(store),
    hsaKiGatewayProvider.overrideWithValue(gateway),
  ],
);

class _MemoryCredentialStore implements HsaKiCredentialStore {
  HsaKiCredential? value;

  @override
  Future<HsaKiCredential?> read() async => value;

  @override
  Future<void> write(HsaKiCredential credential) async => value = credential;

  @override
  Future<void> clear() async => value = null;
}

class _Gateway implements HsaKiGateway {
  _Gateway({
    this.models = const <HsaKiModel>[],
    this.listModelsFails = false,
    this.reply = '',
    this.blockSend = false,
  });

  final List<HsaKiModel> models;
  final bool listModelsFails;
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
  Future<void> revoke(HsaKiCredential credential, {required String password}) async {}

  @override
  Future<List<HsaKiModel>> listModels(HsaKiCredential credential) async {
    listModelsCalls++;
    if (listModelsFails) throw StateError('unavailable');
    return models;
  }

  @override
  Future<String> sendMessage(
    HsaKiCredential credential, {
    required String modelId,
    required List<HsaKiMessage> messages,
  }) async {
    sendMessageCalls++;
    if (!sendEntered.isCompleted) sendEntered.complete();
    if (blockSend) await releaseSend.future;
    return reply;
  }
}
