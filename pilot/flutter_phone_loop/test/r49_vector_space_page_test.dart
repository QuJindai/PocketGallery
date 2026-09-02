import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/observability/trace_vector_space_service.dart';
import 'package:pocketgallery_phone_pilot/observability/vector_microscope_service.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/vector_microscope_page.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/vector_space_3d.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/vector_space_page.dart';

void main() {
  const queryPoint = TraceVectorPoint(
    embeddingId: 'query-embedding',
    chunkId: null,
    documentId: null,
    sourceName: '当前查询',
    locator: '',
    representation: EmbeddingRepresentation.query,
    x: 0,
    y: 0,
    z: 0,
    cosineToQuery: 1,
    isQuery: true,
    lane: RetrievalLane.active,
    text: '为什么界面要同时呈现答案与证据？',
    candidateId: null,
    sourceChannels: null,
    selectedForEvidence: false,
    selectionReason: null,
    dropReason: null,
    ftsRank: null,
    vectorRank: null,
    finalRank: null,
  );
  const evidencePoint = TraceVectorPoint(
    embeddingId: 'evidence-embedding',
    chunkId: 'chunk-18',
    documentId: 'doc-design',
    sourceName: '设计系统.md',
    locator: '第 4 章 / Chunk 18',
    representation: EmbeddingRepresentation.body,
    x: 0.32,
    y: 0.19,
    z: 0.18,
    cosineToQuery: 0.87,
    isQuery: false,
    lane: RetrievalLane.active,
    text: '稳定的界面不只要给出答案，还要让用户能够沿着证据回到原始上下文。',
    candidateId: 'candidate-18',
    sourceChannels: 'fts5+vector',
    selectedForEvidence: true,
    selectionReason: 'direct_support',
    dropReason: null,
    ftsRank: 2,
    vectorRank: 1,
    finalRank: 1,
  );
  const candidatePoint = TraceVectorPoint(
    embeddingId: 'candidate-embedding',
    chunkId: 'chunk-31',
    documentId: 'doc-interaction',
    sourceName: '交互原则.md',
    locator: '第 6 章 / Chunk 31',
    representation: EmbeddingRepresentation.body,
    x: 0.48,
    y: -0.22,
    z: -0.12,
    cosineToQuery: 0.64,
    isQuery: false,
    lane: RetrievalLane.active,
    text: '候选内容与查询接近，但没有直接支撑最终结论。',
    candidateId: 'candidate-31',
    sourceChannels: 'vector',
    selectedForEvidence: false,
    selectionReason: null,
    dropReason: 'max_evidence',
    ftsRank: null,
    vectorRank: 4,
    finalRank: 5,
  );
  const contextPoint = TraceVectorPoint(
    embeddingId: 'context-embedding',
    chunkId: 'chunk-42',
    documentId: 'doc-notes',
    sourceName: '知识库笔记.md',
    locator: 'Chunk 42',
    representation: EmbeddingRepresentation.body,
    x: -0.36,
    y: -0.11,
    z: 0.28,
    cosineToQuery: 0.41,
    isQuery: false,
    lane: null,
    text: '该切片属于查询附近的分层采样语料。',
    candidateId: null,
    sourceChannels: null,
    selectedForEvidence: false,
    selectionReason: null,
    dropReason: null,
    ftsRank: null,
    vectorRank: null,
    finalRank: null,
  );
  const traceData = TraceVectorSpaceSnapshot(
    queryEmbeddingId: 'query-embedding',
    queryVectorSha256: 'sha256-query',
    usedCapturedQuery: true,
    samplePolicy:
        'ACTIVE hits → SHADOW hits → deterministic document-stratified body fill',
    totalPersistentBodyCount: 332,
    points: <TraceVectorPoint>[
      evidencePoint,
      candidatePoint,
      contextPoint,
      queryPoint,
    ],
    neighbors: <TraceVectorPoint>[evidencePoint, candidatePoint],
    explainedVarianceRatios: <double>[0.52, 0.27, 0.11],
    originalDimension: 768,
    effectiveComponentCount: 3,
  );

  testWidgets('Trace vector view is readable, truthful and phone-safe', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(12),
            child: TraceVectorSpaceView(data: traceData),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('768D → 3D PCA'), findsOneWidget);
    expect(find.textContaining('解释方差'), findsOneWidget);
    expect(find.text('有效主成分 3/3'), findsOneWidget);
    expect(find.byType(InteractiveVectorPlot), findsOneWidget);
    expect(find.text('切片原文'), findsOneWidget);
    expect(find.textContaining('沿着证据回到原始上下文'), findsWidgets);
    expect(find.text('为何入选'), findsOneWidget);
    expect(find.text('直接支撑答案'), findsOneWidget);
    expect(find.text('开发者详情'), findsWidgets);
    expect(find.text('2D PCA'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'live microscope reuses rotatable 3D without claiming Trace truth',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const chunk = PgChunk(
        id: 'live-chunk',
        documentId: 'live-document',
        sourceName: '即时观测.md',
        locator: 'Chunk 1',
        ordinal: 0,
        text: '即时查询生成的最近邻切片。',
      );
      const data = VectorMicroscopeSnapshot(
        query: '即时查询',
        modelIdentity: 'EmbeddingGemma-test',
        dimension: 768,
        queryNorm: 1,
        queryFingerprint: 'sha256:live-query',
        points: <VectorMapPoint>[
          VectorMapPoint(
            id: '__query__',
            documentId: '',
            sourceName: 'Query',
            locator: '',
            x: 0,
            y: 0,
            z: 0,
            cosineToQuery: 1,
            isQuery: true,
          ),
          VectorMapPoint(
            id: 'live-chunk',
            documentId: 'live-document',
            sourceName: '即时观测.md',
            locator: 'Chunk 1',
            x: 0.4,
            y: 0.1,
            z: -0.2,
            cosineToQuery: 0.8,
            isQuery: false,
          ),
        ],
        neighbors: <VectorNeighbor>[
          VectorNeighbor(chunk: chunk, cosine: 0.8, norm: 1),
        ],
        explainedVarianceRatios: <double>[0.7, 0.2, 0.1],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(12),
              child: VectorMicroscopePlotSection(data: data),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(InteractiveVectorPlot), findsOneWidget);
      expect(find.textContaining('即时观测'), findsWidgets);
      expect(find.textContaining('不是历史 Trace'), findsOneWidget);
      expect(find.text('2D PCA'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
