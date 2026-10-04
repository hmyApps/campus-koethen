// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'nextcloud_entry.dart';

enum NextcloudSort { name, modifiedNewest, sizeLargest }

/// Applies presentation-only filters to one already validated DAV listing.
///
/// The returned list is new and deterministic. Directories always stay before
/// files so changing the file sort cannot make basic navigation jump around.
List<NextcloudEntry> nextcloudVisibleEntries(
  Iterable<NextcloudEntry> entries, {
  required String query,
  required NextcloudSort sort,
  required Set<String> favouritePaths,
  bool favouritesOnly = false,
}) {
  final String needle = query.trim().toLowerCase();
  final List<NextcloudEntry> result = entries
      .where(
        (NextcloudEntry entry) =>
            (!favouritesOnly || favouritePaths.contains(entry.path)) &&
            (needle.isEmpty || entry.name.toLowerCase().contains(needle)),
      )
      .toList(growable: false);
  result.sort((NextcloudEntry a, NextcloudEntry b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    final int ordered = switch (sort) {
      NextcloudSort.name => _compareName(a, b),
      NextcloudSort.modifiedNewest => _compareNullableNewest(
        a.modifiedAt,
        b.modifiedAt,
      ),
      NextcloudSort.sizeLargest => _compareNullableLargest(
        a.sizeBytes,
        b.sizeBytes,
      ),
    };
    return ordered != 0 ? ordered : _compareName(a, b);
  });
  return List<NextcloudEntry>.unmodifiable(result);
}

int _compareName(NextcloudEntry a, NextcloudEntry b) {
  final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return byName != 0 ? byName : a.path.compareTo(b.path);
}

int _compareNullableNewest(DateTime? a, DateTime? b) {
  if (a == null) return b == null ? 0 : 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

int _compareNullableLargest(int? a, int? b) {
  if (a == null) return b == null ? 0 : 1;
  if (b == null) return -1;
  return b.compareTo(a);
}
