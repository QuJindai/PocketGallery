enum OkfTrustTier { verified, generated, provenance, typeOnly }

enum OkfFreshness { fresh, stale, deprecated, unknown }

class OkfSource {
  const OkfSource({
    required this.location,
    required this.pin,
    required this.role,
    required this.licenses,
    required this.retrievedAt,
    required this.contentSha256,
  });

  final String location;
  final String? pin;
  final String? role;
  final List<String> licenses;
  final DateTime? retrievedAt;
  final String? contentSha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'location': location,
    if (pin != null) 'pin': pin,
    if (role != null) 'role': role,
    if (licenses.isNotEmpty) 'licenses': licenses,
    if (retrievedAt != null) 'retrieved_at': retrievedAt!.toIso8601String(),
    if (contentSha256 != null) 'content_sha256': contentSha256,
  };

  factory OkfSource.fromJson(Map<String, Object?> json) {
    final rawLicenses = json['licenses'];
    final licenses = rawLicenses is List
        ? rawLicenses.map((value) => value.toString()).toList(growable: false)
        : <String>[];
    return OkfSource(
      location: (json['location'] ?? '').toString(),
      pin: _nullableString(json['pin']),
      role: _nullableString(json['role']),
      licenses: licenses,
      retrievedAt: _parseDate(json['retrieved_at']),
      contentSha256: _nullableString(json['content_sha256']),
    );
  }
}

class OkfLink {
  const OkfLink({
    required this.documentId,
    required this.label,
    required this.target,
    required this.isRelativeBundleLink,
  });

  final String documentId;
  final String label;
  final String target;
  final bool isRelativeBundleLink;
}

class OkfDocument {
  const OkfDocument({
    required this.documentId,
    required this.sourceName,
    required this.type,
    required this.title,
    required this.trustTier,
    required this.freshness,
    required this.verifiedActors,
    required this.generatedActors,
    required this.sources,
    required this.status,
    required this.staleAfter,
    required this.supersededBy,
    required this.frontmatter,
  });

  final String documentId;
  final String sourceName;
  final String type;
  final String? title;
  final OkfTrustTier trustTier;
  final OkfFreshness freshness;
  final List<String> verifiedActors;
  final List<String> generatedActors;
  final List<OkfSource> sources;
  final String? status;
  final DateTime? staleAfter;
  final String? supersededBy;
  final Map<String, Object?> frontmatter;
}

class OkfParseResult {
  const OkfParseResult({
    required this.document,
    required this.links,
    required this.bodyStartOffset,
  });

  final OkfDocument document;
  final List<OkfLink> links;
  final int bodyStartOffset;
}

class OkfCandidateSignal {
  const OkfCandidateSignal({
    required this.traceId,
    required this.strategyId,
    required this.candidateId,
    required this.chunkId,
    required this.documentId,
    required this.baseScore,
    required this.trustAdjustment,
    required this.freshnessAdjustment,
    required this.linkAdjustment,
    required this.finalScore,
    required this.reason,
  });

  final String traceId;
  final String strategyId;
  final String candidateId;
  final String chunkId;
  final String documentId;
  final double baseScore;
  final double trustAdjustment;
  final double freshnessAdjustment;
  final double linkAdjustment;
  final double finalScore;
  final String reason;
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _parseDate(Object? value) {
  final text = _nullableString(value);
  if (text == null) return null;
  return DateTime.tryParse(text)?.toUtc();
}
