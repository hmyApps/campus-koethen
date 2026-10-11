// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../l10n/l10n.dart';
import '../domain/chat_models.dart';
import '../domain/matrix_failure.dart';

/// The classified failure as a sentence. Never server text.
String chatFailureMessage(AppLocalizations l10n, Object error) {
  final MatrixFailureKind kind = error is MatrixFailure
      ? error.kind
      : MatrixFailureKind.unknown;
  return switch (kind) {
    MatrixFailureKind.notConfigured => l10n.chatNotConfigured,
    MatrixFailureKind.unsupportedServer => l10n.chatErrorUnsupportedServer,
    MatrixFailureKind.invalidCredentials => l10n.chatErrorInvalidCredentials,
    MatrixFailureKind.networkUnavailable => l10n.chatErrorNetwork,
    MatrixFailureKind.timeout => l10n.chatErrorTimeout,
    MatrixFailureKind.tlsOrHostRejected => l10n.chatErrorSecurity,
    MatrixFailureKind.serviceUnavailable => l10n.chatErrorServiceUnavailable,
    MatrixFailureKind.rateLimited => l10n.chatErrorRateLimited,
    MatrixFailureKind.invalidResponse => l10n.chatErrorInvalidResponse,
    MatrixFailureKind.secureStorageUnavailable => l10n.chatErrorSecureStorage,
    MatrixFailureKind.databaseUnavailable => l10n.chatErrorDatabase,
    MatrixFailureKind.encryptionUnavailable => l10n.chatErrorEncryption,
    MatrixFailureKind.notConnected => l10n.chatErrorNotConnected,
    MatrixFailureKind.roomUnavailable => l10n.chatRoomUnavailable,
    MatrixFailureKind.sendFailed => l10n.chatErrorSendFailed,
    MatrixFailureKind.invalidUserId => l10n.chatErrorInvalidUserId,
    MatrixFailureKind.notAllowed => l10n.chatErrorNotAllowed,
    MatrixFailureKind.notFound => l10n.chatErrorNotFound,
    MatrixFailureKind.sessionEnded => l10n.chatErrorSessionEnded,
    MatrixFailureKind.unknown => l10n.chatErrorUnknown,
  };
}

/// Whether deleting the local chat data is the way out of [error]: the
/// encrypted database or its key can no longer be opened.
bool chatFailureNeedsReset(Object? error) =>
    error is MatrixFailure &&
    (error.kind == MatrixFailureKind.databaseUnavailable ||
        error.kind == MatrixFailureKind.secureStorageUnavailable);

/// What a message shows as text: its body, or what it is when it has none
/// this app can show.
String chatMessageText(AppLocalizations l10n, ChatMessage message) =>
    switch (message.kind) {
      ChatMessageKind.text ||
      ChatMessageKind.notice ||
      ChatMessageKind.emote => message.body,
      ChatMessageKind.undecryptable => l10n.chatMessageUndecryptable,
      ChatMessageKind.redacted => l10n.chatMessageRedacted,
      ChatMessageKind.unsupported => l10n.chatMessageUnsupported,
    };

/// One line for the room list: who wrote the last message, and what.
String chatPreviewText(AppLocalizations l10n, ChatMessage message) {
  final String sender = message.isMine
      ? l10n.chatOwnSender
      : message.senderName;
  final String text = chatMessageText(l10n, message);
  return sender.isEmpty ? text : l10n.chatPreviewLine(sender, text);
}
