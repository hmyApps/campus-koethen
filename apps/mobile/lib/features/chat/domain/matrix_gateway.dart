// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'chat_models.dart';

/// The device-direct connection to the configured Matrix homeserver
/// (AGENTS.md §2). Every failure surfaces as a `MatrixFailure`.
abstract interface class MatrixGateway {
  /// The account of a stored session, or `null` when signed out. Touches
  /// neither disk nor network when no session was ever stored.
  Future<MatrixAccount?> restore();

  /// Signs in with Matrix username (or full Matrix ID) and password. The
  /// password is only used for this request and never stored.
  Future<MatrixAccount> login({
    required String username,
    required String password,
  });

  /// Signs this device out at the homeserver (best effort) and then deletes
  /// the local database and its key, verified, even without a server.
  Future<void> logout();

  /// Syncs only while the app is in the foreground: there is no push gateway.
  void setSyncActive(bool active);

  /// Fires whenever rooms, messages or the session changed.
  Stream<void> get changes;

  /// The rooms, most recent activity first. Invites included.
  List<ChatRoomSummary> get rooms;

  Future<ChatRoomTimeline> openTimeline(String roomId);

  Future<void> sendText(String roomId, String text);

  Future<void> acceptInvite(String roomId);

  Future<void> declineInvite(String roomId);

  /// Stops syncing and closes the database. The session stays stored.
  Future<void> dispose();
}

/// The open message list of one room. Close it when the room is left.
abstract interface class ChatRoomTimeline {
  /// Newest first.
  List<ChatMessage> get messages;

  Stream<void> get changes;

  bool get canLoadMore;

  Future<void> loadMore();

  /// Marks everything up to the newest message as read, privately (no public
  /// read receipt).
  Future<void> markRead();

  void close();
}
