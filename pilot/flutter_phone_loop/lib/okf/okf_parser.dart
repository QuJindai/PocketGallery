import 'package:yaml/yaml.dart';

import 'okf_models.dart';

class OkfParseException implements Exception {
  const OkfParseException(this.message);

  final String message;

  @override
  String toString() => 'OkfParseException: $message';
}

class OkfParser {
  const OkfParser();

  OkfParseResult parseMarkdown(
    String markdown, {
    required String documentId,
    required String sourceName,
    DateTime? now,
  }) {
    final frontMatter = _readFrontMatter(markdown);
    if (frontMatter == null) {
      throw const OkfParseException(
        'OKF Markdown must start with YAML frontmatter and define type.',
      );
    }
    final map = _loadMap(frontMatter.yaml);
    return _parse(
      markdown: markdown,
      frontMatter: frontMatter,
      map: map,
      documentId: documentId,
      sourceName: sourceName,
      now: now,
    );
  }

  OkfParseResult? tryParseMarkdown(
    String markdown, {
    required String documentId,
    required String sourceName,
    DateTime? now,
  }) {
    final frontMatter = _readFrontMatter(markdown);
    if (frontMatter == null) return null;
    final map = _loadMap(frontMatter.yaml);
    final type = _string(map['type']);
    if (type == null) return null;
    return _parse(
      markdown: markdown,
      frontMatter: frontMatter,
      map: map,
      documentId: documentId,
      sourceName: sourceName,
      now: now,
    );
  }

  OkfParseResult _parse({
    required String markdown,
    required _FrontMatter frontMatter,
    required Map<String, Object?> map,
    required String documentId,
    required String sourceName,
    required DateTime? now,
  }) {
    final type = _string(map['type']);
    if (type == null) {
      throw const OkfParseException('OKF v0.2 requires a non-empty type.');
    }
    final body = markdown.substring(frontMatter.bodyStartOffset);
    final verified = _stringList(map['verified']);
    final generated = _stringList(map['generated']);
    final sources = _sources(map['sources']);
    final trustTier = verified.isNotEmpty
        ? OkfTrustTier.verified
        : generated.isNotEmpty
        ? OkfTrustTier.generated
        : sources.isNotEmpty
        ? OkfTrustTier.provenance
        : OkfTrustTier.typeOnly;
    final status = _string(map['status']);
    final staleAfter = _date(map['stale_after']);
    final referenceNow = (now ?? DateTime.now()).toUtc();
    final freshness = status?.toLowerCase() == 'deprecated'
        ? OkfFreshness.deprecated
        : staleAfter != null && referenceNow.isAfter(staleAfter)
        ? OkfFreshness.stale
        : staleAfter != null
        ? OkfFreshness.fresh
        : OkfFreshness.unknown;
    final title = _string(map['title']) ?? _firstHeading(body);
    final links = _links(body, documentId);

    return OkfParseResult(
      document: OkfDocument(
        documentId: documentId,
        sourceName: sourceName,
        type: type,
        title: title,
        trustTier: trustTier,
        freshness: freshness,
        verifiedActors: List<String>.unmodifiable(verified),
        generatedActors: List<String>.unmodifiable(generated),
        sources: List<OkfSource>.unmodifiable(sources),
        status: status,
        staleAfter: staleAfter,
        supersededBy: _string(map['superseded_by']),
        frontmatter: Map<String, Object?>.unmodifiable(map),
      ),
      links: List<OkfLink>.unmodifiable(links),
      bodyStartOffset: frontMatter.bodyStartOffset,
    );
  }

  _FrontMatter? _readFrontMatter(String markdown) {
    final match = RegExp(
      r'^---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|$)',
      dotAll: true,
    ).firstMatch(markdown);
    if (match == null) return null;
    return _FrontMatter(match.group(1) ?? '', match.end);
  }

  Map<String, Object?> _loadMap(String yaml) {
    try {
      final loaded = loadYaml(yaml);
      if (loaded is! Map) {
        throw const OkfParseException('OKF frontmatter must be a YAML map.');
      }
      final normalized = _normalize(loaded);
      if (normalized is! Map<String, Object?>) {
        throw const OkfParseException('OKF frontmatter is not map-shaped.');
      }
      return normalized;
    } on OkfParseException {
      rethrow;
    } catch (error) {
      throw OkfParseException('Invalid OKF YAML frontmatter: $error');
    }
  }

  Object? _normalize(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _normalize(entry.value),
      };
    }
    if (value is Iterable && value is! String) {
      return value.map(_normalize).toList(growable: false);
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) return value.toUtc().toIso8601String();
    return value.toString();
  }

  List<String> _stringList(Object? value) {
    if (value == null) return const <String>[];
    if (value is Iterable && value is! String) {
      return value.map(_string).whereType<String>().toList(growable: false);
    }
    final single = _string(value);
    return single == null ? const <String>[] : <String>[single];
  }

  List<OkfSource> _sources(Object? value) {
    if (value == null) return const <OkfSource>[];
    final rawItems = value is Iterable && value is! String
        ? value
        : <Object?>[value];
    final sources = <OkfSource>[];
    for (final raw in rawItems) {
      if (raw is String) {
        final location = raw.trim();
        if (location.isNotEmpty) {
          sources.add(
            OkfSource(
              location: location,
              pin: null,
              role: null,
              licenses: const <String>[],
              retrievedAt: null,
              contentSha256: null,
            ),
          );
        }
        continue;
      }
      if (raw is! Map) continue;
      final map = <String, Object?>{
        for (final entry in raw.entries) entry.key.toString(): entry.value,
      };
      final location = _string(map['location']);
      if (location == null) continue;
      final licenses = _stringList(map['licenses'] ?? map['license']);
      sources.add(
        OkfSource(
          location: location,
          pin: _string(map['pin']),
          role: _string(map['role']),
          licenses: licenses,
          retrievedAt: _date(map['retrieved_at']),
          contentSha256: _string(map['content_sha256']),
        ),
      );
    }
    return sources;
  }

  List<OkfLink> _links(String body, String documentId) {
    final links = <OkfLink>[];
    final expression = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
    for (final match in expression.allMatches(body)) {
      if (match.start > 0 && body[match.start - 1] == '!') continue;
      final label = (match.group(1) ?? '').trim();
      final target = (match.group(2) ?? '').trim();
      if (target.isEmpty) continue;
      links.add(
        OkfLink(
          documentId: documentId,
          label: label,
          target: target,
          isRelativeBundleLink: _isRelative(target),
        ),
      );
    }
    return links;
  }

  bool _isRelative(String target) {
    var value = target.trim();
    if (value.startsWith('<') && value.endsWith('>') && value.length > 2) {
      value = value.substring(1, value.length - 1);
    }
    if (value.startsWith('#') ||
        value.startsWith('/') ||
        value.startsWith('//')) {
      return false;
    }
    return !RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(value);
  }

  String? _firstHeading(String body) {
    final match = RegExp(r'^#\s+(.+?)\s*#?$', multiLine: true).firstMatch(body);
    return _string(match?.group(1));
  }

  String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  DateTime? _date(Object? value) {
    final text = _string(value);
    if (text == null) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      throw OkfParseException('Invalid OKF date: $text');
    }
    if (parsed.isUtc) return parsed;
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  }
}

class _FrontMatter {
  const _FrontMatter(this.yaml, this.bodyStartOffset);

  final String yaml;
  final int bodyStartOffset;
}
