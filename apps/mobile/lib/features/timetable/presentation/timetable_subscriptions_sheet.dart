// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/loaded.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/semester_assistant.dart';
import '../application/timetable_providers.dart';
import '../data/timetable_models.dart';

Future<void> showAdditionalTimetableGroupsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.9,
        child: SafeArea(child: _AdditionalGroupsSheet()),
      ),
    );

Future<void> showSemesterSuggestionSheet(
  BuildContext context,
  TimetableSemesterSuggestion suggestion,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.9,
    child: SafeArea(child: _SemesterSuggestionSheet(suggestion: suggestion)),
  ),
);

Future<void> showTimetableModulesSheet(
  BuildContext context,
  TimetableGroup group,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.9,
    child: SafeArea(child: _TimetableModulesSheet(group: group)),
  ),
);

class _AdditionalGroupsSheet extends ConsumerStatefulWidget {
  const _AdditionalGroupsSheet();

  @override
  ConsumerState<_AdditionalGroupsSheet> createState() =>
      _AdditionalGroupsSheetState();
}

class _AdditionalGroupsSheetState
    extends ConsumerState<_AdditionalGroupsSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppSettings settings = ref.watch(settingsProvider);
    final AsyncValue<Loaded<List<TimetableGroup>>> groups = ref.watch(
      timetableGroupsProvider,
    );
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              header: true,
              child: Text(
                l10n.timetableSubscriptionsTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.timetableGroupSearchLabel,
              hintText: l10n.timetableGroupSearchHint,
              prefixIcon: const Icon(AppIcons.search),
            ),
          ),
        ),
        Expanded(
          child: groups.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              failure: error,
              onRetry: () => ref.invalidate(timetableGroupsProvider),
            ),
            data: (loaded) {
              final String query = _search.text.trim().toLowerCase();
              final List<TimetableGroup> matches = loaded.value
                  .where((group) => group.matchesNeedle(query))
                  .toList(growable: false);
              if (matches.isEmpty) {
                return EmptyView(
                  icon: AppIcons.search_off_outlined,
                  title: l10n.timetableGroupSearchEmptyTitle,
                  message: l10n.timetableGroupSearchEmptyMessage,
                );
              }
              final Set<String> selected = settings.timetableAdditionalGroupIds
                  .toSet();
              final Map<String, int> selectedModuleCounts = <String, int>{};
              for (final TimetableModuleSubscription subscription
                  in settings.timetableAdditionalModules) {
                selectedModuleCounts.update(
                  subscription.groupId,
                  (count) => count + 1,
                  ifAbsent: () => 1,
                );
              }
              final int selectedGroupCount = <String>{
                ...selected,
                ...selectedModuleCounts.keys,
              }.length;
              final bool atLimit =
                  selectedGroupCount >=
                  SettingsController.maxAdditionalTimetableGroups;
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final TimetableGroup group = matches[index];
                  final bool primary = group.id == settings.timetableGroupId;
                  final bool fullGroup = selected.contains(group.id);
                  final int moduleCount = selectedModuleCounts[group.id] ?? 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      CheckboxListTile(
                        value: primary || fullGroup,
                        onChanged:
                            primary ||
                                (atLimit && !fullGroup && moduleCount == 0)
                            ? null
                            : (checked) async {
                                final Set<String> next = <String>{...selected};
                                if (checked ?? false) {
                                  next.add(group.id);
                                } else {
                                  next.remove(group.id);
                                }
                                await ref
                                    .read(settingsProvider.notifier)
                                    .setAdditionalTimetableGroups(next);
                              },
                        title: Text(group.shortName),
                        subtitle: Text(
                          primary
                              ? l10n.timetablePrimaryGroupLabel
                              : <String?>[
                                  group.longName,
                                  group.department,
                                ].whereType<String>().join(' · '),
                        ),
                      ),
                      if (!primary)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          leading: const Icon(AppIcons.book_outlined),
                          title: Text(
                            fullGroup
                                ? l10n.timetableAllModulesSelected
                                : l10n.timetableModulesManage(moduleCount),
                          ),
                          trailing: fullGroup
                              ? null
                              : const Icon(AppIcons.chevron_right),
                          enabled: !fullGroup,
                          onTap: fullGroup
                              ? null
                              : () => showTimetableModulesSheet(context, group),
                        ),
                      const Divider(height: 1),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TimetableModulesSheet extends ConsumerWidget {
  const _TimetableModulesSheet({required this.group});

  final TimetableGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<Loaded<List<TimetableModule>>> modules = ref.watch(
      timetableModulesProvider(group.id),
    );
    final AppSettings settings = ref.watch(settingsProvider);
    final List<TimetableModuleSubscription> subscriptions =
        settings.timetableAdditionalModules;
    final Set<String> selected = subscriptions
        .where((item) => item.groupId == group.id)
        .map((item) => item.moduleKey)
        .toSet();
    final bool atModuleLimit =
        subscriptions.length >=
        SettingsController.maxAdditionalTimetableModules;
    final int selectedGroupCount = <String>{
      ...settings.timetableAdditionalGroupIds,
      ...subscriptions.map((item) => item.groupId),
    }.length;
    final bool atGroupLimit =
        selected.isEmpty &&
        selectedGroupCount >= SettingsController.maxAdditionalTimetableGroups;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              header: true,
              child: Text(
                l10n.timetableModulesFor(group.shortName),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
        ),
        Expanded(
          child: modules.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              failure: error,
              onRetry: () => ref.invalidate(timetableModulesProvider(group.id)),
            ),
            data: (loaded) {
              if (loaded.value.isEmpty) {
                return EmptyView(
                  icon: AppIcons.menu_book_outlined,
                  title: l10n.timetableModulesEmptyTitle,
                  message: l10n.timetableModulesEmptyMessage,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemCount: loaded.value.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final TimetableModule module = loaded.value[index];
                  final bool checked = selected.contains(module.moduleKey);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (atModuleLimit || atGroupLimit) && !checked
                        ? null
                        : (value) async {
                            final List<TimetableModuleSubscription> next =
                                subscriptions
                                    .where(
                                      (item) =>
                                          item.groupId != group.id ||
                                          item.moduleKey != module.moduleKey,
                                    )
                                    .toList(growable: true);
                            if (value ?? false) {
                              next.add(
                                TimetableModuleSubscription(
                                  groupId: group.id,
                                  moduleKey: module.moduleKey,
                                ),
                              );
                            }
                            await ref
                                .read(settingsProvider.notifier)
                                .setAdditionalTimetableModules(next);
                          },
                    title: Text(module.title),
                    subtitle: module.subjectCode == null
                        ? null
                        : Text(module.subjectCode!),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SemesterSuggestionSheet extends ConsumerStatefulWidget {
  const _SemesterSuggestionSheet({required this.suggestion});

  final TimetableSemesterSuggestion suggestion;

  @override
  ConsumerState<_SemesterSuggestionSheet> createState() =>
      _SemesterSuggestionSheetState();
}

class _SemesterSuggestionSheetState
    extends ConsumerState<_SemesterSuggestionSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String query = _search.text.trim().toLowerCase();
    final List<TimetableGroup> candidates = widget.suggestion.candidates
        .where((group) => group.matchesNeedle(query))
        .toList(growable: false);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              header: true,
              child: Text(
                l10n.timetableSemesterAssistantTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Text(
            l10n.timetableSemesterAssistantChoose(widget.suggestion.next.name),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.timetableGroupSearchLabel,
              prefixIcon: const Icon(AppIcons.search),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final TimetableGroup group = candidates[index];
              return ListTile(
                leading: const Icon(AppIcons.school_outlined),
                title: Text(group.shortName),
                subtitle: Text(
                  <String?>[
                    group.longName,
                    group.department,
                  ].whereType<String>().join(' · '),
                ),
                trailing: const Icon(AppIcons.chevron_right),
                onTap: () async {
                  await ref
                      .read(settingsProvider.notifier)
                      .setTimetableGroup(group.id);
                  if (context.mounted) Navigator.of(context).pop();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
