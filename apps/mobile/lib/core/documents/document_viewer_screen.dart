// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../l10n/l10n.dart';
import '../theme/app_dimensions.dart';
import 'app_document.dart';
import 'document_share_service.dart';
import '../widgets/screen_scaffold.dart';

/// Full-screen in-app viewer for a downloaded [AppDocument]: images (zoomable),
/// PDFs (native renderer, no WebView), plain text; anything else offers a
/// share/save action. Source-agnostic — it depends on neither mail nor Moodle
/// domain types, only [AppDocument].
class DocumentViewerScreen extends StatefulWidget {
  const DocumentViewerScreen({
    required this.document,
    this.shareService = const DocumentShareService(),
    this.allowSharing = true,
    this.actions = const <Widget>[],
    super.key,
  });

  final AppDocument document;
  final DocumentShareService shareService;

  /// Whether the document may leave the app.
  ///
  /// Off for anything reachable only through a secret token — a committee
  /// receipt embeds the same token as the status link, so sharing the PDF
  /// would hand over access to the whole case. The viewer then shows the
  /// document and offers no way out of it.
  final bool allowSharing;
  final List<Widget> actions;

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  // pdfrx uses this for its local document cache. Do not pass a downloaded
  // filename here: mail subjects and application receipt names may be private.
  final String _pdfSourceName =
      'local-${DateTime.now().microsecondsSinceEpoch}.pdf';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppDocument doc = widget.document;

    return ScreenScaffold(
      title: doc.filename,
      actions: <Widget>[
        ...widget.actions,
        if (widget.allowSharing)
          IconButton(
            onPressed: () => widget.shareService.share(doc),
            tooltip: l10n.documentShare,
            icon: const Icon(AppIcons.ios_share),
          ),
      ],
      body: _body(context, l10n, doc),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, AppDocument doc) {
    if (doc.isImage) {
      return InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.memory(
            doc.bytes,
            errorBuilder: (_, _, _) =>
                _Centered(text: l10n.documentPreviewUnavailable),
          ),
        ),
      );
    }
    if (doc.isPdf) {
      return PdfViewer.data(
        doc.bytes,
        sourceName: _pdfSourceName,
        params: const PdfViewerParams(
          annotationRenderingMode:
              PdfAnnotationRenderingMode.annotationAndForms,
        ),
      );
    }
    if (doc.isText) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SelectableText(
          utf8.decode(doc.bytes, allowMalformed: true),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    // Unsupported format: a safe share/open alternative.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              AppIcons.description_outlined,
              size: AppSizes.illustrationIcon,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.documentPreviewUnavailable, textAlign: TextAlign.center),
            if (widget.allowSharing) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () => widget.shareService.share(doc),
                icon: const Icon(AppIcons.ios_share),
                label: Text(l10n.documentShare),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
