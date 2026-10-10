// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_providers.dart';
import '../../../core/network/loaded.dart';
import '../../../core/prefs/settings_controller.dart';
import '../data/canteen_models.dart';
import '../data/canteen_repository.dart';
import '../domain/meal_highlight.dart';

/// The canteen list. Comes exclusively from the API.
final FutureProvider<Loaded<List<Canteen>>> canteensProvider =
    FutureProvider<Loaded<List<Canteen>>>((Ref ref) async {
      final String locale = ref.watch(localeCodeProvider);
      return ref.watch(canteenRepositoryProvider).fetchCanteens(locale: locale);
    });

/// The canteen currently shown: the stored preference if it still exists,
/// otherwise the first canteen the API offers.
final Provider<String?> selectedCanteenSlugProvider = Provider<String?>((
  Ref ref,
) {
  final List<Canteen> canteens =
      ref.watch(canteensProvider).value?.value ?? const <Canteen>[];
  if (canteens.isEmpty) return null;
  final String? preferred = ref.watch(
    settingsProvider.select(
      (AppSettings settings) => settings.preferredCanteenSlug,
    ),
  );
  final bool preferredExists = canteens.any(
    (Canteen canteen) => canteen.slug == preferred,
  );
  return preferredExists ? preferred : canteens.first.slug;
});

/// The menu of one canteen for the cached two-week window.
final canteenMenuProvider = FutureProvider.family<Loaded<CanteenMenu>, String>((
  Ref ref,
  String slug,
) async {
  final String locale = ref.watch(localeCodeProvider);
  return ref
      .watch(canteenRepositoryProvider)
      .fetchMenu(locale: locale, slug: slug);
});

/// The clock the canteen's "today" is read from. Overridden in tests, same
/// convention as `savedEventsClockProvider`.
final Provider<DateTime Function()> canteenClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now);

/// The day the canteen screen currently shows. Defaults to today.
///
/// "Today" is a moving target: the menu window is re-requested from the
/// current date on every refresh, so a selection left on yesterday after
/// midnight points at a day the menu no longer holds (G-04). As long as the
/// reader has not picked another day on purpose, [followToday] moves the
/// selection along with the calendar.
class SelectedMenuDayController extends Notifier<DateTime> {
  /// Whether the selection is "today" rather than one particular date.
  bool _followsToday = true;

  @override
  DateTime build() {
    _followsToday = true;
    return _today();
  }

  DateTime _today() {
    final DateTime now = ref.read(canteenClockProvider)();
    return DateTime(now.year, now.month, now.day);
  }

  void select(DateTime date) {
    state = DateTime(date.year, date.month, date.day);
    // Going back to today is a choice to follow it again.
    _followsToday = state == _today();
  }

  /// Moves a selection that follows today on to the current date.
  ///
  /// A day the reader chose deliberately stays — unless the calendar has
  /// caught up with it, from which point it is simply today again.
  void followToday() {
    final DateTime today = _today();
    if (state == today) {
      _followsToday = true;
      return;
    }
    if (_followsToday) state = today;
  }

  /// Moves [days] days, DST-safe.
  ///
  /// `add(Duration(days: 1))` on a 25-hour day lands back on the same
  /// calendar date, so once a year the "next day" arrow simply did nothing.
  /// The constructor normalises month and year boundaries and has no such
  /// blind spot — the same fix `TimetableWeek.shift` already carries.
  void shiftBy(int days) =>
      select(DateTime(state.year, state.month, state.day + days));
}

final NotifierProvider<SelectedMenuDayController, DateTime>
selectedMenuDayProvider = NotifierProvider<SelectedMenuDayController, DateTime>(
  SelectedMenuDayController.new,
);

/// The dish a notification tap asked the screen to mark, if any.
///
/// Set by the notification host before it navigates, so the card is already
/// marked on the first frame instead of lighting up afterwards. It clears
/// itself the moment the reader moves to another day: from then on the
/// marker would point at nothing they asked for.
class MealHighlightController extends Notifier<MealHighlight?> {
  @override
  MealHighlight? build() {
    ref.listen<DateTime>(selectedMenuDayProvider, (DateTime? _, DateTime day) {
      final MealHighlight? current = state;
      if (current == null) return;
      if (current.day.year == day.year &&
          current.day.month == day.month &&
          current.day.day == day.day) {
        return;
      }
      state = null;
    });
    return null;
  }

  void mark(MealHighlight highlight) => state = highlight;

  void clear() => state = null;
}

final NotifierProvider<MealHighlightController, MealHighlight?>
mealHighlightProvider =
    NotifierProvider<MealHighlightController, MealHighlight?>(
      MealHighlightController.new,
    );
