import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/knowledge_engine.dart';

class RetrievalBenchmarkLease {
  RetrievalBenchmarkLease({
    required this.engine,
    required this.importedDocumentIds,
    required this.directory,
  });

  final KnowledgeEngine engine;
  final List<String> importedDocumentIds;
  final Directory directory;
  bool _cleaned = false;

  Future<void> cleanup() async {
    if (_cleaned) return;
    _cleaned = true;

    // All files created by this lease use reserved pg_golden_* source names.
    // Force-remove those names from the lexical library even if native vector
    // cleanup has failed previously. This makes diagnostics non-destructive to
    // the user's real knowledge library.
    await RetrievalBenchmarkFixture.cleanupReservedGoldenDocuments(engine);

    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }
}

class RetrievalBenchmarkFixture {
  static const Map<String, String> documents = {
    'pg_golden_calibration.txt':
        '标定结果诊断说明。\n'
        '当诊断程序发送 31 03 51 01 获取标定结果时，车辆可能持续返回处理中响应，'
        '但尚未返回最终标定结果。DSA 此时会继续等待终止结果，不应把处理中响应当作最终成功。\n'
        '处理建议：确认 ECU 最终结果状态以及超时策略。',
    'pg_golden_robot.txt':
        '机器人维护说明。喷涂机器人每周检查润滑状态，'
        '发生关节过载时应检查机械干涉和负载参数。',
    'pg_golden_network.txt':
        '网联台站说明。DoIP 建链后需要保持诊断会话，'
        '网络断开会导致诊断服务中断，与标定结果等待不是同一故障。',
  };

  static Set<String> get sourceNames => documents.keys.toSet();

  /// Hard cleanup for PocketGallery-owned deterministic benchmark sources.
  ///
  /// We intentionally make lexical deletion independent from the native RAG
  /// database. Semantic search always resolves returned ids through the
  /// lexical store, so an orphaned native row cannot become user evidence.
  /// Removing the observation rows also keeps Index Health truthful.
  static Future<void> cleanupReservedGoldenDocuments(
    KnowledgeEngine engine,
  ) async {
    await engine.initialize();
    final existing = await engine.listDocuments();
    for (final doc in existing) {
      if (!sourceNames.contains(doc.sourceName)) continue;
      final ids = await engine.lexicalStore.chunkIdsForDocument(doc.documentId);
      try {
        await engine.lexicalStore.removeDocument(doc.documentId);
      } finally {
        if (ids.isNotEmpty) {
          try {
            await engine.semanticStore.observationStore.removeChunkIds(ids);
          } catch (_) {}
        }
      }
    }
  }

  static Future<void> removeKnownFixtures(KnowledgeEngine engine) =>
      cleanupReservedGoldenDocuments(engine);

  static Future<RetrievalBenchmarkLease> prepare(
    KnowledgeEngine engine, {
    bool resetKnownFixtures = false,
  }) async {
    if (resetKnownFixtures) {
      await cleanupReservedGoldenDocuments(engine);
    }

    final existing = await engine.listDocuments();
    final existingSources = existing.map((e) => e.sourceName).toSet();
    final temp = await getTemporaryDirectory();
    final dir = await Directory(p.join(
      temp.path,
      'pocketgallery_golden_${DateTime.now().microsecondsSinceEpoch}',
    )).create(recursive: true);
    final importedIds = <String>[];

    try {
      for (final entry in documents.entries) {
        if (existingSources.contains(entry.key)) continue;
        final file = File(p.join(dir.path, entry.key));
        await file.writeAsString(entry.value);
        final imported = await engine.importPath(file.path);
        importedIds.add(imported.documentId);
      }
      return RetrievalBenchmarkLease(
        engine: engine,
        importedDocumentIds: importedIds,
        directory: dir,
      );
    } catch (_) {
      final lease = RetrievalBenchmarkLease(
        engine: engine,
        importedDocumentIds: importedIds,
        directory: dir,
      );
      await lease.cleanup();
      rethrow;
    }
  }
}
