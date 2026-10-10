// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:typed_data';

import 'package:campus_koethen/features/mail/data/mail_attachment_picker.dart';
import 'package:campus_koethen/features/mail/domain/mail_credential_store.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:campus_koethen/features/mail/domain/mail_folder.dart';
import 'package:campus_koethen/features/mail/domain/mail_gateway.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';

/// In-memory credential store for tests. NEVER touches a real platform channel.
class InMemoryMailCredentialStore implements MailCredentialStore {
  InMemoryMailCredentialStore({
    this.available = true,
    this.clearAvailable = true,
  });

  /// When false, mimics a device where secure storage cannot be used.
  final bool available;
  bool clearAvailable;
  MailCredentials? _stored;

  int writes = 0;
  int clears = 0;

  /// The most recently written credentials (synchronous peek for assertions).
  MailCredentials? get lastWritten => _stored;

  @override
  Future<MailCredentials?> read() async => _stored;

  @override
  Future<void> write(MailCredentials credentials) async {
    if (!available) {
      throw const MailFailure(MailFailureKind.secureStorageUnavailable);
    }
    _stored = credentials;
    writes++;
  }

  @override
  Future<void> clear() async {
    if (!clearAvailable) {
      throw const MailFailure(MailFailureKind.localDataWipeIncomplete);
    }
    _stored = null;
    clears++;
  }
}

/// Scriptable fake gateway. Records calls so tests can assert no double-send etc.
class FakeMailGateway implements MailGateway {
  FakeMailGateway({
    this.verifyError,
    this.inbox = const <MailMessageHeader>[],
    this.olderInbox = const <MailMessageHeader>[],
    this.detail,
    this.fetchInboxError,
    this.sendError,
    this.sentCopy = SentCopyResult.appended,
    this.folders = const <MailFolder>[],
    this.detailsById = const <String, MailMessageDetail>{},
    this.searchResults = const <MailMessageHeader>[],
    this.fetchHeadersGate,
    this.fetchHeadersStarted,
    this.fetchOlderHeadersGate,
    this.fetchOlderHeadersStarted,
    this.verifyGate,
    this.verifyStarted,
    this.searchError,
    this.searchGate,
    this.searchStarted,
    this.markSeenError,
    this.sendGate,
    this.sendStarted,
    this.messagesExists,
    this.uidValidity,
  });

  MailFailure? verifyError;
  MailFailure? fetchInboxError;
  MailFailure? sendError;
  List<MailMessageHeader> inbox;
  List<MailMessageHeader> olderInbox;
  MailMessageDetail? detail;
  SentCopyResult sentCopy;
  List<MailFolder> folders;

  /// Full messages returned by [fetchMessage]/[fetchMessages], keyed by id.
  Map<String, MailMessageDetail> detailsById;

  /// Headers returned by [searchMessages]. Records the last query/mailbox.
  List<MailMessageHeader> searchResults;
  Completer<void>? fetchHeadersGate;
  Completer<void>? fetchHeadersStarted;
  Completer<void>? fetchOlderHeadersGate;
  Completer<void>? fetchOlderHeadersStarted;

  /// Lets a test hold [verifyConnection] open (simulating a hang) and signal
  /// once the call has actually started, so it can assert on the loading
  /// state before completing or aborting it.
  Completer<void>? verifyGate;
  Completer<void>? verifyStarted;

  /// Lets a test hold [searchMessages] open the same way, and inject a
  /// distinct server-error failure independent of [fetchInboxError].
  MailFailure? searchError;
  Completer<void>? searchGate;
  Completer<void>? searchStarted;

  /// When set, [markSeen] throws instead of recording — simulates a network
  /// failure of the best-effort server sync.
  MailFailure? markSeenError;
  String? lastSearchQuery;
  String? lastSearchMailbox;

  /// Lets a test hold [send] open (simulating an in-flight submission) and
  /// signal once the call has actually started, so it can assert on the
  /// sending UI state before completing it.
  Completer<void>? sendGate;
  Completer<void>? sendStarted;

  int verifyCalls = 0;
  int sendCalls = 0;
  int appendCalls = 0;
  bool lastIncludeAttachmentBytes = false;
  final List<String> markedSeen = <String>[];
  final List<({String mailboxPath, String id})> deletedMessages =
      <({String mailboxPath, String id})>[];
  final List<String> fetchedMailboxes = <String>[];
  final StreamController<MailLiveSignal> liveSignals =
      StreamController<MailLiveSignal>.broadcast();
  int watchInboxCalls = 0;
  String? lastFetchHeadersBeforeId;
  int? lastFetchHeadersLimit;
  List<String> lastFetchMessageIds = <String>[];
  final List<OutgoingMessage> sent = <OutgoingMessage>[];
  final List<OutgoingMessage> appended = <OutgoingMessage>[];

  @override
  Future<void> verifyConnection(MailCredentials credentials) async {
    verifyCalls++;
    if (!(verifyStarted?.isCompleted ?? true)) {
      verifyStarted!.complete();
    }
    await verifyGate?.future;
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<List<MailFolder>> fetchMailboxes(MailCredentials credentials) async {
    return folders;
  }

  /// IMAP EXISTS reported with every header page. Unset, the fake's [inbox]
  /// is the whole mailbox; a test modelling a mailbox larger than the fetched
  /// window sets it explicitly.
  int? messagesExists;

  /// UIDVALIDITY reported with every header page (null: not reported).
  int? uidValidity;

  /// The UIDVALIDITY guard passed with the last markSeen/deleteMessage.
  int? lastExpectedUidValidity;

  @override
  Future<MailHeaderPage> fetchHeaders(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    int limit = 50,
    String? beforeId,
  }) async {
    fetchedMailboxes.add(mailboxPath);
    lastFetchHeadersBeforeId = beforeId;
    lastFetchHeadersLimit = limit;
    if (beforeId == null) {
      if (!(fetchHeadersStarted?.isCompleted ?? true)) {
        fetchHeadersStarted!.complete();
      }
      await fetchHeadersGate?.future;
    } else {
      if (!(fetchOlderHeadersStarted?.isCompleted ?? true)) {
        fetchOlderHeadersStarted!.complete();
      }
      await fetchOlderHeadersGate?.future;
    }
    if (fetchInboxError != null) throw fetchInboxError!;
    return MailHeaderPage(
      headers: beforeId == null ? inbox : olderInbox,
      messagesExists: messagesExists ?? inbox.length,
      uidValidity: uidValidity,
    );
  }

  @override
  Future<List<MailMessageHeader>> searchMessages(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String query,
    int limit = 50,
  }) async {
    lastSearchQuery = query;
    lastSearchMailbox = mailboxPath;
    if (!(searchStarted?.isCompleted ?? true)) {
      searchStarted!.complete();
    }
    await searchGate?.future;
    if (searchError != null) throw searchError!;
    if (fetchInboxError != null) throw fetchInboxError!;
    return searchResults;
  }

  @override
  Future<MailMessageDetail> fetchMessage(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String id,
    bool includeAttachmentBytes = false,
  }) async {
    lastIncludeAttachmentBytes = includeAttachmentBytes;
    final MailMessageDetail? d = detailsById[id] ?? detail;
    if (d == null) throw const MailFailure(MailFailureKind.protocol);
    return d;
  }

  @override
  Future<List<MailMessageDetail>> fetchMessages(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required List<String> ids,
    bool includeAttachmentBytes = false,
  }) async {
    lastIncludeAttachmentBytes = includeAttachmentBytes;
    lastFetchMessageIds = List<String>.of(ids);
    return ids
        .map((String id) => detailsById[id])
        .whereType<MailMessageDetail>()
        .toList();
  }

  @override
  Future<void> markSeen(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String id,
    int? expectedUidValidity,
  }) async {
    lastExpectedUidValidity = expectedUidValidity;
    if (markSeenError != null) throw markSeenError!;
    markedSeen.add(id);
  }

  @override
  Future<void> deleteMessage(
    MailCredentials credentials, {
    String mailboxPath = kInboxPath,
    required String id,
    int? expectedUidValidity,
  }) async {
    lastExpectedUidValidity = expectedUidValidity;
    deletedMessages.add((mailboxPath: mailboxPath, id: id));
  }

  @override
  Stream<MailLiveSignal> watchInbox(MailCredentials credentials) {
    watchInboxCalls++;
    return liveSignals.stream;
  }

  @override
  Future<void> send(
    MailCredentials credentials,
    OutgoingMessage message,
  ) async {
    sendCalls++;
    if (!(sendStarted?.isCompleted ?? true)) {
      sendStarted!.complete();
    }
    await sendGate?.future;
    if (sendError != null) throw sendError!;
    sent.add(message);
  }

  @override
  Future<SentCopyResult> appendToSent(
    MailCredentials credentials,
    OutgoingMessage message,
  ) async {
    appendCalls++;
    appended.add(message);
    return sentCopy;
  }
}

/// Scriptable fake picked file. Lets a test simulate a file that becomes
/// unreadable by send time without touching any real filesystem.
class FakePickedMailFile implements PickedMailFile {
  FakePickedMailFile({
    required this.filename,
    required this.mediaType,
    required Uint8List bytes,
    this.readError,
    this.reportedSizeBytes,
    // The public parameter is named `bytes` for a readable call site, so it
    // cannot be an initializing formal for the private `_bytes` field (that
    // would force callers to write the private name).
    // ignore: prefer_initializing_formals
  }) : _bytes = bytes;

  @override
  final String filename;
  @override
  final String mediaType;
  final Uint8List _bytes;

  /// When set, [readBytes] throws this instead of returning the bytes.
  final Object? readError;
  final int? reportedSizeBytes;

  int readCalls = 0;

  @override
  Future<int?> sizeBytes() async => reportedSizeBytes ?? _bytes.length;

  @override
  Future<Uint8List> readBytes({
    int maxBytes = MailAttachmentLimits.maxFileBytes,
  }) async {
    readCalls++;
    if (readError != null) throw readError!;
    if (_bytes.length > maxBytes) {
      throw const MailAttachmentLimitException(
        MailAttachmentBudgetIssue.fileTooLarge,
      );
    }
    return _bytes;
  }
}

/// Scriptable fake picker so widget tests never open a real OS dialog.
class FakeMailAttachmentPicker implements MailAttachmentPicker {
  FakeMailAttachmentPicker({this.results = const <MailFilePickResult>[]});

  /// Results returned in order across successive calls; once exhausted the
  /// last one repeats.
  List<MailFilePickResult> results;
  int calls = 0;

  @override
  Future<MailFilePickResult> pickFiles() async {
    if (results.isEmpty) return const MailFilePickCancelled();
    final MailFilePickResult result =
        results[calls.clamp(0, results.length - 1)];
    calls++;
    return result;
  }
}
