import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_af_benchmark.dart';

void main() {
  late OkfAfRetriever retriever;

  setUp(() {
    retriever = OkfAfRetriever(
      corpus: OkfAfCorpus.syntheticFrTest(),
      now: () => DateTime.utc(2026, 9, 5),
    );
  });

  test('A-F lane contract is stable and ordered', () {
    expect(OkfAfLane.values, hasLength(6));
    expect(
      OkfAfLane.values.map((lane) => lane.code).toList(),
      <String>['A', 'B', 'C', 'D', 'E', 'F'],
    );
  });

  test('A bare-model lane supplies no external evidence', () {
    expect(
      retriever.retrieve(
        'X7是否经过B工序？',
        lane: OkfAfLane.bareModel,
      ),
      isEmpty,
    );
  });

  test('D passage retrieval is finer grained than C concept retrieval', () {
    final concepts = retriever.retrieve(
      '1线C工序时间',
      lane: OkfAfLane.okfConcept,
      limit: 4,
    );
    final passages = retriever.retrieve(
      '1线C工序时间',
      lane: OkfAfLane.okfPassage,
      limit: 4,
    );

    expect(concepts, isNotEmpty);
    expect(passages, isNotEmpty);
    expect(passages.first.chunk.text.length, lessThan(concepts.first.chunk.text.length));
  });

  test('E graph lane assembles route current timing and bottleneck rule', () {
    final results = retriever.retrieve(
      'X7在1线的瓶颈是什么？',
      lane: OkfAfLane.okfGraph,
      limit: 8,
    );
    final ids = results.map((item) => item.conceptId).toSet();

    expect(ids, contains('vehicles/x7'));
    expect(ids, contains('lines/line1-r19'));
    expect(ids, contains('rules/bottleneck'));
  });

  test('F trust freshness lane rejects deprecated R18 and keeps verified R19', () {
    final results = retriever.retrieve(
      '2026年9月5日，1线C工序应使用多少秒？',
      lane: OkfAfLane.okfTrustFreshness,
      limit: 8,
    );
    final ids = results.map((item) => item.conceptId).toSet();

    expect(ids, contains('lines/line1-r19'));
    expect(ids, isNot(contains('lines/line1-r18')));
    final r19 = results.firstWhere((item) => item.conceptId == 'lines/line1-r19');
    expect(r19.sourceIds, contains('spec://FR-Test/SPEC-R19'));
    expect(r19.trustLabel, 'verified');
  });

  test('synthetic benchmark covers fact multi-hop conflict and provenance', () {
    expect(okfAfBenchmarkCases, hasLength(4));
    expect(okfAfBenchmarkCases.map((item) => item.category).toSet(), {
      'single_fact',
      'multi_hop',
      'version_conflict',
      'provenance',
    });
    expect(
      okfAfBenchmarkCases.last.expectedAnswerFragments,
      contains('SPEC-R19'),
    );
  });
}
