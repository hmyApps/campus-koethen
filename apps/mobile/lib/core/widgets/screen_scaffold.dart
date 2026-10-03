// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_metrics.dart';
import 'section_header.dart';

/// The masthead every screen opens with.
///
/// Three lines and a rule, always in the same order:
///
/// ```
/// ‹  CAMPUS                                     ← where you are
///    Mensa                          [actions]   ← what this is
/// ══════════════════════════════════════        ← the Taktstrich
/// ```
///
/// One line of controls, and it is the line the title is already on. The
/// masthead spends no row on glyphs alone — a strip holding nothing but a
/// back arrow and two icons in the corner is exactly the waste this header
/// was built to stop. The title is set in the display face and is nearly as
/// tall as a touch target, so the controls cost almost no height beside it.
///
/// The price is that the title and its eyebrow are indented past the back
/// glyph and no longer line up with the content below. That is a deliberate
/// trade: the rule still runs the full width of the content column, and it is
/// the rule — not the title — that carries the alignment of the screen.
///
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.eyebrow,
    this.actions,
    this.showBack,
    this.backEnabled = true,
    this.singleLineTitle = false,
    this.rule = true,
    super.key,
  });

  /// What this screen is. Set in the display face.
  final String title;

  /// Where you are — usually the module's category. Optional, because a screen
  /// reached from one place only has nothing to disambiguate.
  final String? eyebrow;

  /// Screen-level actions. Icon buttons, never more than three.
  final List<Widget>? actions;

  /// Whether to offer a way back. Defaults to "whenever there is one".
  final bool? showBack;
  final bool backEnabled;

  /// Keep names that must not break within a word on one ellipsized line.
  final bool singleLineTitle;

  /// Whether the header closes with the bar line. Off where the screen puts
  /// its own controls directly underneath and draws the rule itself.
  final bool rule;

  @override
  Widget build(BuildContext context) {
    final AppMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;
    final bool canPop = ModalRoute.of(context)?.canPop ?? false;
    final bool back = showBack ?? canPop;
    final List<Widget> trailing = actions ?? const <Widget>[];
    // The controls share the title line while they fit. Once the reader
    // scales text up, the title needs the full column for a single word and
    // they step above it instead — legibility outranks the saved height.
    final bool inlineControls = _controlsFitBesideTitle(context);
    final bool stacked = (back || trailing.isNotEmpty) && !inlineControls;

    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (eyebrow != null) ...<Widget>[
          Eyebrow(eyebrow!, color: context.colors.primary),
          const SizedBox(height: AppSpacing.xs),
        ],
        Semantics(
          header: true,
          child: singleLineTitle
              ? Tooltip(
                  message: title,
                  excludeFromSemantics: true,
                  child: Text(
                    title,
                    style: _titleStyle(context, text),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : Text(
                  title,
                  style: _titleStyle(context, text),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.screenPadding,
        AppSpacing.lg,
        metrics.screenPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Only reached at large text sizes, where the controls cannot share
          // the title line. Everywhere else this row does not exist at all.
          if (stacked)
            Row(
              children: <Widget>[
                if (back)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _BackButton(enabled: backEnabled),
                  ),
                const Spacer(),
                ...trailing,
              ],
            ),
          Row(
            children: <Widget>[
              if (!stacked && back)
                // Pulled to the edge: an icon button carries 12 dp of its own
                // padding, and without this the glyph would sit further in
                // than the rule beneath it.
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _BackButton(enabled: backEnabled),
                ),
              Expanded(child: heading),
              if (!stacked && trailing.isNotEmpty) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                ...trailing,
              ],
            ],
          ),
          if (rule) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Container(height: AppSizes.rule, color: context.colors.rule),
          ],
        ],
      ),
    );
  }
}

/// The size the title is set in, given how large the reader has set their text.
///
/// The display size steps down as the text scale goes up. This is **not** a cap
/// on the reader's setting — every step is still fully scaled, and the title
/// stays comfortably larger than the body copy around it. It is a cap on the
/// *design*: a 29-point display face at a doubled text size is 58 points of
/// masthead before the screen has said anything, which on a 360 dp phone is a
/// third of the viewport spent on a word the reader already knows.
///
/// Two steps rather than a continuous curve, so the header has two shapes a
/// reader can get used to instead of a different one at every setting.
TextStyle? _titleStyle(BuildContext context, TextTheme text) {
  final double scale = MediaQuery.textScalerOf(context).scale(100) / 100;
  if (scale >= 1.8) return text.headlineMedium;
  if (scale >= 1.35) return text.headlineLarge;
  return text.displaySmall;
}

/// Whether the controls can sit beside the title at the reader's text size.
///
/// The same 1.35 step at which the title gives up the display face: past it
/// the title needs two lines for a single word, and a back glyph plus a row of
/// icons would take the width it needs to set them. Below it the title is one
/// short line in a large face, with room to spare.
bool _controlsFitBesideTitle(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(100) / 100 < 1.35;

/// The back control, in the app's own shape rather than the platform's.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? () => Navigator.of(context).maybePop() : null,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: const Icon(AppIcons.arrow_back),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: AppSizes.minTouchTarget,
        minHeight: AppSizes.minTouchTarget,
      ),
      alignment: AlignmentDirectional.centerStart,
    );
  }
}

/// A screen: the masthead, optional controls pinned under it, and the content.
///
/// The alternative — every screen assembling its own `Scaffold`, `SafeArea` and
/// title row — is what let fifteen screens drift into fifteen slightly
/// different headers. Screens that need the masthead to scroll away with the
/// content do not use this: they take a plain `Scaffold` and put a
/// [ScreenHeader] into their own scroll view as the first item.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    required this.title,
    required this.body,
    this.eyebrow,
    this.actions,
    this.showBack,
    this.backEnabled = true,
    this.singleLineTitle = false,
    this.controls,
    this.floatingActionButton,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final List<Widget>? actions;
  final bool? showBack;
  final bool backEnabled;
  final bool singleLineTitle;

  /// Controls that stay put while the body scrolls — a view switcher, a day
  /// navigator. They sit **below** the bar line, so the rule keeps meaning
  /// "the masthead ends here".
  final Widget? controls;

  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: floatingActionButton,
      // A big Android keyboard shrinking the whole Scaffold can squeeze the
      // masthead below its own minimum height and overflow it — most visibly
      // at large text scale, where the masthead is tallest. The keyboard
      // inset is applied to the body below instead, where it only ever
      // takes space away from something that can scroll.
      resizeToAvoidBottomInset: false,
      // The bottom inset belongs to the navigation bar, which the shell draws.
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ScreenHeader(
              title: title,
              eyebrow: eyebrow,
              actions: actions,
              showBack: showBack,
              backEnabled: backEnabled,
              singleLineTitle: singleLineTitle,
            ),
            ?controls,
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
