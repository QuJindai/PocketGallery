import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/observability/retrieval_trace.dart';
import 'package:pocketgallery_phone_pilot/observability/retrieval_trace_store.dart';

void main() {
  test('retrieval trace round-trips real scores ranks timings and citations', () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = RetrievalTraceStore(database: db);
    await store.initialize();

    final trace = RetrievalTrace(
      traceId: 'trace-1',
      sessionId: 'session-1',
      query: '31 03 51 01 为什么一直等待',
      mode: 'knowledge',
      startedAt: DateTime.utc(2026, 8, 28, 1),
      completedAt: DateTime.utc(2026, 8, 28, 1, 0, 1),
      scopeDocumentIds: const {'doc-a'},
      timings: const TraceStageTiming(
        lexicalMs: 6,
        semanticMs: 41,
        fusionMs: 2,
        evidenceMs: 1,
        generationMs: 811,
      ),
      lexicalHits: const [
        TraceHit(
          channel: 'fts5',
          chunkId: 'chunk-1',
          documentId: 'doc-a',
          sourceName: 'calibration.txt',
          locator: 'p.12',
          rank: 1,
          rawScore: -8.42,
          normalizedScore: 0.106157,
        ),
      ],
      semanticHits: const [
        TraceHit(
          channel: 'embedding',
          chunkId: 'chunk-1',
          documentId: 'doc-a',
          sourceName: 'calibration.txt',
          locator: 'p.12',
          rank: 1,
          rawScore: 0.625,
          normalizedScore: 0.625,
        ),
      ],
      hybridHits: const [
        TraceHit(
          channel: 'hybrid',
          chunkId: 'chunk-1',
          documentId: 'doc-a',
          sourceName: 'calibration.txt',
          locator: 'p.12',
          rank: 1,
          rawScore: 0.1078,
          normalizedScore: 0.1078,
          lexicalRank: 1,
          semanticRank: 1,
          lexicalContribution: 0.01639,
          semanticContribution: 0.01885,
          dualChannelBonus: 0.035,
          exactTermBonus: 0.025,
        ),
      ],
      evidenceAnchors: const ['E1'],
      citations: const ['E1'],
      queryVectorFingerprint: 'sha256:abc',
    );

    await store.save(trace);
    final loaded = await store.get('trace-1');
    expect(loaded, isNotNull);
    expect(loaded!.query, trace.query);
    expect(loaded.timings.semanticMs, 41);
    expect(loaded.lexicalHits.single.rawScore, -8.42);
    expect(loaded.semanticHits.single.rawScore, 0.625);
    expect(loaded.hybridHits.single.lexicalContribution, 0.01639);
    expect(loaded.hybridHits.single.semanticRank, 1);
    expect(loaded.evidenceAnchors, ['E1']);
    expect(loaded.citations, ['E1']);
    expect(loaded.scopeDocumentIds, {'doc-a'});
    expect(loaded.queryVectorFingerprint, 'sha256:abc');

    final latest = await store.latestForSession('session-1');
    expect(latest?.traceId, 'trace-1');
  });

  test('trace persistence caps every candidate channel at twenty', () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = RetrievalTraceStore(database: db);
    await store.initialize();

    List<TraceHit> hits(String channel) => [
          for (var i = 0; i < 30; i++)
            TraceHit(
              channel: channel,
              chunkId: 'c$i',
              documentId: 'd',
              sourceName: 'd.txt',
              locator: '$i',
              rank: i + 1,
              rawScore: i.toDouble(),
              normalizedScore: i / 30,
            ),
        ];

    await store.save(RetrievalTrace(
      traceId: 'cap',
      sessionId: 's',
      query: 'q',
      mode: 'auto',
      startedAt: DateTime.utc(2026),
      completedAt: DateTime.utc(2026),
      scopeDocumentIds: const {},
      timings: const TraceStageTiming(),
      lexicalHits: hits('fts5'),
      semanticHits: hits('embedding'),
      hybridHits: hits('hybrid'),
      evidenceAnchors: const [],
      citations: const [],
    ));

    final loaded = (await store.get('cap'))!;
    expect(loaded.lexicalHits, hasLength(20));
    expect(loaded.semanticHits, hasLength(20));
    expect(loaded.hybridHits, hasLength(20));
  });
}
