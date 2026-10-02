// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/app_modules.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/prefs/key_value_store.dart';
import 'package:campus_koethen/core/prefs/preference_keys.dart';
import 'package:campus_koethen/core/theme/app_colors.dart';
import 'package:campus_koethen/core/theme/app_icons.dart';
import 'package:campus_koethen/features/more/presentation/more_screen.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

Future<AppLocalizations> pumpMore(
  WidgetTester tester, {
  List<AppModule>? bar,
  Locale locale = AppLocales.german,
  ThemeMode themeMode = ThemeMode.light,
  TextScaler textScaler = TextScaler.noScaling,
  Size surface = const Size(390, 2000),
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final InMemoryKeyValueStore store = InMemoryKeyValueStore();
  if (bar != null) {
    await store.setStringList(
      PreferenceKeys.navigationTabs,
      bar.map((AppModule m) => m.storageValue).toList(),
    );
  }

  await pumpScreen(
    tester,
    const MoreScreen(),
    locale: locale,
    themeMode: themeMode,
    keyValueStore: store,
    textScaler: textScaler,
  );
  await tester.pumpAndSettle();

  return await AppLocalizations.delegate.load(locale);
}

void main() {
  testWidgets('the default bar produces exactly the specified hub', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = await pumpMore(tester);

    // Headings. Looked up by their accessible name, not by the glyphs on
    // screen: a section heading is set in capitals for the eye, and the string
    // a screen reader is handed stays the original one.
    for (final ModuleCategory category in ModuleCategory.values) {
      expect(find.bySemanticsLabel(category.label(l10n)), findsWidgets);
    }

    // Studium: what is not pinned.
    for (final AppModule module in <AppModule>[
      AppModule.timetable,
      AppModule.moodle,
      AppModule.grades,
      AppModule.todos,
      AppModule.campusMap,
      AppModule.contacts,
      AppModule.requests,
      AppModule.settings,
      AppModule.about,
    ]) {
      expect(
        find.text(module.title(l10n)),
        findsOneWidget,
        reason: module.storageValue,
      );
    }
  });

  testWidgets('module icons use the requested glyphs and theme brand colour', (
    WidgetTester tester,
  ) async {
    for (final (ThemeMode mode, Color expected) in <(ThemeMode, Color)>[
      (ThemeMode.light, AppColors.light.primary),
      (ThemeMode.dark, AppColors.dark.primary),
    ]) {
      await pumpMore(tester, themeMode: mode);

      for (final IconData glyph in <IconData>[
        AppIcons.schedule_outlined,
        AppIcons.book_outlined,
        AppIcons.grade_outlined,
        AppIcons.file_pencil,
      ]) {
        final Icon icon = tester.widget<Icon>(find.byIcon(glyph));
        expect(icon.color, expected);
      }
    }
  });

  testWidgets('what is on the bar is not repeated here', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = await pumpMore(tester);
    for (final AppModule module in <AppModule>[
      AppModule.news,
      AppModule.calendar,
      AppModule.canteen,
      AppModule.mail,
    ]) {
      expect(
        find.text(module.title(l10n)),
        findsNothing,
        reason: module.storageValue,
      );
    }
  });

  testWidgets('a module pushed off the bar appears under its category', (
    WidgetTester tester,
  ) async {
    // The invariant the hub exists for: whichever four are pinned, the rest
    // stay reachable.
    final AppLocalizations l10n = await pumpMore(
      tester,
      bar: <AppModule>[
        AppModule.moodle,
        AppModule.todos,
        AppModule.campusMap,
        AppModule.grades,
      ],
    );

    for (final AppModule module in <AppModule>[
      AppModule.calendar,
      AppModule.mail,
      AppModule.news,
      AppModule.canteen,
    ]) {
      expect(
        find.text(module.title(l10n)),
        findsOneWidget,
        reason: module.storageValue,
      );
    }
    expect(find.text(AppModule.moodle.title(l10n)), findsNothing);
  });

  testWidgets('settings and about are always under App', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = await pumpMore(
      tester,
      bar: <AppModule>[
        AppModule.moodle,
        AppModule.todos,
        AppModule.campusMap,
        AppModule.grades,
      ],
    );
    expect(find.text(l10n.moreSettings), findsOneWidget);
    expect(find.text(l10n.aboutTitle), findsOneWidget);
  });

  testWidgets('there is no Today entry any more', (WidgetTester tester) async {
    final AppLocalizations l10n = await pumpMore(tester);
    expect(find.text(l10n.navToday), findsNothing);
  });

  testWidgets('renders in English', (WidgetTester tester) async {
    final AppLocalizations l10n = await pumpMore(
      tester,
      locale: AppLocales.english,
    );
    expect(find.bySemanticsLabel(l10n.moduleCategoryStudy), findsWidgets);
    expect(find.text(l10n.moduleContactsTitle), findsOneWidget);
  });

  testWidgets('every row stays a 48dp target', (WidgetTester tester) async {
    await pumpMore(tester);
    for (final Element element in find.byType(ListTile).evaluate()) {
      final RenderBox box = element.renderObject! as RenderBox;
      expect(box.size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('survives a narrow phone with doubled text', (
    WidgetTester tester,
  ) async {
    await pumpMore(
      tester,
      textScaler: const TextScaler.linear(2),
      surface: const Size(320, 4000),
    );
    expect(tester.takeException(), isNull);
  });
}
