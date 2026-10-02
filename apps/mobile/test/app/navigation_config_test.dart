// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/app_modules.dart';
import 'package:campus_koethen/app/navigation_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a fresh install shows News, Kalender, Mensa and E-Mail', () {
    expect(NavigationConfig.defaults.tabs, <AppModule>[
      AppModule.news,
      AppModule.calendar,
      AppModule.canteen,
      AppModule.mail,
    ]);
    expect(NavigationConfig.defaults.isValid, isTrue);
    expect(NavigationConfig.fromStorage(null), NavigationConfig.defaults);
  });

  group('repairing stored input', () {
    test('an exact configuration is kept in its order', () {
      final NavigationConfig config = NavigationConfig.fromStorage(<String>[
        'todos',
        'news',
        'campus-map',
        'grades',
      ]);
      expect(config.tabs, <AppModule>[
        AppModule.todos,
        AppModule.news,
        AppModule.campusMap,
        AppModule.grades,
      ]);
    });

    test('the timetable storage id remains pinnable after an upgrade', () {
      final NavigationConfig config = NavigationConfig.fromStorage(<String>[
        'timetable',
        'news',
        'canteen',
        'mail',
      ]);

      expect(config.tabs.first, AppModule.timetable);
      expect(config.toStorage().first, 'timetable');
      expect(config.isValid, isTrue);
    });

    test('unknown ids are dropped, not fatal', () {
      // A module removed in a later version, or a hand-edited preference.
      final NavigationConfig config = NavigationConfig.fromStorage(<String>[
        'today',
        'news',
        'was-auch-immer',
        'calendar',
      ]);
      expect(config.isValid, isTrue);
      expect(config.tabs.take(2), <AppModule>[
        AppModule.news,
        AppModule.calendar,
      ]);
    });

    test('duplicates collapse and the gap is refilled', () {
      final NavigationConfig config = NavigationConfig.fromStorage(<String>[
        'news',
        'news',
        'news',
        'news',
      ]);
      expect(config.isValid, isTrue);
      expect(config.tabs.first, AppModule.news);
      expect(config.tabs.toSet(), hasLength(4));
    });

    test('too few entries are padded from the defaults', () {
      final NavigationConfig config = NavigationConfig.fromStorage(<String>[
        'todos',
      ]);
      expect(config.tabs.first, AppModule.todos);
      expect(config.isValid, isTrue);
    });

    test('too many entries are truncated', () {
      final NavigationConfig config = NavigationConfig.fromStorage(<String>[
        'news',
        'calendar',
        'canteen',
        'mail',
        'moodle',
        'grades',
      ]);
      expect(config.tabs, hasLength(NavigationConfig.tabCount));
      expect(config.tabs, isNot(contains(AppModule.moodle)));
    });

    test('a module that may not be pinned is refused', () {
      // Settings and About have no business being a tab, however they got in.
      final NavigationConfig config = NavigationConfig.fromStorage(<String>[
        'settings',
        'about',
        'news',
        'calendar',
      ]);
      expect(config.tabs, isNot(contains(AppModule.settings)));
      expect(config.tabs, isNot(contains(AppModule.about)));
      expect(config.isValid, isTrue);
    });

    test('an empty list still yields a usable bar', () {
      expect(
        NavigationConfig.fromStorage(const <String>[]),
        NavigationConfig.defaults,
      );
    });
  });

  test('a configuration survives a round trip through storage', () {
    final NavigationConfig config = NavigationConfig.of(<AppModule>[
      AppModule.contacts,
      AppModule.moodle,
      AppModule.news,
      AppModule.todos,
    ]);
    expect(NavigationConfig.fromStorage(config.toStorage()), config);
  });

  group('which tab owns a route', () {
    test('a tab is found by its own route', () {
      expect(
        NavigationConfig.defaults.indexOfRoute(AppModule.canteen.route),
        2,
      );
    });

    test('a route deeper in a tab still belongs to it', () {
      // /calendar/manage keeps the calendar tab selected.
      expect(NavigationConfig.defaults.indexOfRoute('/calendar/manage'), 1);
    });

    test('a route of an unpinned module belongs to no tab', () {
      // Which is what keeps "More" selected while such a screen is open.
      expect(
        NavigationConfig.defaults.indexOfRoute(AppModule.grades.route),
        -1,
      );
    });

    test('a route that only shares a prefix does not count', () {
      expect(NavigationConfig.defaults.indexOfRoute('/newsletter'), -1);
    });
  });
}
