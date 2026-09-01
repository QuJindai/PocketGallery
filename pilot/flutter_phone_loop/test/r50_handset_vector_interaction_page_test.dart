import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/frame_timing_sampler.dart';
import 'package:pocketgallery_phone_pilot/acceptance/handset_acceptance_runner.dart';
import 'package:pocketgallery_phone_pilot/acceptance/vector_acceptance.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/observability/trace_vector_space_service.dart';
import 'package:pocketgallery_phone_pilot/ui/handset_vector_interaction_page.dart';

void main() {
  testWidgets(
    'real plot gestures unlock all task chips and viewport confirmation',
    (tester) async {
      _setPhoneSize(tester, const Size(412, 915));
      final timing = _FakeFrameTimingSampler(_passingFrameTiming);
      final interruption = ValueNotifier<String?>(null);
      final result = _ResultBox();
      await _openPage(
        tester,
        timing: timing,
        interruption: interruption,
        result: result,
        minimumDuration: const Duration(seconds: 1),
      );

      expect(find.text('已旋转'), findsNothing);
      expect(find.text('已缩放'), findsNothing);
      expect(find.text('已点选'), findsNothing);
      final surface = find.byKey(
        const ValueKey<String>('vector-3d-gesture-surface'),
      );
      await tester.ensureVisible(surface);
      await tester.pump();

      await tester.drag(surface, const Offset(72, 24));
      await tester.pump();
      expect(find.text('已旋转'), findsOneWidget);

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
      expect(find.text('已缩放'), findsOneWidget);

      await tester.tapAt(tester.getCenter(surface));
      await tester.pump();
      expect(find.text('已点选'), findsOneWidget);

      final confirm = find.byKey(
        const ValueKey<String>('handset-vector-confirm'),
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

      await tester.tap(confirm);
      await tester.pump();

      expect(result.value, isNotNull);
      expect(result.value!.rotationComplete, isTrue);
      expect(result.value!.zoomComplete, isTrue);
      expect(result.value!.selectionComplete, isTrue);
      expect(result.value!.viewportConfirmed, isTrue);
      expect(result.value!.reasonCode, isNull);
      expect(result.value!.frameTiming, same(_passingFrameTiming));
      expect(timing.startCount, 1);
      expect(timing.stopCount, 1);
    },
  );

  testWidgets('ninety-second timeout returns USER_ACTION_INCOMPLETE', (
    tester,
  ) async {
    _setPhoneSize(tester, const Size(412, 915));
    final timing = _FakeFrameTimingSampler(_passingFrameTiming);
    final result = _ResultBox();
    await _openPage(
      tester,
      timing: timing,
      interruption: ValueNotifier<String?>(null),
      result: result,
      timeout: const Duration(seconds: 90),
    );

    await tester.pump(const Duration(seconds: 91));
    await tester.pump();

    expect(result.value, isNotNull);
    expect(result.value!.reasonCode, 'USER_ACTION_INCOMPLETE');
    expect(result.value!.viewportConfirmed, isFalse);
    expect(timing.stopCount, 1);
  });

  testWidgets('lifecycle interruption returns APP_BACKGROUND_INTERRUPTION', (
    tester,
  ) async {
    _setPhoneSize(tester, const Size(412, 915));
    final timing = _FakeFrameTimingSampler(_passingFrameTiming);
    final interruption = ValueNotifier<String?>(null);
    final result = _ResultBox();
    await _openPage(
      tester,
      timing: timing,
      interruption: interruption,
      result: result,
    );

    interruption.value = 'APP_BACKGROUND_INTERRUPTION';
    await tester.pump();
    await tester.pump();

    expect(result.value, isNotNull);
    expect(result.value!.reasonCode, 'APP_BACKGROUND_INTERRUPTION');
    expect(timing.stopCount, 1);
  });

  testWidgets('guided page is overflow-free on both supported phone layouts', (
    tester,
  ) async {
    final variants = <({Size size, Brightness brightness, double scale})>[
      (size: const Size(360, 800), brightness: Brightness.light, scale: 1.3),
      (size: const Size(412, 915), brightness: Brightness.dark, scale: 1),
    ];

    for (final variant in variants) {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      final timing = _FakeFrameTimingSampler(_passingFrameTiming);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: variant.brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(variant.scale)),
            child: child!,
          ),
          home: HandsetVectorInteractionPage(
            artifact: _artifact,
            frameTimingSampler: timing,
            interruption: ValueNotifier<String?>(null),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('高维关系 · 物理交互验收'), findsOneWidget);
      expect(find.text('768D → 3D PCA'), findsOneWidget);
      expect(find.text('界面完整并继续'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void _setPhoneSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openPage(
  WidgetTester tester, {
  required _FakeFrameTimingSampler timing,
  required ValueNotifier<String?> interruption,
  required _ResultBox result,
  Duration minimumDuration = const Duration(seconds: 15),
  Duration timeout = const Duration(seconds: 90),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const ValueKey<String>('open-vector-acceptance'),
              onPressed: () async {
                result.value = await Navigator.of(context)
                    .push<VectorInteractionResult>(
                      MaterialPageRoute<VectorInteractionResult>(
                        builder: (context) => HandsetVectorInteractionPage(
                          artifact: _artifact,
                          frameTimingSampler: timing,
                          minimumDuration: minimumDuration,
                          timeout: timeout,
                          interruption: interruption,
                        ),
                      ),
                    );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('open-vector-acceptance')),
  );
  await tester.pump();
  await tester.pump();
}

final class _ResultBox {
  VectorInteractionResult? value;
}

final class _FakeFrameTimingSampler extends FrameTimingSampler {
  _FakeFrameTimingSampler(this.summary)
    : super(
        addTimingsCallback: (callback) {},
        removeTimingsCallback: (callback) {},
      );

  final FrameTimingSummary summary;
  bool running = false;
  int startCount = 0;
  int stopCount = 0;

  @override
  bool get isRunning => running;

  @override
  void start() {
    if (running) return;
    running = true;
    startCount += 1;
  }

  @override
  FrameTimingSummary stop() {
    if (running) {
      running = false;
      stopCount += 1;
    }
    return summary;
  }

  @override
  void dispose() {
    if (running) stop();
  }
}

final class _TestVectorArtifact implements VectorAcceptanceArtifact {
  const _TestVectorArtifact();

  @override
  String get traceId => 'trace-guided-vector';

  @override
  TraceVectorSpaceSnapshot get vectorSpace => _traceData;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const VectorAcceptanceArtifact _artifact = _TestVectorArtifact();

const TraceVectorPoint _queryPoint = TraceVectorPoint(
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
  text: '手机中的高维关系如何验证？',
  candidateId: null,
  sourceChannels: null,
  selectedForEvidence: false,
  selectionReason: null,
  dropReason: null,
  ftsRank: null,
  vectorRank: null,
  finalRank: null,
);

const TraceVectorPoint _evidencePoint = TraceVectorPoint(
  embeddingId: 'evidence-embedding',
  chunkId: 'chunk-1',
  documentId: 'document-1',
  sourceName: '证据.md',
  locator: 'Chunk 1',
  representation: EmbeddingRepresentation.body,
  x: 0.42,
  y: 0.24,
  z: 0.16,
  cosineToQuery: 0.89,
  isQuery: false,
  lane: RetrievalLane.active,
  text: '真实高维向量通过 PCA 投影到三维，并保留来源身份。',
  candidateId: 'candidate-1',
  sourceChannels: 'vector',
  selectedForEvidence: true,
  selectionReason: 'direct_support',
  dropReason: null,
  ftsRank: null,
  vectorRank: 1,
  finalRank: 1,
);

const TraceVectorPoint _candidatePoint = TraceVectorPoint(
  embeddingId: 'candidate-embedding',
  chunkId: 'chunk-2',
  documentId: 'document-2',
  sourceName: '候选.md',
  locator: 'Chunk 2',
  representation: EmbeddingRepresentation.body,
  x: -0.38,
  y: 0.31,
  z: -0.2,
  cosineToQuery: 0.67,
  isQuery: false,
  lane: RetrievalLane.active,
  text: '候选点用于验证三维空间中的相对关系。',
  candidateId: 'candidate-2',
  sourceChannels: 'fts5+vector',
  selectedForEvidence: false,
  selectionReason: null,
  dropReason: 'max_evidence',
  ftsRank: 2,
  vectorRank: 3,
  finalRank: 4,
);

const TraceVectorSpaceSnapshot _traceData = TraceVectorSpaceSnapshot(
  queryEmbeddingId: 'query-embedding',
  queryVectorSha256:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  usedCapturedQuery: true,
  samplePolicy: 'same-run captured query and candidates',
  totalPersistentBodyCount: 2,
  points: <TraceVectorPoint>[_evidencePoint, _candidatePoint, _queryPoint],
  neighbors: <TraceVectorPoint>[_evidencePoint, _candidatePoint],
  explainedVarianceRatios: <double>[0.56, 0.27, 0.12],
  originalDimension: 768,
  effectiveComponentCount: 3,
);

const FrameTimingSummary _passingFrameTiming = FrameTimingSummary(
  available: true,
  sampleDuration: Duration(seconds: 15),
  rawFrameCount: 190,
  warmUpFrameCount: 10,
  eligibleFrameCount: 180,
  p95: Duration(milliseconds: 16),
  framesOver16Point7Count: 0,
  framesOver16Point7Ratio: 0,
  framesOver32Count: 0,
  framesOver32Ratio: 0,
);
