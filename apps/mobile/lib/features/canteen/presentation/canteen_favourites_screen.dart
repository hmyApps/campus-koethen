// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../calendar/presentation/calendar_source_sheets.dart'
    show CanteenFavouriteMealsSwitch;
import '../application/canteen_filter_controller.dart';
import '../application/canteen_providers.dart';
import '../data/canteen_models.dart';
import '../domain/canteen_filter.dart';
import 'meal_card.dart';

/// "Meine Favoriten": every starred dish in one place, wherever it was
/// starred from.
///
/// A favourite is stored by **name** (see [CanteenFilter.favourites]), so it
/// can outlive the day, the week or even the canteen it was starred in. This
/// screen looks the name up again in every canteen's currently loaded menu to
/// show the same recognition data [MealCard] would — price, subtitle,
/// markers — and falls back to the bare name when no loaded menu currently
/// carries it. Either way the entry stays listed and removable: a dish that
/// temporarily fell off every menu is not the same as one the user un-starred.
class CanteenFavouritesScreen extends ConsumerWidget {
  const CanteenFavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppMetrics metrics = context.metrics;
    final CanteenFilter filter = ref.watch(canteenFilterProvider);
    final List<String> names = _sortedFavourites(filter.favourites);

    final List<Canteen> canteens =
        ref.watch(canteensProvider).value?.value ?? const <Canteen>[];
    // The loaded menus, in canteen order. Looking a favourite up walks them
    // and asks each one's own index — built once per menu instance instead of
    // walking every canteen, every day and every dish again on every rebuild,
    // which on this screen means on every star and unstar.
    final List<CanteenMenu> menus = <CanteenMenu>[
      for (final Canteen canteen in canteens)
        if (ref.watch(canteenMenuProvider(canteen.slug)).value?.value
            case final CanteenMenu menu)
          menu,
    ];
    Meal? mealNamed(String name) {
      for (final CanteenMenu menu in menus) {
        final Meal? meal = _mealsByName(menu)[name];
        if (meal != null) return meal;
      }
      return null;
    }

    return ScreenScaffold(
      eyebrow: ModuleCategory.campus.label(l10n),
      title: l10n.canteenFavouritesTitle,
      body: Column(
        children: <Widget>[
          const CanteenFavouriteMealsSwitch(),
          const Divider(height: 1),
          Expanded(
            child: names.isEmpty
                ? EmptyView(
                    icon: AppIcons.star_border,
                    title: l10n.canteenFavouritesEmptyTitle,
                    message: l10n.canteenFavouritesEmptyMessage,
                  )
                // A favourite list can run well past one screen, so each
                // card is built as it scrolls into view rather than all of
                // them up front.
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      metrics.screenPadding,
                      AppSpacing.md,
                      metrics.screenPadding,
                      AppSpacing.xxl,
                    ),
                    itemCount: names.length,
                    itemBuilder: (BuildContext context, int index) {
                      final String name = names[index];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (index > 0) const SizedBox(height: AppSpacing.md),
                          switch (mealNamed(name)) {
                            final Meal meal => MealCard(
                              meal: meal,
                              priceGroup: filter.priceGroup,
                              isFavourite: true,
                              onToggleFavourite: () => ref
                                  .read(canteenFilterProvider.notifier)
                                  .toggleFavourite(meal),
                            ),
                            null => _UnavailableFavourite(
                              name: name,
                              onRemove: () => ref
                                  .read(canteenFilterProvider.notifier)
                                  .removeFavouriteNamed(name),
                            ),
                          },
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One menu's dishes, indexed by name — the first occurrence wins, exactly as
/// the flat pass over every canteen, day and dish did.
///
/// Cached on the menu instance: a menu is loaded once and reused unchanged
/// across every rebuild, and a fresh load creates a new instance with its own
/// entry.
final Expando<Map<String, Meal>> _mealIndex = Expando<Map<String, Meal>>(
  'canteenMealsByName',
);

Map<String, Meal> _mealsByName(CanteenMenu menu) =>
    _mealIndex[menu] ??= _indexOf(menu);

Map<String, Meal> _indexOf(CanteenMenu menu) {
  final Map<String, Meal> byName = <String, Meal>{};
  for (final MenuDay day in menu.days) {
    for (final Meal meal in day.meals) {
      byName.putIfAbsent(meal.name, () => meal);
    }
  }
  return Map<String, Meal>.unmodifiable(byName);
}

/// The starred names in display order.
///
/// Cached on the favourites set, which only changes when the user stars or
/// unstars something — every other rebuild of this screen reused the same set
/// and re-copied and re-sorted it anyway.
final Expando<List<String>> _sortedNames = Expando<List<String>>(
  'canteenSortedFavourites',
);

List<String> _sortedFavourites(Set<String> favourites) =>
    _sortedNames[favourites] ??= List<String>.unmodifiable(
      favourites.toList()..sort(),
    );

/// A favourite that no currently loaded menu carries.
///
/// Still shown by name rather than dropped: the dish may simply not be on
/// offer this fortnight, and silently forgetting the favourite would be data
/// loss the user never asked for.
class _UnavailableFavourite extends StatelessWidget {
  const _UnavailableFavourite({required this.name, required this.onRemove});

  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;

    return Panel(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              label:
                  '${l10n.canteenFavouriteSemantic}. $name. '
                  '${l10n.canteenFavouritesUnavailableHint}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name, style: text.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.canteenFavouritesUnavailableHint,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            // No compact density: in Material 3 it shrinks the button AND its
            // padded tap target by 8dp, to 40dp — a minimum-size constraint
            // cannot undo that. The floor keeps the button itself at the 48dp
            // minimum (AGENTS.md §9, G-06), also where the platform does not
            // pad tap targets.
            constraints: const BoxConstraints(
              minWidth: AppSizes.minTouchTarget,
              minHeight: AppSizes.minTouchTarget,
            ),
            tooltip: l10n.canteenFavouriteRemove,
            onPressed: onRemove,
            icon: const Icon(AppIcons.star),
          ),
        ],
      ),
    );
  }
}
