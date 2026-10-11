// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// One request that reached the fake homeserver.
class FakeHomeserverRequest {
  FakeHomeserverRequest(this.method, this.url, this.body);

  final String method;
  final Uri url;
  final String body;

  /// The client-server path without `/_matrix/client`.
  String get path => url.path.replaceFirst('/_matrix/client', '');
}

/// A minimal Matrix homeserver for the chat tests. Every name and ID is
/// demo data; nothing here mirrors a real account.
class FakeHomeserver extends http.BaseClient {
  FakeHomeserver({this.origin = 'https://matrix.example.test'});

  final String origin;
  final List<FakeHomeserverRequest> requests = <FakeHomeserverRequest>[];

  static const String demoUser = 'demo-user';
  static const String demoPassword = 'demo-password';
  static const String userId = '@demo-user:matrix.example.test';
  static const String peerId = '@demo-peer:matrix.example.test';
  static const String groupRoomId = '!demo-group:matrix.example.test';
  static const String encryptedRoomId = '!demo-encrypted:matrix.example.test';
  static const String inviteRoomId = '!demo-invite:matrix.example.test';

  /// Every request fails as an unreachable network does.
  bool offline = false;

  List<String> versions = <String>['v1.11', 'v1.12'];
  List<String> loginFlows = <String>['m.login.password'];

  /// Overrides the answer to `POST /login`: status and Matrix error code.
  (int, String)? loginError;

  /// Overrides the answer to `POST /logout`.
  int logoutStatus = 200;

  /// The rooms delivered with the first sync.
  Map<String, Object?> Function()? firstSyncRooms;

  var _eventCounter = 0;

  Iterable<FakeHomeserverRequest> called(String method, String path) => requests
      .where((FakeHomeserverRequest r) => r.method == method && r.path == path);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final List<int> bytes = await request.finalize().toBytes();
    final FakeHomeserverRequest recorded = FakeHomeserverRequest(
      request.method,
      request.url,
      utf8.decode(bytes, allowMalformed: true),
    );
    requests.add(recorded);
    if (offline) throw const SocketException('offline');
    if (request.url.origin != origin) {
      return _json(404, <String, Object?>{'errcode': 'M_NOT_FOUND'});
    }
    return _route(recorded);
  }

  Future<http.StreamedResponse> _route(FakeHomeserverRequest r) async {
    final String path = r.path;
    final String method = r.method;
    if (method == 'GET' && path == '/versions') {
      return _json(200, <String, Object?>{'versions': versions});
    }
    if (path == '/v3/login') {
      return method == 'GET' ? _loginFlows() : _login(r.body);
    }
    if (method == 'POST' && path == '/v3/logout') {
      return _json(logoutStatus, <String, Object?>{
        if (logoutStatus >= 400) 'errcode': 'M_UNKNOWN',
      });
    }
    if (method == 'POST' && path.endsWith('/filter')) {
      return _json(200, <String, Object?>{'filter_id': 'demo-filter'});
    }
    if (method == 'GET' && path == '/v3/sync') {
      if (r.url.queryParameters['since'] == null) {
        return _json(200, <String, Object?>{
          'next_batch': 'demo-batch-1',
          'rooms': firstSyncRooms?.call() ?? <String, Object?>{},
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return _json(200, <String, Object?>{'next_batch': 'demo-batch-n'});
    }
    if (method == 'PUT' && path.contains('/send/')) {
      return _json(200, <String, Object?>{
        'event_id': '\$demo-sent-${_eventCounter++}',
      });
    }
    if (method == 'POST' &&
        (path.startsWith('/v3/join/') || path.endsWith('/join'))) {
      return _json(200, <String, Object?>{'room_id': inviteRoomId});
    }
    if (method == 'POST' &&
        (path.endsWith('/leave') ||
            path.endsWith('/forget') ||
            path.endsWith('/read_markers') ||
            path.contains('/receipt/'))) {
      return _json(200, <String, Object?>{});
    }
    if (method == 'GET' && path.endsWith('/messages')) {
      return _json(200, <String, Object?>{'chunk': <Object?>[]});
    }
    return _json(404, <String, Object?>{
      'errcode': 'M_UNRECOGNIZED',
      'error': 'demo',
    });
  }

  http.StreamedResponse _loginFlows() => _json(200, <String, Object?>{
    'flows': <Object?>[
      for (final String flow in loginFlows) <String, Object?>{'type': flow},
    ],
  });

  http.StreamedResponse _login(String body) {
    final (int, String)? error = loginError;
    if (error != null) {
      return _json(error.$1, <String, Object?>{
        'errcode': error.$2,
        'error': 'demo',
      });
    }
    final Map<String, Object?> login = jsonDecode(body) as Map<String, Object?>;
    final Object? identifier = login['identifier'];
    final Object? user = identifier is Map ? identifier['user'] : null;
    if (user != demoUser || login['password'] != demoPassword) {
      return _json(403, <String, Object?>{
        'errcode': 'M_FORBIDDEN',
        'error': 'demo',
      });
    }
    return _json(200, <String, Object?>{
      'user_id': userId,
      'access_token': 'demo-access-token',
      'device_id': 'DEMODEVICE',
    });
  }

  /// One joined group room with a message from the demo peer, one joined
  /// encrypted room whose message this device cannot read, and one invite.
  Map<String, Object?> demoRooms() => <String, Object?>{
    'join': <String, Object?>{
      groupRoomId: <String, Object?>{
        'summary': <String, Object?>{
          'm.heroes': <String>[peerId],
          'm.joined_member_count': 2,
        },
        'state': <String, Object?>{
          'events': <Object?>[
            _state('m.room.name', '', <String, Object?>{'name': 'Demo-Gruppe'}),
            _state('m.room.member', peerId, <String, Object?>{
              'membership': 'join',
              'displayname': 'Demo-Kontakt',
            }, sender: peerId),
            _state('m.room.member', userId, <String, Object?>{
              'membership': 'join',
            }),
          ],
        },
        'timeline': <String, Object?>{
          'events': <Object?>[
            _state('m.room.topic', '', <String, Object?>{
              'topic': 'Demo-Thema',
            }),
            _event(
              'm.room.message',
              <String, Object?>{'msgtype': 'm.text', 'body': 'Demo-Nachricht'},
              sender: peerId,
              id: r'$demo-1',
              ts: 1760000000000,
            ),
          ],
          'limited': false,
          'prev_batch': 'demo-prev',
        },
        'unread_notifications': <String, Object?>{
          'notification_count': 2,
          'highlight_count': 0,
        },
      },
      encryptedRoomId: <String, Object?>{
        'state': <String, Object?>{
          'events': <Object?>[
            _state('m.room.name', '', <String, Object?>{
              'name': 'Demo-Verschlüsselt',
            }),
            _state('m.room.encryption', '', <String, Object?>{
              'algorithm': 'm.megolm.v1.aes-sha2',
            }),
          ],
        },
        'timeline': <String, Object?>{
          'events': <Object?>[
            _event(
              'm.room.encrypted',
              <String, Object?>{
                'algorithm': 'm.megolm.v1.aes-sha2',
                'ciphertext': 'ZGVtbw',
                'session_id': 'demo-session',
                'sender_key': 'demo-key',
                'device_id': 'DEMOPEER',
              },
              sender: peerId,
              id: r'$demo-2',
              ts: 1760000060000,
            ),
          ],
          'limited': false,
          'prev_batch': 'demo-prev',
        },
      },
    },
    'invite': <String, Object?>{
      inviteRoomId: <String, Object?>{
        'invite_state': <String, Object?>{
          'events': <Object?>[
            _state('m.room.name', '', <String, Object?>{
              'name': 'Demo-Einladung',
            }, sender: peerId),
            _state('m.room.member', userId, <String, Object?>{
              'membership': 'invite',
            }, sender: peerId),
          ],
        },
      },
    },
  };

  Map<String, Object?> _state(
    String type,
    String stateKey,
    Map<String, Object?> content, {
    String sender = userId,
  }) => <String, Object?>{
    'type': type,
    'state_key': stateKey,
    'content': content,
    'sender': sender,
    'event_id': '\$demo-state-${_eventCounter++}',
    'origin_server_ts': 1759999990000,
  };

  static Map<String, Object?> _event(
    String type,
    Map<String, Object?> content, {
    required String sender,
    required String id,
    required int ts,
  }) => <String, Object?>{
    'type': type,
    'content': content,
    'sender': sender,
    'event_id': id,
    'origin_server_ts': ts,
  };

  static http.StreamedResponse _json(int status, Map<String, Object?> body) =>
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );
}
