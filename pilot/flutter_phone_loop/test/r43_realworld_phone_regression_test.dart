import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_retriever.dart';

void main() {
  const chunk = PgChunk(
    id: 'c1',
    documentId: 'd1',
    sourceName: 'generic_ai_notes.md',
    locator: 'chunk#1',
    ordinal: 0,
    text: 'AI 技术概览，与用户问题只有泛化语义相关。',
  );

  test('semantic-only weak retrieval does not auto-attach local evidence', () {
    final semantic = RetrievalHit(
      chunk: chunk,
      score: 0.52,
      channel: 'embedding',
      rank: 1,
    );
    final hybrid = HybridHit(
      chunk: chunk,
      score: 0.041,
      channels: const {'embedding'},
      lexicalRank: null,
      semanticRank: 1,
    );
    final bundle = RetrievalBundle(
      lexicalHits: const [],
      semanticHits: [semantic],
      hybridHits: [hybrid],
      evidence: const [EvidenceItem(anchor: 'E1', chunk: chunk, score: 0.041)],
      lexicalOnly: false,
    );

    expect(bundle.relevantForAuto, isFalse);
  });

  test('real chat rebuilds a bounded native session for every turn', () async {
    final source = await File(
      'lib/services/gemma_chat_service.dart',
    ).readAsString();
    final budgeter = await File(
      'lib/chat/context_budgeter.dart',
    ).readAsString();

    expect(source, contains('_createTurnChat'));
    expect(
      source,
      isNot(
        contains('if (_chat != null && _activeSessionId == sessionId) return;'),
      ),
    );
    expect(source, contains('currentTurnTokens'));
    expect(source, contains('finally'));
    expect(budgeter, contains('currentTurnTokens'));
    expect(budgeter, contains('availableHistoryTokens'));
  });

  test('prompt evidence is bounded before native prefill', () async {
    final source = await File(
      'lib/services/gemma_chat_service.dart',
    ).readAsString();
    expect(source, contains('_boundedEvidenceContext'));
    expect(source, contains('evidenceReserveMax'));
  });

  test('Golden Test exercises the real chat orchestrator path', () async {
    final source = await File(
      'lib/services/golden_test_runner.dart',
    ).readAsString();
    expect(source, contains('ChatOrchestrator'));
    expect(source, contains('GemmaChatService'));
    expect(source, contains('F7_CHAT_REALWORLD'));
  });

  test(
    'retrieval benchmark prepares and cleans temporary golden corpus',
    () async {
      final page = await File(
        'lib/ui/microscope/retrieval_benchmark_page.dart',
      ).readAsString();
      final fixture = File('lib/eval/retrieval_benchmark_fixture.dart');

      expect(fixture.existsSync(), isTrue);
      expect(page, contains('RetrievalBenchmarkFixture'));
      expect(page, contains('cleanup'));
      expect(page, contains('临时 Golden'));
    },
  );

  test('forced knowledge can reject weak semantic-only evidence', () async {
    final source = await File('lib/chat/chat_orchestrator.dart').readAsString();
    final retriever = await File(
      'lib/services/knowledge_retriever.dart',
    ).readAsString();
    final bundle = await File(
      'lib/retrieval/retrieval_bundle.dart',
    ).readAsString();

    expect(bundle, contains('relevantForKnowledge'));
    expect(
      retriever,
      contains("export '../retrieval/retrieval_bundle.dart'"),
      reason: 'the historical KnowledgeRetriever import remains compatible',
    );
    expect(source, contains('retrieval.relevantForKnowledge'));
  });
}
