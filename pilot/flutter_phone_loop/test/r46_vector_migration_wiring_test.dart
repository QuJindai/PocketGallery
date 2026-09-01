import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'KnowledgeEngine boot wires additive R4.6 migration without rebuilding R4.5 stores',
    () async {
      final source = await File(
        'lib/services/knowledge_engine.dart',
      ).readAsString();

      expect(source, contains('LineageStore'));
      expect(source, contains('SqliteActiveVectorIndex'));
      expect(source, contains('R45VectorMigration'));
      expect(source, contains('TaskType.retrievalDocument'));

      final start = source.indexOf('Future<void> initialize() async');
      final end = source.indexOf('Future<ImportedDocument> importPath', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final initializeBody = source.substring(start, end);

      expect(initializeBody, contains('await lineageStore.initialize()'));
      expect(initializeBody, contains('await activeVectorIndex.initialize()'));
      expect(initializeBody, contains('FlutterGemma.hasActiveEmbedder()'));
      expect(initializeBody, contains('_r46MigrationReady'));
      expect(initializeBody, contains('await embedder.getDimension()'));
      expect(
        initializeBody,
        contains('await r45VectorMigration.migrateActiveBodyVectors'),
      );
      expect(initializeBody, contains('report.failed == 0'));
      expect(initializeBody, isNot(contains('rebuildAllEmbeddings')));
      expect(initializeBody, isNot(contains('semanticStore.clear')));
      expect(initializeBody, isNot(contains('observationStore.clear')));
    },
  );
}
