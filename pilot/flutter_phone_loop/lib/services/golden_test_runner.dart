import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/evidence.dart';
import '../core/models.dart';
import 'knowledge_engine.dart';

class GoldenTestReport {
  GoldenTestReport(this.startedAt, this.results);
  final DateTime startedAt;
  final List<GateResult> results;

  bool get passed => results.every((r) => r.passed);

  Map<String, Object> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'passed': passed,
        'results': results.map((e) => e.toJson()).toList(),
      };
}

class GoldenTestRunner {
  GoldenTestRunner(this.engine);
  final KnowledgeEngine engine;

  Future<GoldenTestReport> run() async {
    final results = <GateResult>[];
    final started = DateTime.now();
    try {
      final dir = await getTemporaryDirectory();
      final d1 = File(p.join(dir.path, 'pg_golden_calibration.txt'));
      final d2 = File(p.join(dir.path, 'pg_golden_robot.txt'));
      final d3 = File(p.join(dir.path, 'pg_golden_network.txt'));

      await d1.writeAsString(
        '标定结果诊断说明。\n'
        '当诊断程序发送 31 03 51 01 获取标定结果时，车辆可能持续返回处理中响应，'
        '但尚未返回最终标定结果。DSA 此时会继续等待终止结果，不应把处理中响应当作最终成功。\n'
        '处理建议：确认 ECU 最终结果状态以及超时策略。',
      );
      await d2.writeAsString(
        '机器人维护说明。喷涂机器人每周检查润滑状态，'
        '发生关节过载时应检查机械干涉和负载参数。',
      );
      await d3.writeAsString(
        '网联台站说明。DoIP 建链后需要保持诊断会话，'
        '网络断开会导致诊断服务中断，与标定结果等待不是同一故障。',
      );

      final a = await engine.importPath(d1.path);
      final b = await engine.importPath(d2.path);
      final c = await engine.importPath(d3.path);
      results.add(GateResult(
        'F1_IMPORT_CHUNK',
        a.chunks.isNotEmpty && b.chunks.isNotEmpty && c.chunks.isNotEmpty,
        'chunks=${a.chunks.length + b.chunks.length + c.chunks.length}',
      ));

      final fts = await engine.lexicalStore.search('31 03 51 01');
      results.add(GateResult(
        'F2_FTS5',
        fts.isNotEmpty && fts.first.chunk.documentId == a.documentId,
        fts.isEmpty ? 'no hit' : 'top1=${fts.first.chunk.sourceName}',
      ));

      final sem = await engine.semanticStore.search('为什么诊断程序一直等不到标定完成状态');
      results.add(GateResult(
        'F3_EMBEDDING',
        sem.isNotEmpty && sem.first.chunk.documentId == a.documentId,
        sem.isEmpty
            ? 'no hit'
            : 'top1=${sem.first.chunk.sourceName} score=${sem.first.score.toStringAsFixed(3)}',
      ));

      final hybrid = engine.ranker.fuse(
        query: '31 03 51 01 为什么 DSA 一直等待',
        lexical: await engine.lexicalStore.search('31 03 51 01 为什么 DSA 一直等待'),
        semantic: await engine.semanticStore.search('31 03 51 01 为什么 DSA 一直等待'),
      );
      results.add(GateResult(
        'F4_HYBRID_RERANK',
        hybrid.isNotEmpty && hybrid.first.chunk.documentId == a.documentId,
        hybrid.isEmpty
            ? 'no hit'
            : 'top1=${hybrid.first.chunk.sourceName} channels=${hybrid.first.channels.join("+")}',
      ));

      final evidence = const EvidencePackBuilder().build(hybrid);
      results.add(GateResult(
        'F5_EVIDENCE',
        evidence.isNotEmpty &&
            evidence.first.chunk.documentId == a.documentId &&
            evidence.first.anchor == 'E1',
        evidence.isEmpty ? 'no evidence' : '${evidence.first.anchor}=${evidence.first.chunk.sourceName}',
      ));

      final answer = await engine.gemma.answer(
        question: '请解释 31 03 51 01 获取标定结果时为什么 DSA 可能持续等待；回答中必须保留“31 03 51 01”并引用 [E#]。',
        evidence: evidence,
      );
      final citations = CitationResolver().extract(answer, evidence);
      final answerOk = answer.contains('31 03 51 01') &&
          (answer.contains('等待') || answer.contains('处理中')) &&
          citations.isNotEmpty;
      results.add(GateResult(
        'F6_GEMMA_CITATION',
        answerOk,
        answer.replaceAll('\n', ' ').substring(0, answer.length > 220 ? 220 : answer.length),
      ));
    } catch (e, st) {
      results.add(GateResult('RUNTIME_EXCEPTION', false, '$e\n$st'));
    }

    final report = GoldenTestReport(started, results);
    final docs = await getApplicationDocumentsDirectory();
    await File(p.join(docs.path, 'PG_GOLDEN_LAST.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    return report;
  }
}
