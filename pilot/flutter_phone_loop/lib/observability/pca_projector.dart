import 'dart:math' as math;

class PcaInput {
  const PcaInput(this.id, this.vector);
  final String id;
  final List<double> vector;
}

class PcaPoint {
  const PcaPoint({
    required this.id,
    required this.x,
    required this.y,
    required this.z,
  });

  final String id;
  final double x;
  final double y;
  final double z;
}

class PcaProjection {
  const PcaProjection({
    required this.points,
    required this.explainedVarianceRatios,
    required this.originalDimension,
  });

  final List<PcaPoint> points;
  final List<double> explainedVarianceRatios;
  final int originalDimension;
}

class PcaProjector {
  const PcaProjector({this.iterations = 40});
  final int iterations;

  PcaProjection project(
    List<PcaInput> input, {
    int components = 3,
  }) {
    if (input.isEmpty) {
      return const PcaProjection(
        points: [],
        explainedVarianceRatios: [],
        originalDimension: 0,
      );
    }
    final dimension = input.first.vector.length;
    if (dimension == 0 || input.any((e) => e.vector.length != dimension)) {
      throw ArgumentError('All PCA vectors must share one non-zero dimension');
    }
    final k = components.clamp(1, math.min(3, dimension)).toInt();
    final mean = List<double>.filled(dimension, 0);
    for (final row in input) {
      for (var j = 0; j < dimension; j++) {
        mean[j] += row.vector[j];
      }
    }
    for (var j = 0; j < dimension; j++) {
      mean[j] /= input.length;
    }

    final centered = [
      for (final row in input)
        [for (var j = 0; j < dimension; j++) row.vector[j] - mean[j]],
    ];
    final denominator = input.length > 1 ? input.length - 1 : 1;
    var totalVariance = 0.0;
    for (final row in centered) {
      for (final value in row) {
        totalVariance += value * value;
      }
    }
    totalVariance /= denominator;

    final axes = <List<double>>[];
    final eigenvalues = <double>[];
    for (var component = 0; component < k; component++) {
      var v = _initialVector(dimension, component);
      _orthogonalize(v, axes);
      _normalizeInPlace(v);
      for (var iteration = 0; iteration < iterations; iteration++) {
        final next = _covarianceTimes(centered, v, denominator);
        _orthogonalize(next, axes);
        if (_norm(next) < 1e-14) {
          next.fillRange(0, next.length, 0);
          break;
        }
        _normalizeInPlace(next);
        v = next;
      }
      _fixSign(v);
      final cv = _covarianceTimes(centered, v, denominator);
      final eigenvalue = math.max(0, _dot(v, cv));
      axes.add(v);
      eigenvalues.add(eigenvalue);
    }

    final points = <PcaPoint>[];
    for (var i = 0; i < centered.length; i++) {
      final coordinates = [
        for (var c = 0; c < axes.length; c++) _dot(centered[i], axes[c]),
      ];
      points.add(PcaPoint(
        id: input[i].id,
        x: coordinates.isNotEmpty ? coordinates[0] : 0,
        y: coordinates.length > 1 ? coordinates[1] : 0,
        z: coordinates.length > 2 ? coordinates[2] : 0,
      ));
    }

    return PcaProjection(
      points: points,
      explainedVarianceRatios: [
        for (final eigenvalue in eigenvalues)
          totalVariance <= 1e-14 ? 0 : eigenvalue / totalVariance,
      ],
      originalDimension: dimension,
    );
  }

  List<double> _initialVector(int dimension, int component) => [
        for (var i = 0; i < dimension; i++)
          math.sin((i + 1) * (component + 1) * 0.731) +
              0.37 * math.cos((i + 1) * (component + 2) * 0.419),
      ];

  List<double> _covarianceTimes(
    List<List<double>> centered,
    List<double> v,
    int denominator,
  ) {
    final result = List<double>.filled(v.length, 0);
    for (final row in centered) {
      final projection = _dot(row, v);
      for (var j = 0; j < v.length; j++) {
        result[j] += row[j] * projection;
      }
    }
    for (var j = 0; j < result.length; j++) {
      result[j] /= denominator;
    }
    return result;
  }

  void _orthogonalize(List<double> v, List<List<double>> axes) {
    for (final axis in axes) {
      final projection = _dot(v, axis);
      for (var j = 0; j < v.length; j++) {
        v[j] -= projection * axis[j];
      }
    }
  }

  void _normalizeInPlace(List<double> v) {
    final n = _norm(v);
    if (n <= 1e-14) return;
    for (var i = 0; i < v.length; i++) {
      v[i] /= n;
    }
  }

  void _fixSign(List<double> v) {
    if (v.isEmpty) return;
    var index = 0;
    for (var i = 1; i < v.length; i++) {
      if (v[i].abs() > v[index].abs()) index = i;
    }
    if (v[index] < 0) {
      for (var i = 0; i < v.length; i++) {
        v[i] = -v[i];
      }
    }
  }

  double _dot(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  double _norm(List<double> v) => math.sqrt(_dot(v, v));
}
