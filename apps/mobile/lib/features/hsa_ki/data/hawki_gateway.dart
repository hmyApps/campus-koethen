// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:dio/dio.dart';

import '../domain/hsa_ki_account.dart';
import '../domain/hsa_ki_chat.dart';
import '../domain/hsa_ki_failure.dart';
import '../domain/hsa_ki_gateway.dart';
import '../domain/hsa_ki_profile.dart';
import 'hawki_session.dart';

/// Talks to the Hochschule Anhalt KI agent (HAWKI, "HSA-GPT") over HTTPS,
/// ONLY to [HsaKiProfile.host].
///
/// The token-mint step (`connect`) is the one place this feature ever
/// touches the central university password; everything afterwards —
/// listing models, sending a message — uses only the minted bearer token.
/// `connect`/`revoke` each open their own short-lived [HawkiSession] and
/// close it in `finally`, matching every other direct integration in this
/// app: no shared session, no lingering cookie jar.
class HawkiGateway implements HsaKiGateway {
  HawkiGateway([this._adapter]);

  final HttpClientAdapter? _adapter;
  static const HsaKiProfile _profile = HsaKiProfile();
  static const String _tokenName = 'Campus Köthen';

  @override
  Future<HsaKiCredential> connect({
    required String username,
    required String password,
  }) async {
    final HawkiSession session = HawkiSession(adapter: _adapter);
    try {
      await session.login(username: username, password: password);
      final Map<String, dynamic> created = await session.postJsonWithFreshCsrf(
        _profile.createTokenUri,
        csrfSourcePage: HsaKiProfile.server.resolve('/profile'),
        body: <String, dynamic>{'name': _tokenName},
      );
      final Object? token = created['token'];
      final Object? id = created['id'];
      if (token is! String || token.isEmpty || id == null) {
        throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
      }
      return HsaKiCredential(
        token: token,
        tokenId: id.toString(),
        username: username,
      );
    } on HsaKiFailure {
      rethrow;
    } on DioException catch (e) {
      throw HawkiSession.mapDioException(e);
    } catch (_) {
      throw const HsaKiFailure(HsaKiFailureKind.unknown);
    } finally {
      session.close();
    }
  }

  @override
  Future<void> revoke(
    HsaKiCredential credential, {
    required String password,
  }) async {
    final int? tokenId = int.tryParse(credential.tokenId);
    if (tokenId == null) {
      // A non-numeric stored id means the credential was never minted by the
      // flow in [connect] (which only ever stores HAWKI's numeric id). Treat
      // it as a structure mismatch instead of throwing an unhandled
      // FormatException out of the sign-out path.
      throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
    }
    final HawkiSession session = HawkiSession(adapter: _adapter);
    try {
      await session.login(username: credential.username, password: password);
      await session.postJsonWithFreshCsrf(
        _profile.revokeTokenUri,
        csrfSourcePage: HsaKiProfile.server.resolve('/profile'),
        body: <String, dynamic>{'tokenId': tokenId},
      );
    } on HsaKiFailure {
      rethrow;
    } on DioException catch (e) {
      throw HawkiSession.mapDioException(e);
    } finally {
      session.close();
    }
  }

  @override
  Future<List<HsaKiModel>> listModels(HsaKiCredential credential) async {
    final HawkiSession session = HawkiSession(adapter: _adapter);
    try {
      final Map<String, dynamic> body = await session.getBearerJson(
        _profile.aiModelsUri,
        token: credential.token,
      );
      final Object? data = body['data'];
      if (data is! List) {
        throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
      }
      final List<HsaKiModel> models = <HsaKiModel>[];
      for (final Object? entry in data) {
        if (entry is! Map<String, dynamic>) continue;
        final Object? attributes = entry['attributes'];
        if (attributes is! Map<String, dynamic>) continue;
        final Object? modelId = attributes['model_id'];
        final Object? label = attributes['label'];
        final Object? active = attributes['active'];
        if (modelId is! String || modelId.isEmpty) continue;
        models.add(
          HsaKiModel(
            modelId: modelId,
            label: label is String && label.isNotEmpty ? label : modelId,
            active: active == true,
          ),
        );
      }
      return models;
    } on HsaKiFailure {
      rethrow;
    } on DioException catch (e) {
      throw HawkiSession.mapDioException(e);
    } finally {
      session.close();
    }
  }

  @override
  Future<String> sendMessage(
    HsaKiCredential credential, {
    required String modelId,
    required List<HsaKiMessage> messages,
  }) async {
    final HawkiSession session = HawkiSession(adapter: _adapter);
    try {
      final Map<String, dynamic> body = await session.postBearerJson(
        _profile.aiRequestUri,
        token: credential.token,
        body: <String, dynamic>{
          'payload': <String, dynamic>{
            'model': modelId,
            'messages': messages
                .map(
                  (HsaKiMessage m) => <String, dynamic>{
                    'role': m.role == HsaKiMessageRole.user
                        ? 'user'
                        : 'assistant',
                    'content': <String, dynamic>{'text': m.text},
                  },
                )
                .toList(growable: false),
          },
        },
      );
      if (body['success'] != true) {
        throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
      }
      final Object? content = body['content'];
      if (content is! String) {
        throw const HsaKiFailure(HsaKiFailureKind.portalStructureChanged);
      }
      return content;
    } on HsaKiFailure {
      rethrow;
    } on DioException catch (e) {
      throw HawkiSession.mapDioException(e);
    } finally {
      session.close();
    }
  }
}
