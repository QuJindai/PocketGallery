import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../chat/chat_session_store.dart';
import '../services/hf_oauth_device_service.dart';
import '../services/knowledge_engine.dart';
import 'device_diagnostics.dart';

final class PreservationProbe {
  const PreservationProbe({
    required KnowledgeEngine engine,
    required ChatSessionStore chatStore,
    required HfOAuthDeviceService oauth,
    required bool Function() hasActiveModel,
    required bool Function() hasActiveEmbedder,
  })  : _engine = engine,
        _chatStore = chatStore,
        _oauth = oauth,
        _hasActiveModel = hasActiveModel,
        _hasActiveEmbedder = hasActiveEmbedder;

  final KnowledgeEngine _engine;
  final ChatSessionStore _chatStore;
  final HfOAuthDeviceService _oauth;
  final bool Function() _hasActiveModel;
  final bool Function() _hasActiveEmbedder;

  Future<PreservationSnapshot> capture(
    DeviceIdentitySnapshot identity,
  ) async {
    final documents = await _engine.listDocuments();
    documents.sort((left, right) => left.documentId.compareTo(right.documentId));
    final sessions = await _chatStore.listSessions();
    sessions.sort((left, right) => left.id.compareTo(right.id));
    final vectorIdentities =
        await _engine.semanticStore.observationStore.listIdentities();
    final traceIds = await _engine.lineageStore.traceIds();
    final oauthState = await _oauth.inspectCredentialState();

    final knowledgeStates = <String, String>{};
    for (final document in documents) {
      final objectIdentity = _digestObject(<String, Object?>{
        'documentId': document.documentId,
      });
      knowledgeStates[objectIdentity] = _digestObject(<String, Object?>{
        'documentId': document.documentId,
        'sourceName': document.sourceName,
        'sha256': document.sha256,
        'chunkCount': document.chunkCount,
      });
    }

    final chatStates = <String, String>{};
    final chatMessageCounts = <String, int>{};
    for (final session in sessions) {
      final messages = await _chatStore.messages(session.id);
      messages.sort((left, right) {
        final byTime = left.createdAt.compareTo(right.createdAt);
        return byTime == 0 ? left.id.compareTo(right.id) : byTime;
      });
      final objectIdentity = _digestObject(<String, Object?>{
        'sessionId': session.id,
      });
      chatMessageCounts[objectIdentity] = messages.length;
      chatStates[objectIdentity] = _digestObject(<String, Object?>{
        'sessionId': session.id,
        'title': session.title,
        'mode': session.mode.name,
        'scope': session.scope.toJson(),
        'createdAt': session.createdAt.toIso8601String(),
        'updatedAt': session.updatedAt.toIso8601String(),
        'messages': <Map<String, Object?>>[
          for (final message in messages)
            <String, Object?>{
              'id': message.id,
              'role': message.role.name,
              'text': message.text,
              'createdAt': message.createdAt.toIso8601String(),
              'retrievalMode': message.retrievalMode,
              'evidenceJson': message.evidenceJson,
              'citedAnchorsJson': message.citedAnchorsJson,
              'traceId': message.traceId,
            },
        ],
      });
    }

    final vectorStates = <String, String>{};
    for (final vector in vectorIdentities) {
      final objectIdentity = _digestObject(<String, Object?>{
        'chunkId': vector.chunkId,
      });
      vectorStates[objectIdentity] = _digestObject(<String, Object?>{
        'chunkId': vector.chunkId,
        'documentId': vector.documentId,
        'dimension': vector.dimension,
        'norm': vector.norm.isFinite ? vector.norm : vector.norm.toString(),
        'modelIdentity': vector.modelIdentity,
      });
    }

    final lineageStates = <String, String>{};
    for (final traceId in traceIds) {
      final objectIdentity = _digestObject(<String, Object?>{
        'traceId': traceId,
      });
      lineageStates[objectIdentity] = _digestObject(<String, Object?>{
        'traceId': traceId,
      });
    }

    return PreservationSnapshot(
      versionCode: identity.versionCode,
      packageName: identity.packageName,
      signerSha256: identity.signerSha256,
      hasActiveModel: _hasActiveModel(),
      hasActiveEmbedder: _hasActiveEmbedder(),
      oauthAccessPresent: oauthState.accessPresent,
      oauthRefreshPresent: oauthState.refreshPresent,
      oauthExpiry: oauthState.expiry,
      knowledgeStates: knowledgeStates,
      chatStates: chatStates,
      chatMessageCounts: chatMessageCounts,
      vectorStates: vectorStates,
      lineageStates: lineageStates,
    );
  }
}

final class PreservationSnapshot {
  PreservationSnapshot({
    this.schemaVersion = currentSchemaVersion,
    required this.versionCode,
    required this.packageName,
    required this.signerSha256,
    required this.hasActiveModel,
    required this.hasActiveEmbedder,
    required this.oauthAccessPresent,
    required this.oauthRefreshPresent,
    required this.oauthExpiry,
    required Map<String, String> knowledgeStates,
    required Map<String, String> chatStates,
    required Map<String, int> chatMessageCounts,
    required Map<String, String> vectorStates,
    required Map<String, String> lineageStates,
  })  : knowledgeStates = Map<String, String>.unmodifiable(
          _sortStringMap(knowledgeStates),
        ),
        chatStates = Map<String, String>.unmodifiable(
          _sortStringMap(chatStates),
        ),
        chatMessageCounts = Map<String, int>.unmodifiable(
          _sortIntMap(chatMessageCounts),
        ),
        vectorStates = Map<String, String>.unmodifiable(
          _sortStringMap(vectorStates),
        ),
        lineageStates = Map<String, String>.unmodifiable(
          _sortStringMap(lineageStates),
        ) {
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException('Unsupported preservation schema: $schemaVersion');
    }
    if (!chatStates.keys.toSet().containsAll(chatMessageCounts.keys) ||
        !chatMessageCounts.keys.toSet().containsAll(chatStates.keys)) {
      throw const FormatException('Chat state/count identities do not match');
    }
  }

  factory PreservationSnapshot.fromJson(Map<String, Object?> value) {
    final schemaVersion = _requiredInt(value, 'schemaVersion');
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException('Unsupported preservation schema: $schemaVersion');
    }
    final expiryName = _requiredString(value, 'oauthExpiry');
    HfTokenExpiryState? expiry;
    for (final candidate in HfTokenExpiryState.values) {
      if (candidate.name == expiryName) {
        expiry = candidate;
        break;
      }
    }
    if (expiry == null) {
      throw FormatException('Unknown OAuth expiry state: $expiryName');
    }

    return PreservationSnapshot(
      schemaVersion: schemaVersion,
      versionCode: _optionalInt(value, 'versionCode'),
      packageName: _optionalString(value, 'packageName'),
      signerSha256: _optionalString(value, 'signerSha256'),
      hasActiveModel: _requiredBool(value, 'hasActiveModel'),
      hasActiveEmbedder: _requiredBool(value, 'hasActiveEmbedder'),
      oauthAccessPresent: _requiredBool(value, 'oauthAccessPresent'),
      oauthRefreshPresent: _requiredBool(value, 'oauthRefreshPresent'),
      oauthExpiry: expiry,
      knowledgeStates: _decodeDigestMap(value, 'knowledgeStates'),
      chatStates: _decodeDigestMap(value, 'chatStates'),
      chatMessageCounts: _decodeCountMap(value, 'chatMessageCounts'),
      vectorStates: _decodeDigestMap(value, 'vectorStates'),
      lineageStates: _decodeDigestMap(value, 'lineageStates'),
    );
  }

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final int? versionCode;
  final String? packageName;
  final String? signerSha256;
  final bool hasActiveModel;
  final bool hasActiveEmbedder;
  final bool oauthAccessPresent;
  final bool oauthRefreshPresent;
  final HfTokenExpiryState oauthExpiry;
  final Map<String, String> knowledgeStates;
  final Map<String, String> chatStates;
  final Map<String, int> chatMessageCounts;
  final Map<String, String> vectorStates;
  final Map<String, String> lineageStates;

  int get chatMessageCount => chatMessageCounts.values.fold<int>(
        0,
        (sum, count) => sum + count,
      );

  Map<String, Object?> get reportSummary => <String, Object?>{
        'schemaVersion': schemaVersion,
        'versionCode': versionCode,
        'packageName': packageName,
        'signerSha256': signerSha256,
        'hasActiveModel': hasActiveModel,
        'hasActiveEmbedder': hasActiveEmbedder,
        'oauthAccessPresent': oauthAccessPresent,
        'oauthRefreshPresent': oauthRefreshPresent,
        'oauthExpiry': oauthExpiry.name,
        'knowledgeCount': knowledgeStates.length,
        'knowledgeDigest': _digestStateMap(knowledgeStates),
        'chatSessionCount': chatStates.length,
        'chatMessageCount': chatMessageCount,
        'chatDigest': _digestStateMap(chatStates),
        'embeddingObservationCount': vectorStates.length,
        'embeddingObservationDigest': _digestStateMap(vectorStates),
        'lineageTraceCount': lineageStates.length,
        'lineageDigest': _digestStateMap(lineageStates),
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'versionCode': versionCode,
        'packageName': packageName,
        'signerSha256': signerSha256,
        'hasActiveModel': hasActiveModel,
        'hasActiveEmbedder': hasActiveEmbedder,
        'oauthAccessPresent': oauthAccessPresent,
        'oauthRefreshPresent': oauthRefreshPresent,
        'oauthExpiry': oauthExpiry.name,
        'knowledgeStates': knowledgeStates,
        'chatStates': chatStates,
        'chatMessageCounts': chatMessageCounts,
        'vectorStates': vectorStates,
        'lineageStates': lineageStates,
      };
}

final class PreservationComparison {
  PreservationComparison._(Set<String> reasonCodes)
      : reasonCodes = List<String>.unmodifiable(reasonCodes);

  factory PreservationComparison.compare({
    required PreservationSnapshot baseline,
    required PreservationSnapshot current,
  }) {
    final reasons = <String>{};
    final baselineVersion = baseline.versionCode;
    final currentVersion = current.versionCode;
    if (baselineVersion == null ||
        currentVersion == null ||
        baselineVersion >= currentVersion) {
      reasons.add('BASELINE_VERSION_NOT_PREVIOUS');
    }
    if (baseline.packageName == null ||
        current.packageName == null ||
        baseline.packageName != current.packageName) {
      reasons.add('PACKAGE_IDENTITY_MISMATCH');
    }
    if (baseline.signerSha256 == null ||
        current.signerSha256 == null ||
        baseline.signerSha256 != current.signerSha256) {
      reasons.add('SIGNER_IDENTITY_MISMATCH');
    }
    if (baseline.hasActiveModel && !current.hasActiveModel) {
      reasons.add('ACTIVE_MODEL_REMOVED');
    }
    if (baseline.hasActiveEmbedder && !current.hasActiveEmbedder) {
      reasons.add('ACTIVE_EMBEDDER_REMOVED');
    }
    if (baseline.oauthAccessPresent && !current.oauthAccessPresent) {
      reasons.add('OAUTH_ACCESS_REMOVED');
    }
    if (baseline.oauthRefreshPresent && !current.oauthRefreshPresent) {
      reasons.add('OAUTH_REFRESH_REMOVED');
    }
    if (baseline.oauthExpiry != HfTokenExpiryState.malformed &&
        current.oauthExpiry == HfTokenExpiryState.malformed) {
      reasons.add('OAUTH_EXPIRY_MALFORMED');
    }

    _compareStateMaps(
      baseline: baseline.knowledgeStates,
      current: current.knowledgeStates,
      reasons: reasons,
      removedReason: 'DOCUMENT_REMOVED',
      changedReason: 'DOCUMENT_CHANGED',
    );
    _compareChatStates(baseline, current, reasons);
    _compareStateMaps(
      baseline: baseline.vectorStates,
      current: current.vectorStates,
      reasons: reasons,
      removedReason: 'VECTOR_OBSERVATION_REMOVED',
      changedReason: 'VECTOR_OBSERVATION_CHANGED',
    );
    _compareStateMaps(
      baseline: baseline.lineageStates,
      current: current.lineageStates,
      reasons: reasons,
      removedReason: 'LINEAGE_TRACE_REMOVED',
      changedReason: 'LINEAGE_TRACE_CHANGED',
    );

    return PreservationComparison._(reasons);
  }

  final List<String> reasonCodes;

  bool get passed => reasonCodes.isEmpty;
}

void _compareStateMaps({
  required Map<String, String> baseline,
  required Map<String, String> current,
  required Set<String> reasons,
  required String removedReason,
  required String changedReason,
}) {
  for (final entry in baseline.entries) {
    final currentState = current[entry.key];
    if (currentState == null) {
      reasons.add(removedReason);
    } else if (currentState != entry.value) {
      reasons.add(changedReason);
    }
  }
}

void _compareChatStates(
  PreservationSnapshot baseline,
  PreservationSnapshot current,
  Set<String> reasons,
) {
  for (final entry in baseline.chatStates.entries) {
    final currentState = current.chatStates[entry.key];
    if (currentState == null) {
      reasons.add('CHAT_SESSION_REMOVED');
      continue;
    }
    if (currentState == entry.value) continue;
    final baselineCount = baseline.chatMessageCounts[entry.key] ?? 0;
    final currentCount = current.chatMessageCounts[entry.key] ?? 0;
    reasons.add(
      currentCount < baselineCount
          ? 'CHAT_HISTORY_REDUCED'
          : 'CHAT_HISTORY_CHANGED',
    );
  }
}

String _digestObject(Object? value) {
  return sha256.convert(utf8.encode(jsonEncode(value))).toString();
}

String _digestStateMap(Map<String, String> value) {
  final entries = value.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return _digestObject(<Map<String, String>>[
    for (final entry in entries)
      <String, String>{'identity': entry.key, 'state': entry.value},
  ]);
}

Map<String, String> _sortStringMap(Map<String, String> value) {
  final keys = value.keys.toList()..sort();
  return <String, String>{for (final key in keys) key: value[key]!};
}

Map<String, int> _sortIntMap(Map<String, int> value) {
  final keys = value.keys.toList()..sort();
  return <String, int>{for (final key in keys) key: value[key]!};
}

Map<String, String> _decodeDigestMap(
  Map<String, Object?> value,
  String key,
) {
  final raw = value[key];
  if (raw is! Map) throw FormatException('$key must be a map');
  final decoded = <String, String>{};
  for (final entry in raw.entries) {
    final identity = entry.key;
    final state = entry.value;
    if (identity is! String ||
        state is! String ||
        !_isSha256(identity) ||
        !_isSha256(state)) {
      throw FormatException('$key contains an invalid digest entry');
    }
    decoded[identity] = state;
  }
  return decoded;
}

Map<String, int> _decodeCountMap(
  Map<String, Object?> value,
  String key,
) {
  final raw = value[key];
  if (raw is! Map) throw FormatException('$key must be a map');
  final decoded = <String, int>{};
  for (final entry in raw.entries) {
    final identity = entry.key;
    final count = entry.value;
    if (identity is! String || !_isSha256(identity) || count is! int || count < 0) {
      throw FormatException('$key contains an invalid count entry');
    }
    decoded[identity] = count;
  }
  return decoded;
}

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

int _requiredInt(Map<String, Object?> value, String key) {
  final decoded = _optionalInt(value, key);
  if (decoded == null) throw FormatException('$key must be an integer');
  return decoded;
}

int? _optionalInt(Map<String, Object?> value, String key) {
  final raw = value[key];
  if (raw == null) return null;
  if (raw is int) return raw;
  throw FormatException('$key must be an integer or null');
}

String _requiredString(Map<String, Object?> value, String key) {
  final decoded = _optionalString(value, key);
  if (decoded == null) throw FormatException('$key must be a string');
  return decoded;
}

String? _optionalString(Map<String, Object?> value, String key) {
  final raw = value[key];
  if (raw == null) return null;
  if (raw is String && raw.isNotEmpty) return raw;
  throw FormatException('$key must be a non-empty string or null');
}

bool _requiredBool(Map<String, Object?> value, String key) {
  final raw = value[key];
  if (raw is bool) return raw;
  throw FormatException('$key must be a boolean');
}
