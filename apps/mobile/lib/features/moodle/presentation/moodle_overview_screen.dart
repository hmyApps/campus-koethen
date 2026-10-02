// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../application/moodle_account_controller.dart';
import '../application/moodle_controller.dart';
import '../domain/moodle_course.dart';
import '../domain/moodle_course_search.dart';
import 'moodle_messages.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../app/app_modules.dart';

/// The connected Moodle home: the course list with a "last updated" line, a
/// manual refresh, and — on a failed refresh — a banner that keeps the last good
/// data visible. Tapping a course opens its detail page.
class MoodleOverviewScreen extends ConsumerStatefulWidget {
  const MoodleOverviewScreen({super.key});

  @override
  ConsumerState<MoodleOverviewScreen> createState() =>
      _MoodleOverviewScreenState();
}

class _MoodleOverviewScreenState extends ConsumerState<MoodleOverviewScreen> {
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
  void initState() {
    super.initState();
    // Lazy automatic sync on open (respects the one-hour gate internally).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(moodleControllerProvider.notifier).maybeAutoSync(),
    );
  }

  Future<void> _confirmDisconnect() async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.moodleDisconnectConfirmTitle),
        content: Text(l10n.moodleDisconnectConfirmMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.moodleCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.moodleDisconnectConfirm),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(moodleAccountControllerProvider.notifier).disconnect();
    } catch (_) {
      // The controller deliberately stays connected when any credential,
      // cache content or encryption key could not be confirmed absent. Keep
      // the retry action visible and report the incomplete local deletion.
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.moodleDisconnectIncomplete)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final MoodleOverviewState view =
        ref.watch(moodleControllerProvider).value ??
        const MoodleOverviewState();

    return ScreenScaffold(
      eyebrow: ModuleCategory.study.label(l10n),
      title: l10n.moodleTitle,
      actions: <Widget>[
        IconButton(
          onPressed: _toggleSearch,
          // One button, two opposite actions — a single fixed label told a
          // screen reader "search" whether the tap would open or close it.
          tooltip: _searching
              ? l10n.moodleSearchClose
              : l10n.moodleSearchTooltip,
          icon: Icon(_searching ? AppIcons.search_off : AppIcons.search),
        ),
        IconButton(
          onPressed: view.isSyncing
              ? null
              : () => ref.read(moodleControllerProvider.notifier).refresh(),
          tooltip: l10n.moodleRefresh,
          icon: view.isSyncing
              ? const SizedBox(
                  height: AppSizes.icon,
                  width: AppSizes.icon,
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xs),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(AppIcons.refresh),
        ),
        PopupMenuButton<String>(
          onSelected: (String value) {
            if (value == 'disconnect') _confirmDisconnect();
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'disconnect',
              child: Text(l10n.moodleDisconnect),
            ),
          ],
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
                decoration: InputDecoration(
                  labelText: l10n.moodleSearchLabel,
                  hintText: l10n.moodleSearchHint,
                  prefixIcon: const Icon(AppIcons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(AppIcons.clear),
                    tooltip: l10n.moodleSearchClear,
                    onPressed: () => setState(_search.clear),
                  ),
                ),
                // Filters the list already on the device. No keystroke turns
                // into a request — not to Moodle, and certainly not to a
                // Campus Köthen backend, which never sees Moodle data.
                onChanged: (String _) => setState(() {}),
              ),
            ),
          Expanded(child: _body(context, l10n, locale, view)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    String locale,
    MoodleOverviewState view,
  ) {
    if (view.courses.isEmpty) {
      if (view.isSyncing && !view.hasCache) {
        return Semantics(
          liveRegion: true,
          label: l10n.moodleConnecting,
          child: const LoadingView(),
        );
      }
      if (view.error != null && !view.hasCache) {
        return EmptyView(
          icon: AppIcons.error_outline,
          message: moodleFailureMessage(l10n, view.error),
          action: FilledButton.icon(
            onPressed: () =>
                ref.read(moodleControllerProvider.notifier).refresh(),
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.moodleRefresh),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: () => ref.read(moodleControllerProvider.notifier).refresh(),
        child: ListView(
          // Short content plus Android clamping physics means no drag, and
          // therefore no refresh gesture — most likely on exactly this empty
          // state, where retrying is the only thing left to do.
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            _Header(view: view, locale: locale),
            EmptyView(
              title: l10n.moodleNoCoursesTitle,
              message: l10n.moodleNoCoursesMessage,
              icon: AppIcons.school_outlined,
            ),
          ],
        ),
      );
    }

    // With no filter the controller's list is already in display order. Keep
    // that instance instead of copying every course on unrelated rebuilds.
    final List<MoodleCourse> visible = _search.text.trim().isEmpty
        ? view.courses
        : searchMoodleCourses(view.courses, _search.text);

    return RefreshIndicator(
      onRefresh: () => ref.read(moodleControllerProvider.notifier).refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _Header(view: view, locale: locale),
          ),
          if (view.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: StatusBanner(
                  tone: StatusTone.warning,
                  icon: AppIcons.sync_problem,
                  title: l10n.moodleOfflineHint,
                  message: moodleFailureMessage(l10n, view.error),
                ),
              ),
            ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: EmptyView(
                  icon: AppIcons.search_off,
                  title: l10n.moodleSearchEmptyTitle,
                  message: l10n.moodleSearchEmptyMessage,
                ),
              ),
            )
          else
            SliverList.builder(
              // Each course keeps the existing divider after it, while both
              // are now instantiated only as they approach the viewport.
              itemCount: visible.length * 2,
              itemBuilder: (BuildContext context, int index) => index.isOdd
                  ? const Divider(height: 1)
                  : _CourseTile(course: visible[index ~/ 2]),
            ),
        ],
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course});

  final MoodleCourse course;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return ListTile(
      leading: Icon(AppIcons.book_outlined, color: context.colors.primary),
      title: Text(moodleCourseName(l10n, course.id, course.fullName)),
      subtitle: course.shortName.isEmpty ? null : Text(course.shortName),
      trailing: const Icon(AppIcons.chevron_right),
      onTap: () => context.push('/more/moodle/course/${course.id}'),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.view, required this.locale});

  final MoodleOverviewState view;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String when = view.lastSuccessfulSync == null
        ? l10n.moodleNeverUpdated
        : l10n.moodleLastUpdated(
            AppDateFormats.dateTime(view.lastSuccessfulSync!, locale),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Semantics(
        liveRegion: true,
        child: Text(when, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}
