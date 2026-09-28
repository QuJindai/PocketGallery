import '../chat/chat_models.dart';

class VectorIndexRecord {
  const VectorIndexRecord({
    required this.embeddingId,
    required this.chunkId,
    required this.documentId,
    required this.content,
    required this.embedding,
    required this.modelIdentity,
  });

  final String embeddingId;
  final String chunkId;
  final String documentId;
  final String content;
  final List<double> embedding;
  final String modelIdentity;
}

class VectorSearchHit {
  const VectorSearchHit({
    required this.embeddingId,
    required this.chunkId,
    required this.documentId,
    required this.similarity,
    required this.rank,
  });

  final String embeddingId;
  final String chunkId;
  final String documentId;
  final double similarity;
  final int rank;
}

class VectorIndexProbe {
  const VectorIndexProbe({
    required this.initialized,
    required this.databasePath,
    required this.backendId,
    required this.searchVerified,
  });

  final bool initialized;
  final String databasePath;
  final String backendId;

  /// Deliberately false until a later health task performs a real add/search
  /// verification. Initialization alone must never be presented as searchable
  /// index health.
  final bool searchVerified;
}

abstract interface class ActiveVectorIndex {
  Future<void> initialize();

  Future<void> add(VectorIndexRecord record);

  Future<void> remove(String embeddingId);

  Future<List<VectorSearchHit>> searchByEmbedding({
    required List<double> queryEmbedding,
    required int topK,
    required KnowledgeScope scope,
  });

  Future<VectorIndexProbe> probe();

  Future<void> close();
}
