import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/observability/pca_projector.dart';

void main() {
  test('PCA projects one-dimensional variance deterministically', () {
    const projector = PcaProjector(iterations: 50);
    final projection = projector.project(const [
      PcaInput('a', [1, 0, 0]),
      PcaInput('b', [2, 0, 0]),
      PcaInput('c', [3, 0, 0]),
    ], components: 3);

    expect(projection.points.map((e) => e.id).toList(), ['a', 'b', 'c']);
    expect(projection.explainedVarianceRatios.first, closeTo(1, 1e-8));
    expect(projection.points[0].x, lessThan(0));
    expect(projection.points[1].x, closeTo(0, 1e-8));
    expect(projection.points[2].x, greaterThan(0));
    expect(projection.points.every((p) => p.y.abs() < 1e-8), isTrue);
  });

  test('PCA output is stable across repeated runs', () {
    const projector = PcaProjector(iterations: 60);
    const input = [
      PcaInput('a', [1, 2, 0, 1]),
      PcaInput('b', [2, 1, 1, 0]),
      PcaInput('c', [4, 2, 0, 1]),
      PcaInput('d', [0, 1, 3, 2]),
    ];
    final a = projector.project(input, components: 3);
    final b = projector.project(input, components: 3);
    for (var i = 0; i < a.points.length; i++) {
      expect(a.points[i].x, closeTo(b.points[i].x, 1e-10));
      expect(a.points[i].y, closeTo(b.points[i].y, 1e-10));
      expect(a.points[i].z, closeTo(b.points[i].z, 1e-10));
    }
    expect(a.explainedVarianceRatios, hasLength(3));
    expect(a.explainedVarianceRatios.every((v) => v >= 0 && v <= 1), isTrue);
  });

  test('PCA rejects inconsistent vector dimensions', () {
    const projector = PcaProjector();
    expect(
      () => projector.project(const [
        PcaInput('a', [1, 2]),
        PcaInput('b', [1, 2, 3]),
      ]),
      throwsArgumentError,
    );
  });
}
