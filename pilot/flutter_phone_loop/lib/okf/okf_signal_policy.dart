import 'dart:math' as math;

import 'okf_models.dart';

class OkfSignalScore {
  const OkfSignalScore({
    required this.baseScore,
    required this.trustAdjustment,
    required this.freshnessAdjustment,
    required this.linkAdjustment,
    required this.finalScore,
    required this.reason,
  });

  final double baseScore;
  final double trustAdjustment;
  final double freshnessAdjustment;
  final double linkAdjustment;
  final double finalScore;
  final String reason;

  double get totalAdjustment => finalScore - baseScore;
}

class OkfSignalPolicy {
  const OkfSignalPolicy();

  static const double _maxAbsoluteAdjustment = 0.08;

  OkfSignalScore score({
    required double baseScore,
    required OkfDocument? document,
    required int relativeLinkCount,
  }) {
    final trust = switch (document?.trustTier) {
      OkfTrustTier.verified => 0.035,
      OkfTrustTier.generated => 0.015,
      OkfTrustTier.provenance => 0.008,
      OkfTrustTier.typeOnly => 0.003,
      null => 0.0,
    };
    final freshness = switch (document?.freshness) {
      OkfFreshness.fresh => 0.005,
      OkfFreshness.stale => -0.035,
      OkfFreshness.deprecated => -0.060,
      OkfFreshness.unknown => 0.0,
      null => 0.0,
    };
    final safeLinks = math.max(0, relativeLinkCount);
    final links = math.min(0.015, safeLinks * 0.005).toDouble();
    final rawAdjustment = trust + freshness + links;
    final bounded = rawAdjustment
        .clamp(-_maxAbsoluteAdjustment, _maxAbsoluteAdjustment)
        .toDouble();
    final finalScore = baseScore + bounded;
    final trustLabel = document?.trustTier.name ?? 'no-okf';
    final freshnessLabel = document?.freshness.name ?? 'unknown';
    final reason =
        '$trustLabel ${_signed(trust)} · '
        '$freshnessLabel ${_signed(freshness)} · '
        'links($safeLinks) ${_signed(links)}';
    return OkfSignalScore(
      baseScore: baseScore,
      trustAdjustment: trust,
      freshnessAdjustment: freshness,
      linkAdjustment: links,
      finalScore: finalScore,
      reason: reason,
    );
  }

  String _signed(double value) =>
      value >= 0 ? '+${value.toStringAsFixed(3)}' : value.toStringAsFixed(3);
}
