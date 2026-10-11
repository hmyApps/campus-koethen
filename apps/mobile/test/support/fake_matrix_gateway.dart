// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/chat/domain/chat_models.dart';
import 'package:campus_koethen/features/chat/domain/matrix_failure.dart';
import 'package:campus_koethen/features/chat/domain/matrix_gateway.dart';

/// Scriptable [MatrixGateway] for controller and widget tests. Demo data only.
class FakeMatrixGateway implements MatrixGateway {
  FakeMatrixGateway({this.stored});

  static const MatrixAccount demoAccount = MatrixAccount(
    userId: '@demo-user:matrix.example.test',
  );

  /// The session `restore` finds; `login` stores into it.
  MatrixAccount? stored;

  MatrixFailure? restoreFailure;
  MatrixFailure? loginFailure;
  MatrixFailure? logoutFailure;
  MatrixFailure? sendFailure;

  /// Completes `login` when set; lets a test observe the loading state.
  Completer<void>? loginGate;

  final List<(String, String)> logins = <(String, String)>[];
  final List<(String, String)> sent = <(String, String)>[];
  final List<String> accepted = <String>[];
  final List<String> declined = <String>[];
  final List<bool> syncActivity = <bool>[];
  int logouts = 0;
  bool disposed = false;

  List<ChatRoomSummary> roomList = <ChatRoomSummary>[];
  final Map<String, FakeChatRoomTimeline> timelines =
      <String, FakeChatRoomTimeline>{};

  final StreamController<void> _changes = StreamController<void>.broadcast();

  void emitChange() => _changes.add(null);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<MatrixAccount?> restore() async {
    final MatrixFailure? failure = restoreFailure;
    if (failure != null) throw failure;
    return stored;
  }

  @override
  Future<MatrixAccount> login({
    required String username,
    required String password,
  }) async {
    logins.add((username, password));
    await loginGate?.future;
    final MatrixFailure? failure = loginFailure;
    if (failure != null) throw failure;
    return stored = demoAccount;
  }

  @override
  Future<void> logout() async {
    logouts++;
    final MatrixFailure? failure = logoutFailure;
    if (failure != null) throw failure;
    stored = null;
    roomList = <ChatRoomSummary>[];
    emitChange();
  }

  @override
  void setSyncActive(bool active) => syncActivity.add(active);

  @override
  List<ChatRoomSummary> get rooms =>
      stored == null ? const <ChatRoomSummary>[] : roomList;

  @override
  Future<ChatRoomTimeline> openTimeline(String roomId) async {
    final FakeChatRoomTimeline? timeline = timelines[roomId];
    if (timeline == null) {
      throw const MatrixFailure(MatrixFailureKind.roomUnavailable);
    }
    timeline.closed = false;
    return timeline;
  }

  @override
  Future<void> sendText(String roomId, String text) async {
    final MatrixFailure? failure = sendFailure;
    if (failure != null) throw failure;
    sent.add((roomId, text));
  }

  @override
  Future<void> acceptInvite(String roomId) async => accepted.add(roomId);

  @override
  Future<void> declineInvite(String roomId) async => declined.add(roomId);

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeChatRoomTimeline implements ChatRoomTimeline {
  FakeChatRoomTimeline(this.messages, {this.canLoadMore = false});

  @override
  List<ChatMessage> messages;

  @override
  bool canLoadMore;

  int loadMoreCalls = 0;
  int markReadCalls = 0;
  bool closed = false;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  void emitChange() => _changes.add(null);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> loadMore() async => loadMoreCalls++;

  @override
  Future<void> markRead() async => markReadCalls++;

  @override
  void close() => closed = true;
}
