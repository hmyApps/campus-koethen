// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Keys of the persistent content cache.
///
/// Keys carry the locale where the cached document is locale dependent, so a
/// language switch never shows the previous language's content.
abstract final class CacheKeys {
  static const String timetableRangeNamespace = 'timetable.entries';
  static const String publicCalendarRangeNamespace = 'calendars.public.events';
  static const String postEventRangeNamespace = 'posts.events';

  static String namespaceOf(String key) {
    for (final String namespace in <String>[
      timetableRangeNamespace,
      publicCalendarRangeNamespace,
      postEventRangeNamespace,
    ]) {
      if (key == namespace || key.startsWith('$namespace.')) return namespace;
    }
    final List<String> parts = key.split('.');
    return parts.take(parts.length < 2 ? parts.length : 2).join('.');
  }

  static bool isRangeNamespace(String namespace) =>
      namespace == timetableRangeNamespace ||
      namespace == publicCalendarRangeNamespace ||
      namespace == postEventRangeNamespace;

  /// Range keys always end in `from.to`; removing those bounds yields the
  /// stable locale/group/selection scope whose newest successful window must
  /// survive retention cleanup.
  static String rangeScopeOf(String key) {
    final String namespace = namespaceOf(key);
    final int bounds = namespace == postEventRangeNamespace ? 3 : 2;
    String scope = key;
    for (int index = 0; index < bounds; index++) {
      final int dot = scope.lastIndexOf('.');
      if (dot < 0) return key;
      scope = scope.substring(0, dot);
    }
    return scope;
  }

  /// Public deployment flags, including the mandatory user-test disclosure.
  static const String appEnvironment = 'environment.public.v1';

  /// Full channel list. `news.*` migrated to `posts.*` when the backend
  /// merged the News/Events domains into Posts; see [isLegacyNewsKey].
  static String postsChannels(String locale) => 'posts.channels.$locale';

  /// Full tag list.
  static String postsTags(String locale) => 'posts.tags.$locale';

  /// The most recently loaded first page of the post list, keyed by the
  /// selected channel set AND the selected tag filter, so changing either
  /// one never shows a stale list cached under the other combination.
  static String postsFirstPage(
    String locale,
    List<String> channels, [
    List<String> tags = const <String>[],
  ]) {
    final List<String> sortedChannels = List<String>.of(channels)..sort();
    final List<String> sortedTags = List<String>.of(tags)..sort();
    return 'posts.page1.$locale.${sortedChannels.join('+')}.tags-${sortedTags.join('+')}';
  }

  /// One requested page of `/v1/posts/events`, keyed by the locale, the
  /// selected channel set, the page number and the server-resolved window
  /// bounds (`meta.from`/`meta.to`) — never the requested bounds, because the
  /// client sends none by default and the server may change its default
  /// window between releases.
  static String postEvents({
    required String locale,
    required List<String> channels,
    required int page,
    required String from,
    required String to,
  }) {
    final List<String> sorted = List<String>.of(channels)..sort();
    return 'posts.events.$locale.${sorted.join('+')}.$from.$to.p$page';
  }

  /// Prefix every legacy `news.*` cache entry carried, from before the
  /// News → Posts rename. Used only to delete them once on cache open,
  /// never to read them back.
  static bool isLegacyNewsKey(String key) => key.startsWith('news.');

  /// Full contact area list.
  static String contactAreas(String locale) => 'contacts.areas.$locale';

  /// The contact search index: every area with its persons and rooms.
  static String contactSearchIndex(String locale) =>
      'contacts.searchIndex.$locale';

  /// A single contact area including its persons.
  static String contactArea(String locale, String slug) =>
      'contacts.area.$locale.$slug';

  /// Canteen list.
  static String canteens(String locale) => 'canteen.list.$locale';

  /// Menu of one canteen for the cached two-week window
  /// (current + upcoming week).
  static String canteenMenu(String locale, String slug) =>
      'canteen.menu.$locale.$slug';

  /// Full study group list of the timetable.
  static String timetableGroups(String locale) => 'timetable.groups.$locale';

  /// Exact lesson information choices of one Campus study group.
  static String timetableLessonInfo(String locale, String groupId) =>
      'timetable.lessonInfo.$locale.$groupId';

  /// One requested timetable range.
  ///
  /// The key carries the locale, the **Campus** group id and both range bounds,
  /// so neither a language switch, another group nor another week can ever be
  /// served from a foreign cache entry.
  static String timetableEntries({
    required String locale,
    required String groupId,
    required String from,
    required String to,
  }) => 'timetable.entries.$locale.$groupId.$from.$to';

  /// Full room catalogue of the campus map.
  ///
  /// The catalogue is small and the client searches locally, so one entry per
  /// locale is enough and the map keeps working offline after a single fetch.
  static String rooms(String locale) => 'campusmap.rooms.$locale';

  /// Full public-calendar catalogue.
  static String publicCalendars(String locale) => 'calendars.public.$locale';

  /// Aggregated events of the SELECTED public calendars for one window.
  /// The key carries the locale, the sorted selection and both bounds, so
  /// another selection, week or language is never served from a foreign entry.
  static String publicCalendarEvents({
    required String locale,
    required List<String> slugs,
    required String from,
    required String to,
  }) {
    final List<String> sorted = List<String>.of(slugs)..sort();
    return 'calendars.public.events.$locale.${sorted.join('+')}.$from.$to';
  }
}
