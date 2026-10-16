// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/links/safe_link_launcher.dart';
import 'package:campus_koethen/features/library/domain/library_resource.dart';
import 'package:campus_koethen/features/library/presentation/library_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

class _Launcher extends SafeLinkLauncher {
  _Launcher(this.result);

  final LinkLaunchResult result;
  final List<String> opened = <String>[];

  @override
  Future<LinkLaunchResult> open(String? rawUrl) async {
    opened.add(rawUrl ?? '');
    return result;
  }
}

void main() {
  test('every library address is one the launcher accepts', () {
    for (final LibraryResource resource in libraryResources) {
      expect(
        SafeLinkLauncher.isAllowed(resource.url),
        isTrue,
        reason: resource.key,
      );
    }
  });

  testWidgets('a catalogue opens in the browser', (WidgetTester tester) async {
    final _Launcher launcher = _Launcher(LinkLaunchResult.opened);
    await pumpScreen(
      tester,
      const LibraryScreen(),
      overrides: [linkLauncherProvider.overrideWithValue(launcher)],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Online-Katalog (OPAC)'));
    await tester.pumpAndSettle();

    expect(launcher.opened, <String>[libraryResources.first.url]);
  });

  testWidgets('a refused launch says so', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      const LibraryScreen(),
      overrides: [
        linkLauncherProvider.overrideWithValue(
          _Launcher(LinkLaunchResult.failed),
        ),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discovery-Suche'));
    await tester.pumpAndSettle();

    expect(find.text('Der Link konnte nicht geöffnet werden.'), findsOneWidget);
  });
}
