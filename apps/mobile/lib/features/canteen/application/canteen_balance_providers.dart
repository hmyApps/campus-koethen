// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/platform_canteen_balance_reader.dart';
import '../domain/canteen_balance_reader.dart';

final Provider<CanteenBalanceReader> canteenBalanceReaderProvider =
    Provider<CanteenBalanceReader>((Ref ref) {
      return PlatformCanteenBalanceReader(
        MethodChannelCanteenBalancePlatformChannel(),
      );
    });
