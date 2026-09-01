import 'dart:math' as math;

import 'package:flutter/material.dart';

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

class InteractiveVectorPlot extends StatefulWidget {
  const InteractiveVectorPlot({
    super.key,
    required this.points,
    required this.explainedVarianceRatios,
    this.initialSelectedId,
    this.onPointSelected,
  });

  final List<VectorPlotPoint> points;
  final List<double> explainedVarianceRatios;
  final String? initialSelectedId;
  final ValueChanged<String>? onPointSelected;

  @override
  State<InteractiveVectorPlot> createState() =>
      _InteractiveVectorPlotState();
}

class _InteractiveVectorPlotState extends State<InteractiveVectorPlot> {
  static const _defaultCamera = VectorCamera();

  VectorCamera camera = _defaultCamera;
  VectorCamera gestureStartCamera = _defaultCamera;
  Offset gestureStartFocalPoint = Offset.zero;
  String? selectedId;

  @override
  void initState() {
    super.initState();
    selectedId = widget.initialSelectedId;
  }

  @override
  void didUpdateWidget(covariant InteractiveVectorPlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelectedId != oldWidget.initialSelectedId &&
        selectedId == oldWidget.initialSelectedId) {
      selectedId = widget.initialSelectedId;
    }
    if (selectedId != null &&
        !widget.points.any((point) => point.id == selectedId)) {
      selectedId = widget.initialSelectedId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'PC1 / PC2 / PC3 · 真实三维视角',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            IconButton.filledTonal(
              key: const ValueKey<String>('vector-3d-reset'),
              tooltip: '重置三维视角',
              onPressed: () => setState(() => camera = _defaultCamera),
              icon: const Icon(Icons.center_focus_strong),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 330,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(
                constraints.maxWidth.isFinite ? constraints.maxWidth : 1,
                constraints.maxHeight.isFinite ? constraints.maxHeight : 1,
              );
              return Semantics(
                container: true,
                image: true,
                label: '三维向量图：单指旋转，双指缩放，点按查看证据',
                child: GestureDetector(
                  key: const ValueKey<String>('vector-3d-gesture-surface'),
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onTapUp: (details) => _handleTap(details.localPosition, size),
                  child: CustomPaint(
                    key: const ValueKey<String>('vector-3d-canvas'),
                    painter: VectorSpace3dPainter(
                      points: widget.points,
                      explainedVarianceRatios:
                          widget.explainedVarianceRatios,
                      camera: camera,
                      selectedId: selectedId,
                      queryColor: colors.error,
                      evidenceColor: colors.tertiary,
                      candidateColor: colors.primary,
                      contextColor: colors.outline,
                      foregroundColor: colors.onSurface,
                      surfaceColor: colors.surfaceContainerLowest,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: <Widget>[
            _VectorLegendItem(
              color: colors.error,
              shape: _LegendShape.diamond,
              label: 'Query',
            ),
            _VectorLegendItem(
              color: colors.tertiary,
              shape: _LegendShape.ring,
              label: 'Evidence',
            ),
            _VectorLegendItem(
              color: colors.primary,
              shape: _LegendShape.circle,
              label: '检索候选',
            ),
            _VectorLegendItem(
              color: colors.outline,
              shape: _LegendShape.circle,
              label: '邻域语料',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '单指旋转 · 双指缩放 · 点按查看证据',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    gestureStartCamera = camera;
    gestureStartFocalPoint = details.focalPoint;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      setState(
        () => camera = gestureStartCamera.copyWith(
          zoom: gestureStartCamera.zoom * details.scale,
        ),
      );
      return;
    }
    final delta = details.focalPoint - gestureStartFocalPoint;
    setState(
      () => camera = gestureStartCamera.copyWith(
        yaw: gestureStartCamera.yaw + delta.dx * 0.012,
        pitch: gestureStartCamera.pitch + delta.dy * 0.01,
      ),
    );
  }

  void _handleTap(Offset localPosition, Size size) {
    final frame = const VectorProjection3d().project(
      points: widget.points,
      size: size,
      camera: camera,
    );
    ProjectedVectorPoint? closest;
    var closestDistance = 22.0;
    for (final point in frame.points) {
      final distance = (point.screen - localPosition).distance;
      if (distance <= closestDistance) {
        closest = point;
        closestDistance = distance;
      }
    }
    if (closest == null) return;
    setState(() => selectedId = closest!.point.id);
    widget.onPointSelected?.call(closest.point.id);
  }
}

class VectorSpace3dPainter extends CustomPainter {
  const VectorSpace3dPainter({
    required this.points,
    required this.explainedVarianceRatios,
    required this.camera,
    required this.selectedId,
    required this.queryColor,
    required this.evidenceColor,
    required this.candidateColor,
    required this.contextColor,
    required this.foregroundColor,
    required this.surfaceColor,
  });

  final List<VectorPlotPoint> points;
  final List<double> explainedVarianceRatios;
  final VectorCamera camera;
  final String? selectedId;
  final Color queryColor;
  final Color evidenceColor;
  final Color candidateColor;
  final Color contextColor;
  final Color foregroundColor;
  final Color surfaceColor;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = const VectorProjection3d().project(
      points: points,
      size: size,
      camera: camera,
    );
    _paintAxes(canvas, frame.axes);
    for (final projected in frame.points) {
      _paintPoint(canvas, projected);
    }
  }

  void _paintAxes(Canvas canvas, List<ProjectedVectorAxis> axes) {
    final axisColors = <Color>[queryColor, evidenceColor, candidateColor];
    for (var index = 0; index < axes.length; index++) {
      final axis = axes[index];
      final color = axisColors[index];
      canvas.drawLine(
        axis.start,
        axis.end,
        Paint()
          ..color = color.withValues(alpha: 0.58)
          ..strokeWidth = 1.4,
      );
      final ratio = index < explainedVarianceRatios.length
          ? explainedVarianceRatios[index]
          : null;
      final label = ratio == null || !ratio.isFinite
          ? axis.label
          : '${axis.label} ${(ratio * 100).toStringAsFixed(1)}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      textPainter.paint(canvas, axis.end + const Offset(4, -13));
    }
  }

  void _paintPoint(Canvas canvas, ProjectedVectorPoint projected) {
    final point = projected.point;
    final baseRadius = switch (point.kind) {
      VectorPlotKind.query => 7.5,
      VectorPlotKind.evidence => 6.4,
      VectorPlotKind.candidate => 4.6,
      VectorPlotKind.context => 3.2,
    };
    final radius = math.max(
      2.6,
      baseRadius * (0.82 + projected.perspective * 0.2),
    );
    final color = switch (point.kind) {
      VectorPlotKind.query => queryColor,
      VectorPlotKind.evidence => evidenceColor,
      VectorPlotKind.candidate => candidateColor,
      VectorPlotKind.context => contextColor,
    };
    final alpha = point.kind == VectorPlotKind.context ? 0.52 : 0.94;
    final fill = Paint()..color = color.withValues(alpha: alpha);
    if (point.kind == VectorPlotKind.query) {
      final path = Path()
        ..moveTo(projected.screen.dx, projected.screen.dy - radius)
        ..lineTo(projected.screen.dx + radius, projected.screen.dy)
        ..lineTo(projected.screen.dx, projected.screen.dy + radius)
        ..lineTo(projected.screen.dx - radius, projected.screen.dy)
        ..close();
      canvas.drawPath(path, fill);
    } else {
      canvas.drawCircle(projected.screen, radius, fill);
    }
    if (point.kind == VectorPlotKind.evidence) {
      canvas.drawCircle(
        projected.screen,
        radius + 2.8,
        Paint()
          ..color = evidenceColor.withValues(alpha: 0.72)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
    if (point.id == selectedId) {
      canvas.drawCircle(
        projected.screen,
        radius + 5,
        Paint()
          ..color = foregroundColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant VectorSpace3dPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.explainedVarianceRatios != explainedVarianceRatios ||
      oldDelegate.camera != camera ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.queryColor != queryColor ||
      oldDelegate.evidenceColor != evidenceColor ||
      oldDelegate.candidateColor != candidateColor ||
      oldDelegate.contextColor != contextColor ||
      oldDelegate.foregroundColor != foregroundColor ||
      oldDelegate.surfaceColor != surfaceColor;
}

enum _LegendShape { circle, diamond, ring }

class _VectorLegendItem extends StatelessWidget {
  const _VectorLegendItem({
    required this.color,
    required this.shape,
    required this.label,
  });

  final Color color;
  final _LegendShape shape;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CustomPaint(
            size: const Size.square(13),
            painter: _LegendPainter(color: color, shape: shape),
          ),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _LegendPainter extends CustomPainter {
  const _LegendPainter({required this.color, required this.shape});

  final Color color;
  final _LegendShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()..color = color;
    switch (shape) {
      case _LegendShape.circle:
        canvas.drawCircle(center, 4.2, paint);
        break;
      case _LegendShape.diamond:
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy - 5)
            ..lineTo(center.dx + 5, center.dy)
            ..lineTo(center.dx, center.dy + 5)
            ..lineTo(center.dx - 5, center.dy)
            ..close(),
          paint,
        );
        break;
      case _LegendShape.ring:
        canvas.drawCircle(center, 3.7, paint);
        canvas.drawCircle(
          center,
          5.7,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _LegendPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.shape != shape;
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
