// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../app/app_routes.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/network/loaded.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/offline_notice.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../core/widgets/translation_fallback_notice.dart';
import '../../../l10n/l10n.dart';
import '../../notifications/domain/notification_category.dart';
import '../../notifications/presentation/pre_permission_sheet.dart';
import '../application/canteen_filter_controller.dart';
import '../application/canteen_providers.dart';
import '../domain/canteen_filter.dart';
import '../domain/canteen_balance_reader.dart';
import '../domain/meal_highlight.dart';
import 'canteen_balance_sheet.dart';
import 'canteen_filter_sheet.dart';
import '../application/canteen_refresh_scheduler.dart';
import '../data/canteen_models.dart';
import 'canteen_picker_sheet.dart';
import 'meal_card.dart';

/// The canteen screen: what is on offer today, as a menu card.
///
/// The stable Campus eyebrow locates the module; the selected canteen is the
/// page title. The picker and filter remain actions in that masthead.
class CanteenScreen extends ConsumerStatefulWidget {
  const CanteenScreen({this.externalBalanceLaunchToken, super.key});

  final String? externalBalanceLaunchToken;

  @override
  ConsumerState<CanteenScreen> createState() => _CanteenScreenState();
}

class _CanteenScreenState extends ConsumerState<CanteenScreen>
    with WidgetsBindingObserver {
  late final CanteenRefreshScheduler _scheduler;
  String? _handledBalanceLaunchToken;

  @override
  void initState() {
    super.initState();
    _scheduler = CanteenRefreshScheduler(onRefresh: _refresh);
    WidgetsBinding.instance.addObserver(this);
    _scheduler.start();
    _scheduleExternalBalanceRead();
  }

  @override
  void didUpdateWidget(CanteenScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalBalanceLaunchToken !=
        oldWidget.externalBalanceLaunchToken) {
      _scheduleExternalBalanceRead();
    }
  }

  void _scheduleExternalBalanceRead() {
    final String? token = widget.externalBalanceLaunchToken;
    if (token == null || token == _handledBalanceLaunchToken) return;
    _handledBalanceLaunchToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showCanteenBalanceSheet(
        context,
        origin: CanteenBalanceReadOrigin.externalTag,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduler.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _scheduler.handleLifecycleState(state);
  }

  Future<void> _refresh() async {
    // Every refresh — on opening, on resume and on the foreground timer —
    // requests the menu from today on, so it is also where a new calendar day
    // has to reach the selected day (G-04). The first refresh runs inside
    // initState, where Riverpod forbids modifying a provider, hence the
    // microtask.
    scheduleMicrotask(() {
      if (mounted) ref.read(selectedMenuDayProvider.notifier).followToday();
    });
    final String? slug = ref.read(selectedCanteenSlugProvider);
    ref.invalidate(canteensProvider);
    if (slug != null) ref.invalidate(canteenMenuProvider(slug));
    await Future.wait<Object?>(<Future<Object?>>[
      ref.read(canteensProvider.future),
      if (slug != null) ref.read(canteenMenuProvider(slug).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<Loaded<List<Canteen>>> canteens = ref.watch(
      canteensProvider,
    );
    final String? slug = ref.watch(selectedCanteenSlugProvider);
    final CanteenMenu? menu = slug == null
        ? null
        : ref.watch(canteenMenuProvider(slug)).value?.value;
    final String? selectedCanteenName = canteens.value?.value
        .where((Canteen canteen) => canteen.slug == slug)
        .firstOrNull
        ?.displayName;

    return ScreenScaffold(
      eyebrow: ModuleCategory.campus.label(l10n),
      title: menu?.displayName ?? selectedCanteenName ?? l10n.navCanteen,
      actions: <Widget>[
        IconButton(
          tooltip: l10n.canteenBalanceAction,
          onPressed: () => showCanteenBalanceSheet(context),
          icon: const Icon(AppIcons.currency_euro),
        ),
        // Always reachable, even before a canteen has loaded: favourites are
        // not scoped to one canteen and outlive the picker's own state.
        IconButton(
          tooltip: l10n.canteenFavouritesTitle,
          onPressed: () =>
              GoRouter.of(context).push(AppRoutes.canteenFavourites),
          icon: const Icon(AppIcons.star),
        ),
        if (slug != null) ...<Widget>[
          IconButton(
            tooltip: l10n.canteenPickerTitle,
            onPressed: () => showCanteenPickerSheet(context),
            icon: const Icon(AppIcons.restaurant_outlined),
          ),
          _FilterAction(slug: slug),
        ],
      ],
      controls: slug == null ? null : _DayNavigator(),
      body: switch (canteens) {
        AsyncLoading<Loaded<List<Canteen>>>() when !canteens.hasValue =>
          const LoadingView(),
        AsyncError<Loaded<List<Canteen>>>(:final Object error) => ErrorView(
          failure: error,
          onRetry: () => ref.invalidate(canteensProvider),
        ),
        _ when slug == null => EmptyView(
          icon: AppIcons.restaurant_outlined,
          title: l10n.canteenNoCanteensTitle,
          message: l10n.canteenNoCanteensMessage,
        ),
        _ => _MenuBody(slug: slug, onRefresh: _refresh),
      },
    );
  }
}

/// The filter, with its state on the glyph rather than only in the sheet.
class _FilterAction extends ConsumerWidget {
  const _FilterAction({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final CanteenFilter filter = ref.watch(canteenFilterProvider);
    final List<Meal> allMeals =
        ref
            .watch(canteenMenuProvider(slug))
            .value
            ?.value
            .dayFor(ref.watch(selectedMenuDayProvider))
            ?.meals ??
        const <Meal>[];

    return IconButton(
      tooltip: filter.isActive
          ? l10n.canteenFilterActive
          : l10n.canteenFilterTitle,
      isSelected: filter.isActive,
      icon: const Icon(AppIcons.tune),
      selectedIcon: const Icon(AppIcons.filter_alt),
      onPressed: () =>
          showCanteenFilterSheet(context, _priceVocabulary(allMeals)),
    );
  }
}

final Expando<List<MealPrice>> _priceVocabCache = Expando<List<MealPrice>>(
  'canteenPriceVocab',
);

/// Every price group known from today's offer, one sample [MealPrice] per
/// group — because a canteen cannot be asked, nor shown, a group it does not
/// have. A single meal is often missing a group the rest of the day has.
List<MealPrice> _priceVocabulary(List<Meal> meals) {
  final List<MealPrice>? cached = _priceVocabCache[meals];
  if (cached != null) return cached;
  final Map<String, MealPrice> byGroup = <String, MealPrice>{
    for (final Meal meal in meals)
      for (final MealPrice price in meal.prices) price.group: price,
  };
  final List<MealPrice> result = byGroup.values.toList(growable: false);
  _priceVocabCache[meals] = result;
  return result;
}

class _MenuBody extends ConsumerWidget {
  const _MenuBody({required this.slug, required this.onRefresh});

  final String slug;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Loaded<CanteenMenu>> menu = ref.watch(
      canteenMenuProvider(slug),
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: switch (menu) {
        AsyncLoading<Loaded<CanteenMenu>>() when !menu.hasValue =>
          const LoadingView(),
        AsyncError<Loaded<CanteenMenu>>(:final Object error) => ErrorView(
          failure: error,
          onRetry: () => ref.invalidate(canteenMenuProvider(slug)),
        ),
        _ => _MenuContent(loaded: menu.requireValue, slug: slug),
      },
    );
  }
}

class _MenuContent extends ConsumerWidget {
  const _MenuContent({required this.loaded, required this.slug});

  final Loaded<CanteenMenu> loaded;
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppMetrics metrics = context.metrics;
    final String locale = Localizations.localeOf(context).languageCode;
    final DateTime selectedDay = ref.watch(selectedMenuDayProvider);
    final CanteenMenu menu = loaded.value;
    final MenuDay? day = menu.dayFor(selectedDay);
    final List<Meal> allMeals = day?.meals ?? const <Meal>[];
    final CanteenFilter filter = ref.watch(canteenFilterProvider);
    final MealHighlight? highlight = ref.watch(mealHighlightProvider);
    final List<Meal> meals = filter.apply(allMeals);
    final List<MealPrice> knownPriceGroups = _priceVocabulary(allMeals);

    final DateTime? lastSync = loaded.meta.lastSuccessfulSyncAt;
    final bool stale = loaded.meta.dataStale;

    final Widget content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        metrics.screenPadding,
        0,
        metrics.screenPadding,
        AppSpacing.xxl,
      ),
      children: <Widget>[
        if (loaded.fromCache) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          OfflineNotice(cachedAt: loaded.cachedAt),
        ],
        if (loaded.meta.translationFallback) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          const TranslationFallbackNotice(),
        ],
        if (stale) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          StatusBanner(
            tone: StatusTone.warning,
            icon: AppIcons.update_disabled_outlined,
            title: l10n.canteenStaleTitle,
            message: l10n.canteenStaleMessage,
          ),
        ],

        // "Nothing on offer" and "nothing matches your filter" are different
        // answers, and only the second one has an obvious remedy.
        if (meals.isEmpty && allMeals.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: EmptyView(
              icon: AppIcons.filter_alt_off_outlined,
              title: l10n.canteenNoMealsAfterFilter,
              message: l10n.canteenNoMealsAfterFilterMessage,
              action: FilledButton.icon(
                onPressed: () =>
                    ref.read(canteenFilterProvider.notifier).clear(),
                icon: const Icon(AppIcons.filter_alt_off_outlined),
                label: Text(l10n.canteenFilterClear),
              ),
            ),
          )
        else if (meals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Builder(
              builder: (BuildContext context) {
                // Closed at the weekend and in the holidays, so an empty day is
                // normal. Offering the next day that HAS something beats making
                // the user tap forward until they find it.
                final MenuDay? next = menu.nextOpenDayFrom(selectedDay);
                // Beyond the delivered window this is not a closing day, it is
                // a day nobody has published yet — the old text claimed the
                // former for both.
                final bool outsideWindow = !menu.covers(selectedDay);
                return EmptyView(
                  icon: AppIcons.soup,
                  title: l10n.canteenNoMealsTitle,
                  message: outsideWindow
                      ? l10n.canteenNoDataForDay
                      : l10n.canteenNoMealsMessage,
                  action: next == null
                      ? null
                      : FilledButton.icon(
                          onPressed: () => ref
                              .read(selectedMenuDayProvider.notifier)
                              .select(next.date),
                          icon: const Icon(AppIcons.skip_next_outlined),
                          label: Text(
                            '${l10n.canteenJumpToNextOpen} · '
                            '${AppDateFormats.shortWeekdayDate(next.date, locale)}',
                          ),
                        ),
                );
              },
            ),
          )
        else
          for (final Meal meal in meals) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            MealCard(
              meal: meal,
              priceGroup: filter.priceGroup,
              knownPriceGroups: knownPriceGroups,
              isFavourite: filter.isFavourite(meal),
              isHighlighted:
                  highlight?.marks(
                    slug: menu.canteenSlug,
                    shownDay: selectedDay,
                    name: meal.name,
                  ) ??
                  false,
              onToggleFavourite: () async {
                final bool willBeFavourite = !filter.isFavourite(meal);
                await ref
                    .read(canteenFilterProvider.notifier)
                    .toggleFavourite(meal);
                // Starring a dish is the contextual entry point for the
                // 11:00 hint (UX spec § 2.2 B). Only on the way in, and only
                // once — un-starring is not a moment to ask anything.
                if (!willBeFavourite || !context.mounted) return;
                await maybeOfferNotificationOptIn(
                  context,
                  ref,
                  category: NotificationCategory.canteenFavourite,
                );
              },
            ),
          ],

        // The provenance of the page, in the smallest voice on it — set in the
        // data face, because a sync timestamp is data about the data.
        SizedBox(height: metrics.sectionGap),
        const HairRule(),
        const SizedBox(height: AppSpacing.sm),
        Text(
          lastSync == null
              ? l10n.canteenNeverSynced
              : l10n.canteenLastSyncAt(
                  AppDateFormats.dateTime(lastSync, locale),
                ),
          style: context.type.dataSmall,
        ),
        if (meals.any((Meal meal) => meal.sourceLanguage == 'de'))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              l10n.canteenSourceLanguageHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Match the calendar's day view: left advances one day, right goes back.
      // Both gestures feed the same controller as the visible arrow buttons,
      // so every navigation path has identical date and DST behaviour.
      onHorizontalDragEnd: (DragEndDetails details) {
        final double velocity = details.primaryVelocity ?? 0;
        if (velocity == 0) return;
        ref
            .read(selectedMenuDayProvider.notifier)
            .shiftBy(velocity < 0 ? 1 : -1);
      },
      child: content,
    );
  }
}

/// The day being read, with a step either side.
///
/// The date is set in the display face and the arrows are plain controls beside
/// it: the day is the loudest thing under the masthead because it is what the
/// whole screen is about.
class _DayNavigator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final AppMetrics metrics = context.metrics;
    final String locale = Localizations.localeOf(context).languageCode;
    final DateTime date = ref.watch(selectedMenuDayProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.screenPadding - AppSpacing.md,
        AppSpacing.xs,
        metrics.screenPadding - AppSpacing.md,
        0,
      ),
      child: Row(
        children: <Widget>[
          // The stepper is unbounded: a reader who walked a fortnight forward
          // had exactly as many taps back. The calendar has had a "today"
          // action all along; this screen had none.
          if (_isAwayFromToday(date))
            IconButton(
              tooltip: l10n.canteenTodayAction,
              onPressed: () => ref
                  .read(selectedMenuDayProvider.notifier)
                  .select(DateTime.now()),
              icon: const Icon(AppIcons.today_outlined),
            ),
          IconButton(
            tooltip: l10n.canteenPreviousDay,
            onPressed: () =>
                ref.read(selectedMenuDayProvider.notifier).shiftBy(-1),
            icon: const Icon(AppIcons.chevron_left),
          ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              label: l10n.canteenDayLabel(
                AppDateFormats.weekdayDate(date, locale),
              ),
              excludeSemantics: true,
              child: Text(
                AppDateFormats.weekdayDate(date, locale),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: colors.textPrimary),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.canteenNextDay,
            onPressed: () =>
                ref.read(selectedMenuDayProvider.notifier).shiftBy(1),
            icon: const Icon(AppIcons.chevron_right),
          ),
        ],
      ),
    );
  }

  /// Whether [date] is not today, so the way back is worth offering.
  static bool _isAwayFromToday(DateTime date) {
    final DateTime now = DateTime.now();
    return date.year != now.year ||
        date.month != now.month ||
        date.day != now.day;
  }
}
