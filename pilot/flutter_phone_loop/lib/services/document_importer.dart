import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/chunker.dart';
import '../core/models.dart';

class DocumentImporter {
  DocumentImporter({PgChunker? chunker}) : chunker = chunker ?? const PgChunker();
  final PgChunker chunker;

  Future<List<String>> pickDocumentPaths() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
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
    final file = File(path);
    if (!await file.exists()) throw StateError('File not found: $path');
    final hash = (await sha256.bind(file.openRead()).first).toString();
    final sourceName = file.uri.pathSegments.isEmpty ? path : file.uri.pathSegments.last;
    final documentId = hash.substring(0, 20);
    final ext = sourceName.toLowerCase().split('.').last;

    final sections = switch (ext) {
      'txt' || 'md' => [TextSection('text', await file.readAsString())],
      'pdf' => await _readPdf(path),
      _ => throw UnsupportedError('Unsupported document type: .$ext'),
    };

    final chunks = chunker.chunkSections(
      documentId: documentId,
      sourceName: sourceName,
      sections: sections,
    );

    return ImportedDocument(
      documentId: documentId,
      sourceName: sourceName,
      sha256: hash,
      chunks: chunks,
    );
  }

  Future<List<TextSection>> _readPdf(String path) async {
    final doc = await PdfDocument.openFile(path);
    try {
      final out = <TextSection>[];
      for (var i = 0; i < doc.pages.length; i++) {
        final pageText = await doc.pages[i].loadText();
        out.add(TextSection('page ${i + 1}', pageText?.fullText ?? ''));
      }
      return out;
    } finally {
      await doc.dispose();
    }
  }
}
