// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The four file fields a finance application is submitted with.
///
/// Named slots rather than a free list of attachments, because the receiving
/// system does not accept a free list: it expects exactly these multipart
/// fields, two of them mandatory, each with its own set of accepted types. A
/// generic "add file" button would let a student attach something that is then
/// silently not sent — the worst possible outcome for a form whose whole point
/// is that it arrives.
///
/// [field] is the wire name and must match the API exactly.
enum ApplicationFileSlot {
  /// The application itself. Mandatory, PDF only.
  financeRequest(
    field: 'finance_request',
    isRequired: true,
    extensions: <String>{'pdf'},
  ),

  /// Proof of enrolment. Mandatory. The receiving system treats it as internal
  /// and never exposes it on the public status page.
  studentCard(
    field: 'student_card',
    isRequired: true,
    extensions: <String>{'pdf', 'png', 'jpg', 'jpeg'},
  ),

  annexA(field: 'annex_a', isRequired: false, extensions: <String>{'pdf'}),
  annexB(field: 'annex_b', isRequired: false, extensions: <String>{'pdf'});

  const ApplicationFileSlot({
    required this.field,
    required this.isRequired,
    required this.extensions,
  });

  /// Multipart field name. Also the storage key — stable, never the enum index.
  final String field;

  final bool isRequired;

  /// Lower-case, without the dot.
  final Set<String> extensions;

  static const Map<String, String> _contentTypes = <String, String>{
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
  };

  static String? _extensionOf(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return null;
    return fileName.substring(dot + 1).toLowerCase();
  }

  /// Whether this slot takes a file of that name.
  ///
  /// Decided by extension alone: the picker gives a name and a path, and
  /// sniffing the bytes to contradict it would only move the guess. The server
  /// validates too — this check exists to fail early and legibly, not to be
  /// the only line of defence.
  bool accepts(String fileName) {
    final String? extension = _extensionOf(fileName);
    return extension != null && extensions.contains(extension);
  }

  bool acceptsSize(int bytes) => ApplicationFileLimits.acceptsFile(bytes);

  /// The content type to send, or `null` when the file does not belong here.
  String? contentTypeFor(String fileName) {
    final String? extension = _extensionOf(fileName);
    if (extension == null || !extensions.contains(extension)) return null;
    return _contentTypes[extension];
  }

  static ApplicationFileSlot? fromStorage(String? value) {
    for (final ApplicationFileSlot slot in ApplicationFileSlot.values) {
      if (slot.field == value) return slot;
    }
    return null;
  }

  /// The slots that must be filled before anything can be sent.
  static List<ApplicationFileSlot> get required => ApplicationFileSlot.values
      .where((ApplicationFileSlot s) => s.isRequired)
      .toList(growable: false);
}

/// Central upload budget for one finance application.
///
/// The endpoint documents 25 MiB per named field. There are exactly four
/// fields, so the aggregate ceiling deliberately preserves that server
/// contract while giving every client layer one explicit count/byte budget.
abstract final class ApplicationFileLimits {
  static const int maxFiles = 4;
  static const int maxFileBytes = 25 * 1024 * 1024;
  static const int maxTotalBytes = maxFiles * maxFileBytes;

  static bool acceptsFile(int bytes) => bytes >= 0 && bytes <= maxFileBytes;

  static bool acceptsTotal(int bytes) => bytes >= 0 && bytes <= maxTotalBytes;
}
