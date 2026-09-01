import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/vector_interaction_evidence.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/observability/trace_vector_space_service.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/vector_space_3d.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/vector_space_page.dart';

void main() {
  test(
    'accumulator applies rotation, zoom, point, and viewport thresholds',
    () {
      final accumulator = VectorInteractionAccumulator(
        knownPointIds: const <String>{'query', 'chunk-1'},
      );
      const initial = VectorCamera(yaw: 0, pitch: 0, zoom: 1);

      accumulator.record(
        const VectorInteractionEvent(
          type: VectorInteractionType.rotation,
          cameraBefore: initial,
          cameraAfter: VectorCamera(yaw: 0.249, pitch: 0.149, zoom: 1),
          pointId: null,
        ),
      );
      expect(accumulator.rotationComplete, isFalse);
      accumulator.record(
        const VectorInteractionEvent(
          type: VectorInteractionType.rotation,
          cameraBefore: initial,
          cameraAfter: VectorCamera(yaw: 0.25, pitch: 0, zoom: 1),
          pointId: null,
        ),
      );
      expect(accumulator.rotationComplete, isTrue);

      accumulator.record(
        const VectorInteractionEvent(
          type: VectorInteractionType.zoom,
          cameraBefore: initial,
          cameraAfter: VectorCamera(yaw: 0, pitch: 0, zoom: 1.119),
          pointId: null,
        ),
      );
      expect(accumulator.zoomComplete, isFalse);
      accumulator.record(
        const VectorInteractionEvent(
          type: VectorInteractionType.zoom,
          cameraBefore: VectorCamera(yaw: 0, pitch: 0, zoom: 1.119),
          cameraAfter: VectorCamera(yaw: 0, pitch: 0, zoom: 1.12),
          pointId: null,
        ),
      );
      expect(accumulator.zoomComplete, isTrue);

      accumulator.record(
        const VectorInteractionEvent(
          type: VectorInteractionType.selection,
          cameraBefore: initial,
          cameraAfter: initial,
          pointId: 'synthetic-point',
        ),
      );
      expect(accumulator.selectionComplete, isFalse);
      accumulator.record(
        const VectorInteractionEvent(
          type: VectorInteractionType.selection,
          cameraBefore: initial,
          cameraAfter: initial,
          pointId: 'query',
        ),
      );
      expect(accumulator.selectionComplete, isTrue);
      expect(accumulator.selectedPointId, 'query');
      expect(accumulator.viewportConfirmed, isFalse);
      expect(accumulator.complete, isFalse);

      accumulator.confirmViewport();

      expect(accumulator.viewportConfirmed, isTrue);
      expect(accumulator.complete, isTrue);
    },
  );

  test('pitch alone can satisfy the rotation threshold', () {
    final accumulator = VectorInteractionAccumulator(
      knownPointIds: const <String>{'query'},
    );
    accumulator.record(
      const VectorInteractionEvent(
        type: VectorInteractionType.rotation,
        cameraBefore: VectorCamera(yaw: 0, pitch: 0, zoom: 1),
        cameraAfter: VectorCamera(yaw: 0.01, pitch: 0.15, zoom: 1),
        pointId: null,
      ),
    );

    expect(accumulator.rotationComplete, isTrue);
  });

  testWidgets('production plot emits one real event per completed gesture', (
    tester,
  ) async {
    final events = <VectorInteractionEvent>[];
    await _pumpPlot(tester, onInteraction: events.add);
    final surface = find.byKey(
      const ValueKey<String>('vector-3d-gesture-surface'),
    );

    await tester.drag(surface, const Offset(72, 34));
    await tester.pump();

    expect(events, hasLength(1));
    expect(events.single.type, VectorInteractionType.rotation);
    expect(
      events.single.cameraAfter.yaw,
      isNot(events.single.cameraBefore.yaw),
    );

    final center = tester.getCenter(surface);
    final first = await tester.startGesture(
      center - const Offset(28, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(28, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(center - const Offset(72, 0));
    await second.moveTo(center + const Offset(72, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump();

    expect(events, hasLength(2));
    expect(events.last.type, VectorInteractionType.zoom);
    expect(
      events.last.cameraAfter.zoom,
      greaterThan(events.last.cameraBefore.zoom),
    );

    await tester.tapAt(tester.getCenter(surface));
    await tester.pump();

    expect(events, hasLength(3));
    expect(events.last.type, VectorInteractionType.selection);
    expect(events.last.pointId, 'query');
  });

  testWidgets('Trace vector view forwards production interaction events', (
    tester,
  ) async {
    final events = <VectorInteractionEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TraceVectorSpaceView(
              data: _traceData,
              onInteraction: events.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surface = find.byKey(
      const ValueKey<String>('vector-3d-gesture-surface'),
    );
    await tester.ensureVisible(surface);
    await tester.pumpAndSettle();
    expect(surface.hitTestable(), findsOneWidget);
    expect(
      tester
          .widget<InteractiveVectorPlot>(find.byType(InteractiveVectorPlot))
          .onInteraction,
      isNotNull,
    );
    final before = _painter(tester).camera;
    await tester.drag(surface, const Offset(72, 0));
    await tester.pump();

    expect(_painter(tester).camera.yaw, isNot(before.yaw));
    expect(events, hasLength(1));
    expect(events.single.type, VectorInteractionType.rotation);
  });
}

Future<void> _pumpPlot(
  WidgetTester tester, {
  required ValueChanged<VectorInteractionEvent> onInteraction,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: InteractiveVectorPlot(
              points: const <VectorPlotPoint>[
                VectorPlotPoint(
                  id: 'query',
                  x: 0,
                  y: 0,
                  z: 0,
                  kind: VectorPlotKind.query,
                  label: 'Query',
                ),
                VectorPlotPoint(
                  id: 'chunk-1',
                  x: 1,
                  y: 0.2,
                  z: 0.1,
                  kind: VectorPlotKind.evidence,
                ),
              ],
              explainedVarianceRatios: const <double>[0.6, 0.3, 0.1],
              onInteraction: onInteraction,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

VectorSpace3dPainter _painter(WidgetTester tester) {
  return tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey<String>('vector-3d-canvas')),
          )
          .painter!
      as VectorSpace3dPainter;
}

const _traceData = TraceVectorSpaceSnapshot(
  queryEmbeddingId: 'query',
  queryVectorSha256: 'sha-query',
  usedCapturedQuery: true,
  samplePolicy: 'test',
  totalPersistentBodyCount: 1,
  points: <TraceVectorPoint>[
    TraceVectorPoint(
      embeddingId: 'chunk-1',
      chunkId: 'chunk-1',
      documentId: 'document-1',
      sourceName: 'truth.md',
      locator: 'section 1',
      representation: EmbeddingRepresentation.body,
      x: 1,
      y: 0.2,
      z: 0.1,
      cosineToQuery: 0.8,
      isQuery: false,
      lane: RetrievalLane.active,
      text: 'captured chunk',
      candidateId: 'candidate-1',
      sourceChannels: 'vector',
      selectedForEvidence: true,
      selectionReason: 'direct_support',
      dropReason: null,
      ftsRank: null,
      vectorRank: 1,
      finalRank: 1,
    ),
    TraceVectorPoint(
      embeddingId: 'query',
      chunkId: null,
      documentId: null,
      sourceName: 'Query',
      locator: '',
      representation: EmbeddingRepresentation.query,
      x: 0,
      y: 0,
      z: 0,
      cosineToQuery: 1,
      isQuery: true,
      lane: RetrievalLane.active,
      text: 'captured query',
      candidateId: null,
      sourceChannels: null,
      selectedForEvidence: false,
      selectionReason: null,
      dropReason: null,
      ftsRank: null,
      vectorRank: null,
      finalRank: null,
    ),
  ],
  neighbors: <TraceVectorPoint>[],
  explainedVarianceRatios: <double>[0.6, 0.3, 0.1],
  originalDimension: 4,
  effectiveComponentCount: 3,
);
