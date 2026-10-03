// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_routes.dart';
import '../../../core/network/loaded.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/icon_keys.dart';
import '../../../core/widgets/offline_notice.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/translation_fallback_notice.dart';
import '../../../l10n/l10n.dart';
import '../application/contacts_providers.dart';
import '../data/contact_models.dart';
import '../data/contact_search_models.dart';
import '../domain/contact_search.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../app/app_modules.dart';

/// Lists the contact areas. Areas without any person are ordinary entries.
///
/// The search is a local one: it replaces the list only while something is
/// typed, and it searches an index that was loaded **once** — no request per
/// keystroke, and no request per area either.
class ContactsListScreen extends ConsumerStatefulWidget {
  const ContactsListScreen({super.key});

  @override
  ConsumerState<ContactsListScreen> createState() => _ContactsListScreenState();
}

class _ContactsListScreenState extends ConsumerState<ContactsListScreen> {
  final TextEditingController _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Opens or closes the search field.
  ///
  /// Closing clears the term, so reopening never shows a stale filter the user
  /// has forgotten about.
  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<Loaded<List<ContactArea>>> areas = ref.watch(
      contactAreasProvider,
    );
    final String term = _search.text.trim();

    return ScreenScaffold(
      eyebrow: ModuleCategory.campus.label(l10n),
      title: l10n.contactsTitle,
      actions: <Widget>[
        IconButton(
          onPressed: _toggleSearch,
          tooltip: l10n.contactsSearchTooltip,
          icon: Icon(_searching ? AppIcons.search_off : AppIcons.search),
        ),
      ],
      body: Column(
        children: <Widget>[
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: l10n.contactsSearchLabel,
                  hintText: l10n.contactsSearchHint,
                  prefixIcon: const Icon(AppIcons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(AppIcons.clear),
                    tooltip: l10n.contactsSearchClear,
                    onPressed: () => setState(_search.clear),
                  ),
                ),
                // Local filtering only: every keystroke rebuilds, none of them
                // reaches the network.
                onChanged: (_) => setState(() {}),
              ),
            ),
          Expanded(
            // An empty search field is not a filter: the ordinary list stays.
            child: _searching && term.isNotEmpty
                ? _SearchResults(term: term)
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(contactAreasProvider);
                      ref.invalidate(contactSearchIndexProvider);
                      await ref.read(contactAreasProvider.future);
                    },
                    child: switch (areas) {
                      AsyncLoading<Loaded<List<ContactArea>>>()
                          when !areas.hasValue =>
                        const LoadingView(),
                      AsyncError<Loaded<List<ContactArea>>>(
                        :final Object error,
                      ) =>
                        ErrorView(
                          failure: error,
                          onRetry: () => ref.invalidate(contactAreasProvider),
                        ),
                      _ => _AreaList(loaded: areas.requireValue),
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.term});

  final String term;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Loaded<List<ContactSearchArea>>> index = ref.watch(
      contactSearchIndexProvider,
    );

    return switch (index) {
      AsyncLoading<Loaded<List<ContactSearchArea>>>() when !index.hasValue =>
        const LoadingView(),
      AsyncError<Loaded<List<ContactSearchArea>>>(:final Object error) =>
        ErrorView(
          failure: error,
          onRetry: () => ref.invalidate(contactSearchIndexProvider),
        ),
      _ => _HitList(
        hits: searchContacts(index.requireValue.value, term),
        fromCache: index.requireValue.fromCache,
        cachedAt: index.requireValue.cachedAt,
        translationFallback: index.requireValue.meta.translationFallback,
      ),
    };
  }
}

class _HitList extends StatelessWidget {
  const _HitList({
    required this.hits,
    required this.fromCache,
    required this.cachedAt,
    required this.translationFallback,
  });

  final List<ContactSearchHit> hits;
  final bool fromCache;
  final DateTime? cachedAt;
  final bool translationFallback;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    if (hits.isEmpty) {
      return EmptyView(
        icon: AppIcons.search_off,
        title: l10n.contactsSearchEmptyTitle,
        message: l10n.contactsSearchEmptyMessage,
      );
    }

    final int leading = (fromCache ? 1 : 0) + (translationFallback ? 1 : 0);

    return ListView.separated(
      padding: EdgeInsets.all(context.metrics.screenPadding),
      itemCount: hits.length + leading + 1,
      separatorBuilder: (BuildContext _, int _) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (BuildContext context, int index) {
        if (fromCache && index == 0) return OfflineNotice(cachedAt: cachedAt);
        if (translationFallback && index == (fromCache ? 1 : 0)) {
          return const TranslationFallbackNotice();
        }
        final int position = index - leading;
        if (position == 0) {
          return Semantics(
            liveRegion: true,
            child: Text(
              l10n.contactsSearchResultCount(hits.length),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return _HitCard(hit: hits[position - 1]);
      },
    );
  }
}

/// One result. Tapping it opens the area the hit belongs to — for a person,
/// that is where their details live.
class _HitCard extends StatelessWidget {
  const _HitCard({required this.hit});

  final ContactSearchHit hit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;

    final (String title, String? subtitle, IconData icon) = switch (hit) {
      AreaHit(:final ContactSearchArea area) => (
        area.name,
        area.shortDescription.isEmpty ? null : area.shortDescription,
        IconKeys.resolve(area.iconKey),
      ),
      PersonHit(
        :final ContactSearchPerson person,
        :final ContactSearchArea area,
      ) =>
        (
          person.name,
          <String>[
            if (person.role != null && person.role!.isNotEmpty) person.role!,
            l10n.contactsSearchInArea(area.name),
          ].join(' · '),
          AppIcons.person_outline,
        ),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.pushNamed(
          AppRoutes.contactAreaName,
          pathParameters: <String, String>{'slug': hit.area.slug},
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
          child: Padding(
            padding: EdgeInsets.all(context.metrics.cardPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, size: AppSizes.icon),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: text.titleSmall),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(subtitle, style: text.bodySmall),
                      ],
                      // Why this result is here. Without it a hit on a phone
                      // number or an opening hour looks arbitrary — but a hit
                      // on the title itself needs no explanation, and repeating
                      // the name under the name would only be noise.
                      if (hit.context != title &&
                          hit.context != subtitle) ...<Widget>[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          hit.context,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(AppIcons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AreaList extends StatelessWidget {
  const _AreaList({required this.loaded});

  final Loaded<List<ContactArea>> loaded;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<ContactArea> areas = loaded.value;

    if (areas.isEmpty) {
      return EmptyView(
        icon: AppIcons.contact_support_outlined,
        title: l10n.contactsEmptyTitle,
        message: l10n.contactsEmptyMessage,
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(context.metrics.screenPadding),
      itemCount:
          areas.length +
          (loaded.fromCache ? 1 : 0) +
          (loaded.meta.translationFallback ? 1 : 0),
      separatorBuilder: (BuildContext _, int _) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (BuildContext context, int index) {
        if (loaded.fromCache && index == 0) {
          return OfflineNotice(cachedAt: loaded.cachedAt);
        }
        if (loaded.meta.translationFallback &&
            index == (loaded.fromCache ? 1 : 0)) {
          return const TranslationFallbackNotice();
        }
        final int leading =
            (loaded.fromCache ? 1 : 0) +
            (loaded.meta.translationFallback ? 1 : 0);
        final ContactArea area = areas[index - leading];
        return _AreaCard(area: area);
      },
    );
  }
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({required this.area});

  final ContactArea area;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: l10n.contactAreaSemanticLabel(area.name),
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushNamed(
            AppRoutes.contactAreaName,
            pathParameters: <String, String>{'slug': area.slug},
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.minTouchTarget,
            ),
            child: Padding(
              padding: EdgeInsets.all(context.metrics.screenPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(IconKeys.resolve(area.iconKey), size: AppSizes.icon),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(area.name, style: text.titleMedium),
                        if (area.shortDescription != null) ...<Widget>[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(area.shortDescription!, style: text.bodyMedium),
                        ],
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.contactPersonCount(area.personCount),
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(AppIcons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
