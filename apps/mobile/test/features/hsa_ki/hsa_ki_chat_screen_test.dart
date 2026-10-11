// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/hsa_ki/application/hsa_ki_providers.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_account.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_chat.dart';
import 'package:campus_koethen/features/hsa_ki/domain/hsa_ki_gateway.dart';
import 'package:campus_koethen/features/hsa_ki/presentation/hsa_ki_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

void main() {
  testWidgets('the model picker carries an accessible label', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpScreen(
      tester,
      const HsaKiChatScreen(),
      overrides: [
        hsaKiCredentialStoreProvider.overrideWithValue(_Store()),
        hsaKiGatewayProvider.overrideWithValue(_Gateway()),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Modell')), findsOneWidget);
    semantics.dispose();
  });
}

class _Store implements HsaKiCredentialStore {
  @override
  Future<HsaKiCredential?> read() async => const HsaKiCredential(
    token: 'demo-token',
    tokenId: '1',
    username: 'demo',
  );

  @override
  Future<void> write(HsaKiCredential credential) async {}

  @override
  Future<void> clear() async {}
}

class _Gateway implements HsaKiGateway {
  @override
  Future<HsaKiCredential> connect({
    required String username,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> revoke(
    HsaKiCredential credential, {
    required String password,
  }) async {}

  @override
  Future<List<HsaKiModel>> listModels(HsaKiCredential credential) async =>
      const <HsaKiModel>[
        HsaKiModel(modelId: 'demo-a', label: 'Demo A', active: true),
        HsaKiModel(modelId: 'demo-b', label: 'Demo B', active: false),
      ];

  @override
  Future<String> sendMessage(
    HsaKiCredential credential, {
    required String modelId,
    required List<HsaKiMessage> messages,
  }) async => '';
}
