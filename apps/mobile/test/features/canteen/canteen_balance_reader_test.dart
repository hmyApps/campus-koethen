// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/canteen/data/platform_canteen_balance_reader.dart';
import 'package:campus_koethen/features/canteen/domain/canteen_balance_apdu.dart';
import 'package:campus_koethen/features/canteen/domain/canteen_balance_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/canteen_balance_responses.dart';

class _FakeChannel implements CanteenBalancePlatformChannel {
  CanteenBalanceAvailability availabilityValue =
      CanteenBalanceAvailability.available;
  bool pendingTag = false;
  final StreamController<void> controller = StreamController<void>.broadcast();
  final List<List<int>> commands = <List<int>>[];
  final List<List<int>> responses = <List<int>>[];
  bool? startedWithPendingTag;
  int finishes = 0;
  int cancels = 0;

  @override
  Stream<void> get externalTagDiscovered => controller.stream;

  @override
  Future<CanteenBalanceAvailability> availability() async => availabilityValue;

  @override
  Future<bool> hasPendingExternalTag() async => pendingTag;

  @override
  Future<void> start({
    required bool usePendingTag,
    required String prompt,
  }) async {
    startedWithPendingTag = usePendingTag;
  }

  @override
  Future<List<int>> transceive(List<int> command) async {
    commands.add(List<int>.of(command));
    return responses.removeAt(0);
  }

  @override
  Future<void> finish() async => finishes++;

  @override
  Future<void> cancel() async => cancels++;
}

void main() {
  test(
    'sends the read APDU only after successful application selection',
    () async {
      final _FakeChannel channel = _FakeChannel()
        ..responses.addAll(<List<int>>[
          CanteenBalanceResponses.selected,
          CanteenBalanceResponses.positive,
        ]);
      final PlatformCanteenBalanceReader reader = PlatformCanteenBalanceReader(
        channel,
      );

      final CanteenBalance balance = await reader.read(
        origin: CanteenBalanceReadOrigin.manual,
        prompt: 'prompt',
      );

      expect(balance.milliEuros, 12345);
      expect(channel.startedWithPendingTag, isFalse);
      expect(channel.commands, <List<int>>[
        CanteenBalanceApdu.selectApplication,
        CanteenBalanceApdu.readBalance,
      ]);
      expect(channel.finishes, 1);
    },
  );

  test('never sends the second APDU after a failed selection', () async {
    final _FakeChannel channel = _FakeChannel()
      ..responses.add(<int>[0x91, 0xae]);
    final PlatformCanteenBalanceReader reader = PlatformCanteenBalanceReader(
      channel,
    );

    await expectLater(
      reader.read(origin: CanteenBalanceReadOrigin.manual, prompt: 'prompt'),
      throwsA(
        isA<CanteenBalanceReadException>().having(
          (CanteenBalanceReadException error) => error.reason,
          'reason',
          CanteenBalanceFailure.invalidResponse,
        ),
      ),
    );
    expect(channel.commands, <List<int>>[CanteenBalanceApdu.selectApplication]);
    expect(channel.finishes, 1);
  });

  test(
    'external launch consumes the intent tag and exposes no card data',
    () async {
      final _FakeChannel channel = _FakeChannel()
        ..pendingTag = true
        ..responses.addAll(<List<int>>[
          CanteenBalanceResponses.selected,
          CanteenBalanceResponses.negative,
        ]);
      final PlatformCanteenBalanceReader reader = PlatformCanteenBalanceReader(
        channel,
      );

      expect(await reader.hasPendingExternalTag(), isTrue);
      final Future<void> externalSignal = reader.externalTagDiscovered.first;
      channel.controller.add(null);
      await externalSignal;
      expect(
        (await reader.read(
          origin: CanteenBalanceReadOrigin.externalTag,
          prompt: 'prompt',
        )).milliEuros,
        -1250,
      );
      expect(channel.startedWithPendingTag, isTrue);
    },
  );

  test('unavailable NFC fails before opening or transmitting', () async {
    final _FakeChannel channel = _FakeChannel()
      ..availabilityValue = CanteenBalanceAvailability.notSupported;
    final PlatformCanteenBalanceReader reader = PlatformCanteenBalanceReader(
      channel,
    );

    await expectLater(
      reader.read(origin: CanteenBalanceReadOrigin.manual, prompt: 'prompt'),
      throwsA(
        isA<CanteenBalanceReadException>().having(
          (CanteenBalanceReadException error) => error.reason,
          'reason',
          CanteenBalanceFailure.notSupported,
        ),
      ),
    );
    expect(channel.commands, isEmpty);
    expect(channel.finishes, 0);
  });

  test('cancel is delegated without retaining a result', () async {
    final _FakeChannel channel = _FakeChannel();
    final PlatformCanteenBalanceReader reader = PlatformCanteenBalanceReader(
      channel,
    );

    await reader.cancel();

    expect(channel.cancels, 1);
  });
}
