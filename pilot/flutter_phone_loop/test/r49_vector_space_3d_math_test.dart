import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/ui/microscope/vector_space_3d.dart';

void main() {
  group('VectorProjection3d', () {
    test('yaw rotates PC1 from screen width into camera depth', () {
      const projector = VectorProjection3d();
      const point = VectorPlotPoint(
        id: 'pc1-point',
        x: 1,
        y: 0,
        z: 0,
        kind: VectorPlotKind.candidate,
      );

      final front = projector.project(
        points: const <VectorPlotPoint>[point],
        size: const Size(300, 300),
        camera: const VectorCamera(yaw: 0, pitch: 0, zoom: 1),
      );
      final turned = projector.project(
        points: const <VectorPlotPoint>[point],
        size: const Size(300, 300),
        camera: const VectorCamera(
          yaw: math.pi / 2,
          pitch: 0,
          zoom: 1,
        ),
      );

      expect(front.points.single.screen.dx, greaterThan(150));
      expect(turned.points.single.screen.dx, closeTo(150, 1e-6));
      expect(
        turned.points.single.depth,
        isNot(closeTo(front.points.single.depth, 1e-6)),
      );
    });

    test('pitch rotates PC2 into camera depth', () {
      const projector = VectorProjection3d();
      const point = VectorPlotPoint(
        id: 'pc2-point',
        x: 0,
        y: 1,
        z: 0,
        kind: VectorPlotKind.candidate,
      );

      final front = projector.project(
        points: const <VectorPlotPoint>[point],
        size: const Size(300, 300),
        camera: const VectorCamera(yaw: 0, pitch: 0, zoom: 1),
      );
      final turned = projector.project(
        points: const <VectorPlotPoint>[point],
        size: const Size(300, 300),
        camera: const VectorCamera(
          yaw: 0,
          pitch: 1.25,
          zoom: 1,
        ),
      );

      expect(front.points.single.screen.dy, lessThan(150));
      expect(
        (turned.points.single.screen.dy - 150).abs(),
        lessThan((front.points.single.screen.dy - 150).abs()),
      );
      expect(
        turned.points.single.depth,
        isNot(closeTo(front.points.single.depth, 1e-6)),
      );
    });

    test('far points are ordered before near points for canvas painting', () {
      const projector = VectorProjection3d();
      final frame = projector.project(
        points: const <VectorPlotPoint>[
          VectorPlotPoint(
            id: 'near',
            x: 0,
            y: 0,
            z: -1,
            kind: VectorPlotKind.context,
          ),
          VectorPlotPoint(
            id: 'far',
            x: 0,
            y: 0,
            z: 1,
            kind: VectorPlotKind.context,
          ),
        ],
        size: const Size(300, 300),
        camera: const VectorCamera(yaw: 0, pitch: 0, zoom: 1),
      );

      expect(
        frame.points.map((point) => point.point.id),
        orderedEquals(<String>['far', 'near']),
      );
    });

    test('zoom expands distance from the center without changing identity', () {
      const projector = VectorProjection3d();
      const point = VectorPlotPoint(
        id: 'zoom-point',
        x: 1,
        y: 0,
        z: 0,
        kind: VectorPlotKind.candidate,
      );

      final normal = projector.project(
        points: const <VectorPlotPoint>[point],
        size: const Size(320, 240),
        camera: const VectorCamera(yaw: 0, pitch: 0, zoom: 1),
      );
      final zoomed = projector.project(
        points: const <VectorPlotPoint>[point],
        size: const Size(320, 240),
        camera: const VectorCamera(yaw: 0, pitch: 0, zoom: 2),
      );

      final normalDistance = (normal.points.single.screen.dx - 160).abs();
      final zoomedDistance = (zoomed.points.single.screen.dx - 160).abs();
      expect(zoomed.points.single.point.id, 'zoom-point');
      expect(zoomedDistance, closeTo(normalDistance * 2, 1e-6));
    });

    test('degenerate and non-finite values produce finite screen coordinates',
        () {
      const projector = VectorProjection3d();
      final frame = projector.project(
        points: const <VectorPlotPoint>[
          VectorPlotPoint(
            id: 'origin',
            x: 0,
            y: 0,
            z: 0,
            kind: VectorPlotKind.context,
          ),
          VectorPlotPoint(
            id: 'invalid',
            x: double.nan,
            y: double.negativeInfinity,
            z: double.infinity,
            kind: VectorPlotKind.context,
          ),
        ],
        size: const Size(320, 240),
        camera: const VectorCamera(
          yaw: double.nan,
          pitch: double.infinity,
          zoom: double.negativeInfinity,
        ),
      );

      expect(frame.points, hasLength(2));
      expect(
        frame.points.every(
          (point) =>
              point.screen.dx.isFinite &&
              point.screen.dy.isFinite &&
              point.depth.isFinite,
        ),
        isTrue,
      );
      expect(
        frame.axes.every(
          (axis) =>
              axis.start.dx.isFinite &&
              axis.start.dy.isFinite &&
              axis.end.dx.isFinite &&
              axis.end.dy.isFinite,
        ),
        isTrue,
      );
    });

    test('camera bounds protect the phone interaction envelope', () {
      const camera = VectorCamera(
        yaw: double.nan,
        pitch: 99,
        zoom: -4,
      );

      expect(
        camera.clamped(),
        const VectorCamera(yaw: -0.58, pitch: 1.25, zoom: 0.62),
      );
      expect(
        const VectorCamera(pitch: -99, zoom: 99).clamped(),
        const VectorCamera(yaw: -0.58, pitch: -1.25, zoom: 2.2),
      );
    });
  });
}
