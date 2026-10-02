// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/sheet_body.dart';
import '../../../l10n/l10n.dart';
import '../application/canteen_balance_providers.dart';
import '../domain/canteen_balance_apdu.dart';
import '../domain/canteen_balance_reader.dart';

Future<void> showCanteenBalanceSheet(
  BuildContext context, {
  CanteenBalanceReadOrigin origin = CanteenBalanceReadOrigin.manual,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (BuildContext _) => CanteenBalanceSheet(origin: origin),
);

enum _BalanceSheetState {
  checking,
  reading,
  success,
  failure,
  notSupported,
  disabled,
}

/// Transient balance UX. The result lives only in this widget and disappears
/// when the sheet is dismissed; it is never written to a provider or store.
class CanteenBalanceSheet extends ConsumerStatefulWidget {
  const CanteenBalanceSheet({required this.origin, super.key});

  final CanteenBalanceReadOrigin origin;

  @override
  ConsumerState<CanteenBalanceSheet> createState() =>
      _CanteenBalanceSheetState();
}

class _CanteenBalanceSheetState extends ConsumerState<CanteenBalanceSheet> {
  _BalanceSheetState _state = _BalanceSheetState.checking;
  CanteenBalance? _balance;
  CanteenBalanceFailure? _failure;
  late final CanteenBalanceReader _reader;
  bool _cancelRequested = false;

  /// What the CURRENT/next [_read] attempt uses — starts at
  /// [CanteenBalanceSheet.origin] but is pinned to
  /// [CanteenBalanceReadOrigin.manual] the moment an attempt fails. The
  /// system tag-dispatch "no second tap" origin consumes a one-shot `Tag`
  /// object the OS handed over at open time: if that tag was already out of
  /// range (the realistic case — a one-handed tap-then-open gesture removes
  /// the card before the app even starts), native code can only fail with
  /// `no_pending_tag`, and a retry that asked for the pending tag again
  /// would fail the exact same way without ever starting a real scan.
  /// Falling back to manual reader mode gives "Erneut versuchen" an actual
  /// chance to read a card the reader is waiting for.
  CanteenBalanceReadOrigin _attemptOrigin = CanteenBalanceReadOrigin.manual;

  @override
  void initState() {
    super.initState();
    _reader = ref.read(canteenBalanceReaderProvider);
    _attemptOrigin = widget.origin;
    if (widget.origin == CanteenBalanceReadOrigin.externalTag) {
      _state = _BalanceSheetState.reading;
      WidgetsBinding.instance.addPostFrameCallback((_) => _read());
    } else {
      _checkAvailability();
    }
  }

  @override
  void dispose() {
    if (_state == _BalanceSheetState.reading && !_cancelRequested) {
      unawaited(_cancelSilently());
    }
    super.dispose();
  }

  /// Checks availability, then starts reading immediately when NFC is on —
  /// no separate "Start" tap. The explanation stays on screen throughout
  /// (see `_status`'s `reading` branch), so leaving out that extra step
  /// loses no information, only a tap the external-tag entry point never
  /// asked for either.
  Future<void> _checkAvailability() async {
    final CanteenBalanceAvailability availability;
    try {
      availability = await _reader.availability();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _BalanceSheetState.failure;
        _failure = CanteenBalanceFailure.unknown;
      });
      return;
    }
    if (!mounted) return;
    if (availability == CanteenBalanceAvailability.available) {
      setState(() => _state = _BalanceSheetState.reading);
      unawaited(_read());
      return;
    }
    setState(() {
      _state = availability == CanteenBalanceAvailability.disabled
          ? _BalanceSheetState.disabled
          : _BalanceSheetState.notSupported;
    });
  }

  Future<void> _read() async {
    if (_state != _BalanceSheetState.reading) {
      setState(() {
        _state = _BalanceSheetState.reading;
        _balance = null;
        _failure = null;
      });
    }
    try {
      final CanteenBalance balance = await _reader.read(
        origin: _attemptOrigin,
        prompt: context.l10n.canteenBalanceScanPrompt,
      );
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _state = _BalanceSheetState.success;
      });
    } on CanteenBalanceReadException catch (error) {
      if (!mounted) return;
      // Any retry from here on waits for an actively presented card instead
      // of a one-shot pending tag that is, by now, almost certainly gone.
      _attemptOrigin = CanteenBalanceReadOrigin.manual;
      setState(() {
        _failure = error.reason;
        _state = switch (error.reason) {
          CanteenBalanceFailure.notSupported => _BalanceSheetState.notSupported,
          CanteenBalanceFailure.disabled => _BalanceSheetState.disabled,
          _ => _BalanceSheetState.failure,
        };
      });
    } catch (_) {
      if (!mounted) return;
      _attemptOrigin = CanteenBalanceReadOrigin.manual;
      setState(() {
        _failure = CanteenBalanceFailure.unknown;
        _state = _BalanceSheetState.failure;
      });
    }
  }

  Future<void> _cancel() async {
    _cancelRequested = true;
    try {
      await _reader.cancel();
    } catch (_) {
      // Closing the transient surface is still the safe local outcome.
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cancelSilently() async {
    try {
      await _reader.cancel();
    } catch (_) {
      // The sheet is already being removed; no UI remains for this failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(l10n.canteenBalanceTitle, style: text.headlineSmall),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _attemptOrigin == CanteenBalanceReadOrigin.externalTag
                  ? l10n.canteenBalanceExternalExplanation
                  : l10n.canteenBalanceExplanation,
              style: text.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.canteenBalancePrivacy,
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            Semantics(
              liveRegion: true,
              container: true,
              child: _status(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _status(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return switch (_state) {
      _BalanceSheetState.checking => const Center(
        child: CircularProgressIndicator(),
      ),
      _BalanceSheetState.reading => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox.square(
                dimension: AppSizes.icon,
                child: CircularProgressIndicator(strokeWidth: AppSizes.rule),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.canteenBalanceReading,
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: _cancel,
            child: Text(l10n.canteenBalanceCancel),
          ),
        ],
      ),
      _BalanceSheetState.success => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.canteenBalanceResultTitle, style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            MoneyFormatter.format(
                  amount: _balance!.euroAmount,
                  currencyCode: 'EUR',
                  locale: Localizations.localeOf(context).languageCode,
                ) ??
                _balance!.euroAmount,
            style: text.displaySmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.actionClose),
            ),
          ),
        ],
      ),
      _BalanceSheetState.notSupported => _UnavailableStatus(
        icon: AppIcons.nfc_off,
        title: l10n.canteenBalanceNotSupportedTitle,
        message: l10n.canteenBalanceNotSupportedMessage,
      ),
      _BalanceSheetState.disabled => _UnavailableStatus(
        icon: AppIcons.nfc_off,
        title: l10n.canteenBalanceDisabledTitle,
        message: l10n.canteenBalanceDisabledMessage,
      ),
      _BalanceSheetState.failure => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.canteenBalanceFailureTitle,
            style: text.titleMedium?.copyWith(color: colors.error),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(_failureMessage(l10n, _failure)),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _read,
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.actionRetry),
          ),
        ],
      ),
    };
  }

  static String _failureMessage(
    AppLocalizations l10n,
    CanteenBalanceFailure? failure,
  ) => switch (failure) {
    CanteenBalanceFailure.cancelled => l10n.canteenBalanceCancelled,
    CanteenBalanceFailure.tagLost => l10n.canteenBalanceTagLost,
    CanteenBalanceFailure.unsupportedTag => l10n.canteenBalanceUnsupportedTag,
    CanteenBalanceFailure.invalidResponse => l10n.canteenBalanceInvalidResponse,
    CanteenBalanceFailure.busy => l10n.canteenBalanceBusy,
    _ => l10n.canteenBalanceUnknown,
  };
}

class _UnavailableStatus extends StatelessWidget {
  const _UnavailableStatus({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(icon, size: AppSizes.illustrationIcon),
      const SizedBox(height: AppSpacing.sm),
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.xs),
      Text(message),
    ],
  );
}
