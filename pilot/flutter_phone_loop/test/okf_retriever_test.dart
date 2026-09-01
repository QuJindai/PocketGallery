import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_lab_corpus.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_retriever.dart';

void main() {
  late OkfLabRetriever retriever;

  setUp(() {
    retriever = OkfLabRetriever(
      bundle: buildFrTestOkfBundle(),
      ordinaryChunks: buildFrTestOrdinaryChunks(),
      clock: () => DateTime.utc(2026, 9, 5),
    );
  });

  test('A bare lane supplies no external evidence', () {
    expect(
      retriever.retrieve(
        'X7是否经过B工序？',
        lane: OkfLabLane.bareModel,
      ),
      isEmpty,
    );
  });

  test('D passage lane returns bounded passages instead of whole concepts', () {
    final concept = retriever.retrieve(
      '1线C工序时间',
      lane: OkfLabLane.okfConcept,
      limit: 3,
    );
    final passage = retriever.retrieve(
      '1线C工序时间',
      lane: OkfLabLane.okfPassage,
      limit: 3,
    );

    expect(concept, isNotEmpty);
    expect(passage, isNotEmpty);
    expect(
      passage.first.chunk.text.length,
      lessThan(concept.first.chunk.text.length),
    );
  });

  test('E graph lane can assemble X7 route timing and bottleneck rule', () {
    final results = retriever.retrieve(
      'X7在1线的瓶颈是什么？',
      lane: OkfLabLane.okfGraph,
      limit: 8,
    );
    final ids = results.map((item) => item.conceptId).toSet();

    expect(ids, contains('vehicles/x7'));
    expect(ids, contains('lines/line1-r19'));
    expect(ids, contains('rules/bottleneck'));
  });

  test('F trust/freshness excludes deprecated R18 and keeps verified R19', () {
    final results = retriever.retrieve(
      '2026年9月5日，1线C工序应使用多少秒？',
      lane: OkfLabLane.okfTrustFreshness,
      limit: 8,
    );
    final ids = results.map((item) => item.conceptId).toSet();

    expect(ids, contains('lines/line1-r19'));
    expect(ids, isNot(contains('lines/line1-r18')));
    final r19 = results.firstWhere(
      (item) => item.conceptId == 'lines/line1-r19',
    );
    expect(r19.sourceIds, contains('spec-r19'));
  });

  test('benchmark questions carry expected answer/source contracts', () {
    expect(frTestBenchmarkCases, hasLength(4));
    expect(
      frTestBenchmarkCases.last.expectedAnswerFragments,
      contains('SPEC-R19'),
    );
    expect(
      frTestBenchmarkCases.last.expectedSourceIds,
      contains('spec-r19'),
    );
  });
}
