import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/eval/retrieval_benchmark.dart';
import 'package:pocketgallery_phone_pilot/eval/retrieval_evaluator.dart';

void main() {
  const cases = [
    RetrievalBenchmarkCase(
      id: 'q1',
      question: 'calibration',
      expectedDocumentIds: {'d1'},
      expectedSourceNames: {},
      tags: {'en'},
    ),
    RetrievalBenchmarkCase(
      id: 'q2',
      question: 'robot',
      expectedDocumentIds: {'d2', 'd3'},
      expectedSourceNames: {},
      tags: {'en'},
    ),
  ];

  test('metrics match hand-computable rankings', () {
    const evaluator = RetrievalEvaluator();
    final metrics = evaluator.aggregate(cases, const [
      BenchmarkCaseResult(
        caseId: 'q1',
        strategy: RetrievalStrategy.hybrid,
        hits: [
          BenchmarkHit(chunkId: 'c1', documentId: 'd1', sourceName: 'a'),
          BenchmarkHit(chunkId: 'c9', documentId: 'dx', sourceName: 'x'),
        ],
      ),
      BenchmarkCaseResult(
        caseId: 'q2',
        strategy: RetrievalStrategy.hybrid,
        hits: [
          BenchmarkHit(chunkId: 'cx', documentId: 'dx', sourceName: 'x'),
          BenchmarkHit(chunkId: 'c2', documentId: 'd2', sourceName: 'b'),
          BenchmarkHit(chunkId: 'c3', documentId: 'd3', sourceName: 'c'),
        ],
      ),
    ]);

    expect(metrics, isNotNull);
    expect(metrics!.hitAt1, closeTo(0.5, 1e-12));
    expect(metrics.hitAt3, closeTo(1.0, 1e-12));
    expect(metrics.recallAt5, closeTo(1.0, 1e-12));
    expect(metrics.mrr, closeTo(0.75, 1e-12));
    // q1: 1/2 relevant, q2: 2/3 relevant; average = 7/12.
    expect(metrics.contextPrecision, closeTo(7 / 12, 1e-12));
    expect(metrics.caseCount, 2);
  });

  test('zero executed cases returns no fabricated metric', () {
    const evaluator = RetrievalEvaluator();
    expect(evaluator.aggregate(cases, const []), isNull);
  });

  test('source name can act as benchmark relevance label', () {
    const evaluator = RetrievalEvaluator();
    const sourceCase = RetrievalBenchmarkCase(
      id: 'q',
      question: '标定',
      expectedDocumentIds: {},
      expectedSourceNames: {'pg_golden_calibration.txt'},
      tags: {'zh'},
    );
    final metrics = evaluator.aggregate(
      const [sourceCase],
      const [
        BenchmarkCaseResult(
          caseId: 'q',
          strategy: RetrievalStrategy.ftsOnly,
          hits: [
            BenchmarkHit(
              chunkId: 'x',
              documentId: 'dynamic-id',
              sourceName: 'pg_golden_calibration.txt',
            ),
          ],
        ),
      ],
    );
    expect(metrics!.hitAt1, 1);
  });

  test('ranking comparison reports per-case and top1 changes', () {
    const evaluator = RetrievalEvaluator();
    const current = [
      BenchmarkCaseResult(
        caseId: 'q1',
        strategy: RetrievalStrategy.hybrid,
        hits: [
          BenchmarkHit(chunkId: 'c1', documentId: 'd1', sourceName: 'a'),
          BenchmarkHit(chunkId: 'c2', documentId: 'd2', sourceName: 'b'),
        ],
      ),
      BenchmarkCaseResult(
        caseId: 'q2',
        strategy: RetrievalStrategy.hybrid,
        hits: [
          BenchmarkHit(chunkId: 'c3', documentId: 'd3', sourceName: 'c'),
          BenchmarkHit(chunkId: 'c4', documentId: 'd4', sourceName: 'd'),
        ],
      ),
    ];
    const alternate = [
      BenchmarkCaseResult(
        caseId: 'q2',
        strategy: RetrievalStrategy.alternateHybrid,
        hits: [
          BenchmarkHit(chunkId: 'c4', documentId: 'd4', sourceName: 'd'),
          BenchmarkHit(chunkId: 'c3', documentId: 'd3', sourceName: 'c'),
        ],
      ),
      BenchmarkCaseResult(
        caseId: 'q1',
        strategy: RetrievalStrategy.alternateHybrid,
        hits: [
          BenchmarkHit(chunkId: 'c1', documentId: 'd1', sourceName: 'a'),
          BenchmarkHit(chunkId: 'c2', documentId: 'd2', sourceName: 'b'),
        ],
      ),
    ];

    final comparison = evaluator.compareRankings(current, alternate);

    expect(comparison.pairedCaseCount, 2);
    expect(comparison.rankingChangedCases, 1);
    expect(comparison.top1ChangedCases, 1);
    expect(comparison.summary, '对比 C · 1/2 cases 排名变化 · 1 top1 变化');
  });
}
