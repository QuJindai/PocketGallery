import '../core/models.dart';

enum ProvenanceQuality { exact, legacy }

enum ParseStatus { parsed, empty, parseFailed, legacy }

extension ParseStatusStorage on ParseStatus {
  String get dbValue => switch (this) {
        ParseStatus.parsed => 'parsed',
        ParseStatus.empty => 'empty',
        ParseStatus.parseFailed => 'parse_failed',
        ParseStatus.legacy => 'legacy-existing',
      };
}

ParseStatus parseStatusFromDb(String value) => switch (value) {
      'parsed' => ParseStatus.parsed,
      'empty' => ParseStatus.empty,
      'parse_failed' => ParseStatus.parseFailed,
      'legacy-existing' => ParseStatus.legacy,
      _ => throw StateError('Unknown parse status: $value'),
    };

class LineageDocumentRecord {
  const LineageDocumentRecord({
    required this.documentId,
    required this.sourceName,
    required this.sha256,
    required this.fileType,
    required this.sizeBytes,
    required this.pageCount,
    required this.parseStatus,
    required this.parseErrorCode,
    required this.parseErrorDetail,
    required this.extractedCharCount,
    required this.emptyPageCount,
    required this.provenanceQuality,
    required this.importedAt,
  });

  final String documentId;
  final String sourceName;
  final String sha256;
  final String fileType;
  final int? sizeBytes;
  final int? pageCount;
  final ParseStatus parseStatus;
  final String? parseErrorCode;
  final String? parseErrorDetail;
  final int extractedCharCount;
  final int emptyPageCount;
  final ProvenanceQuality provenanceQuality;
  final DateTime importedAt;
}

class LineageSectionRecord {
  const LineageSectionRecord({
    required this.sectionId,
    required this.documentId,
    required this.pageNo,
    required this.heading,
    required this.sectionType,
    required this.startOffset,
    required this.endOffset,
    required this.charCount,
    required this.parseStatus,
  });

  final String sectionId;
  final String documentId;
  final int? pageNo;
  final String? heading;
  final String sectionType;
  final int? startOffset;
  final int? endOffset;
  final int charCount;
  final ParseStatus parseStatus;
}

class LineageChunkRecord {
  const LineageChunkRecord({
    required this.chunkId,
    required this.documentId,
    required this.sectionId,
    required this.locator,
    required this.ordinal,
    required this.startOffset,
    required this.endOffset,
    required this.charCount,
    required this.tokenCount,
    required this.overlapFromPrevious,
    required this.chunkStrategy,
    required this.boundaryReason,
    required this.provenanceQuality,
  });

  final String chunkId;
  final String documentId;
  final String? sectionId;
  final String locator;
  final int ordinal;
  final int? startOffset;
  final int? endOffset;
  final int charCount;
  final int? tokenCount;
  final int overlapFromPrevious;
  final String chunkStrategy;
  final String? boundaryReason;
  final ProvenanceQuality provenanceQuality;
}

class LineageImportResult {
  const LineageImportResult({
    required this.document,
    required this.lineageDocument,
    required this.sections,
    required this.chunks,
  });

  final ImportedDocument document;
  final LineageDocumentRecord lineageDocument;
  final List<LineageSectionRecord> sections;
  final List<LineageChunkRecord> chunks;
}
