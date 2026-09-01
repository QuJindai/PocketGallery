import 'dart:collection';

import '../core/models.dart';

class EvidenceSelection {
  EvidenceSelection({
    required List<EvidenceItem> evidence,
    required Map<String, String> dropReasons,
  }) : evidence = List<EvidenceItem>.unmodifiable(evidence),
       dropReasons = UnmodifiableMapView<String, String>(dropReasons);

  final List<EvidenceItem> evidence;
  final Map<String, String> dropReasons;

  String? dropReasonFor(String chunkId) => dropReasons[chunkId];
}

class EvidencePolicy {
  const EvidencePolicy({this.maxEvidence = 5, this.minRelativeScore = 0.72});

  /// R4.7 raised ordinary evidence coverage to five. This remains independent
  /// from candidate retention, which is capped separately by lineage storage.
  final int maxEvidence;
  final double minRelativeScore;

  EvidenceSelection select(
    List<HybridHit> hits, {
    bool conservative = true,
    int? maxItems,
    int? maxTotalChars,
  }) {
    final itemLimit = maxItems ?? maxEvidence;
    final evidence = <EvidenceItem>[];
    final drops = <String, String>{};
    if (hits.isEmpty) {
      return EvidenceSelection(evidence: evidence, dropReasons: drops);
    }

    final topScore = hits.first.score;
    var consumedChars = 0;
    for (final hit in hits) {
      if (conservative && evidence.isNotEmpty && topScore > 0) {
        final relative = hit.score / topScore;
        if (relative < minRelativeScore) {
          drops[hit.chunk.id] = 'relative_score_cutoff';
          continue;
        }
      }
      if (evidence.length >= itemLimit) {
        drops[hit.chunk.id] = 'max_evidence';
        continue;
      }
      final nextChars = hit.chunk.text.length;
      if (maxTotalChars != null && consumedChars + nextChars > maxTotalChars) {
        drops[hit.chunk.id] = 'token_budget';
        continue;
      }
      evidence.add(
        EvidenceItem(
          anchor: 'E${evidence.length + 1}',
          chunk: hit.chunk,
          score: hit.score,
        ),
      );
      consumedChars += nextChars;
    }

    return EvidenceSelection(evidence: evidence, dropReasons: drops);
  }
}
