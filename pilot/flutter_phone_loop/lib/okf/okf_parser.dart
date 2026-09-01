import 'okf_models.dart';

class OkfParser {
  const OkfParser();

  OkfConcept parseConcept({
    required String path,
    required String markdown,
  }) {
    final lines = markdown.split(RegExp(r'\r?\n'));
    if (lines.isEmpty || lines.first.trim() != '---') {
      throw const FormatException('OKF concept requires YAML frontmatter');
    }
    var end = -1;
    for (var index = 1; index < lines.length; index++) {
      if (lines[index].trim() == '---') {
        end = index;
        break;
      }
    }
    if (end < 0) {
      throw const FormatException('Unterminated OKF frontmatter');
    }

    final front = lines.sublist(1, end);
    final body = lines.sublist(end + 1).join('\n').trim();
    final type = _scalar(front, 'type')?.trim() ?? '';
    if (type.isEmpty) {
      throw const FormatException('OKF concept type is required');
    }
    final id = _conceptId(path);
    final title = _unquote(_scalar(front, 'title') ?? _titleFromId(id));
    final description = _unquote(_scalar(front, 'description') ?? '');
    final tags = _inlineList(_scalar(front, 'tags'));
    final status = _parseStatus(_unquote(_scalar(front, 'status') ?? ''));
    final staleAfter = _parseDate(_unquote(_scalar(front, 'stale_after') ?? ''));

    final generatedMap = _inlineMap(_scalar(front, 'generated'));
    final generatedBy = _unquote(generatedMap['by'] ?? '');
    final generatedAt = _parseDate(_unquote(generatedMap['at'] ?? ''));

    final verifiedBy = <String>[];
    final verifiedInline = _inlineMap(_scalar(front, 'verified'));
    final inlineActor = verifiedInline['by'];
    if (inlineActor != null && inlineActor.trim().isNotEmpty) {
      verifiedBy.add(_unquote(inlineActor));
    }
    for (final line in _block(front, 'verified')) {
      final mapping = _inlineMap(line.trim().replaceFirst(RegExp(r'^-\s*'), ''));
      final actor = mapping['by'];
      if (actor != null && actor.trim().isNotEmpty) {
        verifiedBy.add(_unquote(actor));
      }
    }

    final sources = _parseSources(front);
    final links = <String>[
      for (final match in RegExp(r'\[[^\]]+\]\(([^)]+)\)').allMatches(body))
        if ((match.group(1) ?? '').trim().isNotEmpty)
          (match.group(1) ?? '').trim(),
    ];

    return OkfConcept(
      id: id,
      type: type,
      title: title,
      description: description,
      tags: List.unmodifiable(tags),
      status: status,
      staleAfter: staleAfter,
      generatedBy: generatedBy.isEmpty ? null : generatedBy,
      generatedAt: generatedAt,
      verifiedBy: List.unmodifiable(verifiedBy),
      sources: List.unmodifiable(sources),
      links: List.unmodifiable(links),
      body: body,
    );
  }

  OkfBundle parseBundle(Map<String, String> documents) {
    final concepts = <String, OkfConcept>{};
    for (final entry in documents.entries) {
      final concept = parseConcept(path: entry.key, markdown: entry.value);
      concepts[concept.id] = concept;
    }
    return OkfBundle(concepts);
  }

  List<OkfPassage> passages(OkfConcept concept) {
    final lines = concept.body.split(RegExp(r'\r?\n'));
    final passages = <OkfPassage>[];
    var heading = concept.title;
    final buffer = <String>[];

    void flush() {
      final text = buffer.join('\n').trim();
      if (text.isEmpty) return;
      passages.add(OkfPassage(
        conceptId: concept.id,
        heading: heading,
        ordinal: passages.length,
        text: '$heading\n$text',
      ));
      buffer.clear();
    }

    for (final line in lines) {
      final match = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(line.trim());
      if (match != null) {
        flush();
        heading = match.group(1)!.trim();
      } else if (line.trim().isEmpty) {
        if (buffer.isNotEmpty) flush();
      } else {
        buffer.add(line);
      }
    }
    flush();
    if (passages.isEmpty && concept.body.isNotEmpty) {
      passages.add(OkfPassage(
        conceptId: concept.id,
        heading: concept.title,
        ordinal: 0,
        text: '${concept.title}\n${concept.body}',
      ));
    }
    return passages;
  }

  String _conceptId(String path) {
    var id = path.replaceAll('\\', '/');
    while (id.startsWith('/')) {
      id = id.substring(1);
    }
    if (id.endsWith('.md')) id = id.substring(0, id.length - 3);
    return id;
  }

  String _titleFromId(String id) {
    final tail = id.split('/').last;
    return tail
        .split(RegExp(r'[-_]'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String? _scalar(List<String> lines, String key) {
    final pattern = RegExp('^${RegExp.escape(key)}: *(.*)\$');
    for (final line in lines) {
      if (line.startsWith(' ') || line.startsWith('\t')) continue;
      final match = pattern.firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
  }

  List<String> _block(List<String> lines, String key) {
    final start = lines.indexWhere((line) => line.trimRight() == '$key:');
    if (start < 0) return const <String>[];
    final out = <String>[];
    for (var index = start + 1; index < lines.length; index++) {
      final line = lines[index];
      if (line.isNotEmpty &&
          !line.startsWith(' ') &&
          !line.startsWith('\t')) {
        break;
      }
      out.add(line);
    }
    return out;
  }

  List<OkfSource> _parseSources(List<String> lines) {
    final block = _block(lines, 'sources');
    final out = <OkfSource>[];
    Map<String, String>? current;

    void emit() {
      final map = current;
      if (map == null) return;
      final resource = _unquote(map['resource'] ?? '');
      if (resource.isEmpty) return;
      out.add(OkfSource(
        id: _nullable(_unquote(map['id'] ?? '')),
        resource: resource,
        title: _nullable(_unquote(map['title'] ?? '')),
        author: _nullable(_unquote(map['author'] ?? '')),
        lastModified: _parseDate(_unquote(map['last_modified'] ?? '')),
      ));
    }

    for (final rawLine in block) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('- ')) {
        emit();
        current = <String, String>{};
        final rest = line.substring(2).trim();
        final colon = rest.indexOf(':');
        if (colon > 0) {
          current[rest.substring(0, colon).trim()] =
              rest.substring(colon + 1).trim();
        }
        continue;
      }
      if (current == null) continue;
      final colon = line.indexOf(':');
      if (colon > 0) {
        current[line.substring(0, colon).trim()] =
            line.substring(colon + 1).trim();
      }
    }
    emit();
    return out;
  }

  Map<String, String> _inlineMap(String? value) {
    if (value == null) return const <String, String>{};
    var text = value.trim();
    if (!text.startsWith('{') || !text.endsWith('}')) {
      return const <String, String>{};
    }
    text = text.substring(1, text.length - 1);
    final out = <String, String>{};
    for (final piece in text.split(',')) {
      final colon = piece.indexOf(':');
      if (colon <= 0) continue;
      out[piece.substring(0, colon).trim()] =
          piece.substring(colon + 1).trim();
    }
    return out;
  }

  List<String> _inlineList(String? value) {
    if (value == null) return const <String>[];
    var text = value.trim();
    if (!text.startsWith('[') || !text.endsWith(']')) {
      return text.isEmpty ? const <String>[] : <String>[_unquote(text)];
    }
    text = text.substring(1, text.length - 1);
    return <String>[
      for (final item in text.split(','))
        if (_unquote(item.trim()).isNotEmpty) _unquote(item.trim()),
    ];
  }

  OkfStatus? _parseStatus(String value) => switch (value.toLowerCase()) {
        'draft' => OkfStatus.draft,
        'stable' => OkfStatus.stable,
        'deprecated' => OkfStatus.deprecated,
        _ => null,
      };

  DateTime? _parseDate(String value) {
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _unquote(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2 &&
        ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
            (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  String? _nullable(String value) => value.isEmpty ? null : value;
}
