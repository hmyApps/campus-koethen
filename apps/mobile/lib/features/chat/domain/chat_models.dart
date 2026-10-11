// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

/// The signed-in Matrix account. Never carries the access token: that stays
/// inside the encrypted SDK database (AGENTS.md §2).
@immutable
class MatrixAccount {
  const MatrixAccount({required this.userId, this.displayName});

  /// The full Matrix ID, shown to the user as their own address.
  final String userId;
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      other is MatrixAccount &&
      other.userId == userId &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(userId, displayName);

  /// No IDs in diagnostics.
  @override
  String toString() => 'MatrixAccount(…)';
}

enum ChatMessageKind {
  text,
  notice,
  emote,

  /// Encrypted, and the keys to read it are not (yet) on this device. Shown
  /// as such, never as an empty message.
  undecryptable,
  redacted,

  /// A message type this client does not show yet (images, files, polls…).
  unsupported,
}

enum ChatMessageStatus { sending, sent, failed }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderName,
    required this.isMine,
    required this.kind,
    required this.body,
    required this.timestamp,
    this.status = ChatMessageStatus.sent,
  });

  final String id;
  final String senderName;
  final bool isMine;
  final ChatMessageKind kind;

  /// Plain text for [ChatMessageKind.text], [notice] and [emote]; empty
  /// otherwise.
  final String body;
  final DateTime timestamp;
  final ChatMessageStatus status;

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.id == id &&
      other.senderName == senderName &&
      other.isMine == isMine &&
      other.kind == kind &&
      other.body == body &&
      other.timestamp == timestamp &&
      other.status == status;

  @override
  int get hashCode =>
      Object.hash(id, senderName, isMine, kind, body, timestamp, status);

  /// No content in diagnostics.
  @override
  String toString() => 'ChatMessage(${kind.name}, ${status.name})';
}

@immutable
class ChatRoomSummary {
  const ChatRoomSummary({
    required this.id,
    required this.isDirect,
    required this.isEncrypted,
    required this.isInvite,
    required this.unreadCount,
    this.title,
    this.lastMessage,
    this.lastActivity,
  });

  final String id;

  /// The room name, or the other members' names. `null` when the room has
  /// neither; the UI then shows a localized placeholder.
  final String? title;
  final bool isDirect;
  final bool isEncrypted;
  final bool isInvite;
  final int unreadCount;
  final ChatMessage? lastMessage;
  final DateTime? lastActivity;

  @override
  bool operator ==(Object other) =>
      other is ChatRoomSummary &&
      other.id == id &&
      other.title == title &&
      other.isDirect == isDirect &&
      other.isEncrypted == isEncrypted &&
      other.isInvite == isInvite &&
      other.unreadCount == unreadCount &&
      other.lastMessage == lastMessage &&
      other.lastActivity == lastActivity;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    isDirect,
    isEncrypted,
    isInvite,
    unreadCount,
    lastMessage,
    lastActivity,
  );

  /// No IDs or names in diagnostics.
  @override
  String toString() => 'ChatRoomSummary(…)';
}
