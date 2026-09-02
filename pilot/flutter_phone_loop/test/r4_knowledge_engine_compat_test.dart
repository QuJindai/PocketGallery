import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R4 keeps R3 diagnostics and exposes document management', () async {
    final source = await File('lib/services/knowledge_engine.dart')
        .readAsString();
    expect(source, contains('KnowledgeRetriever'));
    expect(source, contains('Future<ImportedDocument> importPath'));
    expect(source, contains('Future<KnowledgeAnswer> ask'));
    expect(source, contains('Future<List<KnowledgeDocument>> listDocuments'));
    expect(source, contains('Future<void> removeDocument'));
    expect(source, contains('Future<void> rebuildAllEmbeddings'));
  });
}
