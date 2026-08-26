import 'models.dart';

class EvidencePackBuilder {
  const EvidencePackBuilder({this.maxEvidence = 5, this.maxCharsPerEvidence = 1400});

  final int maxEvidence;
  final int maxCharsPerEvidence;

  List<EvidenceItem> build(List<HybridHit> hits) {
    final out = <EvidenceItem>[];
    for (var i = 0; i < hits.length && i < maxEvidence; i++) {
      out.add(EvidenceItem(
        anchor: 'E${i + 1}',
        chunk: hits[i].chunk,
        score: hits[i].score,
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
