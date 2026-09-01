import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/ui/microscope/vector_space_3d.dart';

void main() {
  const points = <VectorPlotPoint>[
    VectorPlotPoint(
      id: 'query',
      x: 0,
      y: 0,
      z: 0,
      kind: VectorPlotKind.query,
      label: 'Query',
    ),
    VectorPlotPoint(
      id: 'evidence',
      x: 0.3,
      y: 0.2,
      z: 0.1,
      kind: VectorPlotKind.evidence,
      label: 'Evidence',
    ),
    VectorPlotPoint(
      id: 'candidate',
      x: 1,
      y: 0,
      z: 0,
      kind: VectorPlotKind.candidate,
    ),
    VectorPlotPoint(
      id: 'context',
      x: -0.7,
      y: 0.4,
      z: -0.2,
      kind: VectorPlotKind.context,
    ),
  ];

  Future<void> pumpPlot(
    WidgetTester tester, {
    ValueChanged<String>? onPointSelected,
    String? initialSelectedId = 'evidence',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: InteractiveVectorPlot(
                points: points,
                explainedVarianceRatios: const <double>[0.52, 0.27, 0.11],
                initialSelectedId: initialSelectedId,
                onPointSelected: onPointSelected,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  VectorSpace3dPainter painter(WidgetTester tester) =>
      tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey<String>('vector-3d-canvas')),
          )
          .painter! as VectorSpace3dPainter;

  testWidgets('single-finger drag rotates camera and reset restores it',
      (tester) async {
    await pumpPlot(tester);
    final before = painter(tester).camera;

    await tester.drag(
      find.byKey(const ValueKey<String>('vector-3d-gesture-surface')),
      const Offset(72, 34),
    );
    await tester.pump();

    final moved = painter(tester).camera;
    expect(moved.yaw, isNot(before.yaw));
    expect(moved.pitch, isNot(before.pitch));

    await tester.tap(
      find.byKey(const ValueKey<String>('vector-3d-reset')),
    );
    await tester.pump();

    expect(painter(tester).camera, const VectorCamera());
  });

  testWidgets('two-finger pinch changes zoom without exceeding bounds',
      (tester) async {
    await pumpPlot(tester);
    final surface =
        find.byKey(const ValueKey<String>('vector-3d-gesture-surface'));
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

    expect(painter(tester).camera.zoom, greaterThan(1));
    expect(painter(tester).camera.zoom, lessThanOrEqualTo(VectorCamera.maxZoom));

    await first.up();
    await second.up();
  });

  testWidgets('tapping the projected Query selects the real point id',
      (tester) async {
    String? selected;
    await pumpPlot(
      tester,
      initialSelectedId: null,
      onPointSelected: (id) => selected = id,
    );
    final surface =
        find.byKey(const ValueKey<String>('vector-3d-gesture-surface'));

    await tester.tapAt(tester.getCenter(surface));
    await tester.pump();

    expect(selected, 'query');
    expect(painter(tester).selectedId, 'query');
  });

  testWidgets('phone-width plot exposes gesture instructions without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    await pumpPlot(tester);

    expect(
      find.bySemanticsLabel('三维向量图：单指旋转，双指缩放，点按查看证据'),
      findsOneWidget,
    );
    expect(find.textContaining('单指旋转'), findsOneWidget);
    expect(find.text('Query'), findsOneWidget);
    expect(find.text('Evidence'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
