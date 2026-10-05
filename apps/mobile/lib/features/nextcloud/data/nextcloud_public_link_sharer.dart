// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:share_plus/share_plus.dart';

abstract interface class NextcloudPublicLinkSharer {
  Future<void> share(Uri link);
}

class SystemNextcloudPublicLinkSharer implements NextcloudPublicLinkSharer {
  const SystemNextcloudPublicLinkSharer();

  @override
  Future<void> share(Uri link) async {
    await SharePlus.instance.share(ShareParams(text: link.toString()));
  }
}
