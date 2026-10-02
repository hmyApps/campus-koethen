// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Protects the app-wide decision to use only Tabler icons.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> _productionDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((File file) => file.path.endsWith('.dart'))
    .toList(growable: false);

/// Forward-slash form of [File.path] — on Windows, `Directory.listSync`
/// yields backslash paths, which never equal a hardcoded `lib/...` literal.
String _posixPath(File file) => file.path.replaceAll('\\', '/');

void main() {
  const String cataloguePath = 'lib/core/theme/app_icons.dart';

  test('production code never uses a non-Tabler icon catalogue', () {
    final RegExp forbidden = RegExp(
      r'\b(?:Icons|CupertinoIcons|FluentIcons|FontAwesomeIcons|EvaIcons|'
      r'PhosphorIcons|LucideIcons|HeroIcons|Ionicons)\s*\.',
    );
    final List<String> offenders = <String>[];

    for (final File file in _productionDartFiles()) {
      final String content = file.readAsStringSync();
      if (forbidden.hasMatch(content)) offenders.add(file.path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use a matching Tabler glyph through AppIcons instead:\n'
          '${offenders.join('\n')}',
    );
  });

  test('flutter_tabler_icons is imported only by the central catalogue', () {
    final List<String> importers = _productionDartFiles()
        .where(
          (File file) => file.readAsStringSync().contains(
            'package:flutter_tabler_icons/flutter_tabler_icons.dart',
          ),
        )
        .map(_posixPath)
        .toList(growable: false);

    expect(importers, <String>[cataloguePath]);
  });

  test('every AppIcons glyph resolves directly to TablerIcons', () {
    final String catalogue = File(cataloguePath).readAsStringSync();
    final Iterable<RegExpMatch> declarations = RegExp(
      r'static const IconData\s+\w+\s*=\s*([^;]+);',
    ).allMatches(catalogue);
    final List<String> offenders = declarations
        .where(
          (RegExpMatch match) =>
              !match.group(1)!.trim().startsWith('TablerIcons.'),
        )
        .map((RegExpMatch match) => match.group(0)!)
        .toList(growable: false);

    expect(declarations, isNotEmpty);
    expect(
      offenders,
      isEmpty,
      reason:
          'Every public AppIcons entry must resolve to flutter_tabler_icons:\n'
          '${offenders.join('\n')}',
    );
  });
}
