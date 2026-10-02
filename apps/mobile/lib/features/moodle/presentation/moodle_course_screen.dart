// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/documents/app_document.dart';
import '../../../core/documents/document_viewer_screen.dart';
import '../../../core/links/safe_link_launcher.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/moodle_course_detail.dart';
import '../application/moodle_providers.dart';
import '../domain/moodle_announcement.dart';
import '../domain/moodle_assignment.dart';
import '../domain/moodle_content.dart';
import '../domain/moodle_downloader.dart';
import '../domain/moodle_course.dart';
import '../domain/moodle_repository.dart';
import 'moodle_messages.dart';
import 'moodle_course_refresh_controller.dart';
import '../../../core/widgets/screen_scaffold.dart';

/// A course detail page with three tabs: contents (sections/modules/files),
/// assignments (with submission status) and announcements — all read-only.
class MoodleCourseScreen extends ConsumerStatefulWidget {
  const MoodleCourseScreen({required this.courseId, super.key});

  final int courseId;

  @override
  ConsumerState<MoodleCourseScreen> createState() => _MoodleCourseScreenState();
}

class _MoodleCourseScreenState extends ConsumerState<MoodleCourseScreen> {
  late final MoodleCourseRefreshController _refreshState;

  @override
  void initState() {
    super.initState();
    _refreshState = MoodleCourseRefreshController()
      ..addListener(_onRefreshChanged);
  }

  @override
  void dispose() {
    _refreshState
      ..removeListener(_onRefreshChanged)
      ..dispose();
    super.dispose();
  }

  void _onRefreshChanged() {
    if (mounted) setState(() {});
  }

  /// Runs a manual refresh and actually reports what happened.
  ///
  /// The old call site dropped the future on the floor: no spinner, the button
  /// stayed live, and a refresh that threw — offline, or an expired token —
  /// left the screen showing the same stale bundle with an unhandled async
  /// error behind it. Nothing on screen moved at all.
  Future<void> _refresh() async {
    await _refreshState.run(
      () => refreshMoodleCourseDetail(ref, widget.courseId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final int courseId = widget.courseId;
    final AsyncValue<MoodleCourseDetail> detail = ref.watch(
      moodleCourseDetailProvider(courseId),
    );

    return DefaultTabController(
      length: 3,
      child: ScreenScaffold(
        title: switch (detail.value?.course) {
          final MoodleCourse c => moodleCourseName(l10n, c.id, c.fullName),
          null => l10n.moodleTitle,
        },
        actions: <Widget>[
          IconButton(
            tooltip: l10n.moodleRefresh,
            onPressed: _refreshState.refreshing ? null : _refresh,
            icon: _refreshState.refreshing
                ? Semantics(
                    liveRegion: true,
                    label: l10n.moodleRefreshing,
                    child: const SizedBox(
                      height: AppSizes.icon,
                      width: AppSizes.icon,
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.xs),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : const Icon(AppIcons.refresh),
          ),
        ],
        // Scrollable, so all three labels stay whole. Three equal thirds of a
        // 320 px phone cannot hold "Ankündigungen" at a large text size, and an
        // abbreviation nobody can decode is worse than a swipe.
        controls: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: <Widget>[
            Tab(text: l10n.moodleTabContents),
            Tab(text: l10n.moodleTabAssignments),
            Tab(text: l10n.moodleTabAnnouncements),
          ],
        ),
        body: detail.when(
          loading: () => const LoadingView(),
          error: (Object error, _) => EmptyView(
            icon: AppIcons.error_outline,
            message: moodleFailureMessage(l10n, error),
            action: FilledButton.icon(
              onPressed: _refreshState.refreshing ? null : _refresh,
              icon: const Icon(AppIcons.refresh),
              label: Text(l10n.moodleRefresh),
            ),
          ),
          data: (MoodleCourseDetail d) => Column(
            children: <Widget>[
              // The overview says how old its data is; this page did not,
              // although it is the page carrying submission states and
              // deadlines — where a stale reading actually costs something.
              if (d.fetchedAt != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    0,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n.moodleLastUpdated(
                        AppDateFormats.dateTime(d.fetchedAt!, locale),
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              // A failed refresh over a bundle that is still good must be
              // visible: submission states here carry deadlines, and content
              // weeks old looks exactly like content from a minute ago.
              if (_refreshState.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    0,
                  ),
                  child: StatusBanner(
                    tone: StatusTone.warning,
                    icon: AppIcons.sync_problem,
                    title: l10n.moodleRefreshFailed,
                    message: moodleFailureMessage(l10n, _refreshState.error),
                    action: TextButton(
                      onPressed: _refreshState.refreshing ? null : _refresh,
                      child: Text(l10n.moodleRefresh),
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    _ContentsTab(detail: d),
                    _AssignmentsTab(detail: d, locale: locale),
                    _AnnouncementsTab(detail: d, locale: locale),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContentsTab extends StatelessWidget {
  const _ContentsTab({required this.detail});

  final MoodleCourseDetail detail;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<MoodleSection> sections = detail.sections
        .where((MoodleSection s) => s.visible)
        .toList();
    final List<MoodleSection> nonEmptySections = <MoodleSection>[
      for (final MoodleSection section in sections)
        if (section.modules.isNotEmpty) section,
    ];
    if (nonEmptySections.isEmpty) {
      return _EmptyTab(message: l10n.moodleNoSections);
    }
    // Each section renders as a header row, one row per module, then a
    // trailing divider — flattened up front (cheap: just closures, no
    // widgets built yet) so ListView.builder can construct rows lazily as
    // they scroll into view, matching the previous eager Column layout
    // pixel-for-pixel.
    final List<WidgetBuilder> rows = <WidgetBuilder>[
      for (final MoodleSection section in nonEmptySections) ...<WidgetBuilder>[
        (BuildContext _) => _SectionHeader(section: section),
        for (final MoodleModule module in section.modules)
          (BuildContext _) => _ModuleTile(module: module),
        (BuildContext _) => const Divider(height: 1),
      ],
    ];
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: rows.length,
      itemBuilder: (BuildContext ctx, int index) => rows[index](ctx),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final MoodleSection section;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        section.name.isEmpty ? '—' : section.name,
        style: text.titleMedium,
      ),
    );
  }
}

class _ModuleTile extends ConsumerWidget {
  const _ModuleTile({required this.module});

  final MoodleModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;

    if (!module.visible) {
      return ListTile(
        leading: const Icon(AppIcons.lock_outline),
        title: Text(module.name),
        subtitle: Text(
          module.availabilityInfo ?? l10n.moodleHiddenModule,
          style: text.bodySmall,
        ),
        enabled: false,
      );
    }

    // A file-bearing module: one tile per file.
    if (module.files.isNotEmpty) {
      return Column(
        children: <Widget>[
          for (final MoodleFile file in module.files)
            _FileTile(module: module, file: file),
        ],
      );
    }

    // An external link module: opened WITHOUT any token.
    if (module.type == MoodleModuleType.url && module.url != null) {
      return ListTile(
        leading: const Icon(AppIcons.link_outlined),
        title: Text(module.name),
        subtitle: Text(l10n.moodleExternalLinkNotice, style: text.bodySmall),
        trailing: const Icon(AppIcons.open_in_new),
        onTap: () => _openExternal(context, ref, module.url!),
      );
    }

    // A description-only module (label/page snippet).
    return ListTile(
      leading: Icon(_iconFor(module.type)),
      title: Text(module.name),
      subtitle: module.description.isEmpty
          ? null
          : Text(module.description, style: text.bodySmall),
    );
  }

  static IconData _iconFor(MoodleModuleType type) => switch (type) {
    MoodleModuleType.forum => AppIcons.forum_outlined,
    MoodleModuleType.quiz => AppIcons.quiz_outlined,
    MoodleModuleType.assign => AppIcons.assignment_outlined,
    MoodleModuleType.folder => AppIcons.folder_outlined,
    MoodleModuleType.page => AppIcons.article_outlined,
    MoodleModuleType.label => AppIcons.label_outline,
    _ => AppIcons.circle_outlined,
  };

  Future<void> _openExternal(
    BuildContext context,
    WidgetRef ref,
    String url,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final LinkLaunchResult result = await ref
        .read(linkLauncherProvider)
        .open(url);
    if (result != LinkLaunchResult.opened) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.moodleOpenLinkFailed)),
      );
    }
  }
}

/// A single downloadable file. Downloads on tap (never preloaded); a cancel is
/// fired if the tile leaves the tree mid-download so no partial data is kept.
class _FileTile extends ConsumerStatefulWidget {
  const _FileTile({required this.module, required this.file});

  final MoodleModule module;
  final MoodleFile file;

  @override
  ConsumerState<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends ConsumerState<_FileTile> {
  bool _downloading = false;

  /// Fraction complete, or null while the server withholds a content length.
  double? _progress;

  MoodleDownloadCancelHandle? _cancel;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  void _cancelDownload() => _cancel?.cancel();

  Future<void> _open() async {
    if (_downloading) return;
    final AppLocalizations l10n = context.l10n;
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final MoodleRepository repo = ref.read(moodleRepositoryProvider);

    final MoodleDownloadCancelHandle cancel = MoodleDownloadCancelHandle();
    setState(() {
      _downloading = true;
      _progress = null;
      _cancel = cancel;
    });
    try {
      final AppDocument doc = await repo.downloadFile(
        widget.file,
        // The downloader reported progress all along; the tile simply never
        // asked for it, so a 25 MB file spun an indeterminate dot for minutes.
        onProgress: (double? value) {
          if (mounted && !cancel.token.isCancelled) {
            setState(() => _progress = value);
          }
        },
        cancel: cancel.token,
      );
      if (!mounted || cancel.token.isCancelled) return;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => DocumentViewerScreen(document: doc),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(moodleFailureMessage(l10n, error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _progress = null;
          _cancel = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final int? size = widget.file.fileSize;
    final String subtitle = <String>[
      if (widget.file.mimeType != null) widget.file.mimeType!,
      if (size != null)
        humanFileSize(
          size,
          locale: Localizations.localeOf(context).languageCode,
        ),
    ].join(' · ');

    final double? progress = _progress;
    final String status = !_downloading
        ? subtitle
        : progress == null
        ? l10n.moodleFileDownloading
        : l10n.moodleDownloadProgress('${(progress * 100).round()}');

    return ListTile(
      leading: _downloading
          ? SizedBox(
              height: AppSizes.icon,
              width: AppSizes.icon,
              child: CircularProgressIndicator(strokeWidth: 2, value: progress),
            )
          // Decorative: the tile's own title and subtitle already say what
          // this row is and what state it is in.
          : const ExcludeSemantics(
              child: Icon(AppIcons.insert_drive_file_outlined),
            ),
      title: Text(widget.file.fileName),
      // A live region, because the only thing that changed while a download
      // ran was this line — silently, as far as a screen reader was concerned.
      subtitle: Semantics(
        liveRegion: _downloading,
        child: Text(status, style: text.bodySmall),
      ),
      // Leaving the screen already cancels; an explicit stop means a download
      // can be abandoned without abandoning the course page with it.
      trailing: _downloading
          ? IconButton(
              onPressed: _cancelDownload,
              tooltip: l10n.moodleDownloadCancel,
              icon: const Icon(AppIcons.close),
            )
          : const ExcludeSemantics(child: Icon(AppIcons.download_outlined)),
      onTap: _downloading ? null : _open,
    );
  }
}

/// Small owner of a [MoodleDownloadCancel] so the tile can cancel on dispose.
class MoodleDownloadCancelHandle {
  final MoodleDownloadCancel token = MoodleDownloadCancel();
  void cancel() => token.cancel();
}

class _AssignmentsTab extends StatelessWidget {
  const _AssignmentsTab({required this.detail, required this.locale});

  final MoodleCourseDetail detail;
  final String locale;

  // `_AssignmentsTab` is a new instance on every rebuild, but `detail`
  // frequently keeps the same `assignments` list instance (tab switches,
  // theme changes, ...) — keying the sorted result on that identity avoids
  // re-sorting on every one of those rebuilds.
  static final Expando<List<MoodleAssignment>> _sortedCache =
      Expando<List<MoodleAssignment>>();

  List<MoodleAssignment> _sortedAssignments() {
    final List<MoodleAssignment> assignments = detail.assignments;
    final List<MoodleAssignment>? cached = _sortedCache[assignments];
    if (cached != null) return cached;
    final List<MoodleAssignment> sorted = List<MoodleAssignment>.of(assignments)
      ..sort((MoodleAssignment a, MoodleAssignment b) {
        final DateTime? da = a.dueDate;
        final DateTime? db = b.dueDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    _sortedCache[assignments] = sorted;
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    if (detail.assignments.isEmpty) {
      return _EmptyTab(message: l10n.moodleNoAssignments);
    }
    final List<MoodleAssignment> items = _sortedAssignments();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) =>
          _AssignmentTile(assignment: items[index], locale: locale),
    );
  }
}

class _AssignmentTile extends StatelessWidget {
  const _AssignmentTile({required this.assignment, required this.locale});

  final MoodleAssignment assignment;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final String due = assignment.dueDate == null
        ? l10n.moodleAssignmentNoDue
        : l10n.moodleAssignmentDue(
            AppDateFormats.dateTime(assignment.dueDate!, locale),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(assignment.name, style: text.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(due, style: text.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          _SubmissionChips(
            status: assignment.status,
            dueDate: assignment.dueDate,
          ),
          const Divider(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _SubmissionChips extends StatelessWidget {
  const _SubmissionChips({required this.status, required this.dueDate});

  final MoodleSubmissionStatus? status;

  /// Needed for the overdue chip: "late" only ever described a submission
  /// that arrived after the deadline, so an assignment whose deadline simply
  /// passed with nothing handed in carried no marker at all.
  final DateTime? dueDate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final MoodleSubmissionStatus s = status ?? const MoodleSubmissionStatus();
    final String stateLabel = switch (s.state) {
      MoodleSubmissionState.submitted => l10n.moodleSubmissionSubmitted,
      MoodleSubmissionState.draft => l10n.moodleSubmissionDraft,
      MoodleSubmissionState.none => l10n.moodleSubmissionNone,
      MoodleSubmissionState.unknown => l10n.moodleSubmissionUnknown,
    };
    final IconData stateIcon = switch (s.state) {
      MoodleSubmissionState.submitted => AppIcons.check_circle_outline,
      MoodleSubmissionState.draft => AppIcons.edit_note_outlined,
      MoodleSubmissionState.none => AppIcons.radio_button_unchecked,
      MoodleSubmissionState.unknown => AppIcons.help_outline,
    };
    // A deadline that has passed with nothing submitted. It used to look
    // exactly like a far-off future assignment: a neutral "no submission" and
    // an absolute date the reader had to compare against today themselves.
    // `unknown` is excluded on purpose — a status we could not read is not
    // evidence that nothing was handed in.
    final DateTime? due = dueDate;
    final bool overdue =
        due != null &&
        due.isBefore(DateTime.now()) &&
        (s.state == MoodleSubmissionState.none ||
            s.state == MoodleSubmissionState.draft);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        // State is conveyed with icon + text, never colour alone.
        Chip(
          avatar: Icon(stateIcon, size: AppSizes.iconSmall),
          label: Text(stateLabel),
          visualDensity: VisualDensity.compact,
        ),
        if (overdue)
          Chip(
            avatar: const Icon(
              AppIcons.event_busy_outlined,
              size: AppSizes.iconSmall,
            ),
            label: Text(l10n.moodleOverdue),
            visualDensity: VisualDensity.compact,
          ),
        if (s.isLate)
          Chip(
            avatar: const Icon(
              AppIcons.warning_amber_outlined,
              size: AppSizes.iconSmall,
            ),
            label: Text(l10n.moodleSubmissionLate),
            visualDensity: VisualDensity.compact,
          ),
        if (s.graded && s.gradeText != null)
          Chip(
            avatar: const Icon(
              AppIcons.grade_outlined,
              size: AppSizes.iconSmall,
            ),
            label: Text(l10n.moodleSubmissionGraded(s.gradeText!)),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _AnnouncementsTab extends StatelessWidget {
  const _AnnouncementsTab({required this.detail, required this.locale});

  final MoodleCourseDetail detail;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    if (detail.announcements.isEmpty) {
      return _EmptyTab(message: l10n.moodleNoAnnouncements);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: detail.announcements.length,
      itemBuilder: (BuildContext context, int index) => _AnnouncementTile(
        announcement: detail.announcements[index],
        locale: locale,
      ),
    );
  }
}

class _AnnouncementTile extends ConsumerWidget {
  const _AnnouncementTile({required this.announcement, required this.locale});

  final MoodleAnnouncement announcement;
  final String locale;

  Future<void> _open(BuildContext context, WidgetRef ref, String url) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final LinkLaunchResult result = await ref
        .read(linkLauncherProvider)
        .open(url);
    if (result != LinkLaunchResult.opened) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.moodleOpenLinkFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final String? author = announcement.authorName?.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(announcement.subject, style: text.titleSmall),
          // The author was parsed all along and never shown. On a course
          // announcement it is often the fastest way to judge how much the
          // message matters.
          if (author != null && author.isNotEmpty)
            Text(l10n.moodleAnnouncementAuthor(author), style: text.bodySmall),
          if (announcement.createdAt != null)
            Text(
              AppDateFormats.dateTime(announcement.createdAt!, locale),
              style: text.bodySmall,
            ),
          const SizedBox(height: AppSpacing.xs),
          if (announcement.message.isNotEmpty)
            Text(announcement.message, style: text.bodyMedium),
          // "Details here: link" used to lose the destination entirely. The
          // links are listed at the end rather than rendered inline, so the
          // message itself stays plain text — no markup, no WebView.
          if (announcement.links.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.moodleAnnouncementLinks,
              style: text.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            for (final String link in announcement.links)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _open(context, ref, link),
                  icon: const Icon(AppIcons.open_in_new),
                  // The label IS the URL: the same anti-phishing rule the
                  // mail client follows — a reader can see where a tap goes.
                  label: Text(link),
                ),
              ),
          ],
          const Divider(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
