import '../core/models.dart';
import 'retrieval_bundle.dart';

class RouterDecision {
  const RouterDecision({
    required this.useKnowledge,
    required this.reason,
    required this.ruleProfile,
    required this.ftsHitCount,
    required this.top1Cosine,
    required this.top2Cosine,
    required this.top1Top2Gap,
    required this.dualChannel,
    required this.lexicalGatePass,
    required this.semanticStrengthGatePass,
    required this.semanticGapGatePass,
  });

  final bool useKnowledge;
  final String reason;
  final String ruleProfile;
  final int ftsHitCount;
  final double? top1Cosine;
  final double? top2Cosine;
  final double? top1Top2Gap;
  final bool dualChannel;
  final bool lexicalGatePass;
  final bool semanticStrengthGatePass;
  final bool semanticGapGatePass;
}

class RouterPolicy {
  const RouterPolicy();

  RouterDecision evaluate({
    required List<RetrievalHit> lexicalHits,
    required List<RetrievalHit> semanticHits,
    required List<HybridHit> hybridHits,
    required bool evidenceAvailable,
    required String requestedMode,
  }) {
    final knowledgeMode = requestedMode == 'knowledge';
    final strongThreshold = knowledgeMode
        ? RetrievalBundle.semanticOnlyKnowledgeStrongThreshold
        : RetrievalBundle.semanticOnlyAutoStrongThreshold;
    final floor = knowledgeMode
        ? RetrievalBundle.semanticOnlyKnowledgeFloor
        : RetrievalBundle.semanticOnlyAutoFloor;
    final requiredGap = knowledgeMode
        ? RetrievalBundle.semanticOnlyKnowledgeGap
        : RetrievalBundle.semanticOnlyAutoGap;
    final top1 = semanticHits.isEmpty ? null : semanticHits.first.score;
    final top2 = semanticHits.length < 2 ? null : semanticHits[1].score;
    final gap = top1 == null
        ? null
        : top2 == null
            ? 0.0
            : top1 - top2;
    final dual = hybridHits.isNotEmpty &&
        hybridHits.first.channels.contains('fts5') &&
        hybridHits.first.channels.contains('embedding');
    final lexicalPass = lexicalHits.isNotEmpty;
    final semanticStrengthPass = top1 != null && top1 >= strongThreshold;
    final semanticGapPass =
        top1 != null && top1 >= floor && gap != null && gap >= requiredGap;
    final hasRankedEvidence = evidenceAvailable && hybridHits.isNotEmpty;

    late final bool useKnowledge;
    late final String reason;
    if (!hasRankedEvidence) {
      useKnowledge = false;
      reason = 'insufficient_evidence';
    } else if (dual) {
      useKnowledge = true;
      reason = 'dual_channel';
    } else if (lexicalPass) {
      useKnowledge = true;
      reason = 'lexical_hit';
    } else if (semanticStrengthPass) {
      useKnowledge = true;
      reason = 'semantic_strong';
    } else if (semanticGapPass) {
      useKnowledge = true;
      reason = 'semantic_gap';
    } else {
      useKnowledge = false;
      reason = 'insufficient_semantic';
    }

    return RouterDecision(
      useKnowledge: useKnowledge,
      reason: reason,
      ruleProfile: knowledgeMode ? 'r47-knowledge-v1' : 'r47-auto-v1',
      ftsHitCount: lexicalHits.length,
      top1Cosine: top1,
      top2Cosine: top2,
      top1Top2Gap: gap,
      dualChannel: dual,
      lexicalGatePass: lexicalPass,
      semanticStrengthGatePass: semanticStrengthPass,
      semanticGapGatePass: semanticGapPass,
    );
  }
}
