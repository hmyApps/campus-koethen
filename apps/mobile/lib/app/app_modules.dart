// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../l10n/l10n.dart';
import 'app_routes.dart';

/// Where a module belongs in the "More" hub.
///
/// A module's category is a property of the module, not of the screen that
/// happens to render it. That is what lets "More" be derived: whatever is not
/// pinned to the bar turns up under its own heading, wherever the user moved
/// things.
enum ModuleCategory {
  study,
  campus,
  app;

  String label(AppLocalizations l10n) => switch (this) {
    ModuleCategory.study => l10n.moduleCategoryStudy,
    ModuleCategory.campus => l10n.moduleCategoryCampus,
    ModuleCategory.app => l10n.moduleCategoryApp,
  };
}

/// Every area of the app, in one typed catalogue.
///
/// **This is the single source** the bottom navigation, the navigation
/// settings, the onboarding, the "More" hub and the repair of stored
/// configurations all read from. Adding an area means adding a value here —
/// not editing five widgets that each carry their own list and drift apart.
///
/// "More" itself is deliberately **not** a value: it is the fixed fifth slot of
/// the bar and the container the others are listed in, never a module the user
/// could pin, hide or reorder.
///
/// Labels come from `gen_l10n` on purpose: no visible text lives in this file.
enum AppModule {
  // --- Studium -------------------------------------------------------------
  calendar(
    storageValue: 'calendar',
    route: AppRoutes.calendar,
    category: ModuleCategory.study,
    sortOrder: 1,
    icon: AppIcons.calendar_month_outlined,
    selectedIcon: AppIcons.calendar_month,
  ),
  timetable(
    storageValue: 'timetable',
    route: AppRoutes.timetable,
    category: ModuleCategory.study,
    sortOrder: 2,
    icon: AppIcons.schedule_outlined,
    selectedIcon: AppIcons.schedule_outlined,
  ),
  mail(
    storageValue: 'mail',
    route: AppRoutes.mail,
    category: ModuleCategory.study,
    sortOrder: 3,
    icon: AppIcons.mail_outline,
    selectedIcon: AppIcons.mail,
  ),
  moodle(
    storageValue: 'moodle',
    route: AppRoutes.moodle,
    category: ModuleCategory.study,
    sortOrder: 4,
    icon: AppIcons.book_outlined,
    selectedIcon: AppIcons.book_outlined,
  ),
  nextcloud(
    storageValue: 'nextcloud',
    route: AppRoutes.nextcloud,
    category: ModuleCategory.study,
    sortOrder: 5,
    icon: AppIcons.cloud_outlined,
    selectedIcon: AppIcons.cloud_outlined,
  ),
  grades(
    storageValue: 'grades',
    route: AppRoutes.grades,
    category: ModuleCategory.study,
    sortOrder: 6,
    icon: AppIcons.grade_outlined,
    selectedIcon: AppIcons.grade_outlined,
  ),
  studentService(
    storageValue: 'studentService',
    route: AppRoutes.studentService,
    category: ModuleCategory.study,
    sortOrder: 7,
    icon: AppIcons.badge_outlined,
    selectedIcon: AppIcons.badge_outlined,
  ),
  todos(
    storageValue: 'todos',
    route: AppRoutes.todos,
    category: ModuleCategory.study,
    sortOrder: 8,
    icon: AppIcons.checklist_outlined,
    selectedIcon: AppIcons.checklist,
  ),
  hsaKi(
    storageValue: 'hsaKi',
    route: AppRoutes.hsaKi,
    category: ModuleCategory.study,
    sortOrder: 9,
    icon: AppIcons.message_2,
    selectedIcon: AppIcons.message_2,
  ),

  // --- Campus --------------------------------------------------------------
  news(
    storageValue: 'news',
    route: AppRoutes.news,
    category: ModuleCategory.campus,
    sortOrder: 1,
    icon: AppIcons.article_outlined,
    selectedIcon: AppIcons.article,
  ),
  canteen(
    storageValue: 'canteen',
    route: AppRoutes.canteen,
    category: ModuleCategory.campus,
    sortOrder: 2,
    icon: AppIcons.soup,
    selectedIcon: AppIcons.soup,
  ),
  campusMap(
    storageValue: 'campus-map',
    route: AppRoutes.campusMap,
    category: ModuleCategory.campus,
    sortOrder: 3,
    icon: AppIcons.map_outlined,
    selectedIcon: AppIcons.map,
  ),
  contacts(
    storageValue: 'contacts',
    route: AppRoutes.contacts,
    category: ModuleCategory.campus,
    sortOrder: 4,
    icon: AppIcons.contact_support_outlined,
    selectedIcon: AppIcons.contact_support,
  ),
  requests(
    storageValue: 'requests',
    route: AppRoutes.requests,
    category: ModuleCategory.campus,
    sortOrder: 5,
    icon: AppIcons.file_pencil,
    selectedIcon: AppIcons.file_pencil,
  ),

  // --- App -----------------------------------------------------------------
  // Neither of these can be pinned: they are how the app is configured and
  // explained, not places to spend time in.
  settings(
    storageValue: 'settings',
    route: AppRoutes.settings,
    category: ModuleCategory.app,
    sortOrder: 1,
    pinnable: false,
    icon: AppIcons.settings_outlined,
    selectedIcon: AppIcons.settings,
  ),
  about(
    storageValue: 'about',
    route: AppRoutes.about,
    category: ModuleCategory.app,
    sortOrder: 2,
    pinnable: false,
    icon: AppIcons.info_outline,
    selectedIcon: AppIcons.info,
  );

  const AppModule({
    required this.storageValue,
    required this.route,
    required this.category,
    required this.sortOrder,
    required this.icon,
    required this.selectedIcon,
    this.pinnable = true,
  });

  /// Stable identifier written to local storage, never the enum index.
  final String storageValue;

  final String route;
  final ModuleCategory category;

  /// Position within [category]. Unique per category.
  final int sortOrder;

  final IconData icon;
  final IconData selectedIcon;

  /// Whether the user may put this module into the bottom navigation bar.
  final bool pinnable;

  /// The module's full name, as used on its own screen and in lists.
  String title(AppLocalizations l10n) => switch (this) {
    AppModule.calendar => l10n.navCalendar,
    AppModule.timetable => l10n.timetableTitle,
    AppModule.mail => l10n.mailTitle,
    AppModule.moodle => l10n.moodleTitle,
    AppModule.nextcloud => l10n.nextcloudTitle,
    AppModule.grades => l10n.gradesTitle,
    AppModule.studentService => l10n.studentServiceTitle,
    AppModule.todos => l10n.todosTitle,
    AppModule.hsaKi => l10n.hsaKiTitle,
    AppModule.news => l10n.navNews,
    AppModule.canteen => l10n.navCanteen,
    AppModule.campusMap => l10n.moduleCampusMapTitle,
    AppModule.contacts => l10n.moduleContactsTitle,
    AppModule.requests => l10n.requestsTitle,
    AppModule.settings => l10n.moreSettings,
    AppModule.about => l10n.aboutTitle,
  };

  /// The short name the navigation bar uses.
  ///
  /// Only differs where the full title cannot survive a fifth of a phone's
  /// width — "Studentische E-Mail" becomes "E-Mail".
  String shortTitle(AppLocalizations l10n) => switch (this) {
    AppModule.mail => l10n.navMailShort,
    AppModule.campusMap => l10n.campusMapTitle,
    AppModule.contacts => l10n.navContacts,
    _ => title(l10n),
  };

  /// One line explaining the module, or `null` where the name says it all.
  String? subtitle(AppLocalizations l10n) => switch (this) {
    AppModule.timetable => l10n.moreTimetableSubtitle,
    AppModule.mail => l10n.moreMailSubtitle,
    AppModule.grades => l10n.moreGradesSubtitle,
    AppModule.studentService => l10n.moreStudentServiceSubtitle,
    AppModule.moodle => l10n.moreMoodleSubtitle,
    AppModule.nextcloud => l10n.nextcloudSubtitle,
    AppModule.todos => l10n.moreTodosSubtitle,
    AppModule.hsaKi => l10n.hsaKiSubtitle,
    AppModule.campusMap => l10n.moreCampusMapSubtitle,
    AppModule.contacts => l10n.moreContactsSubtitle,
    AppModule.requests => l10n.requestsSubtitle,
    _ => null,
  };

  /// Whether this module talks to an official system directly from the device.
  ///
  /// A property of the module itself, so no caller has to remember the list.
  bool get isPersonalService => switch (this) {
    AppModule.mail ||
    AppModule.grades ||
    AppModule.studentService ||
    AppModule.moodle => true,
    AppModule.nextcloud => true,
    AppModule.hsaKi => true,
    _ => false,
  };

  static AppModule? fromStorage(String? value) {
    for (final AppModule module in AppModule.values) {
      if (module.storageValue == value) return module;
    }
    return null;
  }

  /// Everything the user may pin, in catalogue order.
  static List<AppModule> get pinnableModules => AppModule.values
      .where((AppModule m) => m.pinnable)
      .toList(growable: false);

  /// The modules of one category, in their product order.
  static List<AppModule> inCategory(ModuleCategory category) =>
      (AppModule.values.where((AppModule m) => m.category == category).toList()
            ..sort(
              (AppModule a, AppModule b) => a.sortOrder.compareTo(b.sortOrder),
            ))
          .toList(growable: false);
}

/// One heading of the "More" hub with the modules under it.
@immutable
class MoreCategoryEntry {
  const MoreCategoryEntry({required this.category, required this.modules});

  final ModuleCategory category;
  final List<AppModule> modules;
}

/// Builds the "More" hub from the catalogue and the current bar.
///
/// Whatever is not pinned appears under its own category, in catalogue order.
/// This derivation is the app's guarantee that no module can become
/// unreachable, whichever four the user pins — a hand-written list looks
/// identical on a default install and silently strands the rest.
///
/// Empty categories are dropped rather than shown as a bare heading.
List<MoreCategoryEntry> moreEntriesFor(Iterable<AppModule> pinned) {
  final Set<AppModule> onBar = pinned.toSet();
  final List<MoreCategoryEntry> entries = <MoreCategoryEntry>[];
  for (final ModuleCategory category in ModuleCategory.values) {
    final List<AppModule> modules = AppModule.inCategory(
      category,
    ).where((AppModule m) => !onBar.contains(m)).toList(growable: false);
    if (modules.isEmpty) continue;
    entries.add(MoreCategoryEntry(category: category, modules: modules));
  }
  return List<MoreCategoryEntry>.unmodifiable(entries);
}
