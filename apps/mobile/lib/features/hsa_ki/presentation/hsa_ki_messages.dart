// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../l10n/l10n.dart';
import '../domain/hsa_ki_failure.dart';

String hsaKiFailureMessage(AppLocalizations l10n, Object error) {
  final HsaKiFailureKind kind = error is HsaKiFailure
      ? error.kind
      : HsaKiFailureKind.unknown;
  return switch (kind) {
    HsaKiFailureKind.invalidCredentials => l10n.hsaKiErrorInvalidCredentials,
    HsaKiFailureKind.notRegistered => l10n.hsaKiErrorNotRegistered,
    HsaKiFailureKind.portalUnavailable => l10n.hsaKiErrorPortalUnavailable,
    HsaKiFailureKind.portalStructureChanged =>
      l10n.hsaKiErrorPortalStructureChanged,
    HsaKiFailureKind.tlsOrHostRejected => l10n.hsaKiErrorSecurity,
    HsaKiFailureKind.timeout => l10n.hsaKiErrorTimeout,
    HsaKiFailureKind.networkUnavailable => l10n.hsaKiErrorNetwork,
    HsaKiFailureKind.externalAccessDisabled =>
      l10n.hsaKiErrorExternalAccessDisabled,
    HsaKiFailureKind.secureStorageUnavailable =>
      l10n.hsaKiErrorSecureStorage,
    HsaKiFailureKind.notConnected => l10n.hsaKiErrorNotConnected,
    HsaKiFailureKind.unknown => l10n.hsaKiErrorUnknown,
  };
}
