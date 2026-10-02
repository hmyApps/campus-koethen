// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/documents/app_document.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../application/mail_account_controller.dart';
import '../application/mail_compose_controller.dart';
import '../data/mail_attachment_picker.dart';
import '../domain/mail_credentials.dart';
import '../domain/mail_failure.dart';
import '../domain/mail_gateway.dart';
import '../domain/mail_message.dart';
import 'compose_draft.dart';
import 'mail_error_messages.dart';
import 'recipient_field.dart';
import '../../../core/widgets/screen_scaffold.dart';

/// A file picked for this draft: the port's handle plus its size, resolved
/// once right after picking so the list can show it without an async gap.
class _DraftAttachment {
  _DraftAttachment({required this.file, required this.sizeBytes});

  final PickedMailFile file;
  final int? sizeBytes;
}

/// Compose a text-only message. The sender is always the signed-in account
/// address — there is no From field to edit. A send in flight disables the
/// button, and the controller ignores a second trigger, so a message is never
/// sent twice.
///
/// The screen closes the instant the SMTP submission succeeds; storing the Sent
/// copy happens in the background so the user is never left on a spinner after
/// the message has actually left.
class MailComposeScreen extends ConsumerStatefulWidget {
  const MailComposeScreen({this.draft, super.key});

  /// Optional pre-filled content (a reply or reply-all).
  final ComposeDraft? draft;

  @override
  ConsumerState<MailComposeScreen> createState() => _MailComposeScreenState();
}

class _MailComposeScreenState extends ConsumerState<MailComposeScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _toController;
  late final TextEditingController _ccController;
  late final TextEditingController _subjectController;
  late final TextEditingController _bodyController;
  final FocusNode _toFocus = FocusNode();
  final FocusNode _ccFocus = FocusNode();

  /// Ephemeral compose-only state — like the text controllers, this never
  /// leaves the screen except mapped into an [OutgoingMessage] at send time.
  final List<_DraftAttachment> _attachments = <_DraftAttachment>[];

  @override
  void initState() {
    super.initState();
    final ComposeDraft draft = widget.draft ?? const ComposeDraft();
    _toController = TextEditingController(text: draft.to.join(', '));
    _ccController = TextEditingController(text: draft.cc.join(', '));
    _subjectController = TextEditingController(text: draft.subject);
    _bodyController = TextEditingController(text: draft.body);
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _toFocus.dispose();
    _ccFocus.dispose();
    super.dispose();
  }

  static final RegExp _separator = RegExp(r'[,;]');

  /// Splits a recipient field on commas/semicolons into trimmed addresses.
  List<String> _parseRecipients(String raw) => raw
      .split(_separator)
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toList();

  /// Opens the OS file picker and appends every chosen file to the draft. A
  /// cancelled picker leaves the draft — including any already-picked
  /// attachments — unchanged.
  Future<void> _pickAttachments() async {
    final MailFilePickResult result = await ref
        .read(mailAttachmentPickerProvider)
        .pickFiles();
    if (result is! MailFilesPicked) return;

    final List<_DraftAttachment> picked = <_DraftAttachment>[];
    int total = _attachmentTotalBytes;
    if (_attachments.length + result.files.length >
        MailAttachmentLimits.maxCount) {
      _showAttachmentError(MailFailureKind.attachmentLimitExceeded);
      return;
    }
    for (final PickedMailFile file in result.files) {
      final int? size = await file.sizeBytes();
      if (size == null) {
        _showAttachmentError(MailFailureKind.attachmentUnreadable);
        return;
      }
      total += size;
      if (size > MailAttachmentLimits.maxFileBytes ||
          total > MailAttachmentLimits.maxTotalBytes) {
        _showAttachmentError(MailFailureKind.attachmentLimitExceeded);
        return;
      }
      picked.add(_DraftAttachment(file: file, sizeBytes: size));
    }
    if (!mounted) return;
    setState(() => _attachments.addAll(picked));
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  int get _attachmentTotalBytes => _attachments.fold<int>(
    0,
    (int total, _DraftAttachment attachment) =>
        total + (attachment.sizeBytes ?? 0),
  );

  void _showAttachmentError(MailFailureKind kind) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mailFailureMessage(context.l10n, MailFailure(kind))),
      ),
    );
  }

  /// Reads every picked file's CURRENT bytes — deliberately not the bytes
  /// captured at pick time — so a file that became unreadable in between
  /// (deleted, moved, permission revoked) is caught here rather than sent
  /// silently stale or not at all.
  Future<List<OutgoingAttachment>> _readAttachments() async {
    if (_attachments.length > MailAttachmentLimits.maxCount) {
      throw const MailFailure(MailFailureKind.attachmentLimitExceeded);
    }
    final List<OutgoingAttachment> result = <OutgoingAttachment>[];
    int total = 0;
    for (final _DraftAttachment attachment in _attachments) {
      final int? currentSize = await attachment.file.sizeBytes();
      if (currentSize == null) {
        throw const MailFailure(MailFailureKind.attachmentUnreadable);
      }
      if (currentSize > MailAttachmentLimits.maxFileBytes ||
          total + currentSize > MailAttachmentLimits.maxTotalBytes) {
        throw const MailFailure(MailFailureKind.attachmentLimitExceeded);
      }
      final int remaining = MailAttachmentLimits.maxTotalBytes - total;
      final int readLimit = remaining < MailAttachmentLimits.maxFileBytes
          ? remaining
          : MailAttachmentLimits.maxFileBytes;
      final Uint8List bytes;
      try {
        bytes = await attachment.file.readBytes(maxBytes: readLimit);
      } on MailAttachmentLimitException {
        throw const MailFailure(MailFailureKind.attachmentLimitExceeded);
      }
      total += bytes.length;
      if (bytes.length > MailAttachmentLimits.maxFileBytes ||
          total > MailAttachmentLimits.maxTotalBytes) {
        throw const MailFailure(MailFailureKind.attachmentLimitExceeded);
      }
      result.add(
        OutgoingAttachment(
          filename: attachment.file.filename,
          mediaType: attachment.file.mediaType,
          bytes: bytes,
        ),
      );
    }
    return result;
  }

  Future<void> _send() async {
    final AppLocalizations l10n = context.l10n;
    if (ref.read(mailComposeControllerProvider)) return; // already sending
    if (!(_formKey.currentState?.validate() ?? false)) {
      // In a scrolled compose form the invalid field is often off screen, so
      // pressing "send" looked like it did nothing whatsoever.
      _focusFirstInvalidField();
      return;
    }

    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final MailComposeController controller = ref.read(
      mailComposeControllerProvider.notifier,
    );

    final List<OutgoingAttachment> attachments;
    try {
      attachments = await _readAttachments();
    } on MailFailure catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(mailFailureMessage(l10n, error))),
      );
      return;
    } catch (_) {
      // Never let the raw I/O error (which could carry a local path) reach
      // the UI. The draft — recipients, subject, body, attachment list —
      // stays exactly as it was; there is no automatic retry.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            mailFailureMessage(
              l10n,
              const MailFailure(MailFailureKind.attachmentUnreadable),
            ),
          ),
        ),
      );
      return;
    }

    final OutgoingMessage message = OutgoingMessage(
      to: _parseRecipients(_toController.text),
      cc: _parseRecipients(_ccController.text),
      subject: _subjectController.text,
      text: _bodyController.text,
      attachments: attachments,
    );

    try {
      final bool sent = await controller.send(message);
      if (!sent) return; // a concurrent send was already running
      messenger.showSnackBar(SnackBar(content: Text(l10n.mailComposeSent)));
      // Only pop if this screen is still the one on top. Popping after the
      // user has already navigated away would close whatever they opened
      // next — a route this screen never owned.
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        if (navigator.canPop()) navigator.pop();
      }

      // Store the Sent copy in the background. The message has already left, so
      // a failure here is only a gentle hint — it never blocks or re-sends.
      unawaited(
        controller.appendSentCopy(message).then((SentCopyResult result) {
          if (result != SentCopyResult.appended) {
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.mailComposeSentNoCopy)),
            );
          }
        }),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(mailFailureMessage(l10n, error))),
      );
    }
  }

  /// True while the draft holds anything the user would not want to lose.
  bool get _hasContent =>
      _toController.text.trim().isNotEmpty ||
      _ccController.text.trim().isNotEmpty ||
      _subjectController.text.trim().isNotEmpty ||
      _bodyController.text.trim().isNotEmpty ||
      _attachments.isNotEmpty;

  void _focusFirstInvalidField() {
    if (_validateTo(_toController.text) != null) {
      _toFocus.requestFocus();
      return;
    }
    if (_validateCc(_ccController.text) != null) _ccFocus.requestFocus();
  }

  /// Handles a back gesture or the system back button.
  ///
  /// There is deliberately no drafts folder, so leaving really does throw the
  /// message away — which is exactly why it should not happen by accident.
  Future<void> _onPopInvoked(bool didPop, Object? _) async {
    if (didPop) return;
    final AppLocalizations l10n = context.l10n;
    final NavigatorState navigator = Navigator.of(context);

    if (ref.read(mailComposeControllerProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.mailComposeSendingBlocksBack)),
      );
      return;
    }

    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.mailComposeDiscardTitle),
        content: Text(l10n.mailComposeDiscardBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.mailComposeKeepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.mailComposeDiscardConfirm),
          ),
        ],
      ),
    );
    if ((discard ?? false) && navigator.canPop()) navigator.pop();
  }

  String? _validateTo(String? value) {
    final List<String> recipients = _parseRecipients(value ?? '');
    if (recipients.isEmpty ||
        recipients.any((String r) => !isValidEmailAddress(r))) {
      return context.l10n.mailComposeInvalidRecipient;
    }
    return null;
  }

  String? _validateCc(String? value) {
    final List<String> recipients = _parseRecipients(value ?? '');
    if (recipients.any((String r) => !isValidEmailAddress(r))) {
      return context.l10n.mailComposeInvalidRecipient;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool sending = ref.watch(mailComposeControllerProvider);
    final String? email = ref
        .watch(mailAccountControllerProvider)
        .value
        ?.emailAddress;

    return PopScope(
      // Blocked whenever there is something to lose or a send is in flight;
      // `_onPopInvoked` then decides whether to actually leave.
      canPop: !sending && !_hasContent,
      onPopInvokedWithResult: _onPopInvoked,
      child: ScreenScaffold(
        title: l10n.mailComposeTitle,
        actions: <Widget>[
          IconButton(
            onPressed: sending ? null : _pickAttachments,
            tooltip: l10n.mailComposeAttach,
            icon: const Icon(AppIcons.attach_file),
          ),
          IconButton(
            onPressed: sending ? null : _send,
            tooltip: l10n.mailComposeSend,
            icon: sending
                ? const SizedBox(
                    height: AppSizes.icon,
                    width: AppSizes.icon,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.send_outlined),
          ),
        ],
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.all(context.metrics.screenPadding),
              children: <Widget>[
                if (email != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      l10n.mailComposeFrom(email),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                RecipientAutocompleteField(
                  controller: _toController,
                  focusNode: _toFocus,
                  enabled: !sending,
                  label: l10n.mailComposeTo,
                  helperText: l10n.mailComposeRecipientsHint,
                  icon: AppIcons.alternate_email,
                  validator: _validateTo,
                ),
                const SizedBox(height: AppSpacing.md),
                RecipientAutocompleteField(
                  controller: _ccController,
                  focusNode: _ccFocus,
                  enabled: !sending,
                  label: l10n.mailComposeCc,
                  icon: AppIcons.group_outlined,
                  validator: _validateCc,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _subjectController,
                  enabled: !sending,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.mailComposeSubject,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _bodyController,
                  enabled: !sending,
                  minLines: 8,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: l10n.mailComposeBody,
                    alignLabelWithHint: true,
                  ),
                ),
                if (_attachments.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  for (int index = 0; index < _attachments.length; index++)
                    _AttachmentTile(
                      attachment: _attachments[index],
                      totalLabel: index == 0
                          ? l10n.mailComposeAttachmentTotal(
                              humanFileSize(
                                _attachmentTotalBytes,
                                locale: Localizations.localeOf(
                                  context,
                                ).languageCode,
                              ),
                              humanFileSize(
                                MailAttachmentLimits.maxTotalBytes,
                                locale: Localizations.localeOf(
                                  context,
                                ).languageCode,
                              ),
                            )
                          : null,
                      enabled: !sending,
                      onRemove: () => _removeAttachment(index),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One picked-but-not-yet-sent attachment: filename, formatted size and a
/// remove action.
class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.totalLabel,
    required this.enabled,
    required this.onRemove,
  });

  final _DraftAttachment attachment;
  final String? totalLabel;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final int? size = attachment.sizeBytes;
    final String sizeLabel = size == null
        ? ''
        : humanFileSize(
            size,
            locale: Localizations.localeOf(context).languageCode,
          );
    return Semantics(
      label: l10n.mailComposeAttachmentSemantics(
        attachment.file.filename,
        sizeLabel,
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: ListTile(
          leading: const Icon(AppIcons.insert_drive_file_outlined),
          title: Text(
            attachment.file.filename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            <String>[
              sizeLabel,
              ?totalLabel,
            ].where((String part) => part.isNotEmpty).join(' · '),
          ),
          trailing: IconButton(
            onPressed: enabled ? onRemove : null,
            tooltip: l10n.mailComposeAttachmentRemove,
            icon: const Icon(AppIcons.close),
          ),
        ),
      ),
    );
  }
}
