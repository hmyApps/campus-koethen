// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'university_identity.dart';

/// Persistence boundary for the central local identity.
///
/// Production has exactly one implementation: the device-bound keychain /
/// keystore. There is intentionally no Hive or SharedPreferences fallback.
abstract interface class UniversityIdentityStore {
  Future<UniversityIdentity?> read();
  Future<void> write(UniversityIdentity identity);
  Future<void> clear();
}
