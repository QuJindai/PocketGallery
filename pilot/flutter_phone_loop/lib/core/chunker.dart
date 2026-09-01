import 'models.dart';

class TextSection {
  const TextSection(
    this.locator,
    this.text, {
    this.sectionId,
    this.startOffset,
  });

  final String locator;
  final String text;
  final String? sectionId;
  final int? startOffset;
}

class ChunkSlice {
  const ChunkSlice({
    required this.chunk,
    required this.sectionId,
    required this.startOffset,
    required this.endOffset,
    required this.overlapFromPrevious,
    required this.boundaryReason,
  });

  final PgChunk chunk;
  final String? sectionId;
  final int? startOffset;
  final int? endOffset;
  final int overlapFromPrevious;
  final String boundaryReason;
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
  }) => chunkSectionsWithLineage(
    documentId: documentId,
    sourceName: sourceName,
    sections: sections,
  ).map((slice) => slice.chunk).toList(growable: false);

  List<ChunkSlice> chunkSectionsWithLineage({
    required String documentId,
    required String sourceName,
    required List<TextSection> sections,
  }) {
    final out = <ChunkSlice>[];
    var ordinal = 0;
    for (final section in sections) {
      final mapped = _normalizeWithOffsets(section.text);
      final normalized = mapped.text;
      if (normalized.trim().isEmpty) continue;
      var start = 0;
      var previousEnd = 0;
      while (start < normalized.length) {
        var end = (start + targetChars).clamp(0, normalized.length).toInt();
        var boundaryReason = 'section_end';
        if (end < normalized.length) {
          final preferred = _preferredBoundary(normalized, start, end);
          if (preferred != null && preferred > start + minChunkChars) {
            end = preferred;
            boundaryReason = 'sentence_punctuation';
          } else {
            boundaryReason = 'hard_limit';
          }
        }
        final trimmed = _trimRange(normalized, start, end);
        final text = normalized.substring(trimmed.start, trimmed.end);
        if (text.isNotEmpty) {
          final chunk = PgChunk(
            id: '$documentId:$ordinal',
            documentId: documentId,
            sourceName: sourceName,
            locator: section.locator,
            ordinal: ordinal,
            text: text,
          );
          final sourceStart = section.startOffset == null
              ? null
              : section.startOffset! + mapped.rawStarts[trimmed.start];
          final sourceEnd = section.startOffset == null
              ? null
              : section.startOffset! + mapped.rawEnds[trimmed.end - 1];
          out.add(
            ChunkSlice(
              chunk: chunk,
              sectionId: section.sectionId,
              startOffset: sourceStart,
              endOffset: sourceEnd,
              overlapFromPrevious: previousEnd > trimmed.start
                  ? previousEnd - trimmed.start
                  : 0,
              boundaryReason: boundaryReason,
            ),
          );
          ordinal++;
          previousEnd = trimmed.end;
        }
        if (end >= normalized.length) break;
        final next = end - overlapChars;
        start = next > start ? next : end;
      }
    }
    return out;
  }

  _MappedText _normalizeWithOffsets(String source) {
    final chars = <int>[];
    final rawStarts = <int>[];
    final rawEnds = <int>[];
    var i = 0;
    var newlineRun = 0;
    while (i < source.length) {
      final code = source.codeUnitAt(i);
      if (code == 32 || code == 9) {
        final rawStart = i;
        while (i < source.length) {
          final current = source.codeUnitAt(i);
          if (current != 32 && current != 9) break;
          i++;
        }
        chars.add(32);
        rawStarts.add(rawStart);
        rawEnds.add(i);
        newlineRun = 0;
        continue;
      }

      if (code == 13 || code == 10) {
        final rawStart = i;
        if (code == 13 &&
            i + 1 < source.length &&
            source.codeUnitAt(i + 1) == 10) {
          i += 2;
        } else {
          i++;
        }
        if (newlineRun < 2) {
          chars.add(10);
          rawStarts.add(rawStart);
          rawEnds.add(i);
        } else if (rawEnds.isNotEmpty) {
          rawEnds[rawEnds.length - 1] = i;
        }
        newlineRun++;
        continue;
      }

      chars.add(code);
      rawStarts.add(i);
      rawEnds.add(i + 1);
      newlineRun = 0;
      i++;
    }

    final untrimmed = String.fromCharCodes(chars);
    final withoutLeft = untrimmed.trimLeft();
    final left = untrimmed.length - withoutLeft.length;
    final trimmed = withoutLeft.trimRight();
    final right = left + trimmed.length;
    return _MappedText(
      trimmed,
      rawStarts.sublist(left, right),
      rawEnds.sublist(left, right),
    );
  }

  _TextRange _trimRange(String text, int start, int end) {
    final raw = text.substring(start, end);
    final withoutLeft = raw.trimLeft();
    final left = raw.length - withoutLeft.length;
    final trimmed = withoutLeft.trimRight();
    return _TextRange(start + left, start + left + trimmed.length);
  }

  int? _preferredBoundary(String s, int start, int hardEnd) {
    const marks = '。！？；\n.!?;';
    final floor = start + (targetChars * 0.60).round();
    for (var i = hardEnd - 1; i >= floor; i--) {
      if (marks.contains(s[i])) return i + 1;
    }
    return null;
  }
}

class _MappedText {
  const _MappedText(this.text, this.rawStarts, this.rawEnds);

  final String text;
  final List<int> rawStarts;
  final List<int> rawEnds;
}

class _TextRange {
  const _TextRange(this.start, this.end);

  final int start;
  final int end;
}
