import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../observability/vector_microscope_service.dart';

class VectorMapPainter extends CustomPainter {
  VectorMapPainter({
    required this.points,
    required this.show3d,
    required this.queryColor,
    required this.lineColor,
  });

  final List<VectorMapPoint> points;
  final bool show3d;
  final Color queryColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    final projected = <VectorMapPoint, Offset>{};
    final xs = <double>[];
    final ys = <double>[];
    for (final point in points) {
      final x = show3d ? point.x + point.z * 0.35 : point.x;
      final y = show3d ? point.y - point.z * 0.22 : point.y;
      xs.add(x);
      ys.add(y);
    }
    var minX = xs.reduce(math.min);
    var maxX = xs.reduce(math.max);
    var minY = ys.reduce(math.min);
    var maxY = ys.reduce(math.max);
    if ((maxX - minX).abs() < 1e-12) {
      minX -= 1;
      maxX += 1;
    }
    if ((maxY - minY).abs() < 1e-12) {
      minY -= 1;
      maxY += 1;
    }

    const pad = 18.0;
    for (final point in points) {
      final rawX = show3d ? point.x + point.z * 0.35 : point.x;
      final rawY = show3d ? point.y - point.z * 0.22 : point.y;
      final x = pad +
          (rawX - minX) / (maxX - minX) * math.max(1, size.width - pad * 2);
      final y = pad +
          (1 - (rawY - minY) / (maxY - minY)) *
              math.max(1, size.height - pad * 2);
      projected[point] = Offset(x, y);
    }

    final query = points.where((p) => p.isQuery).firstOrNull;
    if (query != null) {
      final q = projected[query]!;
      final neighbors = points
          .where((p) => !p.isQuery && p.cosineToQuery != null)
          .toList()
        ..sort((a, b) =>
            (b.cosineToQuery ?? -1).compareTo(a.cosineToQuery ?? -1));
      final linePaint = Paint()
        ..color = lineColor.withValues(alpha: 0.35)
        ..strokeWidth = 1.2;
      for (final point in neighbors.take(5)) {
        canvas.drawLine(q, projected[point]!, linePaint);
      }
    }

    for (final point in points) {
      final offset = projected[point]!;
      if (point.isQuery) {
        final paint = Paint()..color = queryColor;
        canvas.drawCircle(offset, 7, paint);
        final ring = Paint()
          ..color = queryColor.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(offset, 11, ring);
        continue;
      }
      final paint = Paint()
        ..color = _documentColor(point.documentId).withValues(
          alpha: (0.38 + 0.58 * ((point.cosineToQuery ?? 0) + 1) / 2)
              .clamp(0.35, 0.95),
        );
      canvas.drawCircle(offset, 3.4, paint);
    }
  }

  Color _documentColor(String documentId) {
    var hash = 17;
    for (final unit in documentId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.58, 0.48).toColor();
  }

  @override
  bool shouldRepaint(covariant VectorMapPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.show3d != show3d;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
