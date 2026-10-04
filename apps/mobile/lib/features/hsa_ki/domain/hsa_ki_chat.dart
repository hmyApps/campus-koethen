// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

enum HsaKiMessageRole { user, assistant }

/// One turn of a chat exchange. HAWKI's external `ai-req` endpoint is
/// stateless — it does not persist a conversation server-side — so the app
/// is the only place this history exists, exactly like every other
/// in-memory-only exchange this app makes with a personal direct service.
class HsaKiMessage {
  const HsaKiMessage({required this.role, required this.text});

  final HsaKiMessageRole role;
  final String text;
}

/// One AI model HSA's instance currently offers, as read from
/// `GET /api/hawki/v1/ai-models`.
class HsaKiModel {
  const HsaKiModel({
    required this.modelId,
    required this.label,
    required this.active,
  });

  /// The literal id to send back as `payload.model` in an `ai-req` call —
  /// never assumed to equal [label] or the JSON:API resource `id`.
  final String modelId;
  final String label;
  final bool active;
}
