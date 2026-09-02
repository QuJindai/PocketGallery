import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/experiments/retrieval_strategy.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_models.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_store.dart';
import 'package:pocketgallery_phone_pilot/services/document_importer.dart';

void main() {
  test('OKF markdown keeps normal chunks and adds a sidecar graph', () async {
    final tmp = await Directory.systemTemp.createTemp('pg-r47-okf-');
    addTearDown(() => tmp.delete(recursive: true));
    final file = File('${tmp.path}/concept.md');
    await file.writeAsString('''---
type: Concept
verified: human:qa
sources:
  - location: source/manual.md
---
# Torque
Torque limit is 320 Nm. See [Policy](policy.md).
''');

    final result = await DocumentImporter().importPathWithLineage(file.path);

    expect(result.document.chunks, isNotEmpty);
    expect(result.okf, isNotNull);
    expect(result.okf!.document.type, 'Concept');
    expect(result.okf!.document.trustTier, OkfTrustTier.verified);
    expect(result.okf!.links.single.target, 'policy.md');
  });

  test('ordinary markdown import remains OKF-free', () async {
    final tmp = await Directory.systemTemp.createTemp('pg-r47-plain-');
    addTearDown(() => tmp.delete(recursive: true));
    final file = File('${tmp.path}/plain.md');
    await file.writeAsString(
      '# Plain\nExisting Gallery behavior remains intact.',
    );

    final result = await DocumentImporter().importPathWithLineage(file.path);

    expect(result.document.chunks, isNotEmpty);
    expect(result.okf, isNull);
  });

  test('OKF store round-trips the sidecar graph in SQLite', () async {
    final tmp = await Directory.systemTemp.createTemp('pg-r47-store-');
    addTearDown(() => tmp.delete(recursive: true));
    final file = File('${tmp.path}/metric.md');
    await file.writeAsString('''---
type: Metric
generated: process:openwiki
stale_after: 2027-01-01
---
# FPY
See [Definition](definition.md).
''');
    final imported = await DocumentImporter().importPathWithLineage(file.path);
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = OkfStore(database: db);

    await store.replaceDocument(imported.document.documentId, imported.okf);

    final doc = await store.documentById(imported.document.documentId);
    final links = await store.linksForDocument(imported.document.documentId);
    expect(doc, isNotNull);
    expect(doc!.type, 'Metric');
    expect(doc.trustTier, OkfTrustTier.generated);
    expect(links.single.target, 'definition.md');
  });

  test('OKF experiment is registered as on-demand SHADOW only', () {
    final strategy = RetrievalStrategies.okfV02Structured;

    expect(strategy.id, 'shadow.okf-v02-structured');
    expect(strategy.onDemand, isTrue);
    expect(strategy.lane.name, 'shadow');
    expect(RetrievalStrategies.activeControl.id, 'active.r45-body-hybrid');
  });
}
