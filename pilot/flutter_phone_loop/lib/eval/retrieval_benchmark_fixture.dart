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
        '发生关节过载时应检查机械干涉和负载参数。'
        '机械干涉、负载参数异常都可能造成关节过载报警。',
    'pg_golden_network.txt':
        '网联台站说明。DoIP 建链后需要保持诊断会话，'
        '网络断开会导致诊断服务中断，与标定结果等待不是同一故障。'
        '排查时应区分网络掉线、诊断会话失效和 ECU 标定状态等待。',
    'pg_golden_edge_ai.txt':
        '端侧模型性能测试方法。手机、车端和边缘设备部署本地大模型时，'
        '应测量首 token 延迟 TTFT、解码速度 tokens/s、峰值内存、模型冷启动时间、'
        '持续运行功耗、温度与温控降频。受限硬件还应进行任务特定基准测试，'
        '验证模型在真实数据分布、长上下文和资源约束下的准确性与稳定性。'
        '功耗测试需要同时记录电池或外部供电功率、持续时间和温度，'
        '避免把过热降频误判为模型或算法本身性能回退。',
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
