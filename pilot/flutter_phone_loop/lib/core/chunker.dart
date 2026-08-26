import 'models.dart';

class TextSection {
  const TextSection(this.locator, this.text);
  final String locator;
  final String text;
}

class PgChunker {
  const PgChunker({
    this.targetChars = 900,
    this.overlapChars = 140,
    this.minChunkChars = 120,
  });

  final int targetChars;
  final int overlapChars;
  final int minChunkChars;

  List<PgChunk> chunkSections({
    required String documentId,
    required String sourceName,
    required List<TextSection> sections,
  }) {
    final out = <PgChunk>[];
    var ordinal = 0;
    for (final section in sections) {
      final normalized = _normalize(section.text);
      if (normalized.trim().isEmpty) continue;
      var start = 0;
      while (start < normalized.length) {
        var end = (start + targetChars).clamp(0, normalized.length).toInt();
        if (end < normalized.length) {
          final preferred = _preferredBoundary(normalized, start, end);
          if (preferred > start + minChunkChars) end = preferred;
        }
        final text = normalized.substring(start, end).trim();
        if (text.isNotEmpty) {
          out.add(PgChunk(
            id: '$documentId:$ordinal',
            documentId: documentId,
            sourceName: sourceName,
            locator: section.locator,
            ordinal: ordinal,
            text: text,
          ));
          ordinal++;
        }
        if (end >= normalized.length) break;
        final next = end - overlapChars;
        start = next > start ? next : end;
      }
    }
    return out;
  }

  String _normalize(String s) => s
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  int _preferredBoundary(String s, int start, int hardEnd) {
    const marks = '。！？；\n.!?;';
    final floor = start + (targetChars * 0.60).round();
    for (var i = hardEnd - 1; i >= floor; i--) {
      if (marks.contains(s[i])) return i + 1;
    }
    return hardEnd;
  }
}
