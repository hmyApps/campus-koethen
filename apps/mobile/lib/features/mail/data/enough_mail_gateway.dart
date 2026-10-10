// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';
import 'package:meta/meta.dart';

import '../domain/hsa_mail_profile.dart';
import '../domain/mail_credentials.dart' as domain;
import '../domain/mail_failure.dart';
import '../domain/mail_folder.dart';
import '../domain/mail_gateway.dart';
import '../domain/mail_message.dart' as model;
import 'html_to_text.dart';
import 'mail_mime_builder.dart';

/// The single boundary to enough_mail.
///
/// Security posture, enforced here and nowhere else:
///  - IMAP uses implicit TLS on 993; SMTP uses mandatory STARTTLS on 587. There
///    is no plaintext path and no fallback to 143 / 25 / 465.
///  - `onBadCertificate` is NEVER supplied, so `SecureSocket` performs full
///    certificate AND hostname validation and rejects anything invalid.
///  - `isLogEnabled` is NEVER set, so enough_mail's protocol logging — which
///    would print credentials and message content — stays off.
///  - Request methods open, use and close their own connections. The sole
///    exception is the explicitly cancellable foreground [watchInbox] stream.
///  - Raw exceptions are converted to a [MailFailure] classification; server
///    responses and credentials never escape this class.
/// The slowest throughput a transfer is given time for: 64 KiB/s (about
/// 0.5 Mbit/s, a weak mobile link). Transfers that carry a message body —
/// fetching it, submitting it, storing the Sent copy — get the normal command
/// timeout plus the time this rate needs for their size, instead of one fixed
/// limit that a large attachment can never meet.
const int kMailMinTransferBytesPerSecond = 64 * 1024;

class EnoughMailGateway implements MailGateway {
  factory EnoughMailGateway(
    HsaMailProfile profile, {
    Duration connectionTimeout = const Duration(seconds: 20),
    Duration commandTimeout = const Duration(seconds: 20),
    Duration cleanupTimeout = const Duration(seconds: 2),
    Duration verificationTimeout = const Duration(seconds: 25),
    int minTransferBytesPerSecond = kMailMinTransferBytesPerSecond,
    @visibleForTesting SmtpClient Function()? smtpClientFactory,
  }) => EnoughMailGateway._(
    profile,
    connectionTimeout,
    commandTimeout,
    cleanupTimeout,
    verificationTimeout,
    minTransferBytesPerSecond,
    smtpClientFactory,
  );

  EnoughMailGateway._(
    this._profile,
    this._connectionTimeout,
    this._commandTimeout,
    this._cleanupTimeout,
    this._verificationTimeout,
    this._minTransferBytesPerSecond,
    this._smtpClientFactory,
  );

  final HsaMailProfile _profile;
  final Duration _connectionTimeout;
  final Duration _commandTimeout;
  final Duration _cleanupTimeout;
  final Duration _verificationTimeout;
  final int _minTransferBytesPerSecond;
  final SmtpClient Function()? _smtpClientFactory;

  // --- IMAP -----------------------------------------------------------------

  Future<T> _withImap<T>(
    domain.MailCredentials credentials,
    Future<T> Function(ImapClient client) body, {
    Duration? operationTimeout,
  }) async {
    // No onBadCertificate, no isLogEnabled: defaults give full TLS validation
    // and silence.
    final ImapClient client = ImapClient(
      isLogEnabled: false,
      defaultWriteTimeout: _commandTimeout,
      defaultResponseTimeout: _commandTimeout,
    );
    bool timedOut = false;
    try {
      final Future<T> operation = () async {
        // The library's connection timeout covers opening the socket, but not a
        // server that accepts it and never sends its greeting. The outer timeout
        // bounds both parts.
        await client
            .connectToServer(
              _profile.imapHost,
              _profile.imapPort,
              isSecure: _profile.imapImplicitTls, // implicit TLS
              timeout: _connectionTimeout,
            )
            .timeout(_connectionTimeout);
        await client.login(credentials.emailAddress, credentials.password);
        return body(client);
      }();
      return await (operationTimeout == null
          ? operation
          : operation.timeout(operationTimeout));
    } on TimeoutException {
      timedOut = true;
      rethrow;
    } finally {
      // A timed-out command must not be followed by another protocol command:
      // close the socket directly so the abandoned Future cannot keep the
      // login alive in the background. Normal logout stays best effort only.
      if (!timedOut) {
        try {
          await client.logout().timeout(_cleanupTimeout);
        } catch (_) {}
      }
      try {
        await client.disconnect().timeout(_cleanupTimeout);
      } catch (_) {}
    }
  }

  // --- SMTP -----------------------------------------------------------------

  Future<T> _withSmtp<T>(
    domain.MailCredentials credentials,
    Future<T> Function(SmtpClient client) body, {
    Duration? operationTimeout,
  }) async {
    final SmtpClient client =
        _smtpClientFactory?.call() ??
        SmtpClient(_hostnameForEhlo, isLogEnabled: false);
    bool timedOut = false;
    try {
      final Future<T> operation = () async {
        await client
            .connectToServer(
              _profile.smtpHost,
              _profile.smtpPort,
              isSecure: false, // submission port, TLS via STARTTLS
              timeout: _connectionTimeout,
            )
            .timeout(_connectionTimeout);
        await client.ehlo().timeout(_commandTimeout);
        if (!client.serverInfo.supportsStartTls) {
          // The contract: abort rather than continue in the clear.
          throw const MailFailure(MailFailureKind.tls);
        }
        // enough_mail performs the mandatory second EHLO inside startTls().
        await client.startTls().timeout(_commandTimeout);
        await client
            .authenticate(
              credentials.emailAddress,
              credentials.password,
              AuthMechanism.login,
            )
            .timeout(_commandTimeout);
        return body(client);
      }();
      return await (operationTimeout == null
          ? operation
          : operation.timeout(operationTimeout));
    } on TimeoutException {
      timedOut = true;
      rethrow;
    } finally {
      if (!timedOut) {
        try {
          await client.quit().timeout(_cleanupTimeout);
        } catch (_) {}
      }
      try {
        await client.disconnect().timeout(_cleanupTimeout);
      } catch (_) {}
    }
  }

  /// A neutral EHLO identifier. Never a personal or campus hostname.
  static const String _hostnameForEhlo = 'campus-koethen.localhost';

  /// Selects [mailboxPath], taking the cheap INBOX shortcut when possible.
  Future<void> _select(ImapClient client, String mailboxPath) async {
    if (mailboxPath == kInboxPath) {
      await client.selectInbox();
    } else {
      await client.selectMailboxByPath(mailboxPath);
    }
  }

  /// Runs `TEXT` search declaring `CHARSET "UTF-8"` (quoted — the astring
  /// form every real IMAP server expects; an earlier, unquoted `CHARSET
  /// UTF-8` was rejected outright by the search folder's server for every
  /// query, regardless of content). If the server still cannot honour ANY
  /// explicit charset (`NO [BADCHARSET ...]`), retry once using its own
  /// default charset instead of surfacing a blanket protocol error — a
  /// documented, compatible fallback where non-ASCII terms may then not
  /// match, but ASCII search still works.
  Future<SearchImapResult> _searchText(ImapClient client, String safe) async {
    try {
      return await client.uidSearchMessages(
        searchCriteria: 'CHARSET "UTF-8" TEXT "$safe"',
        responseTimeout: _commandTimeout,
      );
    } on ImapException catch (e) {
      if (!_isUnsupportedCharset(e)) rethrow;
      return client.uidSearchMessages(
        searchCriteria: 'TEXT "$safe"',
        responseTimeout: _commandTimeout,
      );
    }
  }

  bool _isUnsupportedCharset(ImapException e) {
    final String detail = e.message?.toLowerCase() ?? '';
    return detail.contains('badcharset') || detail.contains('charset');
  }

  // --- Public API -----------------------------------------------------------

  @override
  Future<List<MailFolder>> fetchMailboxes(
    domain.MailCredentials credentials,
  ) async {
    return _guard(() async {
      return _withImap<List<MailFolder>>(credentials, (
        ImapClient client,
      ) async {
        final List<Mailbox> boxes = await client.listMailboxes(recursive: true);
        return boxes.map(_toFolder).toList();
      });
    });
  }

  @override
  Future<void> verifyConnection(domain.MailCredentials credentials) async {
    await _guard(() async {
      final DateTime deadline = DateTime.now().add(_verificationTimeout);
      // IMAP: connect + login proves the mailbox credentials.
      await _withImap(credentials, (ImapClient client) async {
        await client.selectInbox();
      }, operationTimeout: _remainingUntil(deadline));
      // SMTP: connect + STARTTLS + AUTH proves submission works, with no side
      // effect (no test mail is ever sent).
      await _withSmtp(
        credentials,
        (SmtpClient _) async {},
        operationTimeout: _remainingUntil(deadline),
      );
    });
  }

  Duration _remainingUntil(DateTime deadline) {
    final Duration remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) throw TimeoutException('mail verification');
    return remaining;
  }

  @override
  Future<List<model.MailMessageHeader>> fetchHeaders(
    domain.MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    int limit = 50,
    String? beforeId,
  }) async {
    return _guard(() async {
      return _withImap<List<model.MailMessageHeader>>(credentials, (
        ImapClient client,
      ) async {
        final Mailbox inbox = mailboxPath == kInboxPath
            ? await client.selectInbox()
            : await client.selectMailboxByPath(mailboxPath);
        if (inbox.messagesExists == 0) return <model.MailMessageHeader>[];

        if (beforeId != null) {
          final int? beforeUid = int.tryParse(beforeId);
          if (beforeUid == null) {
            throw const MailFailure(MailFailureKind.protocol);
          }
          if (beforeUid <= 1) return <model.MailMessageHeader>[];
          final SearchImapResult search = await client.uidSearchMessages(
            searchCriteria: 'UID 1:${beforeUid - 1}',
            responseTimeout: _commandTimeout,
          );
          final MessageSequence? matches = search.matchingSequence;
          if (matches == null || matches.isEmpty) {
            return <model.MailMessageHeader>[];
          }
          final List<int> uids = matches.toList()..sort();
          final List<int> page = uids.reversed.take(limit).toList();
          final FetchImapResult result = await client.uidFetchMessages(
            MessageSequence.fromIds(page, isUid: true),
            '(UID FLAGS ENVELOPE BODYSTRUCTURE)',
            responseTimeout: _commandTimeout,
          );
          return result.messages.map(_toHeader).toList()..sort(_newestFirst);
        }

        final int upper = inbox.messagesExists;
        final int lower = (upper - limit + 1).clamp(1, upper);
        final FetchImapResult result = await client.fetchMessages(
          MessageSequence.fromRange(lower, upper),
          // Headers + flags only. BODY.PEEK avoids marking anything \Seen; no
          // full body and no attachment is downloaded.
          '(UID FLAGS ENVELOPE BODYSTRUCTURE)',
          responseTimeout: _commandTimeout,
        );
        return result.messages.map(_toHeader).toList()..sort(_newestFirst);
      });
    });
  }

  @override
  Future<List<model.MailMessageHeader>> searchMessages(
    domain.MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String query,
    int limit = 50,
  }) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const <model.MailMessageHeader>[];
    return _guard(() async {
      return _withImap<List<model.MailMessageHeader>>(credentials, (
        ImapClient client,
      ) async {
        await _select(client, mailboxPath);
        // IMAP quoted-string escaping; TEXT matches the whole message (headers,
        // so the sender, AND the body, so the content).
        final String safe = trimmed
            .replaceAll('\\', r'\\')
            .replaceAll('"', r'\"');
        final SearchImapResult result = await _searchText(client, safe);
        final MessageSequence? matches = result.matchingSequence;
        if (matches == null || matches.isEmpty) {
          return <model.MailMessageHeader>[];
        }
        // Fetch only the newest [limit] matches to bound the work.
        final List<int> uids = matches.toList()..sort();
        final List<int> newest = uids.reversed.take(limit).toList();
        final FetchImapResult fetched = await client.uidFetchMessages(
          MessageSequence.fromIds(newest, isUid: true),
          '(UID FLAGS ENVELOPE BODYSTRUCTURE)',
          responseTimeout: _commandTimeout,
        );
        return fetched.messages.map(_toHeader).toList()..sort(_newestFirst);
      });
    });
  }

  @override
  Future<model.MailMessageDetail> fetchMessage(
    domain.MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String id,
    bool includeAttachmentBytes = false,
  }) async {
    return _guard(() async {
      return _withImap<model.MailMessageDetail>(credentials, (
        ImapClient client,
      ) async {
        await _select(client, mailboxPath);
        final int uid = int.parse(id);
        final FetchImapResult result = await client.uidFetchMessages(
          MessageSequence.fromRange(uid, uid, isUidSequence: true),
          '(UID FLAGS ENVELOPE BODY.PEEK[])',
          responseTimeout: _commandTimeout,
        );
        if (result.messages.isEmpty) {
          throw const MailFailure(MailFailureKind.protocol);
        }
        return _toDetail(result.messages.first, includeAttachmentBytes);
      });
    });
  }

  @override
  Future<List<model.MailMessageDetail>> fetchMessages(
    domain.MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required List<String> ids,
    bool includeAttachmentBytes = false,
  }) async {
    if (ids.isEmpty) return const <model.MailMessageDetail>[];
    return _guard(() async {
      return _withImap<List<model.MailMessageDetail>>(credentials, (
        ImapClient client,
      ) async {
        await _select(client, mailboxPath);
        final List<int> uids = ids
            .map(int.tryParse)
            .whereType<int>()
            .toList(growable: false);
        final List<model.MailMessageDetail> details =
            <model.MailMessageDetail>[];
        // One session, one fetch per id: enough_mail returns whole messages per
        // UID; a tighter batch API is not worth the risk of partial parsing.
        for (final int uid in uids) {
          final FetchImapResult result = await client.uidFetchMessages(
            MessageSequence.fromRange(uid, uid, isUidSequence: true),
            '(UID FLAGS ENVELOPE BODY.PEEK[])',
            responseTimeout: _commandTimeout,
          );
          if (result.messages.isNotEmpty) {
            details.add(
              _toDetail(result.messages.first, includeAttachmentBytes),
            );
          }
        }
        return details;
      });
    });
  }

  @override
  Future<void> markSeen(
    domain.MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String id,
  }) async {
    await _guard(() async {
      await _withImap(credentials, (ImapClient client) async {
        await _select(client, mailboxPath);
        final int uid = int.parse(id);
        await client.uidMarkSeen(
          MessageSequence.fromRange(uid, uid, isUidSequence: true),
        );
      });
    });
  }

  @override
  Future<void> deleteMessage(
    domain.MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String id,
  }) async {
    await _guard(() async {
      await _withImap(credentials, (ImapClient client) async {
        final int? uid = int.tryParse(id);
        if (uid == null || uid <= 0) {
          throw const MailFailure(MailFailureKind.protocol);
        }
        final List<Mailbox> boxes = await client.listMailboxes(recursive: true);
        Mailbox? trash = boxes.where((Mailbox box) => box.isTrash).firstOrNull;
        trash ??= boxes
            .where(
              (Mailbox box) =>
                  box.name == 'Trash' ||
                  box.name == 'Deleted Items' ||
                  box.name == 'Gelöschte Elemente' ||
                  box.name == 'Papierkorb',
            )
            .firstOrNull;
        await _select(client, mailboxPath);
        final MessageSequence sequence = MessageSequence.fromRange(
          uid,
          uid,
          isUidSequence: true,
        );

        if (trash != null && trash.encodedPath != mailboxPath) {
          // enough_mail sets no response timeout for MOVE/COPY. On timeout
          // [_withImap] closes the socket instead of sending LOGOUT.
          if (client.serverInfo.supportsMove) {
            await client
                .uidMove(sequence, targetMailbox: trash)
                .timeout(_commandTimeout);
            return;
          }
          if (!client.serverInfo.supportsUidPlus) {
            // A broad EXPUNGE could irreversibly remove unrelated messages
            // another client marked. Fail closed when UID-scoped cleanup is
            // unavailable.
            throw const MailFailure(MailFailureKind.protocol);
          }
          await client
              .uidCopy(sequence, targetMailbox: trash)
              .timeout(_commandTimeout);
          await client.uidMarkDeleted(sequence, silent: true);
          await client.uidExpunge(sequence);
          return;
        }

        if (!client.serverInfo.supportsUidPlus) {
          throw const MailFailure(MailFailureKind.protocol);
        }
        await client.uidMarkDeleted(sequence, silent: true);
        await client.uidExpunge(sequence);
      });
    });
  }

  @override
  Stream<MailLiveSignal> watchInbox(domain.MailCredentials credentials) {
    late final StreamController<MailLiveSignal> controller;
    ImapClient? client;
    Timer? keepAlive;
    final List<StreamSubscription<dynamic>> subscriptions =
        <StreamSubscription<dynamic>>[];
    bool idle = false;
    bool closing = false;
    bool restarting = false;

    Future<void> cleanup() async {
      if (closing) return;
      closing = true;
      keepAlive?.cancel();
      for (final StreamSubscription<dynamic> subscription in subscriptions) {
        await subscription.cancel();
      }
      final ImapClient? active = client;
      if (active == null) return;
      if (idle) {
        try {
          await active.idleDone().timeout(_cleanupTimeout);
        } catch (_) {}
      }
      try {
        await active.logout().timeout(_cleanupTimeout);
      } catch (_) {}
      try {
        await active.disconnect().timeout(_cleanupTimeout);
      } catch (_) {}
    }

    MailFailure safeFailure(Object error) {
      if (error is MailFailure) return error;
      if (error is TimeoutException) {
        return const MailFailure(MailFailureKind.timeout);
      }
      if (error is HandshakeException || error is TlsException) {
        return const MailFailure(MailFailureKind.tls);
      }
      if (error is SocketException) {
        return const MailFailure(MailFailureKind.serverUnreachable);
      }
      if (error is ImapException) {
        return MailFailure(_classifyImap(error));
      }
      return const MailFailure(MailFailureKind.protocol);
    }

    Future<void> fail(Object error) async {
      if (closing || controller.isClosed) return;
      controller.addError(safeFailure(error));
      await controller.close();
    }

    void changed() {
      if (!closing && !controller.isClosed) {
        controller.add(MailLiveSignal.changed);
      }
    }

    Future<void> restartIdle() async {
      final ImapClient? active = client;
      if (active == null || closing || restarting) return;
      restarting = true;
      try {
        await active.idleDone().timeout(_commandTimeout);
        idle = false;
        await active.idleStart().timeout(_commandTimeout);
        idle = true;
      } catch (error) {
        await fail(error);
      } finally {
        restarting = false;
      }
    }

    Future<void> poll() async {
      final ImapClient? active = client;
      if (active == null || closing || restarting) return;
      restarting = true;
      try {
        await active.noop().timeout(_commandTimeout);
        changed();
      } catch (error) {
        await fail(error);
      } finally {
        restarting = false;
      }
    }

    Future<void> connect() async {
      try {
        final ImapClient active = ImapClient(
          isLogEnabled: false,
          defaultWriteTimeout: _commandTimeout,
          defaultResponseTimeout: _commandTimeout,
        );
        client = active;
        await active
            .connectToServer(
              _profile.imapHost,
              _profile.imapPort,
              isSecure: _profile.imapImplicitTls,
              timeout: _connectionTimeout,
            )
            .timeout(_connectionTimeout);
        await active.login(credentials.emailAddress, credentials.password);
        await active.selectInbox();
        if (closing) return;

        subscriptions.addAll(<StreamSubscription<dynamic>>[
          active.eventBus.on<ImapMessagesExistEvent>().listen((event) {
            if (event.newMessagesExists > event.oldMessagesExists) changed();
          }),
          active.eventBus.on<ImapMessagesRecentEvent>().listen((event) {
            if (event.newMessagesRecent > event.oldMessagesRecent) changed();
          }),
          active.eventBus.on<ImapExpungeEvent>().listen((_) => changed()),
          active.eventBus.on<ImapVanishedEvent>().listen((_) => changed()),
          active.eventBus.on<ImapFetchEvent>().listen((_) => changed()),
          active.eventBus.on<ImapConnectionLostEvent>().listen(
            (_) => unawaited(
              fail(const MailFailure(MailFailureKind.serverUnreachable)),
            ),
          ),
        ]);

        if (active.serverInfo.supportsIdle) {
          await active.idleStart().timeout(_commandTimeout);
          idle = true;
          controller.add(MailLiveSignal.connected);
          // RFC 2177 recommends ending IDLE before the common 30-minute
          // server timeout. Restarting keeps one authenticated foreground
          // session without periodic full mailbox downloads.
          keepAlive = Timer.periodic(
            const Duration(minutes: 25),
            (_) => unawaited(restartIdle()),
          );
        } else {
          controller.add(MailLiveSignal.pollingFallback);
          keepAlive = Timer.periodic(
            const Duration(minutes: 1),
            (_) => unawaited(poll()),
          );
        }
      } catch (error) {
        await fail(error);
      }
    }

    controller = StreamController<MailLiveSignal>(
      onListen: () => unawaited(connect()),
      onCancel: cleanup,
    );
    return controller.stream;
  }

  @override
  Future<void> send(
    domain.MailCredentials credentials,
    model.OutgoingMessage message,
  ) async {
    final MimeMessage mime = buildOutgoingMime(credentials, message);
    // SMTP send only. Storing a Sent copy is a separate call so the UI is not
    // blocked on a second IMAP round trip.
    bool submitting = false;
    try {
      await _guard(() async {
        await _withSmtp(credentials, (SmtpClient client) async {
          submitting = true;
          // Bounded by size: a stalled submission must not hold the compose
          // screen forever. On timeout [_withSmtp] closes the socket without
          // another protocol command.
          await client
              .sendMessage(mime)
              .timeout(_transferTimeout(_estimatedWireBytes(message)));
        });
      });
    } on MailFailure catch (failure) {
      if (submitting && failure.kind == MailFailureKind.timeout) {
        // The message data may already be with the server. Never report this
        // as "not sent", which invites a duplicate, and never retry here.
        throw const MailFailure(MailFailureKind.sendOutcomeUnknown);
      }
      rethrow;
    }
  }

  /// The command timeout plus the time [bytes] need at the minimum assumed
  /// throughput ([kMailMinTransferBytesPerSecond] by default).
  Duration _transferTimeout(int bytes) =>
      _commandTimeout +
      Duration(
        milliseconds: (bytes * 1000 / _minTransferBytesPerSecond).ceil(),
      );

  /// An upper estimate of the message on the wire: base64 grows attachments by
  /// a third, plus room for headers and MIME boundaries.
  static int _estimatedWireBytes(model.OutgoingMessage message) {
    int bytes = 64 * 1024 + utf8.encode(message.text).length;
    for (final model.OutgoingAttachment attachment in message.attachments) {
      bytes += (attachment.bytes.length * 4 / 3).ceil();
    }
    return bytes;
  }

  @override
  Future<SentCopyResult> appendToSent(
    domain.MailCredentials credentials,
    model.OutgoingMessage message,
  ) async {
    // Never throws: the message has already been sent, so a copy failure is a
    // reported outcome, not an error.
    try {
      return await _appendMimeToSent(
        credentials,
        buildOutgoingMime(credentials, message),
      );
    } catch (_) {
      return SentCopyResult.appendFailed;
    }
  }

  Future<SentCopyResult> _appendMimeToSent(
    domain.MailCredentials credentials,
    MimeMessage mime,
  ) async {
    return _withImap<SentCopyResult>(credentials, (ImapClient client) async {
      final List<Mailbox> boxes = await client.listMailboxes();
      // Prefer the \Sent special-use flag; fall back to conservative names.
      Mailbox? sent = boxes
          .where((Mailbox b) => b.flags.contains(MailboxFlag.sent))
          .firstOrNull;
      sent ??= boxes
          .where(
            (Mailbox b) =>
                b.name == 'Sent' ||
                b.name == 'Gesendet' ||
                b.name == 'Sent Items',
          )
          .firstOrNull;
      if (sent == null) {
        // Never create a folder unprompted.
        return SentCopyResult.noSentFolder;
      }
      // Rendered once here (appendMessage would render it again) so the
      // upload can be bounded by its size; enough_mail sets no limit itself.
      final String text = mime.renderMessage();
      await client
          .appendMessageText(
            text,
            targetMailbox: sent,
            flags: <String>[MessageFlags.seen],
          )
          .timeout(_transferTimeout(utf8.encode(text).length));
      return SentCopyResult.appended;
    });
  }

  // --- Mapping --------------------------------------------------------------

  /// Sorts headers newest first; messages without a date sink to the end.
  static int _newestFirst(
    model.MailMessageHeader a,
    model.MailMessageHeader b,
  ) {
    final DateTime? da = a.date;
    final DateTime? db = b.date;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  }

  model.MailMessageHeader _toHeader(MimeMessage m) {
    final MailAddress? from = m.from?.firstOrNull ?? m.sender;
    return model.MailMessageHeader(
      id: (m.uid ?? m.sequenceId ?? 0).toString(),
      subject: m.decodeSubject() ?? '',
      from: model.MailAddress(
        email: from?.email ?? '',
        name: from?.personalName,
      ),
      date: m.decodeDate(),
      isSeen: m.isSeen,
      hasAttachments: m.hasAttachments(),
    );
  }

  model.MailMessageDetail _toDetail(
    MimeMessage m,
    bool includeAttachmentBytes,
  ) {
    final MailAddress? from = m.from?.firstOrNull ?? m.sender;
    final String? plain = m.decodeTextPlainPart();
    final String body = (plain != null && plain.trim().isNotEmpty)
        ? normalizeMailBody(plain)
        // Only if there is no plain part: reduce HTML to safe text. No remote
        // images are ever fetched because we render text, not HTML.
        : htmlToPlainText(m.decodeTextHtmlPart());
    return model.MailMessageDetail(
      id: (m.uid ?? m.sequenceId ?? 0).toString(),
      subject: m.decodeSubject() ?? '',
      from: model.MailAddress(
        email: from?.email ?? '',
        name: from?.personalName,
      ),
      to: (m.to ?? const <MailAddress>[])
          .map(
            (MailAddress a) =>
                model.MailAddress(email: a.email, name: a.personalName),
          )
          .toList(),
      cc: (m.cc ?? const <MailAddress>[])
          .map(
            (MailAddress a) =>
                model.MailAddress(email: a.email, name: a.personalName),
          )
          .toList(),
      date: m.decodeDate(),
      body: body,
      attachments: _attachmentsOf(m, includeAttachmentBytes),
    );
  }

  /// Extracts attachment metadata. Bytes are decoded from the already downloaded
  /// message (no extra fetch, no network, no file written): images always (for
  /// the inline preview) and — when [includeFiles] — other types too, so a
  /// downloaded attachment is available offline.
  List<model.MailAttachment> _attachmentsOf(MimeMessage m, bool includeFiles) {
    final List<ContentInfo> infos = m.findContentInfo();
    return infos.map((ContentInfo info) {
      final String type = info.mediaType?.text ?? 'application/octet-stream';
      final Uint8List? bytes = (info.isImage || includeFiles)
          ? m.getPart(info.fetchId)?.decodeContentBinary()
          : null;
      return model.MailAttachment(
        filename: info.fileName ?? info.fetchId,
        mediaType: type,
        sizeBytes: info.size ?? bytes?.length,
        bytes: bytes,
      );
    }).toList();
  }

  MailFolder _toFolder(Mailbox box) => MailFolder(
    path: box.encodedPath,
    name: box.name,
    role: _roleOf(box),
    isSelectable: !box.isNotSelectable,
  );

  MailFolderRole _roleOf(Mailbox box) {
    if (box.isInbox) return MailFolderRole.inbox;
    if (box.isSent) return MailFolderRole.sent;
    if (box.isDrafts) return MailFolderRole.drafts;
    if (box.isTrash) return MailFolderRole.trash;
    if (box.isJunk) return MailFolderRole.junk;
    if (box.isArchive) return MailFolderRole.archive;
    return MailFolderRole.plain;
  }

  // --- Error handling -------------------------------------------------------

  /// Runs [body], converting every raw failure into a typed [MailFailure] so no
  /// server text or credential can reach the UI.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on MailFailure {
      rethrow;
    } on TimeoutException {
      throw const MailFailure(MailFailureKind.timeout);
    } on HandshakeException {
      throw const MailFailure(MailFailureKind.tls);
    } on TlsException {
      throw const MailFailure(MailFailureKind.tls);
    } on SocketException {
      throw const MailFailure(MailFailureKind.serverUnreachable);
    } on ImapException catch (e) {
      throw MailFailure(_classifyImap(e));
    } on SmtpException catch (e) {
      throw MailFailure(_classifySmtp(e));
    } catch (_) {
      throw const MailFailure(MailFailureKind.protocol);
    }
  }

  /// SMTP reply codes that genuinely mean "these credentials are wrong".
  ///
  /// 534 and 538 ask for a different mechanism, 535 rejects the credentials
  /// outright. Everything else — including the 4xx family, where 454 is
  /// literally *temporary* authentication failure — is a server condition,
  /// and telling someone to check a password they typed correctly sends them
  /// off to reset a working university account.
  static const Set<int> _smtpAuthRejected = <int>{534, 535, 538};

  /// IMAP has no reply code on its exception, only free text, so the match has
  /// to stay textual. It is kept as narrow as the protocol allows: RFC 3501
  /// spells the authentication rejections `AUTHENTICATIONFAILED`,
  /// `AUTHORIZATIONFAILED` and `[PRIVACYREQUIRED]`, and the bare words "auth"
  /// or "login" appear in far too much unrelated server chatter — they are
  /// what made an overloaded server report itself as a wrong password.
  static final RegExp _imapAuthRejected = RegExp(
    r'authenticationfailed|authorizationfailed|invalid credentials|'
    r'authentication failed|login failed',
    caseSensitive: false,
  );

  MailFailureKind _classifyImap(ImapException e) {
    final String detail = e.message ?? '';
    if (detail.toLowerCase().contains('timeout')) {
      return MailFailureKind.timeout;
    }
    if (_imapAuthRejected.hasMatch(detail)) {
      return MailFailureKind.invalidCredentials;
    }
    return MailFailureKind.protocol;
  }

  MailFailureKind _classifySmtp(SmtpException e) {
    // The structured code, not the prose around it.
    final int? code = e.response.code;
    if (code != null && _smtpAuthRejected.contains(code)) {
      return MailFailureKind.invalidCredentials;
    }
    if (e.response.type == SmtpResponseType.temporaryError) {
      // 4xx: come back later. Not a credential problem, whatever the text says.
      return MailFailureKind.serverUnreachable;
    }
    return MailFailureKind.protocol;
  }
}
