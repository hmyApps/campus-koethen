// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/nextcloud/domain/nextcloud_browser_view.dart';
import 'package:campus_koethen/features/nextcloud/domain/nextcloud_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const NextcloudEntry folder = NextcloudEntry(
    path: '/Unterlagen',
    name: 'Unterlagen',
    isDirectory: true,
  );
  final NextcloudEntry older = NextcloudEntry(
    path: '/Alpha.pdf',
    name: 'Alpha.pdf',
    isDirectory: false,
    sizeBytes: 20,
    modifiedAt: DateTime.utc(2026, 1, 1),
  );
  final NextcloudEntry newer = NextcloudEntry(
    path: '/beta.pdf',
    name: 'beta.pdf',
    isDirectory: false,
    sizeBytes: 10,
    modifiedAt: DateTime.utc(2026, 2, 1),
  );

  test('filters names case-insensitively without mutating the source', () {
    final List<NextcloudEntry> source = <NextcloudEntry>[newer, folder, older];

    final List<NextcloudEntry> visible = nextcloudVisibleEntries(
      source,
      query: ' ALPHA ',
      sort: NextcloudSort.name,
      favouritePaths: const <String>{},
    );

    expect(visible.map((NextcloudEntry entry) => entry.path), <String>[
      '/Alpha.pdf',
    ]);
    expect(source.map((NextcloudEntry entry) => entry.path), <String>[
      '/beta.pdf',
      '/Unterlagen',
      '/Alpha.pdf',
    ]);
  });

  test('keeps folders first and applies every deterministic sort', () {
    final List<NextcloudEntry> source = <NextcloudEntry>[older, newer, folder];

    expect(
      nextcloudVisibleEntries(
        source,
        query: '',
        sort: NextcloudSort.modifiedNewest,
        favouritePaths: const <String>{},
      ).map((NextcloudEntry entry) => entry.path),
      <String>['/Unterlagen', '/beta.pdf', '/Alpha.pdf'],
    );
    expect(
      nextcloudVisibleEntries(
        source,
        query: '',
        sort: NextcloudSort.sizeLargest,
        favouritePaths: const <String>{},
      ).map((NextcloudEntry entry) => entry.path),
      <String>['/Unterlagen', '/Alpha.pdf', '/beta.pdf'],
    );
  });

  test('favourites-only is an independent local filter', () {
    final List<NextcloudEntry> visible = nextcloudVisibleEntries(
      <NextcloudEntry>[older, newer, folder],
      query: '',
      sort: NextcloudSort.name,
      favouritePaths: const <String>{'/Unterlagen', '/beta.pdf'},
      favouritesOnly: true,
    );

    expect(visible.map((NextcloudEntry entry) => entry.path), <String>[
      '/Unterlagen',
      '/beta.pdf',
    ]);
  });
}
