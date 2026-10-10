// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';

/// A minimal, hand-rolled IMAP server for gateway integration tests.
///
/// Speaks just enough real IMAP over a real loopback TCP socket — greeting,
/// LOGIN, the implicit LIST that enough_mail runs before the first SELECT,
/// SELECT, UID SEARCH, UID FETCH, LOGOUT — so [EnoughMailGateway] is driven
/// end to end, including the exact command text it puts on the wire and its
/// parsing of the response. Each connected test can inspect
/// [receivedCommands] to assert on that command text.
class FakeImapServer {
  FakeImapServer._(
    this._server,
    this.onCommand,
    this._greeting,
    this._replyDelay,
  );

  final ServerSocket _server;
  final List<String> Function(String tag, String command) onCommand;
  final String _greeting;

  /// Optional per-command delay before the reply is written, to model a slow
  /// link without real network latency.
  final Duration Function(String command)? _replyDelay;

  /// Every command line received, across all connections, in order.
  final List<String> receivedCommands = <String>[];

  static Future<FakeImapServer> start(
    List<String> Function(String tag, String command) onCommand, {
    String greeting = '* OK IMAP4rev1 fake server ready',
    Duration Function(String command)? replyDelay,
  }) async {
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final FakeImapServer fake = FakeImapServer._(
      server,
      onCommand,
      greeting,
      replyDelay,
    );
    server.listen(fake._handleConnection);
    return fake;
  }

  int get port => _server.port;

  void _handleConnection(Socket socket) {
    socket.write('$_greeting\r\n');
    final StringBuffer pending = StringBuffer();
    socket.listen((List<int> data) {
      pending.write(utf8.decode(data));
      String buffered = pending.toString();
      int splitIndex;
      while ((splitIndex = buffered.indexOf('\r\n')) != -1) {
        final String line = buffered.substring(0, splitIndex);
        buffered = buffered.substring(splitIndex + 2);
        _handleLine(socket, line);
      }
      pending
        ..clear()
        ..write(buffered);
    });
  }

  void _handleLine(Socket socket, String line) {
    if (line.isEmpty) return;
    receivedCommands.add(line);
    final int spaceIndex = line.indexOf(' ');
    final String tag = spaceIndex == -1 ? line : line.substring(0, spaceIndex);
    final String command = spaceIndex == -1
        ? ''
        : line.substring(spaceIndex + 1);
    final List<String> reply = onCommand(tag, command);
    void write() {
      for (final String replyLine in reply) {
        socket.write('$replyLine\r\n');
      }
    }

    final Duration delay = _replyDelay?.call(command) ?? Duration.zero;
    if (delay == Duration.zero) {
      write();
    } else {
      Future<void>.delayed(delay, write);
    }
  }

  Future<void> close() => _server.close();
}

/// A canned inbox message for [fakeFetchHandler].
class FakeImapMessage {
  const FakeImapMessage({
    required this.uid,
    required this.subject,
    required this.fromName,
    required this.fromLocal,
    required this.fromDomain,
    this.seen = true,
    this.date = 'Mon, 1 Jun 2026 08:00:00 +0200',
  });

  final int uid;
  final String subject;
  final String fromName;
  final String fromLocal;
  final String fromDomain;
  final bool seen;

  /// IMAP envelope date string (RFC 2822 format).
  final String date;
}

/// The default IMAP scaffolding every test needs: LOGIN, the implicit LIST,
/// and SELECT succeed unconditionally; [onSearch] and [onFetch] decide the
/// part actually under test.
List<String> Function(String tag, String command) fakeImapHandler({
  required List<String> Function(String tag, String command) onSearch,
  required List<String> Function(String tag, String command) onFetch,
}) {
  return (String tag, String command) {
    if (command.startsWith('LOGIN ')) {
      return <String>['$tag OK LOGIN completed'];
    }
    if (command.startsWith('LIST')) {
      return <String>[
        '* LIST (\\HasNoChildren) "/" "INBOX"',
        '$tag OK LIST completed',
      ];
    }
    if (command.startsWith('SELECT') || command.startsWith('EXAMINE')) {
      return <String>[
        '* 1 EXISTS',
        '* 0 RECENT',
        '* OK [UIDVALIDITY 1] UIDs valid',
        '* OK [UIDNEXT 2] Predicted next UID',
        '* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)',
        '$tag OK [READ-WRITE] SELECT completed',
      ];
    }
    if (command.startsWith('UID SEARCH')) {
      return onSearch(tag, command);
    }
    if (command.startsWith('UID FETCH')) {
      return onFetch(tag, command);
    }
    if (command.startsWith('LOGOUT')) {
      return <String>['* BYE logging out', '$tag OK LOGOUT completed'];
    }
    return <String>['$tag OK done'];
  };
}

/// Replies with a `* SEARCH` line listing [uids] (empty means no hits).
List<String> Function(String tag, String command) fakeSearchHits(
  List<int> uids,
) {
  return (String tag, String command) {
    if (uids.isEmpty) return <String>['* SEARCH', '$tag OK SEARCH completed'];
    return <String>['* SEARCH ${uids.join(' ')}', '$tag OK SEARCH completed'];
  };
}

/// Replies `NO [BADCHARSET ...]` whenever the search declares ANY charset —
/// modelling a server that rejects the historic unquoted `CHARSET UTF-8`
/// clause AND cannot honour a charset declaration at all, so the gateway
/// must fall back to a plain, charset-less search.
List<String> Function(String tag, String command) fakeSearchRejectsCharset({
  required List<int> fallbackUids,
}) {
  return (String tag, String command) {
    if (command.contains('CHARSET')) {
      return <String>['$tag NO [BADCHARSET (US-ASCII)] Unsupported charset'];
    }
    return fakeSearchHits(fallbackUids)(tag, command);
  };
}

/// Replies with a FETCH line per requested UID present in [messages],
/// carrying just enough ENVELOPE/BODYSTRUCTURE for [EnoughMailGateway] to map
/// a header.
List<String> Function(String tag, String command) fakeFetchHandler(
  Map<int, FakeImapMessage> messages,
) {
  return (String tag, String command) {
    final RegExp idsPattern = RegExp(r'^UID FETCH ([\d,]+) ');
    final RegExpMatch? match = idsPattern.firstMatch(command);
    final List<int> ids = match == null
        ? const <int>[]
        : match.group(1)!.split(',').map(int.parse).toList(growable: false);
    final List<String> lines = <String>[];
    for (final int id in ids) {
      final FakeImapMessage? m = messages[id];
      if (m == null) continue;
      lines.add(
        '* $id FETCH (UID $id FLAGS (${m.seen ? '\\Seen' : ''}) '
        'ENVELOPE ("${m.date}" "${m.subject}" '
        '(("${m.fromName}" NIL "${m.fromLocal}" "${m.fromDomain}")) '
        '(("${m.fromName}" NIL "${m.fromLocal}" "${m.fromDomain}")) '
        '(("${m.fromName}" NIL "${m.fromLocal}" "${m.fromDomain}")) '
        'NIL NIL NIL NIL "<$id@fake>") '
        'BODYSTRUCTURE ("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 100 5))',
      );
    }
    lines.add('$tag OK FETCH completed');
    return lines;
  };
}
