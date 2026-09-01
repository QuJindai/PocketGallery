import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/eval/retrieval_benchmark.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/benchmark_case_detail_page.dart';

void main() {
  testWidgets(
    'case detail shows expected IDs actual ranks and unavailable facts',
    (tester) async {
      const benchmark = RetrievalBenchmarkCase(
        id: 'q-detail',
        question: '为什么选择这个证据？',
        expectedDocumentIds: {'doc-expected'},
        expectedSourceNames: {},
        expectedChunkIds: {'chunk-expected'},
        expectedUseKnowledge: true,
        tags: {'local-real'},
      );
      const actual = BenchmarkCaseResult(
        caseId: 'q-detail',
        strategy: RetrievalStrategy.hybrid,
        hits: [
          BenchmarkHit(
            chunkId: 'chunk-wrong',
            documentId: 'doc-wrong',
            sourceName: 'wrong.md',
          ),
          BenchmarkHit(
            chunkId: 'chunk-expected',
            documentId: 'doc-expected',
            sourceName: 'expected.md',
          ),
        ],
        failureCode: 'TOP1_MISS',
      );
      const baseline = BenchmarkCaseResult(
        caseId: 'q-detail',
        strategy: RetrievalStrategy.ftsOnly,
        hits: [
          BenchmarkHit(
            chunkId: 'chunk-expected',
            documentId: 'doc-expected',
            sourceName: 'expected.md',
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: BenchmarkCaseDetailPage(
            benchmark: benchmark,
            result: actual,
            baseline: baseline,
          ),
        ),
      );

      expect(find.textContaining('doc-expected'), findsWidgets);
      expect(find.textContaining('chunk-expected'), findsWidgets);
      expect(find.textContaining('#1 · chunk-wrong'), findsOneWidget);
      expect(find.textContaining('#2 · chunk-expected'), findsOneWidget);
      expect(find.textContaining('first relevant rank · 2'), findsOneWidget);
      expect(find.textContaining('failure · TOP1_MISS'), findsOneWidget);
      expect(find.textContaining('ranking differs'), findsOneWidget);
      expect(find.text('Router Accuracy · 不可用'), findsOneWidget);
      expect(find.text('Citation Grounding · 不可用'), findsOneWidget);
      expect(find.textContaining('0.0%'), findsNothing);
    },
  );
}
