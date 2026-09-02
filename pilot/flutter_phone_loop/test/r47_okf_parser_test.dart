import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/okf/okf_models.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_parser.dart';

void main() {
  const parser = OkfParser();

  test('OKF v0.2 requires type when parsed explicitly', () {
    expect(
      () => parser.parseMarkdown(
        '---\ntitle: Missing type\n---\n# Body',
        documentId: 'd-missing',
        sourceName: 'missing.md',
      ),
      throwsA(isA<OkfParseException>()),
    );
  });

  test('verified source freshness and relative links become typed signals', () {
    final parsed = parser.parseMarkdown(
      '''---
type: Concept
title: Motor Torque Limit
verified:
  - human:qa
sources:
  - location: docs/eol.md
    pin: abc123
    role: evidence
stale_after: 2026-12-31
---
# Motor Torque Limit
Use the validated limit. See [Brake Policy](../policy/brake.md).
''',
      documentId: 'd1',
      sourceName: 'motor.md',
      now: DateTime.utc(2026, 9, 2),
    );

    expect(parsed.document.type, 'Concept');
    expect(parsed.document.title, 'Motor Torque Limit');
    expect(parsed.document.trustTier, OkfTrustTier.verified);
    expect(parsed.document.freshness, OkfFreshness.fresh);
    expect(parsed.document.verifiedActors, contains('human:qa'));
    expect(parsed.document.sources.single.location, 'docs/eol.md');
    expect(parsed.links, hasLength(1));
    expect(parsed.links.single.label, 'Brake Policy');
    expect(parsed.links.single.target, '../policy/brake.md');
    expect(parsed.links.single.isRelativeBundleLink, isTrue);
  });

  test('stale and deprecated states fail closed for freshness', () {
    final stale = parser.parseMarkdown(
      '---\ntype: Policy\nstale_after: 2026-01-01\n---\nOld policy',
      documentId: 'stale',
      sourceName: 'stale.md',
      now: DateTime.utc(2026, 9, 2),
    );
    final deprecated = parser.parseMarkdown(
      '---\ntype: Policy\nstatus: deprecated\n---\nRetired policy',
      documentId: 'deprecated',
      sourceName: 'deprecated.md',
      now: DateTime.utc(2026, 9, 2),
    );

    expect(stale.document.freshness, OkfFreshness.stale);
    expect(deprecated.document.freshness, OkfFreshness.deprecated);
  });

  test('tryParseMarkdown does not classify ordinary markdown as OKF', () {
    expect(
      parser.tryParseMarkdown(
        '# Ordinary note\nNo YAML and no OKF type.',
        documentId: 'plain',
        sourceName: 'plain.md',
      ),
      isNull,
    );
    expect(
      parser.tryParseMarkdown(
        '---\ntitle: YAML note\n---\n# Still ordinary',
        documentId: 'yaml',
        sourceName: 'yaml.md',
      ),
      isNull,
    );
  });
}
