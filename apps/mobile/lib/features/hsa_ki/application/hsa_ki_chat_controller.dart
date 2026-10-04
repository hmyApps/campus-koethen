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

class HsaKiChatController extends AsyncNotifier<HsaKiChatState> {
  @override
  Future<HsaKiChatState> build() async {
    final HsaKiCredential? credential = await ref.read(
      hsaKiCredentialStoreProvider,
    ).read();
    if (credential == null) return const HsaKiChatState();
    try {
      final List<HsaKiModel> models = await ref
          .read(hsaKiGatewayProvider)
          .listModels(credential);
      final HsaKiModel? active = models
          .where((HsaKiModel m) => m.active)
          .firstOrNull;
      return HsaKiChatState(
        models: models,
        selectedModelId: active?.modelId ?? models.firstOrNull?.modelId,
      );
    } catch (_) {
      // A failed model list must not block opening the chat; sending a
      // message without a model selected is refused explicitly below.
      return const HsaKiChatState();
    }
  }

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
    final String? modelId = current.selectedModelId;
    if (modelId == null) {
      state = AsyncData<HsaKiChatState>(
        current.copyWith(lastError: HsaKiFailureKind.portalStructureChanged),
      );
      return;
    }

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

    try {
      final HsaKiCredential? credential = await ref.read(
        hsaKiCredentialStoreProvider,
      ).read();
      if (credential == null) {
        throw const HsaKiFailure(HsaKiFailureKind.notConnected);
      }
      final String reply = await ref
          .read(hsaKiGatewayProvider)
          .sendMessage(credential, modelId: modelId, messages: withUserTurn);
      if (ref.read(hsaKiSessionGenerationProvider) != generation) return;
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
      if (ref.read(hsaKiSessionGenerationProvider) != generation) return;
      final HsaKiChatState? latest = state.value;
      if (latest == null) return;
      state = AsyncData<HsaKiChatState>(
        latest.copyWith(
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
    AsyncNotifierProvider<HsaKiChatController, HsaKiChatState>(
      HsaKiChatController.new,
    );
