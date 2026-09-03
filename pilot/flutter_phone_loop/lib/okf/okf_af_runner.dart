import '../core/evidence.dart';
import '../core/models.dart';
import '../lineage/generation_models.dart';
import '../services/gemma_service.dart';
import 'okf_af_benchmark.dart';

class OkfAfRunResult {
  const OkfAfRunResult({
    required this.benchmarkCase,
    required this.lane,
    required this.answer,
    required this.answerPass,
    required this.sourcePass,
    required this.retrieved,
    required this.citedAnchors,
    required this.retrievalUs,
    required this.contextChars,
    required this.contextTokens,
    required this.generation,
  });

  final OkfAfBenchmarkCase benchmarkCase;
  final OkfAfLane lane;
  final String answer;
  final bool answerPass;
  final bool? sourcePass;
  final List<OkfAfEvidence> retrieved;
  final List<String> citedAnchors;
  final int retrievalUs;
  final int contextChars;
  final int contextTokens;
  final GenerationTelemetry generation;
}

class OkfAfRunner {
  OkfAfRunner({
    required this.retriever,
    required this.gemma,
    CitationResolver? citationResolver,
  }) : citationResolver = citationResolver ?? CitationResolver();

  final OkfAfRetriever retriever;
  final GemmaService gemma;
  final CitationResolver citationResolver;

  Future<OkfAfRunResult> run({
    required OkfAfBenchmarkCase benchmarkCase,
    required OkfAfLane lane,
  }) async {
    final retrievalWatch = Stopwatch()..start();
    final retrieved = retriever.retrieve(
      benchmarkCase.question,
      lane: lane,
      limit: 8,
    );
    retrievalWatch.stop();

    final evidence = <EvidenceItem>[
      for (var index = 0; index < retrieved.length && index < 4; index++)
        EvidenceItem(
          anchor: 'E${index + 1}',
          chunk: retrieved[index].chunk,
          score: retrieved[index].score,
        ),
    ];
    final generation = await gemma.benchmarkAnswer(
      question: benchmarkCase.question,
      evidence: evidence,
      groundedOnly: lane != OkfAfLane.bareModel,
    );
    final anchors = citationResolver.extract(generation.text, evidence);
    final citedSources = <String>{};
    for (final anchor in anchors) {
      final number = int.tryParse(anchor.substring(1));
      if (number == null || number <= 0 || number > retrieved.length) continue;
      citedSources.addAll(retrieved[number - 1].sourceIds);
    }

    final contextChars = evidence.fold<int>(
      0,
      (sum, item) => sum + item.chunk.text.length,
    );
    final sourcePass = lane == OkfAfLane.bareModel
        ? null
        : benchmarkCase.expectedSourceIds.every(citedSources.contains);

    return OkfAfRunResult(
      benchmarkCase: benchmarkCase,
      lane: lane,
      answer: generation.text,
      answerPass: benchmarkCase.answerMatches(generation.text),
      sourcePass: sourcePass,
      retrieved: List<OkfAfEvidence>.unmodifiable(retrieved),
      citedAnchors: List<String>.unmodifiable(anchors),
      retrievalUs: retrievalWatch.elapsedMicroseconds,
      contextChars: contextChars,
      contextTokens: (contextChars + 2) ~/ 3,
      generation: generation.telemetry,
    );
  }
}
