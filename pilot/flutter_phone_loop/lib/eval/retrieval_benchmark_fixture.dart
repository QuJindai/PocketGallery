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
    for (final documentId in importedDocumentIds.reversed) {
      try {
        await engine.removeDocument(documentId);
      } catch (_) {
        // Best-effort cleanup: a failed cleanup must not hide benchmark output.
      }
    }
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

  /// Remove only PocketGallery-owned deterministic benchmark sources. These
  /// names are reserved for the built-in Golden fixture and must never remain
  /// in the user's normal knowledge library after diagnostics.
  static Future<void> removeKnownFixtures(KnowledgeEngine engine) async {
    final existing = await engine.listDocuments();
    for (final doc in existing) {
      if (sourceNames.contains(doc.sourceName)) {
        await engine.removeDocument(doc.documentId);
      }
    }
  }

  static Future<RetrievalBenchmarkLease> prepare(
    KnowledgeEngine engine, {
    bool resetKnownFixtures = false,
  }) async {
    if (resetKnownFixtures) {
      await removeKnownFixtures(engine);
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
