import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_models.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_parser.dart';

void main() {
  test('OKF v0.2 parser preserves trust lifecycle provenance and links', () {
    const markdown = '''
---
type: ProcessVersion
title: FR-Test Line 1 R19
description: Current line timing contract.
tags: [fr-test, line-1, timing]
status: stable
generated: { by: compiler/openwiki, at: 2026-09-01T00:00:00Z }
verified: { by: human:lab-expert, at: 2026-09-01T01:00:00Z }
stale_after: 2027-09-01T00:00:00Z
sources:
  - id: spec-r19
    resource: spec://FR-Test/SPEC-R19
    title: SPEC-R19
---
# Timing
C = 76 seconds.

See [X7 route](/vehicles/x7.md).
''';

    final concept = const OkfParser().parseConcept(
      path: 'lines/line1-r19.md',
      markdown: markdown,
    );

    expect(concept.id, 'lines/line1-r19');
    expect(concept.type, 'ProcessVersion');
    expect(concept.title, 'FR-Test Line 1 R19');
    expect(concept.tags, containsAll(<String>['fr-test', 'line-1', 'timing']));
    expect(concept.effectiveStatus, OkfStatus.stable);
    expect(concept.trustTier, OkfTrustTier.humanReviewed);
    expect(concept.generatedBy, 'compiler/openwiki');
    expect(concept.sources.single.id, 'spec-r19');
    expect(concept.sources.single.title, 'SPEC-R19');
    expect(concept.links, contains('/vehicles/x7.md'));
    expect(concept.isStaleAt(DateTime.utc(2026, 9, 5)), isFalse);
    expect(concept.isStaleAt(DateTime.utc(2027, 9, 1)), isTrue);
  });

  test('missing status is stable and machine verification is derived', () {
    const markdown = '''
---
type: Reference
title: Machine checked
verified:
  - { by: process:nightly, at: 2026-09-01T00:00:00Z }
---
Body.
''';

    final concept = const OkfParser().parseConcept(
      path: 'references/machine.md',
      markdown: markdown,
    );

    expect(concept.effectiveStatus, OkfStatus.stable);
    expect(concept.trustTier, OkfTrustTier.machineConfirmed);
  });
}
