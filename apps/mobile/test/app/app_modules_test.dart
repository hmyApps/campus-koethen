// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/app_modules.dart';
import 'package:campus_koethen/app/navigation_config.dart';
import 'package:campus_koethen/core/theme/app_icons.dart';
import 'package:flutter_test/flutter_test.dart';

List<AppModule> modulesUnder(
  List<MoreCategoryEntry> entries,
  ModuleCategory category,
) => entries
    .where((MoreCategoryEntry e) => e.category == category)
    .expand((MoreCategoryEntry e) => e.modules)
    .toList();

void main() {
  group('the catalogue', () {
    test('storage values and routes are unique', () {
      // A collision would silently make one module unreachable and repair the
      // other one's stored id into it.
      expect(
        AppModule.values.map((AppModule m) => m.storageValue).toSet(),
        hasLength(AppModule.values.length),
      );
      expect(
        AppModule.values.map((AppModule m) => m.route).toSet(),
        hasLength(AppModule.values.length),
      );
    });

    test('every module reads back from its stored id', () {
      for (final AppModule module in AppModule.values) {
        expect(AppModule.fromStorage(module.storageValue), module);
      }
      expect(AppModule.fromStorage('heute'), isNull);
      expect(AppModule.fromStorage(null), isNull);
    });

    test('the requested modules use their exact Tabler glyphs', () {
      expect(AppModule.moodle.icon, AppIcons.book_outlined);
      expect(AppModule.moodle.selectedIcon, AppIcons.book_outlined);
      expect(AppModule.grades.icon, AppIcons.grade_outlined);
      expect(AppModule.grades.selectedIcon, AppIcons.grade_outlined);
      expect(AppModule.requests.icon, AppIcons.file_pencil);
      expect(AppModule.requests.selectedIcon, AppIcons.file_pencil);
    });

    test('the categories hold what the product defines', () {
      expect(AppModule.inCategory(ModuleCategory.study), <AppModule>[
        AppModule.calendar,
        AppModule.timetable,
        AppModule.mail,
        AppModule.moodle,
        AppModule.grades,
        AppModule.studentService,
        AppModule.todos,
      ]);
      expect(AppModule.inCategory(ModuleCategory.campus), <AppModule>[
        AppModule.news,
        AppModule.canteen,
        AppModule.campusMap,
        AppModule.contacts,
        AppModule.requests,
      ]);
      expect(AppModule.inCategory(ModuleCategory.app), <AppModule>[
        AppModule.settings,
        AppModule.about,
      ]);
    });

    test('sort order is unique within each category', () {
      for (final ModuleCategory category in ModuleCategory.values) {
        final List<AppModule> modules = AppModule.inCategory(category);
        expect(
          modules.map((AppModule m) => m.sortOrder).toSet(),
          hasLength(modules.length),
          reason: '$category',
        );
      }
    });

    test('settings and about cannot be pinned', () {
      expect(AppModule.settings.pinnable, isFalse);
      expect(AppModule.about.pinnable, isFalse);
      expect(AppModule.pinnableModules, isNot(contains(AppModule.settings)));
      expect(AppModule.pinnableModules, hasLength(12));
    });

    test('the pinnable modules are the leading values of the enum', () {
      // The router lays out one shell branch per pinnable module, in enum
      // order, and More last — so a module's index *is* its branch index.
      // Interleaving a non-pinnable module would point every later tab at the
      // wrong screen, silently.
      final int pinnable = AppModule.pinnableModules.length;
      expect(
        AppModule.values.take(pinnable).every((AppModule m) => m.pinnable),
        isTrue,
      );
      expect(
        AppModule.values.skip(pinnable).every((AppModule m) => !m.pinnable),
        isTrue,
      );
    });

    test('there is no Today module', () {
      // The dashboard was removed; nothing may resurrect it through storage.
      expect(
        AppModule.values.map((AppModule m) => m.storageValue),
        isNot(contains('today')),
      );
    });
  });

  group('the More hub', () {
    test('with the default bar it shows exactly the specified structure', () {
      final List<MoreCategoryEntry> entries =
          NavigationConfig.defaults.moreEntries;

      expect(modulesUnder(entries, ModuleCategory.study), <AppModule>[
        AppModule.timetable,
        AppModule.moodle,
        AppModule.grades,
        AppModule.studentService,
        AppModule.todos,
      ]);
      expect(modulesUnder(entries, ModuleCategory.campus), <AppModule>[
        AppModule.campusMap,
        AppModule.contacts,
        AppModule.requests,
      ]);
      expect(modulesUnder(entries, ModuleCategory.app), <AppModule>[
        AppModule.settings,
        AppModule.about,
      ]);
    });

    test('pinning Moodle instead of mail swaps the two', () {
      final NavigationConfig config = NavigationConfig.of(<AppModule>[
        AppModule.news,
        AppModule.calendar,
        AppModule.canteen,
        AppModule.moodle,
      ]);
      final List<AppModule> study = modulesUnder(
        config.moreEntries,
        ModuleCategory.study,
      );

      expect(study, isNot(contains(AppModule.moodle)));
      expect(study, contains(AppModule.mail));
    });

    test('a module dropped from the bar reappears under its category', () {
      final NavigationConfig config = NavigationConfig.of(<AppModule>[
        AppModule.calendar,
        AppModule.canteen,
        AppModule.mail,
        AppModule.moodle,
      ]);
      expect(
        modulesUnder(config.moreEntries, ModuleCategory.campus),
        contains(AppModule.news),
      );
    });

    test('settings and about are there whatever the bar contains', () {
      for (final NavigationConfig config in <NavigationConfig>[
        NavigationConfig.defaults,
        NavigationConfig.of(<AppModule>[
          AppModule.moodle,
          AppModule.grades,
          AppModule.todos,
          AppModule.campusMap,
        ]),
      ]) {
        expect(
          modulesUnder(config.moreEntries, ModuleCategory.app),
          <AppModule>[AppModule.settings, AppModule.about],
        );
      }
    });

    test('nothing pinned is also listed under More', () {
      final NavigationConfig config = NavigationConfig.defaults;
      final Set<AppModule> listed = config.moreEntries
          .expand((MoreCategoryEntry e) => e.modules)
          .toSet();
      expect(listed.intersection(config.tabs.toSet()), isEmpty);
    });

    test('every module is either pinned or listed — none can be stranded', () {
      // The invariant the whole hub exists for.
      for (final NavigationConfig config in <NavigationConfig>[
        NavigationConfig.defaults,
        NavigationConfig.of(<AppModule>[
          AppModule.todos,
          AppModule.requests,
          AppModule.contacts,
          AppModule.grades,
        ]),
        NavigationConfig.of(<AppModule>[
          AppModule.campusMap,
          AppModule.moodle,
          AppModule.news,
          AppModule.canteen,
        ]),
      ]) {
        final Set<AppModule> reachable = <AppModule>{
          ...config.tabs,
          ...config.moreEntries.expand((MoreCategoryEntry e) => e.modules),
        };
        expect(reachable, AppModule.values.toSet(), reason: '$config');
      }
    });

    test(
      'an empty category is dropped rather than shown as a bare heading',
      () {
        // Not reachable with four slots today, but the rule is the rule.
        final List<MoreCategoryEntry> entries = moreEntriesFor(
          AppModule.inCategory(ModuleCategory.campus),
        );
        expect(
          entries.map((MoreCategoryEntry e) => e.category),
          isNot(contains(ModuleCategory.campus)),
        );
      },
    );
  });
}
