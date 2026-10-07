// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../application/mail_suggestions.dart';
import '../domain/mail_cache_store.dart';

/// A recipient input with autocomplete from Exchange and local mail history.
///
/// The field holds a comma-separated list of addresses; suggestions apply to
/// the token currently being typed (after the last comma), so a chosen address
/// is spliced in without disturbing the ones already entered.
class RecipientAutocompleteField extends ConsumerStatefulWidget {
  const RecipientAutocompleteField({
    required this.controller,
    required this.label,
    this.focusNode,
    this.helperText,
    this.enabled = true,
    this.validator,
    this.icon,
    super.key,
  });

  final TextEditingController controller;

  /// Supplied by the form when it needs to move the caret here — for instance
  /// to the first field that failed validation.
  final FocusNode? focusNode;

  final String label;
  final String? helperText;
  final bool enabled;
  final String? Function(String?)? validator;
  final IconData? icon;

  @override
  ConsumerState<RecipientAutocompleteField> createState() =>
      _RecipientAutocompleteFieldState();
}

class _RecipientAutocompleteFieldState
    extends ConsumerState<RecipientAutocompleteField> {
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  static final RegExp _separator = RegExp(r'[,;]');

  /// The address fragment currently being typed (after the last separator).
  static String _currentToken(String text) {
    final int sep = text.lastIndexOf(_separator);
    return text.substring(sep + 1).trim();
  }

  void _replaceCurrentToken(String email) {
    final String text = widget.controller.text;
    final int sep = text.lastIndexOf(_separator);
    final String head = sep >= 0 ? text.substring(0, sep + 1) : '';
    final String spacer = head.isEmpty ? '' : ' ';
    final String next = '$head$spacer$email, ';
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Trigger loading of the address index.
    ref.watch(mailKnownAddressesProvider);

    return RawAutocomplete<MailAddressEntry>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (MailAddressEntry e) => e.email,
      optionsBuilder: (TextEditingValue value) async {
        final String query = _currentToken(value.text);
        if (query.length < 2) return const <MailAddressEntry>[];
        return ref.read(mailRecipientSuggestionsProvider(query).future);
      },
      onSelected: (MailAddressEntry option) =>
          _replaceCurrentToken(option.email),
      fieldViewBuilder:
          (
            BuildContext context,
            TextEditingController controller,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              enabled: widget.enabled,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              validator: widget.validator,
              decoration: InputDecoration(
                labelText: widget.label,
                helperText: widget.helperText,
                prefixIcon: widget.icon == null ? null : Icon(widget.icon),
              ),
            );
          },
      optionsViewBuilder:
          (
            BuildContext context,
            void Function(MailAddressEntry) onSelected,
            Iterable<MailAddressEntry> options,
          ) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 240,
                    maxWidth: MediaQuery.sizeOf(context).width - AppSpacing.xl,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final MailAddressEntry option = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(option.email),
                        subtitle:
                            (option.name != null && option.name!.isNotEmpty)
                            ? Text(option.name!)
                            : null,
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
    );
  }
}
