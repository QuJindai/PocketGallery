import 'dart:math' as math;

import 'package:flutter/widgets.dart';

enum VectorPlotKind { query, evidence, candidate, context }

class VectorPlotPoint {
  const VectorPlotPoint({
    required this.id,
    required this.x,
    required this.y,
    required this.z,
    required this.kind,
    this.label,
  });

  final String id;
  final double x;
  final double y;
  final double z;
  final VectorPlotKind kind;
  final String? label;
}

class VectorCamera {
  const VectorCamera({
    this.yaw = -0.58,
    this.pitch = 0.34,
    this.zoom = 1,
  });

  static const double minPitch = -1.25;
  static const double maxPitch = 1.25;
  static const double minZoom = 0.62;
  static const double maxZoom = 2.2;

  final double yaw;
  final double pitch;
  final double zoom;

  VectorCamera clamped() => VectorCamera(
        yaw: yaw.isFinite ? yaw : -0.58,
        pitch: (pitch.isFinite ? pitch : 0.34)
            .clamp(minPitch, maxPitch)
            .toDouble(),
        zoom: (zoom.isFinite ? zoom : 1)
            .clamp(minZoom, maxZoom)
            .toDouble(),
      );

  VectorCamera copyWith({double? yaw, double? pitch, double? zoom}) =>
      VectorCamera(
        yaw: yaw ?? this.yaw,
        pitch: pitch ?? this.pitch,
        zoom: zoom ?? this.zoom,
      ).clamped();

  @override
  bool operator ==(Object other) =>
      other is VectorCamera &&
      other.yaw == yaw &&
      other.pitch == pitch &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(yaw, pitch, zoom);
}

class ProjectedVectorPoint {
  const ProjectedVectorPoint({
    required this.point,
    required this.screen,
    required this.depth,
    required this.perspective,
  });

  final VectorPlotPoint point;
  final Offset screen;
  final double depth;
  final double perspective;
}

class ProjectedVectorAxis {
  const ProjectedVectorAxis({
    required this.label,
    required this.start,
    required this.end,
    required this.depth,
  });

  final String label;
  final Offset start;
  final Offset end;
  final double depth;
}

class VectorProjectionFrame {
  const VectorProjectionFrame({
    required this.points,
    required this.axes,
    required this.center,
    required this.radius,
  });

  /// Ordered from farthest to nearest for painter-order depth handling.
  final List<ProjectedVectorPoint> points;
  final List<ProjectedVectorAxis> axes;
  final Offset center;
  final double radius;
}

class VectorProjection3d {
  const VectorProjection3d({this.cameraDistance = 4});

  final double cameraDistance;

  VectorProjectionFrame project({
    required List<VectorPlotPoint> points,
    required Size size,
    required VectorCamera camera,
  }) {
    final safeCamera = camera.clamped();
    final width = size.width.isFinite && size.width > 0 ? size.width : 1.0;
    final height = size.height.isFinite && size.height > 0 ? size.height : 1.0;
    final center = Offset(width / 2, height / 2);
    final coordinates = <_VectorCoordinates>[
      for (final point in points)
        _VectorCoordinates(
          point: point,
          x: _finiteOrZero(point.x),
          y: _finiteOrZero(point.y),
          z: _finiteOrZero(point.z),
        ),
    ];
    var radius = 0.0;
    for (final coordinate in coordinates) {
      radius = math.max(
        radius,
        math.sqrt(
          coordinate.x * coordinate.x +
              coordinate.y * coordinate.y +
              coordinate.z * coordinate.z,
        ),
      );
    }
    if (!radius.isFinite || radius < 1e-12) radius = 1;
    final plotScale = math.min(width, height) * 0.36 * safeCamera.zoom;

    _ProjectedCoordinates projectCoordinates(double x, double y, double z) {
      final cameraPoint = _rotate(
        x / radius,
        y / radius,
        z / radius,
        safeCamera,
      );
      final distance = cameraDistance.isFinite && cameraDistance > 1.5
          ? cameraDistance
          : 4.0;
      final denominator = math.max(1.2, distance + cameraPoint.z);
      final perspective = distance / denominator;
      return _ProjectedCoordinates(
        screen: Offset(
          center.dx + cameraPoint.x * plotScale * perspective,
          center.dy - cameraPoint.y * plotScale * perspective,
        ),
        depth: cameraPoint.z,
        perspective: perspective,
      );
    }

    final projectedPoints = <ProjectedVectorPoint>[
      for (final coordinate in coordinates)
        (() {
          final projected = projectCoordinates(
            coordinate.x,
            coordinate.y,
            coordinate.z,
          );
          return ProjectedVectorPoint(
            point: coordinate.point,
            screen: projected.screen,
            depth: projected.depth,
            perspective: projected.perspective,
          );
        })(),
    ]
      ..sort((left, right) => right.depth.compareTo(left.depth));

    final origin = projectCoordinates(0, 0, 0);
    final axisLength = radius * 0.92;
    final axes = <ProjectedVectorAxis>[
      _axis('PC1', origin, projectCoordinates(axisLength, 0, 0)),
      _axis('PC2', origin, projectCoordinates(0, axisLength, 0)),
      _axis('PC3', origin, projectCoordinates(0, 0, axisLength)),
    ];

    return VectorProjectionFrame(
      points: List<ProjectedVectorPoint>.unmodifiable(projectedPoints),
      axes: List<ProjectedVectorAxis>.unmodifiable(axes),
      center: center,
      radius: radius,
    );
  }

  ProjectedVectorAxis _axis(
    String label,
    _ProjectedCoordinates start,
    _ProjectedCoordinates end,
  ) =>
      ProjectedVectorAxis(
        label: label,
        start: start.screen,
        end: end.screen,
        depth: end.depth,
      );

  _CameraCoordinates _rotate(
    double x,
    double y,
    double z,
    VectorCamera camera,
  ) {
    final cosYaw = math.cos(camera.yaw);
    final sinYaw = math.sin(camera.yaw);
    final cosPitch = math.cos(camera.pitch);
    final sinPitch = math.sin(camera.pitch);
    final yawX = cosYaw * x + sinYaw * z;
    final yawZ = -sinYaw * x + cosYaw * z;
    return _CameraCoordinates(
      x: yawX,
      y: cosPitch * y - sinPitch * yawZ,
      z: sinPitch * y + cosPitch * yawZ,
    );
  }

  double _finiteOrZero(double value) => value.isFinite ? value : 0;
}

class _VectorCoordinates {
  const _VectorCoordinates({
    required this.point,
    required this.x,
    required this.y,
    required this.z,
  });

  final VectorPlotPoint point;
  final double x;
  final double y;
  final double z;
}

class _CameraCoordinates {
  const _CameraCoordinates({
    required this.x,
    required this.y,
    required this.z,
  });

  final double x;
  final double y;
  final double z;
}

class _ProjectedCoordinates {
  const _ProjectedCoordinates({
    required this.screen,
    required this.depth,
    required this.perspective,
  });

  final Offset screen;
  final double depth;
  final double perspective;
}
