// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/panel.dart';
import '../../../l10n/l10n.dart';
import '../data/canteen_models.dart';
import 'meal_price_overview_sheet.dart';

/// One meal, set as a line on a menu card.
///
/// Dish on the left, price on the right, in the data face — the shape every
/// printed menu in the world uses, and the reason it is used here is the same:
/// a reader comparing what to eat is comparing two numbers down a right-hand
/// edge, and a monospaced column is the only way they line up.
///
/// There are deliberately **no meal images** — neither stored nor rendered.
///
/// Only **one** price is shown: the one for the group the reader selected. The
/// other groups are somebody else's price, and three numbers on a card mean
/// three numbers to read past every time.
///
/// The ingredient declarations are not listed either: they are what the filter
/// works on, and a dozen chips under every dish buried the two lines that
/// actually differ between one meal and the next. The remaining markers — Bio,
/// Klima-Teller and the like — stay, because no filter covers them and nothing
/// else on the screen says them.
class MealCard extends StatelessWidget {
  const MealCard({
    required this.meal,
    required this.priceGroup,
    this.knownPriceGroups = const <MealPrice>[],
    this.isFavourite = false,
    this.isHighlighted = false,
    this.onToggleFavourite,
    super.key,
  });

  final Meal meal;

  /// The one price group whose price this card shows.
  final String priceGroup;

  /// The price vocabulary of the whole day's offer, passed through to the
  /// price overview sheet so a group this meal does not price still shows,
  /// marked unavailable, instead of vanishing from the overview.
  final List<MealPrice> knownPriceGroups;

  /// Whether the user starred this dish. Marked by a filled star **and** a
  /// semantic label, never by colour alone.
  ///
  /// A favourite is not a filter and does not move the dish: the list keeps the
  /// counter order, which is the order the food is served in.
  final bool isFavourite;

  /// Whether this is the dish a notification tap pointed at.
  ///
  /// Drawn as the panel's marker edge **and** said in words above the dish, so
  /// the mark carries its meaning without colour (AGENTS.md § 9). It is a
  /// pointer, not a state of the meal: it says "this is the one you tapped",
  /// which is why it disappears as soon as the reader leaves the day.
  final bool isHighlighted;

  final VoidCallback? onToggleFavourite;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // CANT-3: which dish is untranslated was said once, as a footnote under
    // the whole list. It belongs on the dish.
    //
    // Only where it distinguishes anything: in the German UI every name is
    // German, so a marker on every card would be noise rather than
    // information. In English it separates the translated dishes from the
    // ones that arrived unchanged from the German source.
    final bool showsOriginalLanguage =
        meal.sourceLanguage == 'de' &&
        Localizations.localeOf(context).languageCode != 'de';

    return Semantics(
      container: true,
      button: true,
      label: l10n.canteenPriceOverviewOpenSemantic(meal.name),
      explicitChildNodes: true,
      child: Panel(
        live: isHighlighted,
        onTap: () => showMealPriceOverviewSheet(
          context,
          meal: meal,
          priceGroup: priceGroup,
          knownPriceGroups: knownPriceGroups,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (isHighlighted)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  l10n.canteenHighlightedByNotification,
                  style: context.type.eyebrow.copyWith(color: colors.primary),
                ),
              ),
            if (meal.isSprint)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Semantics(
                  label: l10n.canteenSprintSemanticLabel,
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        AppIcons.bolt_outlined,
                        size: AppSizes.iconSmall,
                        color: colors.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        l10n.canteenSprintLabel,
                        style: context.type.eyebrow.copyWith(
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Dish and price on one line. The price column is right-aligned and
            // monospaced, so a list of meals has a straight edge of numbers.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    header: true,
                    label: <String>[
                      if (isFavourite) l10n.canteenFavouriteSemantic,
                      meal.name,
                      if (showsOriginalLanguage)
                        l10n.canteenMealOriginalLanguage,
                    ].join('. '),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(meal.name, style: text.titleMedium),
                        if (showsOriginalLanguage)
                          Text(
                            l10n.canteenMealOriginalLanguage,
                            style: text.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _Price(price: meal.priceFor(priceGroup)),
              ],
            ),

            if (meal.subtitle != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                meal.subtitle!,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ],

            if (meal.extras.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _LabelledWrap(
                label: l10n.canteenExtrasLabel,
                values: meal.extras,
              ),
            ],
            if (meal.nonIngredientMarkers.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _LabelledWrap(
                label: l10n.canteenMarkersLabel,
                values: meal.nonIngredientMarkers
                    .map((MealMarker marker) => marker.label)
                    .toList(growable: false),
              ),
            ],

            if (onToggleFavourite != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                // No compact density: in Material 3 it shrinks the button AND
                // its padded tap target by 8 dp, to 40 dp — under the
                // project's own 48 dp floor, on the main action of the card —
                // and a minimum-size constraint cannot undo that (G-06). The
                // constraints keep the button itself at 48 dp, also where the
                // platform does not pad tap targets.
                child: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSizes.minTouchTarget,
                    minHeight: AppSizes.minTouchTarget,
                  ),
                  tooltip: isFavourite
                      ? l10n.canteenFavouriteRemove
                      : l10n.canteenFavouriteAdd,
                  onPressed: onToggleFavourite,
                  icon: Icon(
                    isFavourite ? AppIcons.star : AppIcons.star_border,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LabelledWrap extends StatelessWidget {
  const _LabelledWrap({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: context.type.eyebrow),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (final String value in values)
              Chip(
                label: Text(value),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The price of the selected group, or a clear statement that there is none —
/// and, tapped, the overview of every price group this meal has.
///
/// A missing price is never replaced by another group's: that would be a
/// different number for a different person, presented as if it were theirs.
class _Price extends StatelessWidget {
  const _Price({required this.price});

  final MealPrice? price;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final AppTypography type = context.type;
    final String locale = Localizations.localeOf(context).languageCode;
    final MealPrice? price = this.price;

    final Widget content;
    if (price == null) {
      content = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: Text(
          l10n.canteenPriceForGroupMissing,
          textAlign: TextAlign.end,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      );
    } else {
      final String formatted =
          MoneyFormatter.format(
            amount: price.amount,
            currencyCode: price.currency,
            locale: locale,
          ) ??
          l10n.canteenPriceMissing;

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            formatted,
            style: type.dataLarge.copyWith(
              color: colors.brightness == Brightness.light
                  ? colors.primaryDark
                  : colors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          // Whose price this is. Never dropped: the same dish costs three
          // different amounts, and a bare number would be a guess.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              price.label,
              textAlign: TextAlign.end,
              style: type.dataSmall,
            ),
          ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: AppSizes.minTouchTarget,
        minHeight: AppSizes.minTouchTarget,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Align(alignment: Alignment.centerRight, child: content),
      ),
    );
  }
}
