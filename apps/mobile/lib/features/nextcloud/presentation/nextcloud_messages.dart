// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../l10n/l10n.dart';
import '../domain/nextcloud_failure.dart';

String nextcloudFailureMessage(AppLocalizations l10n, Object error) {
  final NextcloudFailureKind kind = error is NextcloudFailure
      ? error.kind
      : NextcloudFailureKind.unknown;
  return switch (kind) {
    NextcloudFailureKind.canceled => l10n.nextcloudErrorUnknown,
    NextcloudFailureKind.browserLaunchFailed => l10n.nextcloudErrorBrowser,
    NextcloudFailureKind.loginTimedOut => l10n.nextcloudErrorLoginTimedOut,
    NextcloudFailureKind.loginRejected => l10n.nextcloudErrorLoginRejected,
    NextcloudFailureKind.networkUnavailable => l10n.nextcloudErrorNetwork,
    NextcloudFailureKind.timeout => l10n.nextcloudErrorTimeout,
    NextcloudFailureKind.tlsOrHostRejected => l10n.nextcloudErrorSecurity,
    NextcloudFailureKind.serviceUnavailable => l10n.nextcloudErrorUnavailable,
    NextcloudFailureKind.permissionDenied => l10n.nextcloudErrorPermission,
    NextcloudFailureKind.invalidResponse => l10n.nextcloudErrorInvalidResponse,
    NextcloudFailureKind.secureStorageUnavailable =>
      l10n.nextcloudErrorSecureStorage,
    NextcloudFailureKind.notConnected => l10n.nextcloudErrorNotConnected,
    NextcloudFailureKind.fileTooLarge => l10n.nextcloudErrorFileTooLarge,
    NextcloudFailureKind.downloadFailed => l10n.nextcloudErrorDownload,
    NextcloudFailureKind.unknown => l10n.nextcloudErrorUnknown,
  };
}
