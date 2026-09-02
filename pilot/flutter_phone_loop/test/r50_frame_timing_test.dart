import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/frame_timing_sampler.dart';

void main() {
  test('summary excludes ten warm-up frames and computes nearest-rank P95', () {
    final samples = <Duration>[
      for (var index = 0; index < 10; index++) const Duration(milliseconds: 90),
      for (var index = 0; index < 179; index++) const Duration(milliseconds: 8),
      const Duration(milliseconds: 16),
    ];

    final result = FrameTimingSummary.fromDurations(
      samples,
      sampleDuration: const Duration(seconds: 15),
    );

    expect(result.available, isTrue);
    expect(result.rawFrameCount, 190);
    expect(result.warmUpFrameCount, 10);
    expect(result.eligibleFrameCount, 180);
    expect(result.p95, const Duration(milliseconds: 8));
    expect(result.framesOver16Point7Count, 0);
    expect(result.framesOver32Ratio, 0);
  });

  test('empty post-warm-up sample is unavailable rather than a zero P95', () {
    final result = FrameTimingSummary.fromDurations(
      List<Duration>.filled(10, const Duration(milliseconds: 8)),
      sampleDuration: const Duration(seconds: 1),
    );

    expect(result.available, isFalse);
    expect(result.eligibleFrameCount, 0);
    expect(result.p95, isNull);
    expect(result.passesReleaseThreshold, isFalse);
  });

  test(
    'render gate enforces duration, frames, P95, and severe-jank limits',
    () {
      const passing = FrameTimingSummary(
        available: true,
        sampleDuration: Duration(seconds: 15),
        rawFrameCount: 190,
        warmUpFrameCount: 10,
        eligibleFrameCount: 180,
        p95: Duration(microseconds: 16600),
        framesOver16Point7Count: 0,
        framesOver16Point7Ratio: 0,
        framesOver32Count: 2,
        framesOver32Ratio: 0.01,
      );

      expect(passing.passesReleaseThreshold, isTrue);
      expect(
        _summary(sampleDuration: const Duration(milliseconds: 14999))
            .passesReleaseThreshold,
        isFalse,
      );
      expect(_summary(eligibleFrameCount: 179).passesReleaseThreshold, isFalse);
      expect(
        _summary(p95: const Duration(microseconds: 16701))
            .passesReleaseThreshold,
        isFalse,
      );
      expect(
        _summary(framesOver32Ratio: 0.01001).passesReleaseThreshold,
        isFalse,
      );
    },
  );

  test('sampler registers once and unregisters exactly once', () {
    Object? registeredCallback;
    var addCount = 0;
    var removeCount = 0;
    var now = DateTime.utc(2026, 9, 1);
    final sampler = FrameTimingSampler(
      clock: () => now,
      addTimingsCallback: (callback) {
        addCount += 1;
        registeredCallback = callback;
      },
      removeTimingsCallback: (callback) {
        removeCount += 1;
        expect(callback, same(registeredCallback));
      },
    );

    sampler.start();
    sampler.start();
    expect(addCount, 1);
    now = now.add(const Duration(seconds: 1));
    final result = sampler.stop();
    sampler.stop();
    sampler.dispose();

    expect(result.sampleDuration, const Duration(seconds: 1));
    expect(result.available, isFalse);
    expect(removeCount, 1);
  });
}

FrameTimingSummary _summary({
  Duration sampleDuration = const Duration(seconds: 15),
  int eligibleFrameCount = 180,
  Duration p95 = const Duration(microseconds: 16600),
  double framesOver32Ratio = 0.01,
}) {
  return FrameTimingSummary(
    available: true,
    sampleDuration: sampleDuration,
    rawFrameCount: eligibleFrameCount + 10,
    warmUpFrameCount: 10,
    eligibleFrameCount: eligibleFrameCount,
    p95: p95,
    framesOver16Point7Count: 0,
    framesOver16Point7Ratio: 0,
    framesOver32Count: 0,
    framesOver32Ratio: framesOver32Ratio,
  );
}
