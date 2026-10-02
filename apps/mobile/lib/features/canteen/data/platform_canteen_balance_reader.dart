// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/canteen_balance_apdu.dart';
import '../domain/canteen_balance_reader.dart';

/// Narrow native surface. It can open/close one ISO-DEP/CoreNFC session and
/// exchange bytes, but owns neither the APDU sequence nor balance parsing.
abstract interface class CanteenBalancePlatformChannel {
  Future<CanteenBalanceAvailability> availability();
  Future<bool> hasPendingExternalTag();
  Stream<void> get externalTagDiscovered;
  Future<void> start({required bool usePendingTag, required String prompt});
  Future<List<int>> transceive(List<int> command);
  Future<void> finish();
  Future<void> cancel();
}

class MethodChannelCanteenBalancePlatformChannel
    implements CanteenBalancePlatformChannel {
  MethodChannelCanteenBalancePlatformChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const String _channelName =
      'dev.erikengler.campuskoethen/canteen_balance';

  final MethodChannel _channel;
  final StreamController<void> _externalTags =
      StreamController<void>.broadcast();

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'externalTagDiscovered') {
      _externalTags.add(null);
    }
    return null;
  }

  @override
  Stream<void> get externalTagDiscovered => _externalTags.stream;

  @override
  Future<CanteenBalanceAvailability> availability() async {
    final String? value = await _channel.invokeMethod<String>('availability');
    return switch (value) {
      'available' => CanteenBalanceAvailability.available,
      'disabled' => CanteenBalanceAvailability.disabled,
      _ => CanteenBalanceAvailability.notSupported,
    };
  }

  @override
  Future<bool> hasPendingExternalTag() async =>
      await _channel.invokeMethod<bool>('hasPendingExternalTag') ?? false;

  @override
  Future<void> start({required bool usePendingTag, required String prompt}) =>
      _channel.invokeMethod<void>('start', <String, Object>{
        'usePendingTag': usePendingTag,
        'prompt': prompt,
      });

  @override
  Future<List<int>> transceive(List<int> command) async {
    final Object? response = await _channel.invokeMethod<Object?>(
      'transceive',
      Uint8List.fromList(command),
    );
    if (response is Uint8List) return response;
    if (response is List<Object?> && response.every((Object? e) => e is int)) {
      return response.cast<int>();
    }
    throw PlatformException(code: 'invalid_response');
  }

  @override
  Future<void> finish() => _channel.invokeMethod<void>('finish');

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}

/// Sends exactly the two audited APDUs and maps native failures to data-free
/// categories suitable for localized UI.
class PlatformCanteenBalanceReader implements CanteenBalanceReader {
  PlatformCanteenBalanceReader(this._channel);

  final CanteenBalancePlatformChannel _channel;
  bool _reading = false;

  @override
  Future<CanteenBalanceAvailability> availability() => _channel.availability();

  @override
  Future<bool> hasPendingExternalTag() => _channel.hasPendingExternalTag();

  @override
  Stream<void> get externalTagDiscovered => _channel.externalTagDiscovered;

  @override
  Future<CanteenBalance> read({
    required CanteenBalanceReadOrigin origin,
    required String prompt,
  }) async {
    if (_reading) {
      throw const CanteenBalanceReadException(CanteenBalanceFailure.busy);
    }

    final CanteenBalanceAvailability support;
    try {
      support = await availability();
    } on PlatformException catch (error) {
      throw _mapPlatformFailure(error);
    }
    if (support == CanteenBalanceAvailability.notSupported) {
      throw const CanteenBalanceReadException(
        CanteenBalanceFailure.notSupported,
      );
    }
    if (support == CanteenBalanceAvailability.disabled) {
      throw const CanteenBalanceReadException(CanteenBalanceFailure.disabled);
    }

    _reading = true;
    bool started = false;
    try {
      await _channel.start(
        usePendingTag: origin == CanteenBalanceReadOrigin.externalTag,
        prompt: prompt,
      );
      started = true;

      final List<int> selected = await _channel.transceive(
        CanteenBalanceApdu.selectApplication,
      );
      CanteenBalanceApdu.validateSelection(selected);

      final List<int> response = await _channel.transceive(
        CanteenBalanceApdu.readBalance,
      );
      return CanteenBalanceApdu.parseBalance(response);
    } on CanteenBalanceProtocolException {
      throw const CanteenBalanceReadException(
        CanteenBalanceFailure.invalidResponse,
      );
    } on CanteenBalanceReadException {
      rethrow;
    } on PlatformException catch (error) {
      throw _mapPlatformFailure(error);
    } catch (_) {
      throw const CanteenBalanceReadException(CanteenBalanceFailure.unknown);
    } finally {
      if (started) {
        try {
          await _channel.finish();
        } catch (_) {
          // The result/failure above is authoritative. Session cleanup must
          // never turn a successful, already-validated read into another
          // error, and no cleanup detail is logged.
        }
      }
      _reading = false;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.cancel();
    } on PlatformException catch (error) {
      throw _mapPlatformFailure(error);
    }
  }

  static CanteenBalanceReadException _mapPlatformFailure(
    PlatformException error,
  ) => CanteenBalanceReadException(switch (error.code) {
    'nfc_not_supported' => CanteenBalanceFailure.notSupported,
    'nfc_disabled' => CanteenBalanceFailure.disabled,
    'cancelled' => CanteenBalanceFailure.cancelled,
    'tag_lost' || 'no_pending_tag' => CanteenBalanceFailure.tagLost,
    'unsupported_tag' => CanteenBalanceFailure.unsupportedTag,
    'busy' => CanteenBalanceFailure.busy,
    'invalid_response' => CanteenBalanceFailure.invalidResponse,
    _ => CanteenBalanceFailure.unknown,
  });
}
