import 'dart:collection';

import 'import_lineage.dart';
import 'lineage_ids.dart';
import 'lineage_models.dart';
import 'lineage_store.dart';

class TraceSnapshot {
  TraceSnapshot._({
    required this.trace,
    required List<TraceEventRecord> events,
    required List<CandidateRecord> candidates,
    required this.activeRouter,
    required List<EvidenceRecord> evidence,
    required this.budget,
    required this.generation,
    required List<CitationRecord> citations,
    required this.queryEmbedding,
    required Map<String, LineageChunkRecord> chunksById,
    required Map<String, LineageSectionRecord> sectionsById,
    required Map<String, LineageDocumentRecord> documentsById,
    required List<ExperimentRunRecord> experimentRuns,
  })  : events = List<TraceEventRecord>.unmodifiable(events),
        candidates = List<CandidateRecord>.unmodifiable(candidates),
        evidence = List<EvidenceRecord>.unmodifiable(evidence),
        citations = List<CitationRecord>.unmodifiable(citations),
        chunksById = UnmodifiableMapView<String, LineageChunkRecord>(
          Map<String, LineageChunkRecord>.from(chunksById),
        ),
        sectionsById = UnmodifiableMapView<String, LineageSectionRecord>(
          Map<String, LineageSectionRecord>.from(sectionsById),
        ),
        documentsById = UnmodifiableMapView<String, LineageDocumentRecord>(
          Map<String, LineageDocumentRecord>.from(documentsById),
        ),
        experimentRuns = List<ExperimentRunRecord>.unmodifiable(
          experimentRuns,
        );

  final LineageTrace trace;
  final List<TraceEventRecord> events;
  final List<CandidateRecord> candidates;
  final RouterDecisionRecord? activeRouter;
  final List<EvidenceRecord> evidence;
  final PromptBudgetRecord? budget;
  final GenerationStatsRecord? generation;
  final List<CitationRecord> citations;
  final LineageEmbedding? queryEmbedding;
  final Map<String, LineageChunkRecord> chunksById;
  final Map<String, LineageSectionRecord> sectionsById;
  final Map<String, LineageDocumentRecord> documentsById;
  final List<ExperimentRunRecord> experimentRuns;

  List<CandidateRecord> candidatesFor({
    required String strategyId,
    required RetrievalLane lane,
  }) =>
      candidates
          .where(
            (record) =>
                record.strategyId == strategyId && record.lane == lane,
          )
          .toList(growable: false);

  List<EvidenceRecord> evidenceFor({
    required String strategyId,
    required RetrievalLane lane,
  }) =>
      evidence
          .where(
            (record) =>
                record.strategyId == strategyId && record.lane == lane,
          )
          .toList(growable: false);

  static Future<TraceSnapshot> load(
    LineageStore store,
    String traceId,
  ) async {
    final trace = await store.traceById(traceId);
    if (trace == null) throw StateError('Unknown lineage trace: $traceId');
    final events = await store.eventsForTrace(traceId);
    final candidates = await store.candidatesForTrace(traceId);
    final evidence = await store.evidenceForTrace(traceId);
    final citations = await store.citationsForTrace(traceId);
    final chunkIds = <String>{
      for (final record in candidates) record.chunkId,
      for (final record in evidence) record.chunkId,
      for (final record in citations)
        if (record.chunkId != null) record.chunkId!,
    };
    final chunks = <String, LineageChunkRecord>{};
    for (final chunkId in chunkIds) {
      final chunk = await store.lineageChunkById(chunkId);
      if (chunk != null) chunks[chunkId] = chunk;
    }
    final sectionIds = <String>{
      for (final chunk in chunks.values)
        if (chunk.sectionId != null) chunk.sectionId!,
      for (final citation in citations)
        if (citation.sectionId != null) citation.sectionId!,
    };
    final sections = <String, LineageSectionRecord>{};
    for (final sectionId in sectionIds) {
      final section = await store.lineageSectionById(sectionId);
      if (section != null) sections[sectionId] = section;
    }
    final documentIds = <String>{
      for (final chunk in chunks.values) chunk.documentId,
      for (final citation in citations)
        if (citation.documentId != null) citation.documentId!,
    };
    final documents = <String, LineageDocumentRecord>{};
    for (final documentId in documentIds) {
      final document = await store.lineageDocumentById(documentId);
      if (document != null) documents[documentId] = document;
    }
    return TraceSnapshot._(
      trace: trace,
      events: events,
      candidates: candidates,
      activeRouter: await store.routerDecisionForTrace(
        traceId,
        trace.activeStrategyId,
        RetrievalLane.active,
      ),
      evidence: evidence,
      budget: await store.promptBudgetForTrace(traceId),
      generation: await store.generationStatsForTrace(traceId),
      citations: citations,
      queryEmbedding: await store.embeddingById(
        LineageIds.queryEmbeddingId(traceId),
      ),
      chunksById: chunks,
      sectionsById: sections,
      documentsById: documents,
      experimentRuns: await store.experimentRunsForTrace(traceId),
    );
  }
}
