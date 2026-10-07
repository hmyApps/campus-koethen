// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'mail_cache_store.dart';
import 'mail_credentials.dart';

/// Searches the authenticated Exchange address book directly from the device.
abstract interface class MailDirectoryGateway {
  Future<List<MailAddressEntry>> search(
    MailCredentials credentials,
    String query, {
    int limit = 20,
  });
}
