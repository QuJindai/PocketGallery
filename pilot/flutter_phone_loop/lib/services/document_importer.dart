import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/chunker.dart';
import '../core/models.dart';
import '../lineage/import_lineage.dart';
import '../lineage/lineage_ids.dart';

class DocumentImporter {
  DocumentImporter({PgChunker? chunker}) : chunker = chunker ?? const PgChunker();
  final PgChunker chunker;

  Future<List<String>> pickDocumentPaths() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'pdf'],
    );
    return result
        .map((f) => f.path)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toList();
  }

  Future<ImportedDocument> importPath(String path) async {
    return (await importPathWithLineage(path)).document;
  }

  Future<LineageImportResult> importPathWithLineage(String path) async {
    final file = File(path);
    if (!await file.exists()) throw StateError('File not found: $path');
    final hash = (await sha256.bind(file.openRead()).first).toString();
    final sourceName =
        file.uri.pathSegments.isEmpty ? path : file.uri.pathSegments.last;
    final documentId = hash.substring(0, 20);
    final ext = sourceName.toLowerCase().split('.').last;
    final stat = await file.stat();
    final importedAt = DateTime.now().toUtc();

    final parsed = switch (ext) {
      'txt' => await _readText(file, documentId),
      'md' => await _readMarkdown(file, documentId),
      'pdf' => await _readPdf(path, documentId),
      _ => throw UnsupportedError('Unsupported document type: .$ext'),
    };

    final chunkSlices = chunker.chunkSectionsWithLineage(
      documentId: documentId,
      sourceName: sourceName,
      sections: parsed.sections,
    );
    final document = ImportedDocument(
      documentId: documentId,
      sourceName: sourceName,
      sha256: hash,
      chunks: chunkSlices.map((slice) => slice.chunk).toList(growable: false),
    );
    final documentStatus = parsed.extractedCharCount == 0
        ? ParseStatus.empty
        : parsed.parseStatus;
    final zeroText = parsed.extractedCharCount == 0;

    return LineageImportResult(
      document: document,
      lineageDocument: LineageDocumentRecord(
        documentId: documentId,
        sourceName: sourceName,
        sha256: hash,
        fileType: ext,
        sizeBytes: stat.size,
        pageCount: parsed.pageCount,
        parseStatus: documentStatus,
        parseErrorCode:
            zeroText ? 'NO_EXTRACTED_TEXT' : parsed.parseErrorCode,
        parseErrorDetail: zeroText
            ? 'The parser produced no searchable text and therefore no chunks.'
            : parsed.parseErrorDetail,
        extractedCharCount: parsed.extractedCharCount,
        emptyPageCount: parsed.emptyPageCount,
        provenanceQuality: ProvenanceQuality.exact,
        importedAt: importedAt,
      ),
      sections: parsed.lineageSections,
      chunks: chunkSlices
          .map((slice) => LineageChunkRecord(
                chunkId: slice.chunk.id,
                documentId: slice.chunk.documentId,
                sectionId: slice.sectionId,
                locator: slice.chunk.locator,
                ordinal: slice.chunk.ordinal,
                startOffset: slice.startOffset,
                endOffset: slice.endOffset,
                charCount: slice.chunk.text.length,
                tokenCount: null,
                overlapFromPrevious: slice.overlapFromPrevious,
                chunkStrategy: 'r46-char-window-v1',
                boundaryReason: slice.boundaryReason,
                provenanceQuality: ProvenanceQuality.exact,
              ))
          .toList(growable: false),
    );
  }

  Future<_ParsedDocument> _readText(
    File file,
    String documentId,
  ) async {
    final text = await file.readAsString();
    final status = text.trim().isEmpty ? ParseStatus.empty : ParseStatus.parsed;
    const locator = 'text';
    final sectionId =
        LineageIds.sectionId(documentId, locator, null, 0, text.length);
    return _ParsedDocument(
      sections: [
        TextSection(
          locator,
          text,
          sectionId: sectionId,
          startOffset: 0,
        ),
      ],
      lineageSections: [
        LineageSectionRecord(
          sectionId: sectionId,
          documentId: documentId,
          pageNo: null,
          heading: null,
          sectionType: 'text',
          startOffset: 0,
          endOffset: text.length,
          charCount: text.length,
          parseStatus: status,
        ),
      ],
      pageCount: null,
      parseStatus: status,
      parseErrorCode: null,
      parseErrorDetail: null,
      extractedCharCount: text.length,
      emptyPageCount: 0,
    );
  }

  Future<_ParsedDocument> _readMarkdown(
    File file,
    String documentId,
  ) async {
    final text = await file.readAsString();
    final headings = RegExp(
      r'^(#{1,6})[ \t]+([^\r\n]+?)[ \t]*#*[ \t]*(?:\r)?$',
      multiLine: true,
    ).allMatches(text).toList(growable: false);
    final sections = <TextSection>[];
    final records = <LineageSectionRecord>[];

    void addSection({
      required int start,
      required int end,
      required String locator,
      required String? heading,
      required String sectionType,
    }) {
      final sectionText = text.substring(start, end);
      final status =
          sectionText.trim().isEmpty ? ParseStatus.empty : ParseStatus.parsed;
      final sectionId =
          LineageIds.sectionId(documentId, locator, null, start, end);
      sections.add(TextSection(
        locator,
        sectionText,
        sectionId: sectionId,
        startOffset: start,
      ));
      records.add(LineageSectionRecord(
        sectionId: sectionId,
        documentId: documentId,
        pageNo: null,
        heading: heading,
        sectionType: sectionType,
        startOffset: start,
        endOffset: end,
        charCount: sectionText.length,
        parseStatus: status,
      ));
    }

    if (headings.isEmpty) {
      addSection(
        start: 0,
        end: text.length,
        locator: 'text',
        heading: null,
        sectionType: 'text',
      );
    } else {
      if (headings.first.start > 0 &&
          text.substring(0, headings.first.start).trim().isNotEmpty) {
        addSection(
          start: 0,
          end: headings.first.start,
          locator: 'preamble',
          heading: null,
          sectionType: 'paragraph-group',
        );
      }
      for (var i = 0; i < headings.length; i++) {
        final heading = headings[i];
        final end = i + 1 < headings.length
            ? headings[i + 1].start
            : text.length;
        final headingText = heading.group(2)!.trim();
        addSection(
          start: heading.start,
          end: end,
          locator: 'heading ${i + 1}: $headingText',
          heading: headingText,
          sectionType: 'paragraph-group',
        );
      }
    }

    final status = text.trim().isEmpty ? ParseStatus.empty : ParseStatus.parsed;
    return _ParsedDocument(
      sections: sections,
      lineageSections: records,
      pageCount: null,
      parseStatus: status,
      parseErrorCode: null,
      parseErrorDetail: null,
      extractedCharCount: text.length,
      emptyPageCount: 0,
    );
  }

  Future<_ParsedDocument> _readPdf(String path, String documentId) async {
    final doc = await PdfDocument.openFile(path);
    try {
      final sections = <TextSection>[];
      final records = <LineageSectionRecord>[];
      var extractedCharCount = 0;
      var emptyPageCount = 0;
      for (var i = 0; i < doc.pages.length; i++) {
        final pageText = await doc.pages[i].loadText();
        final text = pageText?.fullText ?? '';
        final pageNo = i + 1;
        final locator = 'page $pageNo';
        final status =
            text.trim().isEmpty ? ParseStatus.empty : ParseStatus.parsed;
        if (status == ParseStatus.empty) emptyPageCount++;
        extractedCharCount += text.length;
        final sectionId =
            LineageIds.sectionId(documentId, locator, pageNo, 0, text.length);
        sections.add(TextSection(
          locator,
          text,
          sectionId: sectionId,
          startOffset: 0,
        ));
        records.add(LineageSectionRecord(
          sectionId: sectionId,
          documentId: documentId,
          pageNo: pageNo,
          heading: null,
          sectionType: 'page',
          startOffset: 0,
          endOffset: text.length,
          charCount: text.length,
          parseStatus: status,
        ));
      }
      return _ParsedDocument(
        sections: sections,
        lineageSections: records,
        pageCount: doc.pages.length,
        parseStatus: extractedCharCount == 0
            ? ParseStatus.empty
            : ParseStatus.parsed,
        parseErrorCode: null,
        parseErrorDetail: null,
        extractedCharCount: extractedCharCount,
        emptyPageCount: emptyPageCount,
      );
    } finally {
      await doc.dispose();
    }
  }
}

class _ParsedDocument {
  const _ParsedDocument({
    required this.sections,
    required this.lineageSections,
    required this.pageCount,
    required this.parseStatus,
    required this.parseErrorCode,
    required this.parseErrorDetail,
    required this.extractedCharCount,
    required this.emptyPageCount,
  });

  final List<TextSection> sections;
  final List<LineageSectionRecord> lineageSections;
  final int? pageCount;
  final ParseStatus parseStatus;
  final String? parseErrorCode;
  final String? parseErrorDetail;
  final int extractedCharCount;
  final int emptyPageCount;
}
