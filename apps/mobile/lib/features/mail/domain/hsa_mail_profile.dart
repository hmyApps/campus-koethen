// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Immutable, verified connection profile for the Hochschule Anhalt mail server.
///
/// These values are the security contract of the whole feature: the app
/// connects DIRECTLY to this server and to no Campus Köthen service. There is
/// deliberately no plaintext port, no port 143 / 25 / 465, and no toggle that
/// could weaken transport security — a profile that could describe an insecure
/// connection would itself be the vulnerability.
class HsaMailProfile {
  const HsaMailProfile();

  String get imapHost => 'mail.hs-anhalt.de';

  /// Implicit TLS (IMAPS). No STARTTLS, no fallback to 143.
  int get imapPort => 993;
  bool get imapImplicitTls => true;

  String get smtpHost => 'mail.hs-anhalt.de';

  /// Submission with mandatory STARTTLS. No fallback to 25 or 465.
  int get smtpPort => 587;
  bool get smtpStartTlsRequired => true;

  /// Read-only Exchange Web Services endpoint for the optional calendar
  /// aggregation. It is pinned to the same university-operated mail host as
  /// IMAP and SMTP; callers must reject redirects rather than replay the
  /// account password to another origin.
  Uri get exchangeCalendarUri =>
      Uri.parse('https://mail.hs-anhalt.de/EWS/Exchange.asmx');

  bool allowsExchangeCalendar(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == exchangeCalendarUri.host &&
      uri.port == exchangeCalendarUri.port &&
      uri.path == exchangeCalendarUri.path &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;

  /// Official HSA webmail, opened externally through the safe launcher only.
  String get webmailUrl => 'https://mail.hs-anhalt.de/';
}
