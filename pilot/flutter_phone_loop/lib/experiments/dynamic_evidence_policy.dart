import 'dart:collection';

class DynamicEvidenceCandidate {
  const DynamicEvidenceCandidate({
    required this.candidateId,
    required this.chunkId,
    required this.documentId,
    required this.ordinal,
    required this.score,
    required this.tokenCount,
  });

  final String candidateId;
  final String chunkId;
  final String documentId;
  final int ordinal;
  final double score;
  final int tokenCount;
}

class DynamicEvidenceSelection {
  DynamicEvidenceSelection({
    required List<DynamicEvidenceCandidate> selected,
    required Map<String, String> dropReasons,
    required this.totalTokens,
  }) : selected = List.unmodifiable(selected),
       dropReasons = UnmodifiableMapView(dropReasons);

  final List<DynamicEvidenceCandidate> selected;
  final Map<String, String> dropReasons;
  final int totalTokens;
}

class DynamicEvidencePolicy {
  const DynamicEvidencePolicy({
    this.maxEvidence = 3,
    this.diversityBonus = 0.03,
  });

  final int maxEvidence;
  final double diversityBonus;

  DynamicEvidenceSelection select(
    List<DynamicEvidenceCandidate> candidates, {
    required int tokenReserve,
  }) {
    if (maxEvidence <= 0 || tokenReserve <= 0 || candidates.isEmpty) {
      return DynamicEvidenceSelection(
        selected: const <DynamicEvidenceCandidate>[],
        dropReasons: <String, String>{
          for (final candidate in candidates) candidate.chunkId: 'token_budget',
        },
        totalTokens: 0,
      );
    }
    final remaining = candidates.toList(growable: true);
    final selected = <DynamicEvidenceCandidate>[];
    final dropReasons = <String, String>{};
    var consumed = 0;

    while (remaining.isNotEmpty && selected.length < maxEvidence) {
      remaining.sort((left, right) {
        final leftAdjusted =
            left.score +
            (selected.any((item) => item.documentId == left.documentId)
                ? 0
                : diversityBonus);
        final rightAdjusted =
            right.score +
            (selected.any((item) => item.documentId == right.documentId)
                ? 0
                : diversityBonus);
        final scoreOrder = rightAdjusted.compareTo(leftAdjusted);
        if (scoreOrder != 0) return scoreOrder;
        return left.chunkId.compareTo(right.chunkId);
      });
      final candidate = remaining.removeAt(0);
      final nearNeighbor = selected.any(
        (item) =>
            item.documentId == candidate.documentId &&
            (item.ordinal - candidate.ordinal).abs() <= 1,
      );
      if (nearNeighbor) {
        dropReasons[candidate.chunkId] = 'near_neighbor_duplicate';
        continue;
      }
      if (consumed + candidate.tokenCount > tokenReserve) {
        dropReasons[candidate.chunkId] = 'token_budget';
        continue;
      }
      selected.add(candidate);
      consumed += candidate.tokenCount;
    }

    for (final candidate in remaining) {
      dropReasons[candidate.chunkId] = selected.length >= maxEvidence
          ? 'max_evidence'
          : 'not_selected';
    }
    return DynamicEvidenceSelection(
      selected: selected,
      dropReasons: dropReasons,
      totalTokens: consumed,
    );
  }
}
