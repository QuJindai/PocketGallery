import 'dart:convert';

import '../core/models.dart';
import '../lineage/generation_models.dart';

enum ChatMode { modelOnly, auto, knowledge }

enum ChatRole { user, assistant }

class KnowledgeScope {
  const KnowledgeScope.all() : documentIds = null;
  const KnowledgeScope.documents(Set<String> ids) : documentIds = ids;

  final Set<String>? documentIds;

  bool get isAll => documentIds == null;

  String toJson() {
    if (isAll) return '{"type":"all"}';
    final ids = documentIds!.toList()..sort();
    return jsonEncode({'type': 'documents', 'documentIds': ids});
  }

  static KnowledgeScope fromJson(String? text) {
    if (text == null || text.isEmpty) return const KnowledgeScope.all();
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['type'] != 'documents') return const KnowledgeScope.all();
      final values = (data['documentIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toSet();
      return KnowledgeScope.documents(values);
    } catch (_) {
      return const KnowledgeScope.all();
    }
  }
}

class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.mode,
    required this.scope,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final ChatMode mode;
  final KnowledgeScope scope;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSession copyWith({
    String? title,
    ChatMode? mode,
    KnowledgeScope? scope,
    DateTime? updatedAt,
  }) => ChatSession(
    id: id,
    title: title ?? this.title,
    mode: mode ?? this.mode,
    scope: scope ?? this.scope,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.text,
    required this.createdAt,
    this.retrievalMode,
    this.evidenceJson,
    this.citedAnchorsJson,
    this.traceId,
  });

  factory ChatMessage.user({
    required String id,
    required String sessionId,
    required String text,
    DateTime? createdAt,
  }) => ChatMessage(
    id: id,
    sessionId: sessionId,
    role: ChatRole.user,
    text: text,
    createdAt: createdAt ?? DateTime.now(),
  );

  factory ChatMessage.assistant({
    required String id,
    required String sessionId,
    required String text,
    DateTime? createdAt,
    String? retrievalMode,
    String? evidenceJson,
    String? citedAnchorsJson,
    String? traceId,
  }) => ChatMessage(
    id: id,
    sessionId: sessionId,
    role: ChatRole.assistant,
    text: text,
    createdAt: createdAt ?? DateTime.now(),
    retrievalMode: retrievalMode,
    evidenceJson: evidenceJson,
    citedAnchorsJson: citedAnchorsJson,
    traceId: traceId,
  );

  final String id;
  final String sessionId;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final String? retrievalMode;
  final String? evidenceJson;
  final String? citedAnchorsJson;
  final String? traceId;

  List<EvidenceItem> get evidence {
    final raw = evidenceJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final rows = jsonDecode(raw) as List<dynamic>;
      return rows.whereType<Map<String, dynamic>>().map((row) {
        final chunkMap = row['chunk'] as Map<String, dynamic>;
        return EvidenceItem(
          anchor: row['anchor'] as String,
          score: (row['score'] as num?)?.toDouble() ?? 0,
          chunk: PgChunk(
            id: chunkMap['id'] as String,
            documentId: chunkMap['documentId'] as String,
            sourceName: chunkMap['sourceName'] as String,
            locator: chunkMap['locator'] as String,
            ordinal: (chunkMap['ordinal'] as num).toInt(),
            text: chunkMap['text'] as String,
          ),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  List<String> get citedAnchors {
    final raw = citedAnchorsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  static String encodeEvidence(List<EvidenceItem> evidence) => jsonEncode([
    for (final item in evidence)
      {
        'anchor': item.anchor,
        'score': item.score,
        'chunk': {
          'id': item.chunk.id,
          'documentId': item.chunk.documentId,
          'sourceName': item.chunk.sourceName,
          'locator': item.chunk.locator,
          'ordinal': item.chunk.ordinal,
          'text': item.chunk.text,
        },
      },
  ]);

  static String encodeAnchors(List<String> anchors) => jsonEncode(anchors);
}

abstract class ChatModelGateway {
  Future<ChatTurnResult> sendTurn({
    required String sessionId,
    required List<ChatMessage> priorMessages,
    required String userText,
    required List<EvidenceItem> evidence,
    required bool forceKnowledge,
  });

  Future<void> resetSession(String sessionId);
  Future<void> close();
}
