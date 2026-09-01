import 'package:flutter/scheduler.dart';

typedef FrameTimingsCallbackRegistrar = void Function(TimingsCallback callback);

class FrameTimingSummary {
  const FrameTimingSummary({
    required this.available,
    required this.sampleDuration,
    required this.rawFrameCount,
    required this.warmUpFrameCount,
    required this.eligibleFrameCount,
    required this.p95,
    required this.framesOver16Point7Count,
    required this.framesOver16Point7Ratio,
    required this.framesOver32Count,
    required this.framesOver32Ratio,
  });

  factory FrameTimingSummary.fromDurations(
    List<Duration> durations, {
    required Duration sampleDuration,
    int warmUpFrames = 10,
  }) {
    final normalizedWarmUp = warmUpFrames < 0 ? 0 : warmUpFrames;
    final skipped = normalizedWarmUp.clamp(0, durations.length).toInt();
    final eligible = durations.skip(skipped).toList(growable: false)
      ..sort((left, right) => left.compareTo(right));
    final over16Point7 = eligible
        .where((duration) => duration > const Duration(microseconds: 16700))
        .length;
    final over32 = eligible
        .where((duration) => duration > const Duration(milliseconds: 32))
        .length;
    final count = eligible.length;
    final p95Index = count == 0 ? null : (count * 0.95).ceil() - 1;
    return FrameTimingSummary(
      available: count > 0,
      sampleDuration: sampleDuration.isNegative
          ? Duration.zero
          : sampleDuration,
      rawFrameCount: durations.length,
      warmUpFrameCount: skipped,
      eligibleFrameCount: count,
      p95: p95Index == null ? null : eligible[p95Index],
      framesOver16Point7Count: over16Point7,
      framesOver16Point7Ratio: count == 0 ? 0 : over16Point7 / count,
      framesOver32Count: over32,
      framesOver32Ratio: count == 0 ? 0 : over32 / count,
    );
  }

  final bool available;
  final Duration sampleDuration;
  final int rawFrameCount;
  final int warmUpFrameCount;
  final int eligibleFrameCount;
  final Duration? p95;
  final int framesOver16Point7Count;
  final double framesOver16Point7Ratio;
  final int framesOver32Count;
  final double framesOver32Ratio;

  bool get passesReleaseThreshold {
    final percentile = p95;
    return available &&
        sampleDuration >= const Duration(seconds: 15) &&
        eligibleFrameCount >= 180 &&
        percentile != null &&
        percentile <= const Duration(microseconds: 16700) &&
        framesOver32Ratio <= 0.01;
  }
}

class FrameTimingSampler {
  FrameTimingSampler({
    DateTime Function()? clock,
    FrameTimingsCallbackRegistrar? addTimingsCallback,
    FrameTimingsCallbackRegistrar? removeTimingsCallback,
    this.warmUpFrames = 10,
  }) : _clock = clock ?? DateTime.now,
       _addTimingsCallback =
           addTimingsCallback ?? SchedulerBinding.instance.addTimingsCallback,
       _removeTimingsCallback =
           removeTimingsCallback ??
           SchedulerBinding.instance.removeTimingsCallback;

  final DateTime Function() _clock;
  final FrameTimingsCallbackRegistrar _addTimingsCallback;
  final FrameTimingsCallbackRegistrar _removeTimingsCallback;
  final int warmUpFrames;
  final List<Duration> _durations = <Duration>[];
  TimingsCallback? _registeredCallback;
  DateTime? _startedAt;
  FrameTimingSummary? _lastSummary;

  bool get isRunning => _registeredCallback != null;

  void start() {
    if (isRunning) return;
    _durations.clear();
    _lastSummary = null;
    _startedAt = _clock();
    final callback = _recordTimings;
    _registeredCallback = callback;
    _addTimingsCallback(callback);
  }

  FrameTimingSummary stop() {
    final callback = _registeredCallback;
    if (callback == null) {
      return _lastSummary ?? _emptySummary;
    }
    _registeredCallback = null;
    _removeTimingsCallback(callback);
    final startedAt = _startedAt;
    _startedAt = null;
    final stoppedAt = _clock();
    final duration = startedAt == null
        ? Duration.zero
        : stoppedAt.difference(startedAt);
    final summary = FrameTimingSummary.fromDurations(
      List<Duration>.of(_durations),
      sampleDuration: duration,
      warmUpFrames: warmUpFrames,
    );
    _lastSummary = summary;
    return summary;
  }

  void dispose() {
    if (isRunning) stop();
  }

  void _recordTimings(List<FrameTiming> timings) {
    if (!isRunning) return;
    _durations.addAll(timings.map((timing) => timing.totalSpan));
  }

  static const _emptySummary = FrameTimingSummary(
    available: false,
    sampleDuration: Duration.zero,
    rawFrameCount: 0,
    warmUpFrameCount: 0,
    eligibleFrameCount: 0,
    p95: null,
    framesOver16Point7Count: 0,
    framesOver16Point7Ratio: 0,
    framesOver32Count: 0,
    framesOver32Ratio: 0,
  );
}
