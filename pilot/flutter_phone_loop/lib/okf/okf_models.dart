import '../core/models.dart';

enum OkfStatus { draft, stable, deprecated }

enum OkfTrustTier { unverified, machineConfirmed, humanReviewed }

class OkfSource {
  const OkfSource({
    required this.resource,
    this.id,
    this.title,
    this.author,
    this.lastModified,
  });

  final String resource;
  final String? id;
  final String? title;
  final String? author;
  final DateTime? lastModified;
}

class OkfConcept {
  const OkfConcept({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.tags,
    required this.status,
    required this.staleAfter,
    required this.generatedBy,
    required this.generatedAt,
    required this.verifiedBy,
    required this.sources,
    required this.links,
    required this.body,
  });

  final String id;
  final String type;
  final String title;
  final String description;
  final List<String> tags;
  final OkfStatus? status;
  final DateTime? staleAfter;
  final String? generatedBy;
  final DateTime? generatedAt;
  final List<String> verifiedBy;
  final List<OkfSource> sources;
  final List<String> links;
  final String body;

  OkfStatus get effectiveStatus => status ?? OkfStatus.stable;

  OkfTrustTier get trustTier {
    if (verifiedBy.any((actor) => actor.startsWith('human:'))) {
      return OkfTrustTier.humanReviewed;
    }
    if (verifiedBy.isNotEmpty) return OkfTrustTier.machineConfirmed;
    return OkfTrustTier.unverified;
  }

  bool isStaleAt(DateTime now) {
    final expiry = staleAfter;
    if (expiry == null) return false;
    return !now.toUtc().isBefore(expiry.toUtc());
  }

  Set<String> get sourceIds => <String>{
        for (final source in sources)
          if (source.id != null && source.id!.isNotEmpty) source.id!,
      };
}

class OkfBundle {
  OkfBundle(Map<String, OkfConcept> concepts)
      : concepts = Map.unmodifiable(concepts);

  final Map<String, OkfConcept> concepts;

  OkfConcept? operator [](String id) => concepts[id];

  String? resolveConceptLink(String fromConceptId, String rawLink) {
    var link = rawLink.trim();
    if (link.isEmpty ||
        link.startsWith('http://') ||
        link.startsWith('https://') ||
        link.startsWith('spec://') ||
        link.startsWith('mailto:')) {
      return null;
    }
    final fragment = link.indexOf('#');
    if (fragment >= 0) link = link.substring(0, fragment);
    if (link.isEmpty) return null;

    final parts = <String>[];
    if (!link.startsWith('/')) {
      final fromParts = fromConceptId.split('/');
      if (fromParts.length > 1) {
        parts.addAll(fromParts.take(fromParts.length - 1));
      }
    }
    for (final raw in link.split('/')) {
      final part = raw.trim();
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    if (parts.isEmpty) return null;
    var id = parts.join('/');
    if (id.endsWith('.md')) id = id.substring(0, id.length - 3);
    return concepts.containsKey(id) ? id : null;
  }

  Set<String> neighbors(String conceptId) {
    final concept = concepts[conceptId];
    if (concept == null) return const <String>{};
    final out = <String>{};
    for (final link in concept.links) {
      final resolved = resolveConceptLink(conceptId, link);
      if (resolved != null) out.add(resolved);
    }
    for (final other in concepts.values) {
      if (other.id == conceptId) continue;
      for (final link in other.links) {
        if (resolveConceptLink(other.id, link) == conceptId) {
          out.add(other.id);
          break;
        }
      }
    }
    return out;
  }
}

class OkfPassage {
  const OkfPassage({
    required this.conceptId,
    required this.heading,
    required this.ordinal,
    required this.text,
  });

  final String conceptId;
  final String heading;
  final int ordinal;
  final String text;
}

class OkfOrdinaryChunk {
  const OkfOrdinaryChunk({
    required this.id,
    required this.documentId,
    required this.sourceName,
    required this.text,
  });

  final String id;
  final String documentId;
  final String sourceName;
  final String text;

  PgChunk toChunk() => PgChunk(
        id: id,
        documentId: documentId,
        sourceName: sourceName,
        locator: 'ordinary/$id',
        ordinal: 0,
        text: text,
      );
}

class OkfBenchmarkCase {
  const OkfBenchmarkCase({
    required this.id,
    required this.question,
    required this.expectedAnswerFragments,
    required this.expectedSourceIds,
    required this.note,
  });

  final String id;
  final String question;
  final List<String> expectedAnswerFragments;
  final List<String> expectedSourceIds;
  final String note;

  bool answerPasses(String answer) {
    final normalized = answer.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return expectedAnswerFragments.every(
      (fragment) => normalized.contains(
        fragment.toLowerCase().replaceAll(RegExp(r'\s+'), ''),
      ),
    );
  }
}
