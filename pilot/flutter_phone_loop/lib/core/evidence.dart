import 'models.dart';

class EvidencePackBuilder {
  const EvidencePackBuilder({
    this.maxEvidence = 5,
    this.maxCharsPerEvidence = 1400,
    this.minRelativeScore = 0.72,
  });

  final int maxEvidence;
  final int maxCharsPerEvidence;
  final double minRelativeScore;

  List<EvidenceItem> build(
    List<HybridHit> hits, {
    bool conservative = true,
  }) {
    if (hits.isEmpty || maxEvidence <= 0) return const [];

    final out = <EvidenceItem>[];
    final topScore = hits.first.score;
    for (final hit in hits) {
      if (out.length >= maxEvidence) break;
      if (conservative && out.isNotEmpty && topScore > 0) {
        final relative = hit.score / topScore;
        if (relative < minRelativeScore) break;
      }
      out.add(EvidenceItem(
        anchor: 'E${out.length + 1}',
        chunk: hit.chunk,
        score: hit.score,
      ));
    }
    return out;
  }

  String toPromptContext(List<EvidenceItem> evidence) {
    final b = StringBuffer();
    for (final e in evidence) {
      var text = e.chunk.text;
      if (text.length > maxCharsPerEvidence) {
        text = '${text.substring(0, maxCharsPerEvidence)}…';
      }
      b.writeln(
        '[${e.anchor}] source="${e.chunk.sourceName}" '
        'location="${e.chunk.locator}" chunk="${e.chunk.id}"',
      );
      b.writeln(text);
      b.writeln();
    }
    return b.toString();
  }
}

class CitationResolver {
  static final RegExp _pattern = RegExp(r'\[E(\d+)\]');

  List<String> extract(String answer, List<EvidenceItem> evidence) {
    final valid = evidence.map((e) => e.anchor).toSet();
    final out = <String>[];
    for (final m in _pattern.allMatches(answer)) {
      final anchor = 'E${m.group(1)}';
      if (valid.contains(anchor) && !out.contains(anchor)) out.add(anchor);
    }
    return out;
  }
}
