import 'dart:convert';

import '../core/models.dart';
import '../lineage/lineage_ids.dart';
import '../lineage/lineage_models.dart';
import '../lineage/lineage_store.dart';
import '../retrieval/query_embedding_runtime.dart';
import '../services/lexical_fts_store.dart';
import 'retrieval_strategy.dart';

class RepresentationSpan {
  const RepresentationSpan({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;
}

class RepresentationBuildResult {
  const RepresentationBuildResult({
    required this.totalItems,
    required this.completedItems,
    required this.generatedItems,
    required this.reusedItems,
    required this.jobIds,
  });

  final int totalItems;
  final int completedItems;
  final int generatedItems;
  final int reusedItems;
  final List<String> jobIds;
}

class RepresentationBuilder {
  RepresentationBuilder({
    required this.store,
    required this.lexicalStore,
    required this.generator,
    this.modelIdentity = 'EmbeddingGemma-300M_seq256_mixed-precision',
  });

  final LineageStore store;
  final LexicalFtsStore lexicalStore;
  final EmbeddingGenerator generator;
  final String modelIdentity;

  Future<RepresentationBuildResult> build({
    required RetrievalStrategyDescriptor strategy,
    List<PgChunk>? chunks,
  }) async {
    final corpus = chunks ?? await lexicalStore.allChunks();
    final targets = await _targets(strategy, corpus);
    final byDocument = <String, List<_RepresentationTarget>>{};
    for (final target in targets) {
      byDocument.putIfAbsent(target.documentId, () => []).add(target);
    }

    var generated = 0;
    var reused = 0;
    var completed = 0;
    final jobIds = <String>[];
    for (final entry in byDocument.entries) {
      final documentId = entry.key;
      final documentTargets = entry.value;
      final jobId = LineageIds.buildJobId(documentId, strategy.id);
      jobIds.add(jobId);
      final existingJob = await store.buildJobById(jobId);
      final createdAt = existingJob?.createdAt ?? DateTime.now().toUtc();
      final completedIds = <String>[];
      final pending = <_RepresentationTarget>[];
      _RepresentationTarget? mismatchedTarget;
      LineageEmbedding? mismatchedEmbedding;
      for (final target in documentTargets) {
        final existing = await store.embeddingById(target.embeddingId);
        if (existing == null) {
          pending.add(target);
        } else if (existing.modelIdentity != modelIdentity) {
          mismatchedTarget = target;
          mismatchedEmbedding = existing;
          break;
        } else {
          completedIds.add(target.embeddingId);
          reused++;
          completed++;
        }
      }
      if (mismatchedTarget != null && mismatchedEmbedding != null) {
        final detail =
            'model identity mismatch for '
            '${mismatchedTarget.embeddingId}: persisted='
            '${mismatchedEmbedding.modelIdentity}, requested=$modelIdentity';
        await _putJob(
          jobId: jobId,
          strategy: strategy,
          documentId: documentId,
          status: BuildJobStatus.failed,
          total: documentTargets.length,
          completed: completedIds.length,
          completedIds: completedIds,
          currentSource: mismatchedTarget.sourceId,
          failureCode: 'REPRESENTATION_MODEL_MISMATCH',
          failureDetail: detail,
          createdAt: createdAt,
        );
        throw StateError(detail);
      }
      await _putJob(
        jobId: jobId,
        strategy: strategy,
        documentId: documentId,
        status: pending.isEmpty
            ? BuildJobStatus.complete
            : BuildJobStatus.running,
        total: documentTargets.length,
        completed: completedIds.length,
        completedIds: completedIds,
        currentSource: pending.firstOrNull?.sourceId,
        createdAt: createdAt,
      );

      for (final target in pending) {
        try {
          final watch = Stopwatch()..start();
          final vector = await generator.generateDocument(target.text);
          watch.stop();
          await store.putEmbedding(
            LineageEmbedding.fromVector(
              embeddingId: target.embeddingId,
              sourceKind: target.sourceKind,
              sourceId: target.sourceId,
              documentId: target.documentId,
              chunkId: target.chunkId,
              representation: target.representation,
              spanStart: target.spanStart,
              spanEnd: target.spanEnd,
              vector: vector,
              modelIdentity: modelIdentity,
              taskMode: 'retrieval_document',
              generationMs: watch.elapsedMilliseconds,
              generatedAt: DateTime.now().toUtc(),
            ),
          );
          completedIds.add(target.embeddingId);
          generated++;
          completed++;
          await _putJob(
            jobId: jobId,
            strategy: strategy,
            documentId: documentId,
            status: completedIds.length == documentTargets.length
                ? BuildJobStatus.complete
                : BuildJobStatus.running,
            total: documentTargets.length,
            completed: completedIds.length,
            completedIds: completedIds,
            currentSource: target.sourceId,
            createdAt: createdAt,
          );
        } catch (error) {
          await _putJob(
            jobId: jobId,
            strategy: strategy,
            documentId: documentId,
            status: BuildJobStatus.failed,
            total: documentTargets.length,
            completed: completedIds.length,
            completedIds: completedIds,
            currentSource: target.sourceId,
            failureCode: 'REPRESENTATION_BUILD_FAILED',
            failureDetail: error.toString(),
            createdAt: createdAt,
          );
          rethrow;
        }
      }
    }
    return RepresentationBuildResult(
      totalItems: targets.length,
      completedItems: completed,
      generatedItems: generated,
      reusedItems: reused,
      jobIds: List.unmodifiable(jobIds),
    );
  }

  Future<List<_RepresentationTarget>> _targets(
    RetrievalStrategyDescriptor strategy,
    List<PgChunk> chunks,
  ) async {
    final targets = <String, _RepresentationTarget>{};
    if (strategy.representations.contains(EmbeddingRepresentation.heading)) {
      for (final chunk in chunks) {
        final lineageChunk = await store.lineageChunkById(chunk.id);
        final sectionId = lineageChunk?.sectionId;
        if (sectionId == null) continue;
        final section = await store.lineageSectionById(sectionId);
        final heading = section?.heading?.trim() ?? '';
        if (heading.length < 2) continue;
        final id = LineageIds.embeddingId(
          sourceKind: 'section',
          sourceId: sectionId,
          representation: EmbeddingRepresentation.heading,
        );
        targets.putIfAbsent(
          id,
          () => _RepresentationTarget(
            embeddingId: id,
            sourceKind: 'section',
            sourceId: sectionId,
            documentId: chunk.documentId,
            chunkId: chunk.id,
            representation: EmbeddingRepresentation.heading,
            spanStart: null,
            spanEnd: null,
            text: heading,
          ),
        );
      }
    }
    if (strategy.representations.contains(EmbeddingRepresentation.sentence)) {
      final cap = strategy.maxSentenceRepresentationsPerChunk <= 0
          ? 4
          : strategy.maxSentenceRepresentationsPerChunk;
      for (final chunk in chunks) {
        for (final span in sentenceSpans(chunk.text).take(cap)) {
          final id = LineageIds.embeddingId(
            sourceKind: 'chunk_span',
            sourceId: chunk.id,
            representation: EmbeddingRepresentation.sentence,
            spanStart: span.start,
            spanEnd: span.end,
          );
          targets[id] = _RepresentationTarget(
            embeddingId: id,
            sourceKind: 'chunk_span',
            sourceId: chunk.id,
            documentId: chunk.documentId,
            chunkId: chunk.id,
            representation: EmbeddingRepresentation.sentence,
            spanStart: span.start,
            spanEnd: span.end,
            text: span.text,
          );
        }
      }
    }
    return targets.values.toList(growable: false);
  }

  List<RepresentationSpan> sentenceSpans(String text) {
    final spans = <RepresentationSpan>[];
    final expression = RegExp(r'[^。！？!?；;\n]+(?:[。！？!?；;]+|$)');
    for (final match in expression.allMatches(text)) {
      final raw = match.group(0) ?? '';
      final trimmed = raw.trim();
      if (!_meaningful(trimmed)) continue;
      final leading = raw.length - raw.trimLeft().length;
      final trailing = raw.length - raw.trimRight().length;
      spans.add(
        RepresentationSpan(
          start: match.start + leading,
          end: match.end - trailing,
          text: trimmed,
        ),
      );
    }
    if (spans.isEmpty && _meaningful(text.trim())) {
      final leading = text.length - text.trimLeft().length;
      final trailing = text.length - text.trimRight().length;
      spans.add(
        RepresentationSpan(
          start: leading,
          end: text.length - trailing,
          text: text.trim(),
        ),
      );
    }
    return spans;
  }

  bool _meaningful(String text) {
    if (text.length < 8) return false;
    return RegExp(r'[A-Za-z0-9\u3400-\u9fff]').allMatches(text).length >= 6;
  }

  Future<void> _putJob({
    required String jobId,
    required RetrievalStrategyDescriptor strategy,
    required String documentId,
    required BuildJobStatus status,
    required int total,
    required int completed,
    required List<String> completedIds,
    required String? currentSource,
    required DateTime createdAt,
    String? failureCode,
    String? failureDetail,
  }) async {
    await store.putBuildJob(
      BuildJobRecord(
        jobId: jobId,
        jobType:
            strategy.representations.contains(EmbeddingRepresentation.sentence)
            ? 'sentence-build'
            : 'heading-build',
        strategyId: strategy.id,
        documentId: documentId,
        status: status,
        totalItems: total,
        completedItems: completed,
        checkpointJson: jsonEncode(<String, Object>{
          'completedEmbeddingIds': completedIds,
        }),
        currentSource: currentSource,
        failureCode: failureCode,
        failureDetail: failureDetail,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

class _RepresentationTarget {
  const _RepresentationTarget({
    required this.embeddingId,
    required this.sourceKind,
    required this.sourceId,
    required this.documentId,
    required this.chunkId,
    required this.representation,
    required this.spanStart,
    required this.spanEnd,
    required this.text,
  });

  final String embeddingId;
  final String sourceKind;
  final String sourceId;
  final String documentId;
  final String chunkId;
  final EmbeddingRepresentation representation;
  final int? spanStart;
  final int? spanEnd;
  final String text;
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
