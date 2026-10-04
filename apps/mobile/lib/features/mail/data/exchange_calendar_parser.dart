// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:xml/xml.dart';

import '../domain/exchange_calendar_event.dart';

/// A deliberately content-free parser failure. Raw Exchange XML may contain
/// personal appointments and must never become a log or exception message.
class ExchangeCalendarResponseException implements Exception {
  const ExchangeCalendarResponseException();

  @override
  String toString() => 'ExchangeCalendarResponseException(<redacted>)';
}

List<ExchangeCalendarEvent> parseExchangeCalendarResponse(String source) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(source);
  } on XmlParserException {
    throw const ExchangeCalendarResponseException();
  }

  if (_elements(document, 'Fault').isNotEmpty) {
    throw const ExchangeCalendarResponseException();
  }
  final XmlElement response = _single(document, 'FindItemResponseMessage');
  if (response.getAttribute('ResponseClass') != 'Success' ||
      _requiredText(response, 'ResponseCode') != 'NoError') {
    throw const ExchangeCalendarResponseException();
  }
  final XmlElement root = _single(response, 'RootFolder');
  if (root.getAttribute('IncludesLastItemInRange')?.toLowerCase() != 'true') {
    // Returning a partial page as a complete calendar would be silent data
    // loss. The caller can narrow/split the requested date window instead.
    throw const ExchangeCalendarResponseException();
  }

  final List<ExchangeCalendarEvent> events = <ExchangeCalendarEvent>[];
  for (final XmlElement item in _elements(root, 'CalendarItem')) {
    final XmlElement itemId = _single(item, 'ItemId');
    final String id = (itemId.getAttribute('Id') ?? '').trim();
    // Exchange permits appointments without a subject. Missing prose is not a
    // malformed occurrence; presentation supplies a localized fallback.
    final String subject = _optionalText(item, 'Subject') ?? '';
    final DateTime start = _requiredUtcDate(item, 'Start');
    final DateTime end = _requiredUtcDate(item, 'End');
    if (id.isEmpty || !end.isAfter(start)) {
      throw const ExchangeCalendarResponseException();
    }
    events.add(
      ExchangeCalendarEvent(
        id: id,
        subject: subject,
        start: start,
        end: end,
        isAllDay: _requiredBool(item, 'IsAllDayEvent'),
        isCancelled: _requiredBool(item, 'IsCancelled'),
        location: _optionalText(item, 'Location'),
      ),
    );
  }
  return List<ExchangeCalendarEvent>.unmodifiable(events);
}

Iterable<XmlElement> _elements(XmlNode node, String localName) => node
    .descendants
    .whereType<XmlElement>()
    .where((XmlElement element) => element.name.local == localName);

XmlElement _single(XmlNode node, String localName) {
  final List<XmlElement> matches = _elements(node, localName).toList();
  if (matches.length != 1) {
    throw const ExchangeCalendarResponseException();
  }
  return matches.single;
}

String _requiredText(XmlNode node, String localName) {
  final String value = _single(node, localName).innerText.trim();
  if (value.isEmpty) throw const ExchangeCalendarResponseException();
  return value;
}

String? _optionalText(XmlNode node, String localName) {
  final List<XmlElement> matches = _elements(node, localName).toList();
  if (matches.length > 1) throw const ExchangeCalendarResponseException();
  if (matches.isEmpty) return null;
  final String value = matches.single.innerText.trim();
  return value.isEmpty ? null : value;
}

bool _requiredBool(XmlNode node, String localName) {
  return switch (_requiredText(node, localName).toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => throw const ExchangeCalendarResponseException(),
  };
}

DateTime _requiredUtcDate(XmlNode node, String localName) {
  final String raw = _requiredText(node, localName);
  // The request pins EWS's response time zone to UTC. Older Exchange builds
  // may still omit the suffix, so an otherwise valid suffix-less value is
  // interpreted in that explicitly requested zone rather than device local.
  final bool hasZone =
      raw.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(raw);
  final DateTime? parsed = DateTime.tryParse(hasZone ? raw : '${raw}Z');
  if (parsed == null) throw const ExchangeCalendarResponseException();
  return parsed.toUtc();
}
