import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/chat/context_budgeter.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/generation_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/streaming_generation_collector.dart';

void main() {
  test('context decision accounts for the actual selected history, evidence and query',
      () {
    const budgeter = ContextBudgeter();
    final history = <ChatMessage>[
      for (var index = 0; index < 18; index++)
        ChatMessage.user(
          id: 'm$index',
          sessionId: 's1',
          text: '历史 $index ${'内容' * 260}',
        ),
    ];
    final evidence = <EvidenceItem>[
      for (var index = 0; index < 3; index++)
        EvidenceItem(
          anchor: 'E${index + 1}',
          chunk: PgChunk(
            id: 'c$index',
            documentId: 'd1',
            sourceName: 'doc.md',
            locator: 'section:$index',
            ordinal: index,
            text: '证据 $index ${'事实' * 180}',
          ),
          score: 1 - index * 0.1,
        ),
    ];
    final evidenceSelection = budgeter.composeEvidenceContextWithDecision(
      evidence,
      maxTokens: 700,
      maxItems: 2,
    );
    final evidenceTokens = budgeter.estimateTokens(evidenceSelection.context);
    final queryTokens = budgeter.estimateTokens('请回答当前问题');
    final systemTokens = budgeter.estimateTokens('system instruction');
    final selection = budgeter.selectHistoryWithDecision(
      history,
      evidenceTokens: evidenceTokens,
      currentTurnTokens: queryTokens,
      systemTokens: systemTokens,
      evidenceItemCount: evidence.length,
      includedEvidenceItemCount: evidenceSelection.includedItemCount,
      trimDetails: evidenceSelection.trimDetails,
    );
    final decision = selection.decision;

    expect(evidenceSelection.context, contains('[E1]'));
    expect(evidenceSelection.context, contains('[E2]'));
    expect(evidenceSelection.context, isNot(contains('[E3]')));
    expect(selection.history.last.id, 'm17');
    expect(decision.trimmedHistoryMessages,
        history.length - selection.history.length);
    expect(decision.trimmedEvidenceItems, 1);
    expect(
      decision.totalPrefillTokens,
      decision.systemTokens +
          decision.historyTokens +
          decision.evidenceTokens +
          decision.queryTokens,
    );
    expect(
      decision.totalPrefillTokens + decision.outputReserveTokens,
      lessThanOrEqualTo(decision.modelContextLimit),
    );
    expect(
      decision.remainingTokens,
      decision.modelContextLimit -
          decision.outputReserveTokens -
          decision.totalPrefillTokens,
    );
    expect(decision.remainingTokens, greaterThanOrEqualTo(0));
  });

  test('unsupported backend generation metrics stay null', () {
    const budget = ContextBudgetDecision(
      modelContextLimit: 8192,
      systemTokens: 100,
      historyTokens: 200,
      evidenceTokens: 300,
      queryTokens: 50,
      outputReserveTokens: 700,
      totalPrefillTokens: 650,
      remainingTokens: 6842,
      trimmedHistoryMessages: 2,
      trimmedEvidenceItems: 1,
      trimDetails: <String>['oldest_history_removed'],
    );
    const telemetry = GenerationTelemetry(generationMs: 321);
    const result = ChatTurnResult(
      text: 'answer',
      budget: budget,
      generation: telemetry,
    );

    expect(result.text, 'answer');
    expect(result.generation.generationMs, 321);
    expect(result.generation.ttftMs, isNull);
    expect(result.generation.outputTokens, isNull);
    expect(result.generation.decodeTokensPerSecond, isNull);
    expect(result.generation.backend, isNull);
  });

  test('streamed text tokens produce measured generation telemetry', () {
    final collector = StreamingGenerationCollector();

    collector.addTextToken('Pocket', elapsedMilliseconds: 125);
    collector.addTextToken('Gallery', elapsedMilliseconds: 225);
    collector.addTextToken('回答', elapsedMilliseconds: 325);
    final result = collector.complete(
      totalElapsedMilliseconds: 425,
      nativeSessionRebuilt: true,
      sessionResetReason: 'fresh_turn_context_bound',
    );

    expect(result.text, 'PocketGallery回答');
    expect(result.telemetry.generationMs, 425);
    expect(result.telemetry.ttftMs, 125);
    expect(result.telemetry.outputTokens, 3);
    expect(result.telemetry.decodeTokensPerSecond, closeTo(6.6667, 0.0001));
    expect(result.telemetry.backend, isNull);
    expect(result.telemetry.nativeSessionRebuilt, isTrue);
    expect(
      result.telemetry.sessionResetReason,
      'fresh_turn_context_bound',
    );
  });

  test('one streamed token has no measurable decode rate', () {
    final collector = StreamingGenerationCollector();

    collector.addTextToken('完整回答', elapsedMilliseconds: 80);
    final result = collector.complete(totalElapsedMilliseconds: 100);

    expect(result.text, '完整回答');
    expect(result.telemetry.ttftMs, 80);
    expect(result.telemetry.outputTokens, 1);
    expect(result.telemetry.decodeTokensPerSecond, isNull);
  });

  test('Gemma gateway returns budget and only measured generation latency',
      () async {
    final source =
        await File('lib/services/gemma_chat_service.dart').readAsString();
    expect(source, contains('Future<ChatTurnResult> sendTurn'));
    expect(source, contains('selectHistoryWithDecision'));
    expect(source, contains('GenerationTelemetry('));
    expect(source, contains('generationMs:'));
    expect(source, contains('ttftMs: null'));
    expect(source, contains('outputTokens: null'));
    expect(source, contains('decodeTokensPerSecond: null'));
    expect(source, contains('backend: null'));
  });
}
