// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_modules.dart';
import '../../../core/links/safe_link_launcher.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../l10n/l10n.dart';
import '../domain/library_resource.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    return ScreenScaffold(
      eyebrow: ModuleCategory.campus.label(l10n),
      title: l10n.libraryTitle,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          Text(
            l10n.libraryIntro,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final LibraryResource resource in libraryResources)
            Card(
              child: ListTile(
                minVerticalPadding: AppSpacing.md,
                leading: Icon(resource.icon),
                title: Text(resource.title(l10n)),
                subtitle: Text(
                  '${resource.description(l10n)}\n${l10n.libraryOpensInBrowser}',
                ),
                isThreeLine: true,
                trailing: const Icon(AppIcons.open_in_new),
                onTap: () async {
                  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
                    context,
                  );
                  final LinkLaunchResult result = await ref
                      .read(linkLauncherProvider)
                      .open(resource.url);
                  if (result != LinkLaunchResult.opened) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(l10n.libraryOpenFailed)),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
