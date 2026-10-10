// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

import '../domain/mail_message.dart';

/// Pre-filled content handed to the compose screen — for a blank message, a
/// reply or a reply-all. Pure data plus the pure logic that derives replies, so
/// the recipient handling can be unit-tested without a widget or a server.
@immutable
class ComposeDraft {
  const ComposeDraft({
    this.to = const <String>[],
    this.cc = const <String>[],
    this.subject = '',
    this.body = '',
  });

  final List<String> to;
  final List<String> cc;
  final String subject;
  final String body;

  /// A reply to [message]: the original sender — or, when the message names
  /// one, its `Reply-To` address.
  factory ComposeDraft.reply(
    MailMessageDetail message, {
    required String attribution,
  }) {
    return ComposeDraft(
      to: _replyTargets(message),
      subject: replySubject(message.subject),
      body: quotedBody(message.body, attribution),
    );
  }

  /// A reply to everyone: the reply target (sender or `Reply-To`) in To, and
  /// every other original recipient (To + Cc) in Cc, minus your own address
  /// and the reply target.
  factory ComposeDraft.replyAll(
    MailMessageDetail message, {
    required String selfEmail,
    required String attribution,
  }) {
    final List<String> targets = _replyTargets(message);
    final List<String> others =
        <String>[
              for (final MailAddress a in message.to) a.email,
              for (final MailAddress a in message.cc) a.email,
            ]
            .where(
              (String e) =>
                  !_same(e, selfEmail) &&
                  !targets.any((String target) => _same(e, target)),
            )
            .toList();

    return ComposeDraft(
      to: targets,
      cc: _dedupe(_clean(others)),
      subject: replySubject(message.subject),
      body: quotedBody(message.body, attribution),
    );
  }

  bool get isEmpty =>
      to.isEmpty && cc.isEmpty && subject.isEmpty && body.isEmpty;

  /// `Reply-To` wins over `From` (RFC 5322 §3.6.2): mailing lists, offices
  /// and no-reply senders use it to route answers.
  static List<String> _replyTargets(MailMessageDetail message) {
    final List<String> replyTo = _dedupe(
      _clean(message.replyTo.map((MailAddress a) => a.email)),
    );
    return replyTo.isNotEmpty ? replyTo : _clean(<String>[message.from.email]);
  }

  static List<String> _clean(Iterable<String> addresses) => addresses
      .map((String e) => e.trim())
      .where((String e) => e.isNotEmpty)
      .toList();

  static List<String> _dedupe(List<String> addresses) {
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final String address in addresses) {
      if (seen.add(address.toLowerCase())) result.add(address);
    }
    return result;
  }

  static bool _same(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();
}

final RegExp _rePrefix = RegExp(r'^re:', caseSensitive: false);

/// Prefixes `Re: ` unless the subject already carries a reply marker.
String replySubject(String subject) {
  final String trimmed = subject.trim();
  if (trimmed.isEmpty) return 'Re:';
  return _rePrefix.hasMatch(trimmed) ? trimmed : 'Re: $trimmed';
}

/// Builds a quoted body: two blank lines, the attribution line, then every
/// original line prefixed with `> `.
String quotedBody(String body, String attribution) {
  final String quoted = body
      .split('\n')
      .map((String line) => '> $line')
      .join('\n');
  return '\n\n$attribution\n$quoted';
}
