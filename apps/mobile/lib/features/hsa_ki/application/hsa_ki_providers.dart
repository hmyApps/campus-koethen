// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hawki_gateway.dart';
import '../data/secure_hsa_ki_credential_store.dart';
import '../domain/hsa_ki_account.dart';
import '../domain/hsa_ki_gateway.dart';

final Provider<HsaKiCredentialStore> hsaKiCredentialStoreProvider =
    Provider<HsaKiCredentialStore>((Ref ref) => SecureHsaKiCredentialStore());

final Provider<HsaKiGateway> hsaKiGatewayProvider = Provider<HsaKiGateway>(
  (Ref ref) => HawkiGateway(),
);

/// Advances whenever the connection is created or torn down, so an operation
/// already in flight when a logout happens can never write a result for the
/// account that is gone — same pattern as every other direct integration's
/// session generation.
class HsaKiSessionGeneration extends Notifier<int> {
  @override
  int build() => 0;

  void advance() => state++;
}

final NotifierProvider<HsaKiSessionGeneration, int>
hsaKiSessionGenerationProvider = NotifierProvider<HsaKiSessionGeneration, int>(
  HsaKiSessionGeneration.new,
);
