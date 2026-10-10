// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:typed_data';

import '../domain/mail_message.dart';
import '../domain/mail_search_match.dart';

/// JSON mappers for the offline mail cache.
///
/// Kept out of the domain models on purpose: the models stay pure, and the
/// persistence format lives next to the store that owns it. Attachment bytes
/// are base64-encoded; a missing or malformed field decodes to null rather than
/// throwing, so a corrupted entry is a recoverable miss.
abstract final class MailCacheCodec {
  static Map<String, dynamic> address(MailAddress a) => <String, dynamic>{
    'email': a.email,
    if (a.name != null) 'name': a.name,
  };

  static MailAddress addressFrom(Map<String, dynamic> json) => MailAddress(
    email: (json['email'] as String?) ?? '',
    name: json['name'] as String?,
  );

  static Map<String, dynamic> header(MailMessageHeader h) => <String, dynamic>{
    'id': h.id,
    'subject': h.subject,
    'from': address(h.from),
    'date': h.date?.toUtc().toIso8601String(),
    'isSeen': h.isSeen,
    'hasAttachments': h.hasAttachments,
  };

  static MailMessageHeader headerFrom(Map<String, dynamic> json) =>
      MailMessageHeader(
        id: (json['id'] as String?) ?? '',
        subject: (json['subject'] as String?) ?? '',
        from: addressFrom(_map(json['from'])),
        date: _date(json['date']),
        isSeen: json['isSeen'] == true,
        hasAttachments: json['hasAttachments'] == true,
      );

  static Map<String, dynamic> attachment(MailAttachment a) => <String, dynamic>{
    'filename': a.filename,
    'mediaType': a.mediaType,
    if (a.sizeBytes != null) 'sizeBytes': a.sizeBytes,
    if (a.bytes != null) 'bytes': base64Encode(a.bytes!),
  };

  static MailAttachment attachmentFrom(Map<String, dynamic> json) {
    final String? encoded = json['bytes'] as String?;
    return MailAttachment(
      filename: (json['filename'] as String?) ?? '',
      mediaType: (json['mediaType'] as String?) ?? 'application/octet-stream',
      sizeBytes: json['sizeBytes'] as int?,
      bytes: encoded == null ? null : Uint8List.fromList(base64Decode(encoded)),
    );
  }

  static Map<String, dynamic> detail(MailMessageDetail d) => <String, dynamic>{
    'id': d.id,
    'subject': d.subject,
    'from': address(d.from),
    if (d.replyTo.isNotEmpty) 'replyTo': d.replyTo.map(address).toList(),
    'to': d.to.map(address).toList(),
    'cc': d.cc.map(address).toList(),
    'date': d.date?.toUtc().toIso8601String(),
    'body': d.body,
    'attachments': d.attachments.map(attachment).toList(),
  };

  static MailMessageDetail detailFrom(Map<String, dynamic> json) =>
      MailMessageDetail(
        id: (json['id'] as String?) ?? '',
        subject: (json['subject'] as String?) ?? '',
        from: addressFrom(_map(json['from'])),
        // Absent in entries cached before Reply-To was kept: replies then go
        // to From, exactly as before.
        replyTo: _list(json['replyTo']).map(addressFrom).toList(),
        to: _list(json['to']).map(addressFrom).toList(),
        cc: _list(json['cc']).map(addressFrom).toList(),
        date: _date(json['date']),
        body: (json['body'] as String?) ?? '',
        attachments: _list(json['attachments']).map(attachmentFrom).toList(),
      );

  /// The searchable text of a stored message, read straight off the JSON.
  ///
  /// Search has to look at *every* cached message; decoding each one into a
  /// [MailMessageDetail] first would base64-decode every stored attachment
  /// along the way — megabytes of image bytes per keystroke-free query, for
  /// fields search never looks at. This walks the same fields as
  /// `mailDetailSearchFields` without touching `attachments`.
  static Iterable<String?> searchFieldsFrom(Map<String, dynamic> json) sync* {
    yield json['subject'] as String?;
    yield json['body'] as String?;
    for (final Map<String, dynamic> address in <Map<String, dynamic>>[
      _map(json['from']),
      ..._list(json['to']),
      ..._list(json['cc']),
    ]) {
      yield address['name'] as String?;
      yield address['email'] as String?;
    }
  }

  /// Compact, attachment-free search document stored separately from bodies.
  static Map<String, dynamic> searchDocument(MailMessageDetail detail) =>
      <String, dynamic>{
        'text': mailDetailSearchFields(detail)
            .whereType<String>()
            .map(normalizeMailSearchTerm)
            .where((String value) => value.isNotEmpty)
            .join('\u0000'),
        'header': header(
          MailMessageHeader(
            id: detail.id,
            subject: detail.subject,
            from: detail.from,
            date: detail.date,
            isSeen: true,
            hasAttachments: detail.hasAttachments,
          ),
        ),
      };

  /// A header for a cached message that is missing from the header index.
  ///
  /// Only a fallback: the index accumulates alongside the bodies, so this is
  /// for a partially written or trimmed cache. \Seen is assumed — the message
  /// has been read into the cache and no unread state is recorded here.
  static MailMessageHeader headerFromDetailJson(Map<String, dynamic> json) =>
      MailMessageHeader(
        id: (json['id'] as String?) ?? '',
        subject: (json['subject'] as String?) ?? '',
        from: addressFrom(_map(json['from'])),
        date: _date(json['date']),
        isSeen: true,
        hasAttachments: _list(json['attachments']).isNotEmpty,
      );

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value.whereType<Map>().map(_map).toList()
      : const <Map<String, dynamic>>[];

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
