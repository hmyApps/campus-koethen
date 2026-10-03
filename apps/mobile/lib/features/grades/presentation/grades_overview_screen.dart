// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/links/safe_link_launcher.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../../settings/domain/direct_service.dart';
import '../../university_account/application/university_service_connector.dart';
import '../application/grade_account_controller.dart';
import '../application/grades_controller.dart';
import '../application/grades_providers.dart';
import '../domain/grade.dart';
import '../domain/grade_portal.dart';
import '../domain/grade_projection.dart';
import '../domain/grades_display.dart';
import '../domain/grade_failure.dart';
import 'grade_detail_sheet.dart';
import 'grade_messages.dart';
import 'grade_tile.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../app/app_modules.dart';

/// Shows the cached Notenspiegel with a "last updated" line, a manual refresh,
/// and — on a failed refresh — a banner while keeping the last good data visible.
class GradesOverviewScreen extends ConsumerStatefulWidget {
  const GradesOverviewScreen({super.key});

  @override
  ConsumerState<GradesOverviewScreen> createState() =>
      _GradesOverviewScreenState();
}

class _GradesOverviewScreenState extends ConsumerState<GradesOverviewScreen> {
  @override
  void initState() {
    super.initState();
    // Lazy automatic sync on open (respects the 24-hour gate internally).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(gradesControllerProvider.notifier).maybeAutoSync(),
    );
  }

  Future<void> _confirmDelete() async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.gradesDeleteConfirmTitle),
        content: Text(l10n.gradesDeleteConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.gradesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.gradesDeleteConfirm),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    {
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      try {
        await ref
            .read(universityServiceConnectorProvider)
            .disconnect(DirectService.grades);
      } catch (_) {
        // A wipe that left the encrypted grades and their key on the device
        // must say so. Reporting "signed out" over a failed delete is the one
        // lie this screen is not allowed to tell.
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.gradesDeleteIncomplete)),
        );
      }
    }
  }

  String _hostOf(GradePortal portal) => portal == GradePortal.hisInOne
      ? ref.read(hisInOneProfileProvider).host
      : ref.read(legacyQisProfileProvider).host;

  /// Opens the portal this account actually uses.
  ///
  /// The setup screen cannot know which one that is — the portal is detected
  /// during sign-in — but here it is settled, so the link goes to the right
  /// host instead of always to the legacy QIS entry page.
  Future<void> _openPortal(GradePortal portal) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String url = portal == GradePortal.hisInOne
        ? ref.read(hisInOneProfileProvider).portalUrl
        : ref.read(legacyQisProfileProvider).portalUrl;
    final LinkLaunchResult result = await ref
        .read(linkLauncherProvider)
        .open(url);
    if (result != LinkLaunchResult.opened) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorLinkNotOpened)));
    }
  }

  Future<void> _switchPortal(GradePortal current) async {
    final AppLocalizations l10n = context.l10n;
    final GradePortal other = current == GradePortal.hisInOne
        ? GradePortal.hisQisLegacy
        : GradePortal.hisInOne;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.gradesSwitchPortalTitle),
        content: Text(l10n.gradesSwitchPortalBody(_hostOf(other))),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.gradesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.gradesSwitchPortalConfirm),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    {
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      try {
        await ref
            .read(gradeAccountControllerProvider.notifier)
            .switchPortal(other);
      } catch (_) {
        // The switch is abandoned rather than half-applied: leaving the old
        // portal's report in place under the new portal's header is worse
        // than staying where we were.
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.gradesPortalSwitchFailed)),
        );
        return;
      }
      if (!mounted) return;
      await ref.read(gradesControllerProvider.notifier).refresh();
    }
  }

  /// Asks for the current password and replaces the stored one.
  ///
  /// The recovery from a routine password change. Deliberately keeps the local
  /// report: nothing about a new password makes the grades already on this
  /// device wrong.
  Future<void> _reauthenticate() async {
    final AppLocalizations l10n = context.l10n;
    final String? password = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _ReauthenticateDialog(),
    );
    if (password == null || !mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(gradeAccountControllerProvider.notifier)
          .reauthenticate(password: password);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(gradeFailureMessage(l10n, error))),
      );
      return;
    }
    if (!mounted) return;
    await ref.read(gradesControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final GradesViewState view =
        ref.watch(gradesControllerProvider).value ?? const GradesViewState();
    final GradePortal? activePortal = ref
        .watch(gradeAccountControllerProvider)
        .value
        ?.activePortal;

    return ScreenScaffold(
      eyebrow: ModuleCategory.study.label(l10n),
      title: l10n.gradesTitle,
      actions: <Widget>[
        IconButton(
          onPressed: view.isSyncing
              ? null
              : () => ref.read(gradesControllerProvider.notifier).refresh(),
          tooltip: l10n.gradesRefresh,
          // With a report already on screen the only sign of a running sync
          // was this spinner — a picture, and therefore silence for a screen
          // reader. The live region says the same thing in words.
          icon: view.isSyncing
              ? Semantics(
                  liveRegion: true,
                  label: l10n.gradesSyncingSemantic,
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
        PopupMenuButton<String>(
          onSelected: (String value) {
            if (value == 'delete') _confirmDelete();
            if (value == 'switchPortal' && activePortal != null) {
              _switchPortal(activePortal);
            }
            if (value == 'openPortal' && activePortal != null) {
              _openPortal(activePortal);
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            if (activePortal != null)
              PopupMenuItem<String>(
                value: 'openPortal',
                child: Text(l10n.gradesOpenPortalLink),
              ),
            if (activePortal != null)
              PopupMenuItem<String>(
                value: 'switchPortal',
                child: Text(l10n.gradesSwitchPortalAction),
              ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Text(l10n.gradesDeleteAction),
            ),
          ],
        ),
      ],
      body: _body(context, l10n, locale, view, activePortal),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    String locale,
    GradesViewState view,
    GradePortal? activePortal,
  ) {
    if (view.report == null) {
      if (view.isSyncing) {
        return Semantics(
          liveRegion: true,
          label: l10n.gradesSyncing,
          child: const LoadingView(),
        );
      }
      final GradeFailure? error = view.error;
      if (error != null) {
        final bool invalid = error.kind == GradeFailureKind.invalidCredentials;
        return EmptyView(
          icon: AppIcons.error_outline,
          message: gradeFailureMessage(l10n, error),
          // A rejected password is answered by entering the new one, not by
          // deleting the account. There is no cached report to protect here,
          // but the wording and the route stay the same as in the banner.
          action: FilledButton.icon(
            onPressed: invalid
                ? _reauthenticate
                : () => ref.read(gradesControllerProvider.notifier).refresh(),
            icon: Icon(invalid ? AppIcons.login : AppIcons.refresh),
            label: Text(invalid ? l10n.gradesReauthenticate : l10n.gradesRetry),
          ),
        );
      }
      return EmptyView(title: l10n.gradesTitle, message: l10n.gradesEmpty);
    }

    // HIS-QIS mixes an average and an administrative row into the same table.
    // The projection separates them; the encrypted cache keeps the raw report.
    //
    // Derived once per report rather than once per build: classifying every row
    // normalises and matches its title, and the ordering sorts them — work that
    // a sync spinner tick or a theme change used to pay for again although the
    // report behind it had not moved.
    final GradesDisplay display = gradesForDisplay(view.report!);
    final GradeProjection projection = display.projection;
    final List<GradeEntry> entries = display.entries;
    final String? activeHost = activePortal == null
        ? null
        : _hostOf(activePortal);
    // A Studienverlauf is far more than one screen of rows, so the list is
    // described first and each row built as it scrolls into view. Building
    // every tile up front cost a full report's worth of work on every
    // rebuild — the same reason the calendar's list view and the Moodle
    // course tabs stopped doing it.
    final List<_GradesRow> rows = _gradesRows(
      leading: <Widget>[
        _Header(view: view, locale: locale, activeHost: activeHost),
        if (projection.hasAverage) _AverageTile(average: projection.average!),
        if (view.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: StatusBanner(
              tone: StatusTone.warning,
              icon: AppIcons.sync_problem,
              title: l10n.gradesUpdateFailed,
              message: gradeFailureMessage(l10n, view.error),
              // Only for a rejected password: the way out of a password
              // change used to be an action called "delete credentials and
              // local grades", which sounds like losing the Notenspiegel.
              action: view.error?.kind == GradeFailureKind.invalidCredentials
                  ? TextButton(
                      onPressed: _reauthenticate,
                      child: Text(l10n.gradesReauthenticate),
                    )
                  : null,
            ),
          ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(l10n.gradesEmpty),
          ),
      ],
      entries: entries,
    );

    return RefreshIndicator(
      onRefresh: () => ref.read(gradesControllerProvider.notifier).refresh(),
      child: ListView.builder(
        // A student with one or two entries has a list shorter than the
        // viewport, and Android's clamping physics simply will not drag it —
        // so the refresh gesture never fired at all. iOS bounces, which is
        // why this only ever showed up on one platform.
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.length,
        itemBuilder: (BuildContext context, int index) => switch (rows[index]) {
          _StaticRow(:final Widget child) => child,
          _ModuleHeadingRow(:final String title) => Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          _EntryRow(:final GradeEntry entry) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              GradeTile(
                entry: entry,
                onTap: () => showGradeDetailSheet(context, entry),
              ),
              const Divider(height: 1),
            ],
          ),
        },
      ),
    );
  }
}

/// One row of the grades list, described rather than built.
///
/// Deciding what the list contains stays a single pass over the ordered
/// entries; turning a row into widgets happens only for the rows on screen.
sealed class _GradesRow {
  const _GradesRow();
}

/// A row that is already a widget — the masthead, the average, the error
/// banner, the empty note. There are at most a handful.
class _StaticRow extends _GradesRow {
  const _StaticRow(this.child);

  final Widget child;
}

class _ModuleHeadingRow extends _GradesRow {
  const _ModuleHeadingRow(this.title);

  final String title;
}

class _EntryRow extends _GradesRow {
  const _EntryRow(this.entry);

  final GradeEntry entry;
}

/// Describes the whole list: the leading widgets, then each module's heading
/// and its leaf exam rows.
///
/// A report without a tree (legacy HIS-QIS, `module` is always null) produces
/// no headings at all and stays the flat, date-sorted list.
List<_GradesRow> _gradesRows({
  required List<Widget> leading,
  required List<GradeEntry> entries,
}) {
  final List<_GradesRow> rows = <_GradesRow>[
    for (final Widget widget in leading) _StaticRow(widget),
  ];
  String? lastModule = _unsetModule;
  for (final GradeEntry entry in entries) {
    if (entry.module != lastModule) {
      lastModule = entry.module;
      if (lastModule != null && lastModule.isNotEmpty) {
        rows.add(_ModuleHeadingRow(lastModule));
      }
    }
    rows.add(_EntryRow(entry));
  }
  return rows;
}

/// A sentinel distinct from both `null` and `''`, so the very first section
/// header is always emitted even when the first entry's module is `null`.
const String _unsetModule = '\u0000';

class _Header extends StatelessWidget {
  const _Header({required this.view, required this.locale, this.activeHost});

  final GradesViewState view;
  final String locale;

  /// The active portal's host, shown as a factual, visible indicator of which
  /// exam portal this account is connected to (`null` while unknown).
  final String? activeHost;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String when = view.lastSuccessfulSync == null
        ? l10n.gradesNeverSynced
        : l10n.gradesLastUpdated(
            AppDateFormats.dateTime(view.lastSuccessfulSync!, locale),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            child: Text(when, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (activeHost != null)
            Text(
              l10n.gradesActivePortal(activeHost!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// The average, as HIS-QIS itself keeps it in the credit account.
///
/// Labelled "Durchschnitt" rather than "Credit-Sammelkonto": that is what the
/// number means to a student. The value is taken over unchanged — the app never
/// computes an average of its own, which would disagree with the official
/// transcript.
class _AverageTile extends StatelessWidget {
  const _AverageTile({required this.average});

  final Grade average;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final String value = gradeText(l10n, locale, average);

    return Semantics(
      label: '${l10n.gradesAverageLabel}: $value',
      excludeSemantics: true,
      child: ListTile(
        leading: const Icon(AppIcons.functions),
        title: Text(l10n.gradesAverageLabel),
        trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

/// Asks for the current portal password.
///
/// Its own dialog rather than a route: the whole point of this flow is that it
/// changes one field and leaves everything else — the cached report, the
/// portal choice, the encryption key — exactly as it was.
class _ReauthenticateDialog extends StatefulWidget {
  const _ReauthenticateDialog();

  @override
  State<_ReauthenticateDialog> createState() => _ReauthenticateDialogState();
}

class _ReauthenticateDialogState extends State<_ReauthenticateDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isEmpty) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.gradesReauthenticateTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.gradesReauthenticateBody),
          const SizedBox(height: AppSpacing.md),
          AutofillGroup(
            child: TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const <String>[AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.gradeSetupPasswordLabel,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  tooltip: _obscure
                      ? l10n.gradesShowPassword
                      : l10n.gradesHidePassword,
                  icon: Icon(
                    _obscure
                        ? AppIcons.visibility_outlined
                        : AppIcons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.gradesCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.gradesReauthenticate),
        ),
      ],
    );
  }
}
