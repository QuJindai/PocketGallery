import '../core/models.dart';
import '../lineage/generation_models.dart';
import 'chat_models.dart';

class EvidenceContextSelection {
  const EvidenceContextSelection({
    required this.context,
    required this.includedItemCount,
    required this.trimmedItemCount,
    required this.trimDetails,
    required this.tokenCountsByAnchor,
  });

  final String context;
  final int includedItemCount;
  final int trimmedItemCount;
  final List<String> trimDetails;
  final Map<String, int> tokenCountsByAnchor;
}

class ContextSelection {
  const ContextSelection({required this.history, required this.decision});

  final List<ChatMessage> history;
  final ContextBudgetDecision decision;
}

class ContextBudgeter {
  const ContextBudgeter();

  static const modelMaxTokens = 8192;
  static const systemReserve = 700;
  static const outputReserve = 700;
  static const evidenceReserveMax = 1900;
  static const safetyReserve = 600;
  static const _evidenceHeaderTokensPerItem = 96;
  static const _truncationMarker = '…[context budget truncated]';

  int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    final cjk = RegExp(r'[\u3400-\u9FFF]').allMatches(text).length;
    final nonCjk = text.length - cjk;
    return cjk + (nonCjk / 4).ceil() + 8;
  }

  String composeEvidenceContext(
    List<EvidenceItem> evidence, {
    int maxTokens = evidenceReserveMax,
    int maxItems = 8,
  }) => composeEvidenceContextWithDecision(
    evidence,
    maxTokens: maxTokens,
    maxItems: maxItems,
  ).context;

  EvidenceContextSelection composeEvidenceContextWithDecision(
    List<EvidenceItem> evidence, {
    int maxTokens = evidenceReserveMax,
    int maxItems = 8,
  }) {
    final context = _composeEvidenceContext(
      evidence,
      maxTokens: maxTokens,
      maxItems: maxItems,
    );
    final considered = maxItems <= 0
        ? const <EvidenceItem>[]
        : evidence.take(maxItems).toList(growable: false);
    final included = context.isEmpty
        ? 0
        : considered
              .where((item) => context.contains('[${item.anchor}]'))
              .length;
    final trimmed = evidence.length - included;
    final details = <String>[
      if (evidence.length > considered.length)
        'evidence_max_items:${evidence.length - considered.length}',
      if (included < considered.length)
        'evidence_budget:${considered.length - included}',
      if (included > 0 &&
          considered
              .take(included)
              .any((item) => !context.contains(item.chunk.text)))
        'evidence_body_truncated',
    ];
    return EvidenceContextSelection(
      context: context,
      includedItemCount: included,
      trimmedItemCount: trimmed,
      trimDetails: List<String>.unmodifiable(details),
      tokenCountsByAnchor: Map<String, int>.unmodifiable(
        _evidenceTokenCounts(context, considered),
      ),
    );
  }

  Map<String, int> _evidenceTokenCounts(
    String context,
    List<EvidenceItem> considered,
  ) {
    if (context.isEmpty || considered.isEmpty) return const <String, int>{};
    final anchors = <({String anchor, int offset})>[];
    for (final item in considered) {
      final offset = context.indexOf('[${item.anchor}]');
      if (offset >= 0) anchors.add((anchor: item.anchor, offset: offset));
    }
    anchors.sort((a, b) => a.offset.compareTo(b.offset));
    final result = <String, int>{};
    var priorCumulative = 0;
    for (var index = 0; index < anchors.length; index++) {
      final end = index + 1 < anchors.length
          ? anchors[index + 1].offset
          : context.length;
      final cumulative = estimateTokens(context.substring(0, end).trimRight());
      result[anchors[index].anchor] = cumulative - priorCumulative;
      priorCumulative = cumulative;
    }
    return result;
  }

  String _composeEvidenceContext(
    List<EvidenceItem> evidence, {
    required int maxTokens,
    required int maxItems,
  }) {
    if (evidence.isEmpty || maxTokens <= 0 || maxItems <= 0) return '';

    final selected = evidence.take(maxItems).toList(growable: false);
    final minimumHeaders = [
      for (final item in selected) _minimumEvidenceHeader(item),
    ];
    var headers = minimumHeaders;
    var headerContext = headers.join('\n\n');

    if (estimateTokens(headerContext) <= maxTokens) {
      final preferredHeaderBudget =
          selected.length * _evidenceHeaderTokensPerItem;
      final headerBudget = preferredHeaderBudget < maxTokens
          ? preferredHeaderBudget
          : maxTokens;
      headers = _expandEvidenceHeaders(selected, minimumHeaders, headerBudget);
      headerContext = headers.join('\n\n');
    } else {
      headers = [for (final item in selected) '[${item.anchor}]'];
      headerContext = headers.join('\n\n');
      if (estimateTokens(headerContext) > maxTokens) {
        // A partial anchor list would misrepresent which evidence was supplied.
        return '';
      }
    }

    final bodyTokenBudget = maxTokens - estimateTokens(headerContext);
    if (bodyTokenBudget <= 0) return headerContext;

    final baseBodyBudget = bodyTokenBudget ~/ selected.length;
    final extraBodyTokens = bodyTokenBudget % selected.length;
    final bodies = <String>[];
    for (var i = 0; i < selected.length; i++) {
      final itemBudget = baseBodyBudget + (i < extraBodyTokens ? 1 : 0);
      bodies.add(trimTextToTokenBudget(selected[i].chunk.text, itemBudget));
    }

    final context = [
      for (var i = 0; i < selected.length; i++)
        bodies[i].isEmpty ? headers[i] : '${headers[i]}\n${bodies[i]}',
    ].join('\n\n');
    if (estimateTokens(context) <= maxTokens) return context;

    // Header reservations are authoritative. If estimator rounding ever makes
    // the combined bodies overflow, retain every identity and discard bodies.
    return headerContext;
  }

  List<String> _expandEvidenceHeaders(
    List<EvidenceItem> evidence,
    List<String> minimumHeaders,
    int maxTokens,
  ) {
    final fullHeaders = [
      for (final item in evidence) _fullEvidenceHeader(item),
    ];
    if (estimateTokens(fullHeaders.join('\n\n')) <= maxTokens) {
      return fullHeaders;
    }

    var longestField = 0;
    for (final item in evidence) {
      final chunk = item.chunk;
      for (final length in [
        chunk.sourceName.length,
        chunk.locator.length,
        chunk.id.length,
      ]) {
        if (length > longestField) longestField = length;
      }
    }

    var low = 10;
    var high = longestField;
    var best = minimumHeaders;
    while (low <= high) {
      final fieldLimit = (low + high) >> 1;
      final candidate = [
        for (final item in evidence) _limitedEvidenceHeader(item, fieldLimit),
      ];
      if (estimateTokens(candidate.join('\n\n')) <= maxTokens) {
        best = candidate;
        low = fieldLimit + 1;
      } else {
        high = fieldLimit - 1;
      }
    }
    return best;
  }

  String _minimumEvidenceHeader(EvidenceItem item) {
    final sourceIdentity = _stableFingerprint(item.chunk.sourceName);
    return '[${item.anchor}] source="#$sourceIdentity"';
  }

  String _fullEvidenceHeader(EvidenceItem item) {
    final chunk = item.chunk;
    return '[${item.anchor}] source="${chunk.sourceName}" '
        'location="${chunk.locator}" chunk="${chunk.id}"';
  }

  String _limitedEvidenceHeader(EvidenceItem item, int fieldLimit) {
    final chunk = item.chunk;
    return '[${item.anchor}] '
        'source="${_compactMetadata(chunk.sourceName, fieldLimit)}" '
        'location="${_compactMetadata(chunk.locator, fieldLimit)}" '
        'chunk="${_compactMetadata(chunk.id, fieldLimit)}"';
  }

  String _compactMetadata(String value, int maxChars) {
    if (value.isEmpty || maxChars <= 0) return '';
    if (value.length <= maxChars) return value;

    final suffix = '…#${_stableFingerprint(value)}';
    if (maxChars <= suffix.length) {
      return suffix;
    }
    final prefixLength = maxChars - suffix.length;
    return '${value.substring(0, prefixLength)}$suffix';
  }

  String _stableFingerprint(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  int availableHistoryTokens({
    int evidenceTokens = 0,
    int currentTurnTokens = 0,
  }) {
    final evidenceReserve = evidenceTokens.clamp(0, evidenceReserveMax);
    final budget =
        modelMaxTokens -
        systemReserve -
        outputReserve -
        safetyReserve -
        evidenceReserve -
        currentTurnTokens;
    return budget < 0 ? 0 : budget;
  }

  List<ChatMessage> selectHistory(
    List<ChatMessage> messages, {
    int evidenceTokens = 0,
    int currentTurnTokens = 0,
  }) => selectHistoryWithDecision(
    messages,
    evidenceTokens: evidenceTokens,
    currentTurnTokens: currentTurnTokens,
  ).history;

  ContextSelection selectHistoryWithDecision(
    List<ChatMessage> messages, {
    int evidenceTokens = 0,
    int currentTurnTokens = 0,
    int systemTokens = systemReserve,
    int evidenceItemCount = 0,
    int includedEvidenceItemCount = 0,
    List<String> trimDetails = const <String>[],
  }) {
    final budget =
        modelMaxTokens -
        outputReserve -
        safetyReserve -
        systemTokens -
        evidenceTokens -
        currentTurnTokens;

    var used = 0;
    final selected = <ChatMessage>[];
    if (budget > 0) {
      for (var i = messages.length - 1; i >= 0; i--) {
        final cost = estimateTokens(messages[i].text);
        if (cost > budget || used + cost > budget) {
          continue;
        }
        selected.add(messages[i]);
        used += cost;
        if (used >= budget) break;
      }
    }
    final history = selected.reversed.toList(growable: false);
    final totalPrefill =
        systemTokens + used + evidenceTokens + currentTurnTokens;
    final remaining = modelMaxTokens - outputReserve - totalPrefill;
    if (remaining < 0) {
      throw StateError(
        'System, evidence and current query exceed the model context budget',
      );
    }
    final trimmedHistory = messages.length - history.length;
    final trimmedEvidence = evidenceItemCount - includedEvidenceItemCount;
    final details = <String>[
      ...trimDetails,
      if (trimmedHistory > 0) 'history_messages:$trimmedHistory',
    ];
    return ContextSelection(
      history: history,
      decision: ContextBudgetDecision(
        modelContextLimit: modelMaxTokens,
        systemTokens: systemTokens,
        historyTokens: used,
        evidenceTokens: evidenceTokens,
        queryTokens: currentTurnTokens,
        outputReserveTokens: outputReserve,
        totalPrefillTokens: totalPrefill,
        remainingTokens: remaining,
        trimmedHistoryMessages: trimmedHistory,
        trimmedEvidenceItems: trimmedEvidence < 0 ? 0 : trimmedEvidence,
        trimDetails: List<String>.unmodifiable(details),
      ),
    );
  }

  String trimTextToTokenBudget(String text, int maxTokens) {
    if (text.isEmpty || maxTokens <= 0) return '';
    if (estimateTokens(text) <= maxTokens) return text;
    if (estimateTokens(_truncationMarker) > maxTokens) return '';

    var low = 0;
    var high = text.length;
    var best = _truncationMarker;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final prefix = text.substring(0, mid).trimRight();
      final candidate = prefix.isEmpty
          ? _truncationMarker
          : '$prefix\n$_truncationMarker';
      if (estimateTokens(candidate) <= maxTokens) {
        best = candidate;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return best;
  }
}
