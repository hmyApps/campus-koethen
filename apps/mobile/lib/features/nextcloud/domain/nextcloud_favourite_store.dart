// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'nextcloud_account.dart';

abstract interface class NextcloudFavouriteStore {
  Future<Set<String>> read(NextcloudAccount account);
  Future<void> write(NextcloudAccount account, Set<String> paths);
  Future<void> clear();
}
