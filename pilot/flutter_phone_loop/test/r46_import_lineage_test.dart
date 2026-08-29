import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/core/chunker.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/import_lineage.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/r45_vector_migration.dart';
import 'package:pocketgallery_phone_pilot/observability/vector_observation_store.dart';
import 'package:pocketgallery_phone_pilot/retrieval/active_vector_index.dart';
import 'package:pocketgallery_phone_pilot/services/document_importer.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_engine.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';
import 'package:pocketgallery_phone_pilot/services/semantic_store.dart';

class NoopActiveVectorIndex implements ActiveVectorIndex {
  bool initialized = false;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<void> add(VectorIndexRecord record) async {}

  @override
  Future<void> remove(String embeddingId) async {}

  @override
  Future<List<VectorSearchHit>> searchByEmbedding({
    required List<double> queryEmbedding,
    required int topK,
    required KnowledgeScope scope,
  }) async =>
      const [];

  @override
  Future<VectorIndexProbe> probe() async => VectorIndexProbe(
        initialized: initialized,
        databasePath: 'memory://r46-import-lineage',
        backendId: 'noop-r46-import-lineage',
        searchVerified: false,
      );

  @override
  Future<void> close() async => initialized = false;
}

class TestSemanticStore extends SemanticStore {
  TestSemanticStore(
    LexicalFtsStore lexicalStore,
    VectorObservationStore observationStore,
  ) : super(lexicalStore, observationStore: observationStore);

  @override
  Future<void> initialize() => observationStore.initialize();
}

void main() {
  test('new markdown import records exact heading and chunk provenance',
      () async {
    final tmp = await Directory.systemTemp.createTemp('pg-r46-md-');
    addTearDown(() => tmp.delete(recursive: true));
    const source =
        '# 端侧测试\n\n第一段内容。第二句。\n\n## 功耗\n\n功耗测试方法。还要记录温度。';
    final file = File('${tmp.path}/a.md');
    await file.writeAsString(source);

    final importer = DocumentImporter(
      chunker: const PgChunker(
        targetChars: 16,
        overlapChars: 4,
        minChunkChars: 6,
      ),
    );
    final result = await importer.importPathWithLineage(file.path);

    expect(result.lineageDocument.provenanceQuality, ProvenanceQuality.exact);
    expect(result.lineageDocument.fileType, 'md');
    expect(result.lineageDocument.parseStatus, ParseStatus.parsed);
    expect(
      result.sections.map((section) => section.heading),
      containsAll(<String?>['端侧测试', '功耗']),
    );
    expect(result.chunks, isNotEmpty);

    final chunksById = <String, PgChunk>{
      for (final chunk in result.document.chunks) chunk.id: chunk,
    };
    for (final lineageChunk in result.chunks) {
      expect(lineageChunk.sectionId, isNotNull);
      expect(lineageChunk.startOffset, isNotNull);
      expect(lineageChunk.endOffset, isNotNull);
      expect(
        lineageChunk.boundaryReason,
        isIn(const <String>{
          'section_end',
          'sentence_punctuation',
          'hard_limit',
        }),
      );
      final chunk = chunksById[lineageChunk.chunkId]!;
      expect(
        source.substring(
          lineageChunk.startOffset!,
          lineageChunk.endOffset!,
        ),
        chunk.text,
        reason: 'exact lineage offsets must resolve to the real source span',
      );
    }
  });

  test('empty text import reports an explicit zero-chunk diagnostic', () async {
    final tmp = await Directory.systemTemp.createTemp('pg-r46-empty-');
    addTearDown(() => tmp.delete(recursive: true));
    final file = File('${tmp.path}/empty.txt');
    await file.writeAsString('');

    final result = await DocumentImporter().importPathWithLineage(file.path);

    expect(result.document.chunks, isEmpty);
    expect(result.chunks, isEmpty);
    expect(result.lineageDocument.parseStatus, ParseStatus.empty);
    expect(result.lineageDocument.parseErrorCode, 'NO_EXTRACTED_TEXT');
    expect(result.lineageDocument.parseErrorDetail, isNotEmpty);
    expect(result.sections, hasLength(1));
    expect(result.sections.single.parseStatus, ParseStatus.empty);
  });

  test('KnowledgeEngine commits lexical and exact lineage before vector work',
      () async {
    final tmp = await Directory.systemTemp.createTemp('pg-r46-engine-');
    addTearDown(() => tmp.delete(recursive: true));
    final file = File('${tmp.path}/notes.txt');
    await file.writeAsString('第一条端侧知识。第二条端侧知识。');

    final lexicalDb = sqlite3.openInMemory();
    final observationDb = sqlite3.openInMemory();
    final lineageDb = sqlite3.openInMemory();
    addTearDown(lexicalDb.close);
    addTearDown(observationDb.close);
    addTearDown(lineageDb.close);

    final lexical = LexicalFtsStore(database: lexicalDb);
    final observations = VectorObservationStore(database: observationDb);
    final lineage = LineageStore(database: lineageDb);
    final semantic = TestSemanticStore(lexical, observations);
    final engine = KnowledgeEngine(
      lexicalStore: lexical,
      semanticStore: semantic,
      lineageStore: lineage,
      activeVectorIndex: NoopActiveVectorIndex(),
    );

    final document = await engine.importPath(file.path);

    expect(await lexical.chunksForDocument(document.documentId), isNotEmpty);
    final storedDocument =
        await lineage.lineageDocumentById(document.documentId);
    expect(storedDocument, isNotNull);
    expect(storedDocument!.provenanceQuality, ProvenanceQuality.exact);
    expect(
      await lineage.lineageSectionsForDocument(document.documentId),
      isNotEmpty,
    );
    expect(
      await lineage.lineageChunksForDocument(document.documentId),
      hasLength(document.chunks.length),
    );

    final job = await lineage.buildJobById(LineageIds.buildJobId(
      document.documentId,
      R45VectorMigration.activeStrategyId,
    ));
    expect(job, isNotNull);
    expect(job!.checkpointJson, contains('lineage_committed'));
    expect(job.status.name, isIn(<String>['pending', 'complete']));
  });
}
