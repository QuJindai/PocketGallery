import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'import_lineage.dart';
import 'lineage_models.dart';

class VectorIndexEntryRecord {
  const VectorIndexEntryRecord({
    required this.indexEntryId,
    required this.embeddingId,
    required this.backendId,
    required this.strategyId,
    required this.lane,
    required this.commitStatus,
    required this.committedAt,
    required this.failureCode,
    required this.failureDetail,
  });

  final String indexEntryId;
  final String embeddingId;
  final String backendId;
  final String strategyId;
  final RetrievalLane lane;
  final VectorCommitStatus commitStatus;
  final DateTime? committedAt;
  final String? failureCode;
  final String? failureDetail;
}

class LineageStore {
  LineageStore({Database? database})
      : _db = database,
        _ownsDatabase = database == null;

  Database? _db;
  final bool _ownsDatabase;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (_db == null) {
      final dir = await getApplicationDocumentsDirectory();
      _db = sqlite3.open(p.join(dir.path, 'pocketgallery_lineage.db'));
    }
    final db = _db!;
    db.execute('PRAGMA foreign_keys=ON;');
    db.execute('PRAGMA journal_mode=WAL;');

    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_lineage_documents (
        document_id TEXT PRIMARY KEY,
        source_name TEXT NOT NULL,
        sha256 TEXT NOT NULL,
        file_type TEXT NOT NULL,
        size_bytes INTEGER,
        page_count INTEGER,
        parse_status TEXT NOT NULL,
        parse_error_code TEXT,
        parse_error_detail TEXT,
        extracted_char_count INTEGER NOT NULL DEFAULT 0,
        empty_page_count INTEGER NOT NULL DEFAULT 0,
        provenance_quality TEXT NOT NULL,
        imported_at TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_lineage_sections (
        section_id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        page_no INTEGER,
        heading TEXT,
        section_type TEXT NOT NULL,
        start_offset INTEGER,
        end_offset INTEGER,
        char_count INTEGER NOT NULL,
        parse_status TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_lineage_chunks (
        chunk_id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        section_id TEXT,
        locator TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        start_offset INTEGER,
        end_offset INTEGER,
        char_count INTEGER NOT NULL,
        token_count INTEGER,
        overlap_from_previous INTEGER NOT NULL DEFAULT 0,
        chunk_strategy TEXT NOT NULL,
        boundary_reason TEXT,
        provenance_quality TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_embeddings (
        embedding_id TEXT PRIMARY KEY,
        source_kind TEXT NOT NULL,
        source_id TEXT NOT NULL,
        document_id TEXT,
        chunk_id TEXT,
        representation_type TEXT NOT NULL,
        span_start INTEGER,
        span_end INTEGER,
        model_identity TEXT NOT NULL,
        task_mode TEXT NOT NULL,
        dimension INTEGER NOT NULL,
        norm REAL NOT NULL,
        vector_f32 BLOB NOT NULL,
        vector_sha256 TEXT NOT NULL,
        generation_ms INTEGER NOT NULL,
        generated_at TEXT NOT NULL,
        truth_kind TEXT NOT NULL DEFAULT 'REAL'
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_vector_index_entries (
        index_entry_id TEXT PRIMARY KEY,
        embedding_id TEXT NOT NULL,
        backend_id TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        lane TEXT NOT NULL,
        commit_status TEXT NOT NULL,
        committed_at TEXT,
        failure_code TEXT,
        failure_detail TEXT,
        UNIQUE(embedding_id, backend_id, strategy_id, lane)
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_traces (
        trace_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        turn_id TEXT NOT NULL,
        query_text TEXT NOT NULL,
        requested_mode TEXT NOT NULL,
        final_mode TEXT NOT NULL,
        scope_json TEXT NOT NULL,
        active_strategy_id TEXT NOT NULL,
        started_at TEXT NOT NULL,
        completed_at TEXT,
        status TEXT NOT NULL,
        failure_stage TEXT,
        failure_code TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_trace_events (
        event_id TEXT PRIMARY KEY,
        trace_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        stage TEXT NOT NULL,
        kind TEXT NOT NULL,
        truth_kind TEXT NOT NULL,
        lane TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        timestamp_us INTEGER NOT NULL,
        duration_us INTEGER,
        payload_json TEXT NOT NULL,
        UNIQUE(trace_id, seq),
        FOREIGN KEY(trace_id) REFERENCES pg_traces(trace_id) ON DELETE CASCADE
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_candidates (
        candidate_id TEXT PRIMARY KEY,
        trace_id TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        lane TEXT NOT NULL,
        chunk_id TEXT NOT NULL,
        embedding_id TEXT,
        source_channels TEXT NOT NULL,
        fts_rank INTEGER,
        raw_bm25 REAL,
        vector_rank INTEGER,
        raw_cosine REAL,
        fusion_rank INTEGER,
        fusion_score REAL,
        rerank_rank INTEGER,
        rerank_score REAL,
        final_rank INTEGER,
        selected_for_evidence INTEGER NOT NULL DEFAULT 0,
        drop_reason TEXT,
        FOREIGN KEY(trace_id) REFERENCES pg_traces(trace_id) ON DELETE CASCADE
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_router_decisions (
        decision_id TEXT PRIMARY KEY,
        trace_id TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        lane TEXT NOT NULL,
        fts_hit_count INTEGER NOT NULL,
        top1_cosine REAL,
        top2_cosine REAL,
        top1_top2_gap REAL,
        dual_channel INTEGER NOT NULL,
        lexical_gate_pass INTEGER NOT NULL,
        semantic_strength_gate_pass INTEGER NOT NULL,
        semantic_gap_gate_pass INTEGER NOT NULL,
        final_use_knowledge INTEGER NOT NULL,
        rule_profile TEXT NOT NULL,
        decision_reason TEXT NOT NULL,
        UNIQUE(trace_id, strategy_id, lane),
        FOREIGN KEY(trace_id) REFERENCES pg_traces(trace_id) ON DELETE CASCADE
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_evidence (
        evidence_id TEXT PRIMARY KEY,
        trace_id TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        lane TEXT NOT NULL,
        anchor TEXT,
        candidate_id TEXT NOT NULL,
        chunk_id TEXT NOT NULL,
        selection_rank INTEGER NOT NULL,
        score REAL NOT NULL,
        token_count INTEGER NOT NULL,
        selection_reason TEXT NOT NULL,
        FOREIGN KEY(trace_id) REFERENCES pg_traces(trace_id) ON DELETE CASCADE
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_prompt_budgets (
        trace_id TEXT PRIMARY KEY,
        strategy_id TEXT NOT NULL,
        lane TEXT NOT NULL,
        model_context_limit INTEGER NOT NULL,
        system_tokens INTEGER NOT NULL,
        history_tokens INTEGER NOT NULL,
        evidence_tokens INTEGER NOT NULL,
        query_tokens INTEGER NOT NULL,
        output_reserve_tokens INTEGER NOT NULL,
        total_prefill_tokens INTEGER NOT NULL,
        remaining_tokens INTEGER NOT NULL,
        trimmed_history_messages INTEGER NOT NULL,
        trimmed_evidence_items INTEGER NOT NULL,
        trim_detail_json TEXT NOT NULL,
        FOREIGN KEY(trace_id) REFERENCES pg_traces(trace_id) ON DELETE CASCADE
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_generation_stats (
        trace_id TEXT PRIMARY KEY,
        strategy_id TEXT NOT NULL,
        lane TEXT NOT NULL,
        ttft_ms INTEGER,
        generation_ms INTEGER NOT NULL,
        output_tokens INTEGER,
        decode_tokens_per_second REAL,
        backend TEXT,
        native_session_rebuilt INTEGER NOT NULL,
        session_reset_reason TEXT,
        FOREIGN KEY(trace_id) REFERENCES pg_traces(trace_id) ON DELETE CASCADE
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_citations (
        citation_id TEXT PRIMARY KEY,
        trace_id TEXT NOT NULL,
        anchor TEXT NOT NULL,
        evidence_id TEXT,
        chunk_id TEXT,
        document_id TEXT,
        section_id TEXT,
        page_no INTEGER,
        citation_status TEXT NOT NULL,
        FOREIGN KEY(trace_id) REFERENCES pg_traces(trace_id) ON DELETE CASCADE
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_experiment_runs (
        experiment_run_id TEXT PRIMARY KEY,
        trace_id TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        lane TEXT NOT NULL,
        status TEXT NOT NULL,
        started_at TEXT NOT NULL,
        completed_at TEXT,
        completed_items INTEGER NOT NULL DEFAULT 0,
        total_items INTEGER NOT NULL DEFAULT 0,
        metric_json TEXT,
        failure_code TEXT,
        FOREIGN KEY(trace_id) REFERENCES pg_traces(trace_id) ON DELETE CASCADE
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_build_jobs (
        job_id TEXT PRIMARY KEY,
        job_type TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        document_id TEXT,
        status TEXT NOT NULL,
        total_items INTEGER NOT NULL,
        completed_items INTEGER NOT NULL,
        checkpoint_json TEXT NOT NULL,
        current_source TEXT,
        failure_code TEXT,
        failure_detail TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    db.execute('CREATE INDEX IF NOT EXISTS pg_trace_events_trace_seq ON pg_trace_events(trace_id, seq);');
    db.execute('CREATE INDEX IF NOT EXISTS pg_embeddings_chunk_representation ON pg_embeddings(chunk_id, representation_type);');
    db.execute('CREATE INDEX IF NOT EXISTS pg_candidates_trace_lane_strategy ON pg_candidates(trace_id, lane, strategy_id);');
    db.execute('CREATE INDEX IF NOT EXISTS pg_build_jobs_document_status ON pg_build_jobs(document_id, status);');
    db.execute('CREATE INDEX IF NOT EXISTS pg_vector_index_entries_embedding ON pg_vector_index_entries(embedding_id, strategy_id, lane);');
    _ensureColumn(
      db,
      'pg_experiment_runs',
      'completed_items',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _ensureColumn(
      db,
      'pg_experiment_runs',
      'total_items',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _initialized = true;
  }

  void _ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) {
    final columns = db
        .select('PRAGMA table_info($table)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!columns.contains(column)) {
      db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<T> runInTransaction<T>(Future<T> Function() operation) async {
    await initialize();
    final db = _db!;
    db.execute('BEGIN IMMEDIATE;');
    try {
      final result = await operation();
      db.execute('COMMIT;');
      return result;
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> upsertLineageDocument({
    required String documentId,
    required String sourceName,
    required String sha256,
    required String fileType,
    int? sizeBytes,
    int? pageCount,
    required String parseStatus,
    String? parseErrorCode,
    String? parseErrorDetail,
    required int extractedCharCount,
    required int emptyPageCount,
    required String provenanceQuality,
    required DateTime importedAt,
  }) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_lineage_documents (
        document_id, source_name, sha256, file_type, size_bytes, page_count,
        parse_status, parse_error_code, parse_error_detail, extracted_char_count,
        empty_page_count, provenance_quality, imported_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(document_id) DO UPDATE SET
        source_name = excluded.source_name,
        sha256 = excluded.sha256,
        file_type = excluded.file_type,
        size_bytes = COALESCE(excluded.size_bytes, pg_lineage_documents.size_bytes),
        page_count = COALESCE(excluded.page_count, pg_lineage_documents.page_count),
        parse_status = excluded.parse_status,
        parse_error_code = excluded.parse_error_code,
        parse_error_detail = excluded.parse_error_detail,
        extracted_char_count = excluded.extracted_char_count,
        empty_page_count = excluded.empty_page_count,
        provenance_quality = excluded.provenance_quality
    ''', [
      documentId,
      sourceName,
      sha256,
      fileType,
      sizeBytes,
      pageCount,
      parseStatus,
      parseErrorCode,
      parseErrorDetail,
      extractedCharCount,
      emptyPageCount,
      provenanceQuality,
      importedAt.toUtc().toIso8601String(),
    ]);
  }

  Future<void> upsertLineageSection({
    required String sectionId,
    required String documentId,
    int? pageNo,
    String? heading,
    required String sectionType,
    int? startOffset,
    int? endOffset,
    required int charCount,
    required String parseStatus,
  }) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_lineage_sections (
        section_id, document_id, page_no, heading, section_type, start_offset,
        end_offset, char_count, parse_status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(section_id) DO UPDATE SET
        document_id = excluded.document_id,
        page_no = excluded.page_no,
        heading = excluded.heading,
        section_type = excluded.section_type,
        start_offset = excluded.start_offset,
        end_offset = excluded.end_offset,
        char_count = excluded.char_count,
        parse_status = excluded.parse_status
    ''', [
      sectionId,
      documentId,
      pageNo,
      heading,
      sectionType,
      startOffset,
      endOffset,
      charCount,
      parseStatus,
    ]);
  }

  Future<void> upsertLineageChunk({
    required String chunkId,
    required String documentId,
    String? sectionId,
    required String locator,
    required int ordinal,
    int? startOffset,
    int? endOffset,
    required int charCount,
    int? tokenCount,
    required int overlapFromPrevious,
    required String chunkStrategy,
    String? boundaryReason,
    required String provenanceQuality,
  }) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_lineage_chunks (
        chunk_id, document_id, section_id, locator, ordinal, start_offset,
        end_offset, char_count, token_count, overlap_from_previous,
        chunk_strategy, boundary_reason, provenance_quality
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(chunk_id) DO UPDATE SET
        document_id = excluded.document_id,
        section_id = COALESCE(excluded.section_id, pg_lineage_chunks.section_id),
        locator = excluded.locator,
        ordinal = excluded.ordinal,
        start_offset = COALESCE(excluded.start_offset, pg_lineage_chunks.start_offset),
        end_offset = COALESCE(excluded.end_offset, pg_lineage_chunks.end_offset),
        char_count = excluded.char_count,
        token_count = COALESCE(excluded.token_count, pg_lineage_chunks.token_count),
        overlap_from_previous = excluded.overlap_from_previous,
        chunk_strategy = excluded.chunk_strategy,
        boundary_reason = COALESCE(excluded.boundary_reason, pg_lineage_chunks.boundary_reason),
        provenance_quality = excluded.provenance_quality
    ''', [
      chunkId,
      documentId,
      sectionId,
      locator,
      ordinal,
      startOffset,
      endOffset,
      charCount,
      tokenCount,
      overlapFromPrevious,
      chunkStrategy,
      boundaryReason,
      provenanceQuality,
    ]);
  }

  Future<void> replaceImportLineage(LineageImportResult result) async {
    await initialize();
    final db = _db!;
    db.execute('BEGIN IMMEDIATE;');
    try {
      final document = result.lineageDocument;
      await upsertLineageDocument(
        documentId: document.documentId,
        sourceName: document.sourceName,
        sha256: document.sha256,
        fileType: document.fileType,
        sizeBytes: document.sizeBytes,
        pageCount: document.pageCount,
        parseStatus: document.parseStatus.dbValue,
        parseErrorCode: document.parseErrorCode,
        parseErrorDetail: document.parseErrorDetail,
        extractedCharCount: document.extractedCharCount,
        emptyPageCount: document.emptyPageCount,
        provenanceQuality: document.provenanceQuality.name,
        importedAt: document.importedAt,
      );
      db.execute(
        'DELETE FROM pg_lineage_sections WHERE document_id = ?',
        [document.documentId],
      );
      db.execute(
        'DELETE FROM pg_lineage_chunks WHERE document_id = ?',
        [document.documentId],
      );
      for (final section in result.sections) {
        await upsertLineageSection(
          sectionId: section.sectionId,
          documentId: section.documentId,
          pageNo: section.pageNo,
          heading: section.heading,
          sectionType: section.sectionType,
          startOffset: section.startOffset,
          endOffset: section.endOffset,
          charCount: section.charCount,
          parseStatus: section.parseStatus.dbValue,
        );
      }
      for (final chunk in result.chunks) {
        await upsertLineageChunk(
          chunkId: chunk.chunkId,
          documentId: chunk.documentId,
          sectionId: chunk.sectionId,
          locator: chunk.locator,
          ordinal: chunk.ordinal,
          startOffset: chunk.startOffset,
          endOffset: chunk.endOffset,
          charCount: chunk.charCount,
          tokenCount: chunk.tokenCount,
          overlapFromPrevious: chunk.overlapFromPrevious,
          chunkStrategy: chunk.chunkStrategy,
          boundaryReason: chunk.boundaryReason,
          provenanceQuality: chunk.provenanceQuality.name,
        );
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<LineageDocumentRecord?> lineageDocumentById(
    String documentId,
  ) async {
    await initialize();
    final rows = _db!.select(
      'SELECT * FROM pg_lineage_documents WHERE document_id = ? LIMIT 1',
      [documentId],
    );
    return rows.isEmpty ? null : _lineageDocumentFromRow(rows.first);
  }

  Future<List<LineageSectionRecord>> lineageSectionsForDocument(
    String documentId,
  ) async {
    await initialize();
    return _db!
        .select('''
          SELECT * FROM pg_lineage_sections
          WHERE document_id = ? ORDER BY COALESCE(page_no, 0), start_offset, section_id
        ''', [documentId])
        .map(_lineageSectionFromRow)
        .toList(growable: false);
  }

  Future<LineageSectionRecord?> lineageSectionById(String sectionId) async {
    await initialize();
    final rows = _db!.select(
      'SELECT * FROM pg_lineage_sections WHERE section_id = ? LIMIT 1',
      [sectionId],
    );
    return rows.isEmpty ? null : _lineageSectionFromRow(rows.first);
  }

  Future<List<LineageChunkRecord>> lineageChunksForDocument(
    String documentId,
  ) async {
    await initialize();
    return _db!
        .select('''
          SELECT * FROM pg_lineage_chunks
          WHERE document_id = ? ORDER BY ordinal, chunk_id
        ''', [documentId])
        .map(_lineageChunkFromRow)
        .toList(growable: false);
  }

  Future<LineageChunkRecord?> lineageChunkById(String chunkId) async {
    await initialize();
    final rows = _db!.select(
      'SELECT * FROM pg_lineage_chunks WHERE chunk_id = ? LIMIT 1',
      [chunkId],
    );
    return rows.isEmpty ? null : _lineageChunkFromRow(rows.first);
  }

  Future<void> putEmbedding(LineageEmbedding embedding) async {
    await initialize();
    embedding.validate();
    final existing = _db!.select(
      'SELECT vector_sha256 FROM pg_embeddings WHERE embedding_id = ? LIMIT 1',
      [embedding.embeddingId],
    );
    if (existing.isNotEmpty) {
      final sha = existing.first['vector_sha256'] as String;
      if (sha != embedding.vectorSha256) {
        throw StateError('Embedding identity collision: ${embedding.embeddingId} already has a different vector');
      }
      return;
    }
    _db!.execute('''
      INSERT INTO pg_embeddings (
        embedding_id, source_kind, source_id, document_id, chunk_id,
        representation_type, span_start, span_end, model_identity, task_mode,
        dimension, norm, vector_f32, vector_sha256, generation_ms, generated_at,
        truth_kind
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      embedding.embeddingId,
      embedding.sourceKind,
      embedding.sourceId,
      embedding.documentId,
      embedding.chunkId,
      embedding.representation.name,
      embedding.spanStart,
      embedding.spanEnd,
      embedding.modelIdentity,
      embedding.taskMode,
      embedding.dimension,
      embedding.norm,
      embedding.vectorF32,
      embedding.vectorSha256,
      embedding.generationMs,
      embedding.generatedAt.toUtc().toIso8601String(),
      embedding.truthKind.dbValue,
    ]);
  }

  Future<LineageEmbedding?> embeddingById(String embeddingId) async {
    await initialize();
    final rows = _db!.select('SELECT * FROM pg_embeddings WHERE embedding_id = ? LIMIT 1', [embeddingId]);
    return rows.isEmpty ? null : _embeddingFromRow(rows.first);
  }

  Future<List<LineageEmbedding>> embeddingsForChunk(String chunkId) async {
    await initialize();
    return _db!
        .select('SELECT * FROM pg_embeddings WHERE chunk_id = ? ORDER BY representation_type, embedding_id', [chunkId])
        .map(_embeddingFromRow)
        .toList(growable: false);
  }

  Future<List<LineageEmbedding>> embeddingsForRepresentation(
    EmbeddingRepresentation representation,
  ) async {
    await initialize();
    return _db!
        .select('''
          SELECT * FROM pg_embeddings
          WHERE source_kind = 'chunk' AND representation_type = ?
          ORDER BY COALESCE(document_id, ''), source_id, embedding_id
        ''', [representation.name])
        .map(_embeddingFromRow)
        .toList(growable: false);
  }

  Future<void> putVectorIndexEntry(VectorIndexEntryRecord record) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_vector_index_entries (
        index_entry_id, embedding_id, backend_id, strategy_id, lane,
        commit_status, committed_at, failure_code, failure_detail
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(embedding_id, backend_id, strategy_id, lane) DO UPDATE SET
        index_entry_id = excluded.index_entry_id,
        commit_status = excluded.commit_status,
        committed_at = excluded.committed_at,
        failure_code = excluded.failure_code,
        failure_detail = excluded.failure_detail
    ''', [
      record.indexEntryId,
      record.embeddingId,
      record.backendId,
      record.strategyId,
      record.lane.dbValue,
      record.commitStatus.name,
      record.committedAt?.toUtc().toIso8601String(),
      record.failureCode,
      record.failureDetail,
    ]);
  }

  Future<VectorIndexEntryRecord?> vectorIndexEntryForEmbedding(
    String embeddingId,
    String strategyId,
    RetrievalLane lane,
  ) async {
    await initialize();
    final rows = _db!.select('''
      SELECT * FROM pg_vector_index_entries
      WHERE embedding_id = ? AND strategy_id = ? AND lane = ?
      ORDER BY index_entry_id
      LIMIT 1
    ''', [embeddingId, strategyId, lane.dbValue]);
    return rows.isEmpty ? null : _vectorEntryFromRow(rows.first);
  }

  Future<void> putTrace(LineageTrace trace) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_traces (
        trace_id, session_id, turn_id, query_text, requested_mode, final_mode,
        scope_json, active_strategy_id, started_at, completed_at, status,
        failure_stage, failure_code
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(trace_id) DO UPDATE SET
        final_mode = excluded.final_mode,
        completed_at = excluded.completed_at,
        status = excluded.status,
        failure_stage = excluded.failure_stage,
        failure_code = excluded.failure_code
    ''', [
      trace.traceId,
      trace.sessionId,
      trace.turnId,
      trace.queryText,
      trace.requestedMode,
      trace.finalMode,
      trace.scopeJson,
      trace.activeStrategyId,
      trace.startedAt.toUtc().toIso8601String(),
      trace.completedAt?.toUtc().toIso8601String(),
      trace.status.name,
      trace.failureStage,
      trace.failureCode,
    ]);
  }

  Future<LineageTrace?> traceById(String traceId) async {
    await initialize();
    final rows = _db!.select('SELECT * FROM pg_traces WHERE trace_id = ? LIMIT 1', [traceId]);
    return rows.isEmpty ? null : _traceFromRow(rows.first);
  }

  Future<List<LineageTrace>> latestTraces({int limit = 200}) async {
    await initialize();
    final safeLimit = limit.clamp(1, 1000).toInt();
    return _db!
        .select('SELECT * FROM pg_traces ORDER BY COALESCE(completed_at, started_at) DESC, trace_id DESC LIMIT ?', [safeLimit])
        .map(_traceFromRow)
        .toList(growable: false);
  }

  Future<void> appendEvent(TraceEventRecord event) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_trace_events (
        event_id, trace_id, seq, stage, kind, truth_kind, lane, strategy_id,
        timestamp_us, duration_us, payload_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      event.eventId,
      event.traceId,
      event.seq,
      event.stage,
      event.kind,
      event.truthKind.dbValue,
      event.lane.dbValue,
      event.strategyId,
      event.timestampUs,
      event.durationUs,
      event.payloadJson,
    ]);
  }

  Future<List<TraceEventRecord>> eventsForTrace(String traceId) async {
    await initialize();
    return _db!
        .select('SELECT * FROM pg_trace_events WHERE trace_id = ? ORDER BY seq ASC', [traceId])
        .map(_eventFromRow)
        .toList(growable: false);
  }

  Future<void> putCandidate(CandidateRecord record) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_candidates (
        candidate_id, trace_id, strategy_id, lane, chunk_id, embedding_id,
        source_channels, fts_rank, raw_bm25, vector_rank, raw_cosine,
        fusion_rank, fusion_score, rerank_rank, rerank_score, final_rank,
        selected_for_evidence, drop_reason
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(candidate_id) DO UPDATE SET
        embedding_id = excluded.embedding_id,
        source_channels = excluded.source_channels,
        fts_rank = excluded.fts_rank,
        raw_bm25 = excluded.raw_bm25,
        vector_rank = excluded.vector_rank,
        raw_cosine = excluded.raw_cosine,
        fusion_rank = excluded.fusion_rank,
        fusion_score = excluded.fusion_score,
        rerank_rank = excluded.rerank_rank,
        rerank_score = excluded.rerank_score,
        final_rank = excluded.final_rank,
        selected_for_evidence = excluded.selected_for_evidence,
        drop_reason = excluded.drop_reason
    ''', [
      record.candidateId,
      record.traceId,
      record.strategyId,
      record.lane.dbValue,
      record.chunkId,
      record.embeddingId,
      record.sourceChannels,
      record.ftsRank,
      record.rawBm25,
      record.vectorRank,
      record.rawCosine,
      record.fusionRank,
      record.fusionScore,
      record.rerankRank,
      record.rerankScore,
      record.finalRank,
      _boolInt(record.selectedForEvidence),
      record.dropReason,
    ]);
  }

  Future<List<CandidateRecord>> candidatesForTrace(
    String traceId, {
    String? strategyId,
    RetrievalLane? lane,
  }) async {
    await initialize();
    final predicates = <String>['trace_id = ?'];
    final parameters = <Object?>[traceId];
    if (strategyId != null) {
      predicates.add('strategy_id = ?');
      parameters.add(strategyId);
    }
    if (lane != null) {
      predicates.add('lane = ?');
      parameters.add(lane.dbValue);
    }
    return _db!
        .select('''
          SELECT * FROM pg_candidates
          WHERE ${predicates.join(' AND ')}
          ORDER BY COALESCE(final_rank, fusion_rank, vector_rank, fts_rank, 2147483647), candidate_id
        ''', parameters)
        .map(_candidateFromRow)
        .toList(growable: false);
  }

  Future<void> putRouterDecision(RouterDecisionRecord record) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_router_decisions (
        decision_id, trace_id, strategy_id, lane, fts_hit_count, top1_cosine,
        top2_cosine, top1_top2_gap, dual_channel, lexical_gate_pass,
        semantic_strength_gate_pass, semantic_gap_gate_pass,
        final_use_knowledge, rule_profile, decision_reason
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(trace_id, strategy_id, lane) DO UPDATE SET
        fts_hit_count = excluded.fts_hit_count,
        top1_cosine = excluded.top1_cosine,
        top2_cosine = excluded.top2_cosine,
        top1_top2_gap = excluded.top1_top2_gap,
        dual_channel = excluded.dual_channel,
        lexical_gate_pass = excluded.lexical_gate_pass,
        semantic_strength_gate_pass = excluded.semantic_strength_gate_pass,
        semantic_gap_gate_pass = excluded.semantic_gap_gate_pass,
        final_use_knowledge = excluded.final_use_knowledge,
        rule_profile = excluded.rule_profile,
        decision_reason = excluded.decision_reason
    ''', [
      record.decisionId,
      record.traceId,
      record.strategyId,
      record.lane.dbValue,
      record.ftsHitCount,
      record.top1Cosine,
      record.top2Cosine,
      record.top1Top2Gap,
      _boolInt(record.dualChannel),
      _boolInt(record.lexicalGatePass),
      _boolInt(record.semanticStrengthGatePass),
      _boolInt(record.semanticGapGatePass),
      _boolInt(record.finalUseKnowledge),
      record.ruleProfile,
      record.decisionReason,
    ]);
  }

  Future<RouterDecisionRecord?> routerDecisionForTrace(
    String traceId,
    String strategyId,
    RetrievalLane lane,
  ) async {
    await initialize();
    final rows = _db!.select('''
      SELECT * FROM pg_router_decisions
      WHERE trace_id = ? AND strategy_id = ? AND lane = ? LIMIT 1
    ''', [traceId, strategyId, lane.dbValue]);
    return rows.isEmpty ? null : _routerFromRow(rows.first);
  }

  Future<void> putEvidence(EvidenceRecord record) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_evidence (
        evidence_id, trace_id, strategy_id, lane, anchor, candidate_id,
        chunk_id, selection_rank, score, token_count, selection_reason
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(evidence_id) DO UPDATE SET
        anchor = excluded.anchor,
        selection_rank = excluded.selection_rank,
        score = excluded.score,
        token_count = excluded.token_count,
        selection_reason = excluded.selection_reason
    ''', [
      record.evidenceId,
      record.traceId,
      record.strategyId,
      record.lane.dbValue,
      record.anchor,
      record.candidateId,
      record.chunkId,
      record.selectionRank,
      record.score,
      record.tokenCount,
      record.selectionReason,
    ]);
  }

  Future<List<EvidenceRecord>> evidenceForTrace(
    String traceId, {
    String? strategyId,
    RetrievalLane? lane,
  }) async {
    await initialize();
    final predicates = <String>['trace_id = ?'];
    final parameters = <Object?>[traceId];
    if (strategyId != null) {
      predicates.add('strategy_id = ?');
      parameters.add(strategyId);
    }
    if (lane != null) {
      predicates.add('lane = ?');
      parameters.add(lane.dbValue);
    }
    return _db!
        .select('''
          SELECT * FROM pg_evidence
          WHERE ${predicates.join(' AND ')}
          ORDER BY selection_rank, evidence_id
        ''', parameters)
        .map(_evidenceFromRow)
        .toList(growable: false);
  }

  Future<void> updateEvidenceTokenCounts({
    required String traceId,
    required String strategyId,
    required RetrievalLane lane,
    required Map<String, int> tokenCountsByAnchor,
  }) async {
    await initialize();
    final rows = _db!.select('''
      SELECT evidence_id, anchor, selection_reason FROM pg_evidence
      WHERE trace_id = ? AND strategy_id = ? AND lane = ?
    ''', [traceId, strategyId, lane.dbValue]);
    for (final row in rows) {
      final anchor = row['anchor'] as String?;
      final allocated = anchor == null ? null : tokenCountsByAnchor[anchor];
      final marker = allocated == null
          ? 'context_trimmed'
          : 'context_token_allocation';
      final currentReason = row['selection_reason'] as String;
      final reason = currentReason.contains(marker)
          ? currentReason
          : '$currentReason;$marker';
      _db!.execute('''
        UPDATE pg_evidence
        SET token_count = ?, selection_reason = ?
        WHERE evidence_id = ?
      ''', [allocated ?? 0, reason, row['evidence_id']]);
    }
  }

  Future<void> putPromptBudget(PromptBudgetRecord record) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_prompt_budgets (
        trace_id, strategy_id, lane, model_context_limit, system_tokens,
        history_tokens, evidence_tokens, query_tokens, output_reserve_tokens,
        total_prefill_tokens, remaining_tokens, trimmed_history_messages,
        trimmed_evidence_items, trim_detail_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(trace_id) DO UPDATE SET
        strategy_id = excluded.strategy_id,
        lane = excluded.lane,
        model_context_limit = excluded.model_context_limit,
        system_tokens = excluded.system_tokens,
        history_tokens = excluded.history_tokens,
        evidence_tokens = excluded.evidence_tokens,
        query_tokens = excluded.query_tokens,
        output_reserve_tokens = excluded.output_reserve_tokens,
        total_prefill_tokens = excluded.total_prefill_tokens,
        remaining_tokens = excluded.remaining_tokens,
        trimmed_history_messages = excluded.trimmed_history_messages,
        trimmed_evidence_items = excluded.trimmed_evidence_items,
        trim_detail_json = excluded.trim_detail_json
    ''', [
      record.traceId,
      record.strategyId,
      record.lane.dbValue,
      record.modelContextLimit,
      record.systemTokens,
      record.historyTokens,
      record.evidenceTokens,
      record.queryTokens,
      record.outputReserveTokens,
      record.totalPrefillTokens,
      record.remainingTokens,
      record.trimmedHistoryMessages,
      record.trimmedEvidenceItems,
      record.trimDetailJson,
    ]);
  }

  Future<PromptBudgetRecord?> promptBudgetForTrace(String traceId) async {
    await initialize();
    final rows = _db!.select('SELECT * FROM pg_prompt_budgets WHERE trace_id = ? LIMIT 1', [traceId]);
    return rows.isEmpty ? null : _promptBudgetFromRow(rows.first);
  }

  Future<void> putGenerationStats(GenerationStatsRecord record) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_generation_stats (
        trace_id, strategy_id, lane, ttft_ms, generation_ms, output_tokens,
        decode_tokens_per_second, backend, native_session_rebuilt,
        session_reset_reason
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(trace_id) DO UPDATE SET
        strategy_id = excluded.strategy_id,
        lane = excluded.lane,
        ttft_ms = excluded.ttft_ms,
        generation_ms = excluded.generation_ms,
        output_tokens = excluded.output_tokens,
        decode_tokens_per_second = excluded.decode_tokens_per_second,
        backend = excluded.backend,
        native_session_rebuilt = excluded.native_session_rebuilt,
        session_reset_reason = excluded.session_reset_reason
    ''', [
      record.traceId,
      record.strategyId,
      record.lane.dbValue,
      record.ttftMs,
      record.generationMs,
      record.outputTokens,
      record.decodeTokensPerSecond,
      record.backend,
      _boolInt(record.nativeSessionRebuilt),
      record.sessionResetReason,
    ]);
  }

  Future<GenerationStatsRecord?> generationStatsForTrace(String traceId) async {
    await initialize();
    final rows = _db!.select('SELECT * FROM pg_generation_stats WHERE trace_id = ? LIMIT 1', [traceId]);
    return rows.isEmpty ? null : _generationStatsFromRow(rows.first);
  }

  Future<void> putCitation(CitationRecord record) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_citations (
        citation_id, trace_id, anchor, evidence_id, chunk_id, document_id,
        section_id, page_no, citation_status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(citation_id) DO UPDATE SET
        evidence_id = excluded.evidence_id,
        chunk_id = excluded.chunk_id,
        document_id = excluded.document_id,
        section_id = excluded.section_id,
        page_no = excluded.page_no,
        citation_status = excluded.citation_status
    ''', [
      record.citationId,
      record.traceId,
      record.anchor,
      record.evidenceId,
      record.chunkId,
      record.documentId,
      record.sectionId,
      record.pageNo,
      record.citationStatus,
    ]);
  }

  Future<List<CitationRecord>> citationsForTrace(String traceId) async {
    await initialize();
    return _db!
        .select('SELECT * FROM pg_citations WHERE trace_id = ? ORDER BY citation_id', [traceId])
        .map(_citationFromRow)
        .toList(growable: false);
  }

  Future<void> putExperimentRun(ExperimentRunRecord record) async {
    await initialize();
    final startedAt = record.startedAt;
    if (startedAt == null) {
      throw ArgumentError('Experiment run startedAt is required');
    }
    if (record.completedItems < 0 ||
        record.totalItems < 0 ||
        record.completedItems > record.totalItems) {
      throw ArgumentError('Invalid experiment progress');
    }
    _db!.execute('''
      INSERT INTO pg_experiment_runs (
        experiment_run_id, trace_id, strategy_id, lane, status, started_at,
        completed_at, completed_items, total_items, metric_json, failure_code
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(experiment_run_id) DO UPDATE SET
        status = excluded.status,
        completed_at = excluded.completed_at,
        completed_items = excluded.completed_items,
        total_items = excluded.total_items,
        metric_json = excluded.metric_json,
        failure_code = excluded.failure_code
    ''', [
      record.experimentRunId,
      record.traceId,
      record.strategyId,
      record.lane.dbValue,
      record.status.name,
      startedAt.toUtc().toIso8601String(),
      record.completedAt?.toUtc().toIso8601String(),
      record.completedItems,
      record.totalItems,
      record.metricJson,
      record.failureCode,
    ]);
  }

  Future<ExperimentRunRecord?> experimentRunById(
    String experimentRunId,
  ) async {
    await initialize();
    final rows = _db!.select('''
      SELECT * FROM pg_experiment_runs
      WHERE experiment_run_id = ? LIMIT 1
    ''', [experimentRunId]);
    return rows.isEmpty ? null : _experimentRunFromRow(rows.first);
  }

  Future<List<ExperimentRunRecord>> experimentRunsForTrace(
    String traceId, {
    String? strategyId,
    RetrievalLane? lane,
  }) async {
    await initialize();
    final predicates = <String>['trace_id = ?'];
    final parameters = <Object?>[traceId];
    if (strategyId != null) {
      predicates.add('strategy_id = ?');
      parameters.add(strategyId);
    }
    if (lane != null) {
      predicates.add('lane = ?');
      parameters.add(lane.dbValue);
    }
    return _db!
        .select('''
          SELECT * FROM pg_experiment_runs
          WHERE ${predicates.join(' AND ')}
          ORDER BY started_at DESC, experiment_run_id DESC
        ''', parameters)
        .map(_experimentRunFromRow)
        .toList(growable: false);
  }

  Future<void> putBuildJob(BuildJobRecord record) async {
    await initialize();
    _db!.execute('''
      INSERT INTO pg_build_jobs (
        job_id, job_type, strategy_id, document_id, status, total_items,
        completed_items, checkpoint_json, current_source, failure_code,
        failure_detail, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(job_id) DO UPDATE SET
        status = excluded.status,
        total_items = excluded.total_items,
        completed_items = excluded.completed_items,
        checkpoint_json = excluded.checkpoint_json,
        current_source = excluded.current_source,
        failure_code = excluded.failure_code,
        failure_detail = excluded.failure_detail,
        updated_at = excluded.updated_at
    ''', [
      record.jobId,
      record.jobType,
      record.strategyId,
      record.documentId,
      record.status.name,
      record.totalItems,
      record.completedItems,
      record.checkpointJson,
      record.currentSource,
      record.failureCode,
      record.failureDetail,
      record.createdAt.toUtc().toIso8601String(),
      record.updatedAt.toUtc().toIso8601String(),
    ]);
  }

  Future<BuildJobRecord?> buildJobById(String jobId) async {
    await initialize();
    final rows = _db!.select('SELECT * FROM pg_build_jobs WHERE job_id = ? LIMIT 1', [jobId]);
    return rows.isEmpty ? null : _buildJobFromRow(rows.first);
  }

  Future<void> pruneCompletedTraces({int keep = 200}) async {
    await initialize();
    final safeKeep = keep < 0 ? 0 : keep;
    final rows = _db!.select('''
      SELECT trace_id FROM pg_traces
      WHERE status = ?
      ORDER BY completed_at DESC, started_at DESC, trace_id DESC
      LIMIT -1 OFFSET ?
    ''', [TraceStatus.complete.name, safeKeep]);
    if (rows.isEmpty) return;
    final db = _db!;
    db.execute('BEGIN IMMEDIATE;');
    try {
      for (final row in rows) {
        final traceId = row['trace_id'] as String;
        db.execute("DELETE FROM pg_embeddings WHERE source_kind = 'query' AND source_id = ?", [traceId]);
        db.execute('DELETE FROM pg_traces WHERE trace_id = ?', [traceId]);
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  LineageDocumentRecord _lineageDocumentFromRow(Row row) =>
      LineageDocumentRecord(
        documentId: row['document_id'] as String,
        sourceName: row['source_name'] as String,
        sha256: row['sha256'] as String,
        fileType: row['file_type'] as String,
        sizeBytes: _intOrNull(row['size_bytes']),
        pageCount: _intOrNull(row['page_count']),
        parseStatus: parseStatusFromDb(row['parse_status'] as String),
        parseErrorCode: row['parse_error_code'] as String?,
        parseErrorDetail: row['parse_error_detail'] as String?,
        extractedCharCount:
            (row['extracted_char_count'] as num).toInt(),
        emptyPageCount: (row['empty_page_count'] as num).toInt(),
        provenanceQuality: ProvenanceQuality.values.firstWhere(
          (quality) => quality.name == row['provenance_quality'],
          orElse: () => throw StateError(
            'Unknown provenance quality: ${row['provenance_quality']}',
          ),
        ),
        importedAt: DateTime.parse(row['imported_at'] as String).toUtc(),
      );

  LineageSectionRecord _lineageSectionFromRow(Row row) =>
      LineageSectionRecord(
        sectionId: row['section_id'] as String,
        documentId: row['document_id'] as String,
        pageNo: _intOrNull(row['page_no']),
        heading: row['heading'] as String?,
        sectionType: row['section_type'] as String,
        startOffset: _intOrNull(row['start_offset']),
        endOffset: _intOrNull(row['end_offset']),
        charCount: (row['char_count'] as num).toInt(),
        parseStatus: parseStatusFromDb(row['parse_status'] as String),
      );

  LineageChunkRecord _lineageChunkFromRow(Row row) => LineageChunkRecord(
        chunkId: row['chunk_id'] as String,
        documentId: row['document_id'] as String,
        sectionId: row['section_id'] as String?,
        locator: row['locator'] as String,
        ordinal: (row['ordinal'] as num).toInt(),
        startOffset: _intOrNull(row['start_offset']),
        endOffset: _intOrNull(row['end_offset']),
        charCount: (row['char_count'] as num).toInt(),
        tokenCount: _intOrNull(row['token_count']),
        overlapFromPrevious:
            (row['overlap_from_previous'] as num).toInt(),
        chunkStrategy: row['chunk_strategy'] as String,
        boundaryReason: row['boundary_reason'] as String?,
        provenanceQuality: ProvenanceQuality.values.firstWhere(
          (quality) => quality.name == row['provenance_quality'],
          orElse: () => throw StateError(
            'Unknown provenance quality: ${row['provenance_quality']}',
          ),
        ),
      );

  LineageEmbedding _embeddingFromRow(Row row) => LineageEmbedding(
        embeddingId: row['embedding_id'] as String,
        sourceKind: row['source_kind'] as String,
        sourceId: row['source_id'] as String,
        documentId: row['document_id'] as String?,
        chunkId: row['chunk_id'] as String?,
        representation: embeddingRepresentationFromDb(row['representation_type'] as String),
        spanStart: _intOrNull(row['span_start']),
        spanEnd: _intOrNull(row['span_end']),
        modelIdentity: row['model_identity'] as String,
        taskMode: row['task_mode'] as String,
        dimension: (row['dimension'] as num).toInt(),
        norm: (row['norm'] as num).toDouble(),
        vectorF32: Uint8List.fromList(row['vector_f32'] as Uint8List),
        vectorSha256: row['vector_sha256'] as String,
        generationMs: (row['generation_ms'] as num).toInt(),
        generatedAt: DateTime.parse(row['generated_at'] as String).toUtc(),
        truthKind: truthKindFromDb(row['truth_kind'] as String),
      );

  VectorIndexEntryRecord _vectorEntryFromRow(Row row) => VectorIndexEntryRecord(
        indexEntryId: row['index_entry_id'] as String,
        embeddingId: row['embedding_id'] as String,
        backendId: row['backend_id'] as String,
        strategyId: row['strategy_id'] as String,
        lane: retrievalLaneFromDb(row['lane'] as String),
        commitStatus: VectorCommitStatus.values.firstWhere(
          (item) => item.name == row['commit_status'] as String,
          orElse: () => throw StateError('Unknown vector commit status: ${row['commit_status']}'),
        ),
        committedAt: _dateOrNull(row['committed_at']),
        failureCode: row['failure_code'] as String?,
        failureDetail: row['failure_detail'] as String?,
      );

  LineageTrace _traceFromRow(Row row) => LineageTrace(
        traceId: row['trace_id'] as String,
        sessionId: row['session_id'] as String,
        turnId: row['turn_id'] as String,
        queryText: row['query_text'] as String,
        requestedMode: row['requested_mode'] as String,
        finalMode: row['final_mode'] as String,
        scopeJson: row['scope_json'] as String,
        activeStrategyId: row['active_strategy_id'] as String,
        startedAt: DateTime.parse(row['started_at'] as String).toUtc(),
        completedAt: _dateOrNull(row['completed_at']),
        status: traceStatusFromDb(row['status'] as String),
        failureStage: row['failure_stage'] as String?,
        failureCode: row['failure_code'] as String?,
      );

  TraceEventRecord _eventFromRow(Row row) => TraceEventRecord(
        eventId: row['event_id'] as String,
        traceId: row['trace_id'] as String,
        seq: (row['seq'] as num).toInt(),
        stage: row['stage'] as String,
        kind: row['kind'] as String,
        truthKind: truthKindFromDb(row['truth_kind'] as String),
        lane: retrievalLaneFromDb(row['lane'] as String),
        strategyId: row['strategy_id'] as String,
        timestampUs: (row['timestamp_us'] as num).toInt(),
        durationUs: _intOrNull(row['duration_us']),
        payloadJson: row['payload_json'] as String,
      );

  CandidateRecord _candidateFromRow(Row row) => CandidateRecord(
        candidateId: row['candidate_id'] as String,
        traceId: row['trace_id'] as String,
        strategyId: row['strategy_id'] as String,
        lane: retrievalLaneFromDb(row['lane'] as String),
        chunkId: row['chunk_id'] as String,
        embeddingId: row['embedding_id'] as String?,
        sourceChannels: row['source_channels'] as String,
        ftsRank: _intOrNull(row['fts_rank']),
        rawBm25: _doubleOrNull(row['raw_bm25']),
        vectorRank: _intOrNull(row['vector_rank']),
        rawCosine: _doubleOrNull(row['raw_cosine']),
        fusionRank: _intOrNull(row['fusion_rank']),
        fusionScore: _doubleOrNull(row['fusion_score']),
        rerankRank: _intOrNull(row['rerank_rank']),
        rerankScore: _doubleOrNull(row['rerank_score']),
        finalRank: _intOrNull(row['final_rank']),
        selectedForEvidence: _boolFromDb(row['selected_for_evidence']),
        dropReason: row['drop_reason'] as String?,
      );

  RouterDecisionRecord _routerFromRow(Row row) => RouterDecisionRecord(
        decisionId: row['decision_id'] as String,
        traceId: row['trace_id'] as String,
        strategyId: row['strategy_id'] as String,
        lane: retrievalLaneFromDb(row['lane'] as String),
        ftsHitCount: (row['fts_hit_count'] as num).toInt(),
        top1Cosine: _doubleOrNull(row['top1_cosine']),
        top2Cosine: _doubleOrNull(row['top2_cosine']),
        top1Top2Gap: _doubleOrNull(row['top1_top2_gap']),
        dualChannel: _boolFromDb(row['dual_channel']),
        lexicalGatePass: _boolFromDb(row['lexical_gate_pass']),
        semanticStrengthGatePass: _boolFromDb(row['semantic_strength_gate_pass']),
        semanticGapGatePass: _boolFromDb(row['semantic_gap_gate_pass']),
        finalUseKnowledge: _boolFromDb(row['final_use_knowledge']),
        ruleProfile: row['rule_profile'] as String,
        decisionReason: row['decision_reason'] as String,
      );

  EvidenceRecord _evidenceFromRow(Row row) => EvidenceRecord(
        evidenceId: row['evidence_id'] as String,
        traceId: row['trace_id'] as String,
        strategyId: row['strategy_id'] as String,
        lane: retrievalLaneFromDb(row['lane'] as String),
        anchor: row['anchor'] as String?,
        candidateId: row['candidate_id'] as String,
        chunkId: row['chunk_id'] as String,
        selectionRank: (row['selection_rank'] as num).toInt(),
        score: (row['score'] as num).toDouble(),
        tokenCount: (row['token_count'] as num).toInt(),
        selectionReason: row['selection_reason'] as String,
      );

  PromptBudgetRecord _promptBudgetFromRow(Row row) => PromptBudgetRecord(
        traceId: row['trace_id'] as String,
        strategyId: row['strategy_id'] as String,
        lane: retrievalLaneFromDb(row['lane'] as String),
        modelContextLimit: (row['model_context_limit'] as num).toInt(),
        systemTokens: (row['system_tokens'] as num).toInt(),
        historyTokens: (row['history_tokens'] as num).toInt(),
        evidenceTokens: (row['evidence_tokens'] as num).toInt(),
        queryTokens: (row['query_tokens'] as num).toInt(),
        outputReserveTokens: (row['output_reserve_tokens'] as num).toInt(),
        totalPrefillTokens: (row['total_prefill_tokens'] as num).toInt(),
        remainingTokens: (row['remaining_tokens'] as num).toInt(),
        trimmedHistoryMessages: (row['trimmed_history_messages'] as num).toInt(),
        trimmedEvidenceItems: (row['trimmed_evidence_items'] as num).toInt(),
        trimDetailJson: row['trim_detail_json'] as String,
      );

  GenerationStatsRecord _generationStatsFromRow(Row row) => GenerationStatsRecord(
        traceId: row['trace_id'] as String,
        strategyId: row['strategy_id'] as String,
        lane: retrievalLaneFromDb(row['lane'] as String),
        ttftMs: _intOrNull(row['ttft_ms']),
        generationMs: (row['generation_ms'] as num).toInt(),
        outputTokens: _intOrNull(row['output_tokens']),
        decodeTokensPerSecond: _doubleOrNull(row['decode_tokens_per_second']),
        backend: row['backend'] as String?,
        nativeSessionRebuilt: _boolFromDb(row['native_session_rebuilt']),
        sessionResetReason: row['session_reset_reason'] as String?,
      );

  CitationRecord _citationFromRow(Row row) => CitationRecord(
        citationId: row['citation_id'] as String,
        traceId: row['trace_id'] as String,
        anchor: row['anchor'] as String,
        evidenceId: row['evidence_id'] as String?,
        chunkId: row['chunk_id'] as String?,
        documentId: row['document_id'] as String?,
        sectionId: row['section_id'] as String?,
        pageNo: _intOrNull(row['page_no']),
        citationStatus: row['citation_status'] as String,
      );

  ExperimentRunRecord _experimentRunFromRow(Row row) => ExperimentRunRecord(
        experimentRunId: row['experiment_run_id'] as String,
        traceId: row['trace_id'] as String,
        strategyId: row['strategy_id'] as String,
        lane: retrievalLaneFromDb(row['lane'] as String),
        status: experimentRunStatusFromDb(row['status'] as String),
        startedAt: DateTime.parse(row['started_at'] as String).toUtc(),
        completedAt: _dateOrNull(row['completed_at']),
        completedItems: (row['completed_items'] as num).toInt(),
        totalItems: (row['total_items'] as num).toInt(),
        metricJson: row['metric_json'] as String?,
        failureCode: row['failure_code'] as String?,
      );

  BuildJobRecord _buildJobFromRow(Row row) => BuildJobRecord(
        jobId: row['job_id'] as String,
        jobType: row['job_type'] as String,
        strategyId: row['strategy_id'] as String,
        documentId: row['document_id'] as String?,
        status: buildJobStatusFromDb(row['status'] as String),
        totalItems: (row['total_items'] as num).toInt(),
        completedItems: (row['completed_items'] as num).toInt(),
        checkpointJson: row['checkpoint_json'] as String,
        currentSource: row['current_source'] as String?,
        failureCode: row['failure_code'] as String?,
        failureDetail: row['failure_detail'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
        updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
      );

  int _boolInt(bool value) => value ? 1 : 0;
  bool _boolFromDb(Object? value) => (value as num).toInt() != 0;
  int? _intOrNull(Object? value) => value == null ? null : (value as num).toInt();
  double? _doubleOrNull(Object? value) => value == null ? null : (value as num).toDouble();
  DateTime? _dateOrNull(Object? value) => value == null ? null : DateTime.parse(value as String).toUtc();

  void dispose() {
    if (_ownsDatabase) _db?.close();
    _db = null;
    _initialized = false;
  }
}
