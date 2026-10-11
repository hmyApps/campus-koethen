// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:io';

import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:meta/meta.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

import '../domain/chat_key_backup.dart';
import '../domain/chat_models.dart';
import '../domain/matrix_failure.dart';
import '../domain/matrix_gateway.dart';
import '../domain/matrix_homeserver.dart';
import '../domain/matrix_user_id.dart';
import 'encrypted_matrix_database.dart';
import 'matrix_origin_http_client.dart';
import 'uia_password_responder.dart';

/// Loads vodozemac (Olm/Megolm) once per process.
///
/// The native library refuses a second initialisation, so every gateway —
/// including one a rebuilt provider creates — shares this one. A failed load
/// is not remembered: the next attempt tries again.
Future<void> initVodozemac() => loadOncePerProcess(vodozemac.init);

Future<void>? _vodozemacLoad;

/// [initVodozemac] with the loader injectable for tests.
@visibleForTesting
Future<void> loadOncePerProcess(Future<void> Function() load) =>
    _vodozemacLoad ??= load().catchError((Object error, StackTrace stack) {
      _vodozemacLoad = null;
      Error.throwWithStackTrace(error, stack);
    });

@visibleForTesting
void resetVodozemacLoadForTest() => _vodozemacLoad = null;

/// [MatrixGateway] on the famedly Matrix SDK.
///
/// Every request goes through [MatrixOriginHttpClient] (exact origin, no
/// redirects); the SDK database is [EncryptedMatrixDatabase].
class SdkMatrixGateway implements MatrixGateway {
  SdkMatrixGateway({
    required this._homeserver,
    required this._database,
    this._httpClient,
    this._initEncryption = initVodozemac,
  }) {
    _quietSdkLogs();
  }

  final MatrixHomeserver? _homeserver;
  final EncryptedMatrixDatabase _database;
  final http.Client? _httpClient;

  /// `null` only in host tests, which have no vodozemac build. On devices a
  /// failure here refuses the chat instead of running it unencrypted.
  final Future<void> Function()? _initEncryption;

  static const String _clientName = 'campus_koethen_chat';

  /// What other sessions of the account see in their device list.
  static const String _deviceName = 'Campus Köthen';

  final StreamController<void> _changes = StreamController<void>.broadcast();
  Client? _client;
  MatrixOriginHttpClient? _originClient;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  bool _syncActive = true;
  bool _encryptionReady = false;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<MatrixAccount?> restore() => _guard(() async {
    final Client? current = _client;
    if (current != null && current.isLogged()) return _account(current);
    final MatrixHomeserver? homeserver = _homeserver;
    if (homeserver == null || !await _database.hasKey()) return null;

    final Client client = await _openClient(homeserver);
    final Map<String, dynamic>? stored = await client.database.getClient(
      _clientName,
    );
    final Uri? storedServer = Uri.tryParse(
      stored?['homeserver_url'] as String? ?? '',
    );
    if (stored == null ||
        stored['token'] == null ||
        storedServer == null ||
        !homeserver.allows(storedServer)) {
      // Nothing usable, or a session of another homeserver (a different
      // build): it can never be used here, and never reach its server.
      await _closeAndWipe();
      return null;
    }
    await client.init(waitForFirstSync: false);
    if (!client.isLogged()) {
      await _closeAndWipe();
      return null;
    }
    _startSyncIfActive(client);
    return _account(client);
  });

  @override
  Future<MatrixAccount> login({
    required String username,
    required String password,
  }) => _guard(login: true, () async {
    final MatrixHomeserver homeserver =
        _homeserver ??
        (throw const MatrixFailure(MatrixFailureKind.notConfigured));
    final MatrixAccount? existing = await restore();
    if (existing != null) return existing;

    final Client client = await _openClient(homeserver);
    try {
      await client.checkHomeserver(
        homeserver.baseUri,
        checkWellKnown: false,
        fetchAuthMetadata: false,
      );
      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username.trim()),
        password: password,
        initialDeviceDisplayName: _deviceName,
      );
    } catch (_) {
      // No half-written session stays behind.
      try {
        await _closeAndWipe();
      } catch (_) {}
      rethrow;
    }
    _startSyncIfActive(client);
    _changes.add(null);
    return _account(client);
  });

  @override
  Future<void> logout() async {
    if (_client == null) {
      try {
        // A stored session that was never opened is still signed out at
        // the server, not just forgotten locally.
        await restore();
      } catch (_) {}
    }
    final Client? client = _client;
    if (client != null && client.isLogged()) {
      try {
        // Clears the SDK's own state even when the request fails.
        await client.logout();
      } catch (_) {
        // Best effort: an unreachable server must not keep data here.
      }
    }
    await _disposeClient();
    try {
      await _database.wipe();
    } finally {
      _changes.add(null);
    }
  }

  @override
  void setSyncActive(bool active) {
    _syncActive = active;
    final Client? client = _client;
    if (client == null || !client.isLogged()) return;
    // Pausing only ends the loop: the request in flight finishes normally.
    // Aborting it would leave the SDK's error back-off armed and delay the
    // next foreground sync by seconds.
    client.backgroundSync = active;
  }

  @override
  List<ChatRoomSummary> get rooms {
    final Client? client = _client;
    if (client == null || !client.isLogged()) return const <ChatRoomSummary>[];
    return client.rooms
        .where(
          (Room room) =>
              room.membership == Membership.join ||
              room.membership == Membership.invite,
        )
        .map((Room room) => _summary(client, room))
        .toList(growable: false);
  }

  @override
  Future<ChatRoomTimeline> openTimeline(String roomId) => _guard(() async {
    final Client client = _requireClient();
    final _SdkChatRoomTimeline timeline = _SdkChatRoomTimeline(
      client,
      _requireRoom(client, roomId),
    );
    await timeline.open();
    return timeline;
  });

  @override
  Future<void> sendText(String roomId, String text) => _guard(() async {
    final Room room = _requireRoom(_requireClient(), roomId);
    if (text.trim().isEmpty) return;
    final String? eventId = await room.sendTextEvent(text);
    if (eventId == null) {
      throw const MatrixFailure(MatrixFailureKind.sendFailed);
    }
  });

  @override
  MatrixAccount? get account {
    final Client? client = _client;
    return client != null && client.isLogged() ? _account(client) : null;
  }

  @override
  Future<String> startDirectChat(String userId) => _guard(() async {
    final Client client = _requireClient();
    final String peer = _requireUserId(client, userId);
    final String roomId = await client.startDirectChat(
      peer,
      enableEncryption: true,
      waitForSync: false,
    );
    await _untilJoined(client, roomId);
    return roomId;
  });

  @override
  Future<String> createGroupChat({
    required String name,
    required List<String> invite,
  }) => _guard(() async {
    final Client client = _requireClient();
    final List<String> invitees = <String>{
      for (final String userId in invite) _requireUserId(client, userId),
    }.toList(growable: false);
    final String trimmed = name.trim();
    final String roomId = await client.createGroupChat(
      groupName: trimmed.isEmpty ? null : trimmed,
      invite: invitees,
      enableEncryption: true,
      preset: CreateRoomPreset.privateChat,
      waitForSync: false,
    );
    await _untilJoined(client, roomId);
    return roomId;
  });

  @override
  Future<ChatKeyBackupState> keyBackupState() => _guard(() async {
    final Client client = _requireClient();
    if (client.encryption == null) return ChatKeyBackupState.unavailable;
    final ({
      bool keyBackupEnabled,
      bool crossSigningEnabled,
      bool initialized,
      bool connected,
    })
    identity = await client.getCryptoIdentityState();
    if (!identity.initialized) return ChatKeyBackupState.notSetUp;
    return identity.connected
        ? ChatKeyBackupState.ready
        : ChatKeyBackupState.locked;
  });

  @override
  Future<String> setUpKeyBackup({String? password}) => _guard(() async {
    final Client client = _requireEncryptedClient();
    // Setting up over an existing backup would wipe it; that is the
    // explicit reset, never a side effect.
    if ((await client.getCryptoIdentityState()).initialized) {
      throw const MatrixFailure(MatrixFailureKind.notAllowed);
    }
    return _confirmedWith(password, client, client.initCryptoIdentity);
  });

  @override
  Future<void> unlockKeyBackup(String recoveryKey) => _guard(() async {
    final Client client = _requireEncryptedClient();
    try {
      await client.restoreCryptoIdentity(recoveryKey.trim());
    } on InvalidPassphraseException {
      throw const MatrixFailure(MatrixFailureKind.invalidRecoveryKey);
    }
  });

  @override
  Future<String> resetKeyBackup({required String password}) => _guard(() async {
    final Client client = _requireEncryptedClient();
    return _confirmedWith(password, client, client.initCryptoIdentity);
  });

  Client _requireEncryptedClient() {
    final Client client = _requireClient();
    if (client.encryption == null) {
      throw const MatrixFailure(MatrixFailureKind.encryptionUnavailable);
    }
    return client;
  }

  /// Runs [operation], answering a re-authentication request from the server
  /// once with [password], or refusing it when there is none.
  static Future<T> _confirmedWith<T>(
    String? password,
    Client client,
    Future<T> Function() operation,
  ) async {
    final UiaPasswordResponder responder = UiaPasswordResponder(
      requests: client.onUiaRequest.stream,
      password: password,
      userId: client.userID ?? '',
    )..start();
    try {
      return await operation();
    } catch (error) {
      if (responder.passwordMissing) {
        throw const MatrixFailure(MatrixFailureKind.passwordRequired);
      }
      if (responder.passwordRejected) {
        throw const MatrixFailure(MatrixFailureKind.invalidCredentials);
      }
      rethrow;
    } finally {
      await responder.stop();
    }
  }

  String _requireUserId(Client client, String input) {
    final String? userId = parseMatrixUserId(
      input,
      ownServerName:
          matrixServerNameOf(client.userID ?? '') ?? _homeserver?.host ?? '',
    );
    if (userId == null) {
      throw const MatrixFailure(MatrixFailureKind.invalidUserId);
    }
    return userId;
  }

  /// A new room only exists locally once a sync delivered it. Waits for that
  /// (bounded); a slow server still gets the room with a later sync.
  static Future<void> _untilJoined(Client client, String roomId) async {
    if (client.getRoomById(roomId)?.membership == Membership.join) return;
    try {
      await client
          .waitForRoomInSync(roomId, join: true)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // Created all the same; it shows up with a later sync.
    }
  }

  @override
  Future<void> acceptInvite(String roomId) =>
      _guard(() => _requireRoom(_requireClient(), roomId).join());

  @override
  Future<void> declineInvite(String roomId) =>
      _guard(() => _requireRoom(_requireClient(), roomId).leave());

  @override
  Future<void> dispose() async {
    await _disposeClient();
    await _changes.close();
  }

  Future<Client> _openClient(MatrixHomeserver homeserver) async {
    final Client? current = _client;
    if (current != null) return current;
    await _ensureEncryption();
    final Database database = await _database.open();
    final MatrixSdkDatabase sdkDatabase;
    try {
      sdkDatabase = await MatrixSdkDatabase.init(
        _clientName,
        database: database,
      );
    } catch (_) {
      await database.close();
      throw const MatrixFailure(MatrixFailureKind.databaseUnavailable);
    }
    final MatrixOriginHttpClient originClient = MatrixOriginHttpClient(
      homeserver,
      _httpClient ?? _defaultHttpClient(),
    );
    final Client client = Client(
      _clientName,
      database: sdkDatabase,
      httpClient: originClient,
      supportedLoginTypes: <String>{AuthenticationTypes.password},
      verificationMethods: <KeyVerificationMethod>{
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.numbers,
      },
      // Private read receipts only (Phase 1 has no receipt setting).
      receiptsPublicByDefault: false,
      logLevel: Level.wtf,
    );
    // Sync runs only once a session exists and the app is in the foreground.
    client.backgroundSync = false;
    _subscriptions
      ..add(client.onSync.stream.listen((_) => _changes.add(null)))
      ..add(
        client.onLoginStateChanged.stream.listen((_) => _changes.add(null)),
      );
    _client = client;
    _originClient = originClient;
    return client;
  }

  static http.Client _defaultHttpClient() =>
      IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 15));

  Future<void> _ensureEncryption() async {
    final Future<void> Function()? initEncryption = _initEncryption;
    if (initEncryption == null || _encryptionReady) return;
    try {
      await initEncryption();
      _encryptionReady = true;
    } catch (_) {
      throw const MatrixFailure(MatrixFailureKind.encryptionUnavailable);
    }
  }

  void _startSyncIfActive(Client client) {
    if (_syncActive) client.backgroundSync = true;
  }

  Client _requireClient() {
    final Client? client = _client;
    if (client == null || !client.isLogged()) {
      throw const MatrixFailure(MatrixFailureKind.notConnected);
    }
    return client;
  }

  static Room _requireRoom(Client client, String roomId) {
    final Room? room = client.getRoomById(roomId);
    if (room == null ||
        (room.membership != Membership.join &&
            room.membership != Membership.invite)) {
      throw const MatrixFailure(MatrixFailureKind.roomUnavailable);
    }
    return room;
  }

  Future<void> _closeAndWipe() async {
    await _disposeClient();
    await _database.wipe();
  }

  Future<void> _disposeClient() async {
    final Client? client = _client;
    final MatrixOriginHttpClient? originClient = _originClient;
    _client = null;
    _originClient = null;
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    if (client == null) return;
    try {
      await client.dispose();
    } catch (_) {}
    // An injected client belongs to its owner.
    if (_httpClient == null) originClient?.close();
  }

  static MatrixAccount _account(Client client) =>
      MatrixAccount(userId: client.userID ?? '');

  static ChatRoomSummary _summary(Client client, Room room) {
    final Event? last = room.lastEvent;
    return ChatRoomSummary(
      id: room.id,
      title: _title(client, room),
      isDirect: room.isDirectChat,
      isEncrypted: room.encrypted,
      isInvite: room.membership == Membership.invite,
      unreadCount: room.notificationCount,
      lastMessage: last == null ? null : chatMessageOf(client, last),
      lastActivity: last?.originServerTs,
    );
  }

  /// The room name, its alias or the other members' names — never the SDK's
  /// English placeholders (the UI localizes the empty case).
  static String? _title(Client client, Room room) {
    if (room.name.isNotEmpty) return room.name;
    final String? alias = room.canonicalAlias.localpart;
    if (alias != null && alias.isNotEmpty) return alias;
    final List<String> heroes = <String>[...?room.summary.mHeroes];
    final String? direct = room.directChatMatrixID;
    if (heroes.isEmpty && direct != null) heroes.add(direct);
    final List<String> names = heroes
        .where((String id) => id.isNotEmpty && id != client.userID)
        .map(
          (String id) =>
              room.unsafeGetUserFromMemoryOrFallback(id).calcDisplayname(),
        )
        .where((String name) => name.isNotEmpty)
        .toList();
    return names.isEmpty ? null : names.join(', ');
  }

  /// Keeps the SDK quiet: its log lines can carry room, event and user IDs.
  /// Only its highest severity still prints, and nothing is collected in
  /// memory.
  static void _quietSdkLogs() {
    final Logs logs = Logs();
    logs.level = Level.wtf;
    logs.nativeColors = false;
    logs.onLog = (_) => logs.outputEvents.clear();
  }

  static Future<T> _guard<T>(
    Future<T> Function() operation, {
    bool login = false,
  }) async {
    try {
      return await operation();
    } on MatrixFailure {
      rethrow;
    } catch (error) {
      throw classifyMatrixError(error, login: login);
    }
  }
}

/// Maps whatever the SDK or the network threw to a classified failure
/// without carrying any of its text along.
///
/// A refusal means a wrong password only while signing in ([login]); for
/// everything after that it means the action is not allowed.
MatrixFailure classifyMatrixError(Object error, {bool login = false}) {
  if (error is MatrixFailure) return error;
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_FORBIDDEN ||
      MatrixError.M_USER_DEACTIVATED => MatrixFailure(
        login
            ? MatrixFailureKind.invalidCredentials
            : MatrixFailureKind.notAllowed,
      ),
      MatrixError.M_UNKNOWN_TOKEN => MatrixFailure(
        login
            ? MatrixFailureKind.invalidCredentials
            : MatrixFailureKind.notConnected,
      ),
      MatrixError.M_NOT_FOUND => const MatrixFailure(
        MatrixFailureKind.notFound,
      ),
      MatrixError.M_LIMIT_EXCEEDED => const MatrixFailure(
        MatrixFailureKind.rateLimited,
      ),
      _ => const MatrixFailure(MatrixFailureKind.unknown),
    };
  }
  if (error is BadServerLoginTypesException) {
    return const MatrixFailure(MatrixFailureKind.unsupportedServer);
  }
  if (error is TimeoutException) {
    return const MatrixFailure(MatrixFailureKind.timeout);
  }
  if (error is TlsException) {
    return const MatrixFailure(MatrixFailureKind.tlsOrHostRejected);
  }
  if (error is SocketException || error is http.ClientException) {
    return const MatrixFailure(MatrixFailureKind.networkUnavailable);
  }
  if (error is FormatException) {
    return const MatrixFailure(MatrixFailureKind.invalidResponse);
  }
  return const MatrixFailure(MatrixFailureKind.unknown);
}

/// Maps one SDK event to what the chat shows.
ChatMessage chatMessageOf(Client client, Event event, {Timeline? timeline}) {
  final Event shown = timeline == null
      ? event
      : event.getDisplayEvent(timeline);
  final ChatMessageKind kind;
  if (shown.redacted) {
    kind = ChatMessageKind.redacted;
  } else if (shown.type == EventTypes.Encrypted) {
    kind = ChatMessageKind.undecryptable;
  } else if (shown.type == EventTypes.Message) {
    kind = switch (shown.messageType) {
      MessageTypes.Text => ChatMessageKind.text,
      MessageTypes.Notice => ChatMessageKind.notice,
      MessageTypes.Emote => ChatMessageKind.emote,
      _ => ChatMessageKind.unsupported,
    };
  } else {
    kind = ChatMessageKind.unsupported;
  }
  final bool hasText =
      kind == ChatMessageKind.text ||
      kind == ChatMessageKind.notice ||
      kind == ChatMessageKind.emote;
  return ChatMessage(
    id: event.eventId,
    senderName: event.senderFromMemoryOrFallback.calcDisplayname(),
    isMine: event.senderId == client.userID,
    kind: kind,
    body: hasText
        ? shown.calcUnlocalizedBody(
            hideReply: true,
            hideEdit: true,
            plaintextBody: true,
          )
        : '',
    timestamp: event.originServerTs,
    status: switch (event.status) {
      EventStatus.error => ChatMessageStatus.failed,
      EventStatus.sending => ChatMessageStatus.sending,
      EventStatus.sent || EventStatus.synced => ChatMessageStatus.sent,
    },
  );
}

class _SdkChatRoomTimeline implements ChatRoomTimeline {
  _SdkChatRoomTimeline(this._client, this._room);

  final Client _client;
  final Room _room;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Timeline? _timeline;

  Future<void> open() async {
    _timeline = await _room.getTimeline(
      onUpdate: () {
        if (!_changes.isClosed) _changes.add(null);
      },
    );
  }

  Timeline get _open =>
      _timeline ?? (throw const MatrixFailure(MatrixFailureKind.notConnected));

  @override
  Stream<void> get changes => _changes.stream;

  @override
  List<ChatMessage> get messages {
    final Timeline timeline = _open;
    return timeline.events
        .where(_isShown)
        .map((Event e) => chatMessageOf(_client, e, timeline: timeline))
        .toList(growable: false);
  }

  /// Messages only: state changes, reactions, edits (folded into their
  /// original) and redaction events stay out of the list.
  static bool _isShown(Event event) =>
      (event.type == EventTypes.Message ||
          event.type == EventTypes.Encrypted) &&
      event.relationshipType != RelationshipTypes.edit;

  @override
  bool get canLoadMore => _timeline?.canRequestHistory ?? false;

  @override
  Future<void> loadMore() async {
    try {
      await _open.requestHistory();
    } catch (error) {
      throw classifyMatrixError(error);
    }
  }

  @override
  Future<void> markRead() async {
    try {
      await _open.setReadMarker(public: false);
    } catch (error) {
      throw classifyMatrixError(error);
    }
  }

  @override
  void close() {
    _timeline?.cancelSubscriptions();
    if (!_changes.isClosed) unawaited(_changes.close());
  }
}
