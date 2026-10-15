// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_bootstrap.dart';
import 'app/campus_app.dart';

/// Entry point.
///
/// The API base URL comes exclusively from
/// `--dart-define=API_BASE_URL=…` (see `core/network/api_config.dart`).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    ProviderScope(
      overrides: await createAppOverrides(),
      child: const CampusApp(),
    ),
  );
}
