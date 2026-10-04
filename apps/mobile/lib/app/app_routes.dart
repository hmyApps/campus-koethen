// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// All route paths and names of the app in one place.
abstract final class AppRoutes {
  /// The news feed — the app's entry point and the first default tab.
  ///
  /// The feed itself has no detail route: it carries the full article and
  /// expands it in place. A channel, unlike an article, does get a page of
  /// its own — a nested route so pushing it keeps the feed's scroll position
  /// and every card's expand/collapse state underneath.
  static const String news = '/news';
  static const String newsChannelName = 'news-channel';
  static const String newsChannelPath = ':slug';

  /// The event view: every channel, filtered to the stable `event` tag. A
  /// static segment, so it must be registered before the dynamic
  /// [newsChannelPath] route to avoid ever being swallowed by it.
  static const String newsEventsName = 'news-events';
  static const String newsEventsPath = 'events';

  /// The cross-source calendar combines timetable, public calendars and
  /// Moodle deadlines locally on the device.
  static const String calendar = '/calendar';

  /// Focused, pinnable timetable module. It shares its data providers and
  /// selected course group with the timetable source in [calendar].
  static const String timetable = '/timetable';

  /// "Manage calendars" (Y-of-X public calendar selection + Google buttons).
  static const String calendarManagePath = 'manage';
  static const String calendarManage = '/calendar/manage';

  static const String canteen = '/canteen';
  static const String canteenFavouritesPath = 'favourites';
  static const String canteenFavourites = '/canteen/favourites';

  /// Non-sensitive Android NFC dispatch marker. It contains neither a card
  /// identifier nor a balance; the changing launch token merely retriggers
  /// the sheet when two tags arrive while the canteen route is already open.
  static const String canteenBalanceParam = 'balance';
  static const String canteenBalanceLaunchParam = 'launch';

  static String canteenExternalBalanceLocation(int launch) => Uri(
    path: canteen,
    queryParameters: <String, String>{
      canteenBalanceParam: 'external',
      canteenBalanceLaunchParam: '$launch',
    },
  ).toString();

  static const String contacts = '/contacts';
  static const String contactAreaName = 'contact-area';
  static const String contactAreaPath = ':slug';

  /// "Mehr" is the fixed fifth destination. Settings and the about page live
  /// underneath it and can never be pinned to the bar.
  static const String more = '/more';

  // Student email client, nested under More.
  static const String mail = '/more/mail';
  static const String mailSearch = '/more/mail/search';
  static const String mailCompose = '/more/mail/compose';
  static const String mailMessageName = 'mail-message';
  static const String mailMessage = '/more/mail/message/:id';

  // Student grades (HIS-QIS), nested under More.
  static const String grades = '/more/grades';

  /// Read-only HISinOne functions (Bescheinigungen, Personen-/Kontaktdaten,
  /// Studiengangsübersicht). Rides on the grades connection — no sign-in of
  /// its own, see `AGENTS.md` §2.
  static const String studentService = '/more/student-service';

  // Moodle (direct integration), nested under More.
  static const String moodle = '/more/moodle';
  static const String moodleCourseName = 'moodle-course';
  static const String moodleCoursePath = 'course/:id';

  // Hochschule Anhalt Nextcloud file explorer (direct WebDAV integration).
  static const String nextcloud = '/more/nextcloud';

  // Local, on-device to-do list, nested under More.
  static const String todosPath = 'todos';
  static const String todos = '/more/todos';

  // Campus map, nested under More.
  static const String campusMapPath = 'campus-map';
  static const String campusMap = '/more/campus-map';

  /// Query parameter carrying the room a deep link should focus.
  static const String campusMapRoomParam = 'room';

  /// In-app deep link used by contact details to open the map on one room.
  ///
  /// A query parameter rather than a path segment: the roomKey is optional,
  /// and the map is a perfectly valid destination without one.
  static String campusMapForRoom(String roomKey) =>
      '$campusMap?$campusMapRoomParam=${Uri.encodeQueryComponent(roomKey)}';

  // Applications and feedback, nested under More.
  static const String requestsPath = 'requests';
  static const String requests = '/more/requests';

  /// The two forms. An existing draft is continued through a `draft` query
  /// parameter; without one the screen starts a new draft.
  static const String requestApplicationName = 'request-application';
  static const String requestApplicationPath = 'application';
  static const String requestFeedbackName = 'request-feedback';
  static const String requestFeedbackPath = 'feedback';

  /// One submitted case.
  ///
  /// The path carries the **local** id and nothing else. The status link, the
  /// receipt link and every document link are bearer credentials: putting one
  /// in a route would leak it into navigation history, deep links and any
  /// analytics that ever watches routes.
  static const String requestSubmissionName = 'request-submission';
  static const String requestSubmissionPath = 'submission/:id';

  /// First-run onboarding. A top-level route, outside the navigation shell.
  static const String onboarding = '/onboarding';

  // Settings is a sub-page of More.
  static const String settings = '/more/settings';
  static const String about = '/more/settings/about';
  static const String imprint = '/more/settings/imprint';
  static const String privacy = '/more/settings/privacy';
  static const String channels = '/more/settings/channels';
  static const String settingsNavigation = '/more/settings/navigation';

  /// Local notification settings — the global opt-in, the three category
  /// switches and the permission banner.
  static const String settingsNotifications = '/more/settings/notifications';
}
