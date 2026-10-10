// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/hsa_ki_account.dart';
import '../domain/hsa_ki_chat.dart';
import '../domain/hsa_ki_failure.dart';
import 'hsa_ki_providers.dart';

/// One chat screen's worth of state. HAWKI's external endpoint keeps no
/// conversation of its own (confirmed from `StreamController::
/// handleExternalRequest`'s source — stateless in, stateless out), so this
/// history exists only here, in memory, for as long as the screen is open.
class HsaKiChatState {
  const HsaKiChatState({
    this.messages = const <HsaKiMessage>[],
    this.models = const <HsaKiModel>[],
    this.selectedModelId,
    this.isSending = false,
    this.lastError,
  });

  final List<HsaKiMessage> messages;
  final List<HsaKiModel> models;
  final String? selectedModelId;
  final bool isSending;
  final HsaKiFailureKind? lastError;

  HsaKiChatState copyWith({
    List<HsaKiMessage>? messages,
    List<HsaKiModel>? models,
    String? selectedModelId,
    bool? isSending,
    HsaKiFailureKind? lastError,
    bool clearError = false,
  }) => HsaKiChatState(
    messages: messages ?? this.messages,
    models: models ?? this.models,
    selectedModelId: selectedModelId ?? this.selectedModelId,
    isSending: isSending ?? this.isSending,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );
}

/// The chat lives only as long as a chat screen shows it (auto-dispose) and
/// only within one HSA-GPT session: connecting, rotating the token or
/// disconnecting advances [hsaKiSessionGenerationProvider], which rebuilds
/// this controller with an empty history. A conversation of one account can
/// thus never be sent with another account's token, and a request that was
/// still running when the session ended cannot leave the composer locked.
class HsaKiChatController extends AsyncNotifier<HsaKiChatState> {
  @override
  Future<HsaKiChatState> build() async {
    ref.watch(hsaKiSessionGenerationProvider);
    try {
      final HsaKiCredential? credential = await ref
          .read(hsaKiCredentialStoreProvider)
          .read();
      if (credential == null) return const HsaKiChatState();
      final List<HsaKiModel> models = await ref
          .read(hsaKiGatewayProvider)
          .listModels(credential);
      return HsaKiChatState(
        models: models,
        selectedModelId: _defaultModelId(models),
      );
    } catch (_) {
      // Neither a failed model list nor a briefly unavailable keystore may
      // block the chat: [send] reads the credential again and retries the
      // model list itself.
      return const HsaKiChatState();
    }
  }

  static String? _defaultModelId(List<HsaKiModel> models) {
    final HsaKiModel? active = models
        .where((HsaKiModel m) => m.active)
        .firstOrNull;
    return active?.modelId ?? models.firstOrNull?.modelId;
  }

  /// Whether results of work started in [generation] may still be published.
  bool _isCurrent(int generation) =>
      ref.mounted && ref.read(hsaKiSessionGenerationProvider) == generation;

  void selectModel(String modelId) {
    final HsaKiChatState? current = state.value;
    if (current == null) return;
    state = AsyncData<HsaKiChatState>(
      current.copyWith(selectedModelId: modelId),
    );
  }

  Future<void> send(String text) async {
    final HsaKiChatState? current = state.value;
    if (current == null || current.isSending || text.trim().isEmpty) return;

    final int generation = ref.read(hsaKiSessionGenerationProvider);
    final HsaKiMessage userMessage = HsaKiMessage(
      role: HsaKiMessageRole.user,
      text: text.trim(),
    );
    final List<HsaKiMessage> withUserTurn = <HsaKiMessage>[
      ...current.messages,
      userMessage,
    ];
    state = AsyncData<HsaKiChatState>(
      current.copyWith(
        messages: withUserTurn,
        isSending: true,
        clearError: true,
      ),
    );

    var reachedHawki = false;
    try {
      final HsaKiCredential? credential = await ref
          .read(hsaKiCredentialStoreProvider)
          .read();
      if (credential == null) {
        throw const HsaKiFailure(HsaKiFailureKind.notConnected);
      }
      String? modelId = current.selectedModelId;
      if (modelId == null) {
        // The list may have failed when the chat opened; retry it here
        // instead of refusing every message until the app restarts.
        final List<HsaKiModel> models = await ref
            .read(hsaKiGatewayProvider)
            .listModels(credential);
        if (!_isCurrent(generation)) return;
        modelId = _defaultModelId(models);
        if (modelId == null) {
          throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
        }
        final HsaKiChatState? latest = state.value;
        if (latest == null) return;
        state = AsyncData<HsaKiChatState>(
          latest.copyWith(models: models, selectedModelId: modelId),
        );
      }
      reachedHawki = true;
      final String reply = await ref
          .read(hsaKiGatewayProvider)
          .sendMessage(credential, modelId: modelId, messages: withUserTurn);
      if (!_isCurrent(generation)) return;
      final HsaKiChatState? latest = state.value;
      if (latest == null) return;
      state = AsyncData<HsaKiChatState>(
        latest.copyWith(
          messages: <HsaKiMessage>[
            ...latest.messages,
            HsaKiMessage(role: HsaKiMessageRole.assistant, text: reply),
          ],
          isSending: false,
        ),
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      final HsaKiChatState? latest = state.value;
      if (latest == null) return;
      state = AsyncData<HsaKiChatState>(
        latest.copyWith(
          // A turn that never reached HAWKI was not sent; keep it out of the
          // history the next request carries.
          messages: reachedHawki
              ? null
              : latest.messages
                    .where((HsaKiMessage m) => !identical(m, userMessage))
                    .toList(growable: false),
          isSending: false,
          lastError: error is HsaKiFailure
              ? error.kind
              : HsaKiFailureKind.unknown,
        ),
      );
    }
  }
}

final AsyncNotifierProvider<HsaKiChatController, HsaKiChatState>
hsaKiChatControllerProvider =
    AsyncNotifierProvider.autoDispose<HsaKiChatController, HsaKiChatState>(
      HsaKiChatController.new,
    );
