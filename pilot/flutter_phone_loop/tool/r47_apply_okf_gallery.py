from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:80]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


root = Path(__file__).resolve().parents[1]
engine = root / "lib/services/knowledge_engine.dart"
ui = root / "lib/ui/microscope/retrieval_experiment_center_page.dart"

replace_once(
    engine,
    "import '../lineage/runtime_lineage_recorder.dart';\nimport '../retrieval/active_vector_index.dart';",
    "import '../lineage/runtime_lineage_recorder.dart';\n"
    "import '../okf/okf_experiment_engine.dart';\n"
    "import '../okf/okf_store.dart';\n"
    "import '../retrieval/active_vector_index.dart';",
)
replace_once(
    engine,
    "    ActiveVectorIndex? activeVectorIndex,\n  }) : lexicalStore",
    "    ActiveVectorIndex? activeVectorIndex,\n"
    "    OkfStore? okfStore,\n"
    "  }) : lexicalStore",
)
replace_once(
    engine,
    "    this.activeVectorIndex = activeVectorIndex ?? SqliteActiveVectorIndex();\n"
    "    queryEmbeddingRuntime = QueryEmbeddingRuntime(",
    "    this.activeVectorIndex = activeVectorIndex ?? SqliteActiveVectorIndex();\n"
    "    this.okfStore = okfStore ?? OkfStore();\n"
    "    queryEmbeddingRuntime = QueryEmbeddingRuntime(",
)
replace_once(
    engine,
    "    experimentEngine = RetrievalExperimentEngine(\n"
    "      store: this.lineageStore,\n"
    "      lexicalStore: this.lexicalStore,\n"
    "      representationBuilder: representationBuilder,\n"
    "    );",
    "    experimentEngine = OkfAwareRetrievalExperimentEngine(\n"
    "      store: this.lineageStore,\n"
    "      lexicalStore: this.lexicalStore,\n"
    "      representationBuilder: representationBuilder,\n"
    "      okfStore: this.okfStore,\n"
    "    );",
)
replace_once(
    engine,
    "  late final ActiveVectorIndex activeVectorIndex;\n"
    "  late final QueryEmbeddingRuntime queryEmbeddingRuntime;",
    "  late final ActiveVectorIndex activeVectorIndex;\n"
    "  late final OkfStore okfStore;\n"
    "  late final QueryEmbeddingRuntime queryEmbeddingRuntime;",
)
replace_once(
    engine,
    "      await lineageStore.replaceImportLineage(result);\n"
    "      buildState = BuildState.lineageCommitted;",
    "      await lineageStore.replaceImportLineage(result);\n"
    "      if (result.okf != null) {\n"
    "        await okfStore.replaceDocument(doc.documentId, result.okf);\n"
    "      }\n"
    "      buildState = BuildState.lineageCommitted;",
)
replace_once(
    engine,
    "    localBenchmarkStore.dispose();\n"
    "    lineageStore.dispose();",
    "    await okfStore.close();\n"
    "    localBenchmarkStore.dispose();\n"
    "    lineageStore.dispose();",
)

replace_once(
    ui,
    "import '../../lineage/lineage_store.dart';\n"
    "import 'experiment_run_detail_page.dart';",
    "import '../../lineage/lineage_store.dart';\n"
    "import '../../okf/okf_experiment_engine.dart';\n"
    "import '../../okf/okf_models.dart';\n"
    "import 'experiment_run_detail_page.dart';",
)
replace_once(
    ui,
    "  Map<String, List<BuildJobRecord>> jobs = const {};\n"
    "  bool loading = true;",
    "  Map<String, List<BuildJobRecord>> jobs = const {};\n"
    "  Future<_OkfLabSnapshot>? okfLabFuture;\n"
    "  bool loading = true;",
)
replace_once(
    ui,
    "      final exactQuery = selected == null\n"
    "          ? null\n"
    "          : await widget.store.embeddingById(",
    "      final labFuture = selected == null\n"
    "          ? null\n"
    "          : _loadOkfLabSnapshot(selected);\n"
    "      final exactQuery = selected == null\n"
    "          ? null\n"
    "          : await widget.store.embeddingById(",
)
replace_once(
    ui,
    "        jobs = jobMap;\n"
    "      });",
    "        jobs = jobMap;\n"
    "        okfLabFuture = labFuture;\n"
    "      });",
)
replace_once(
    ui,
    "              _traceCard(context),\n"
    "              _activeCard(context),\n"
    "              for (final strategy",
    "              _traceCard(context),\n"
    "              _activeCard(context),\n"
    "              _okfLabCard(context),\n"
    "              for (final strategy",
)

marker = "  Widget _promotionCard(BuildContext context) => Card(\n"
methods = r'''  Widget _okfLabCard(BuildContext context) {
    final future = okfLabFuture;
    if (widget.experimentEngine is! OkfAwareRetrievalExperimentEngine ||
        future == null) {
      return const SizedBox.shrink();
    }
    return Card(
      key: const ValueKey<String>('okf-lab-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<_OkfLabSnapshot>(
          future: future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OKF Lab · 三臂对照',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                const Text('同一 Trace / Query Embedding / 本地模型条件下比较知识表示差异。'),
                const SizedBox(height: 8),
                _okfArm(
                  context,
                  title: 'BARE MODEL',
                  detail: '纯模型基线 · Evidence 0 · Context 0 · 本轮生成 NOT RUN',
                ),
                _okfArm(
                  context,
                  title: 'MARKDOWN CONTROL',
                  detail: data == null
                      ? '读取中…'
                      : 'ACTIVE · candidates ${data.activeCandidateCount} · '
                            'evidence ${data.activeEvidenceCount} · 不读取 OKF 信号',
                ),
                _okfArm(
                  context,
                  title: 'OKF v0.2',
                  detail: data == null
                      ? '读取中…'
                      : 'SHADOW · ${data.runStatus} · candidates '
                            '${data.okfCandidateCount} · evidence '
                            '${data.okfEvidenceCount} · OKF docs ${data.okfDocumentCount}',
                ),
                if (snapshot.hasError)
                  Text('OKF Lab 读取失败：${snapshot.error}')
                else if (data != null) ...[
                  const Divider(),
                  Text(
                    '信任 · verified ${data.verifiedCount} · generated '
                    '${data.generatedCount} · provenance ${data.provenanceCount}',
                  ),
                  Text(
                    '新鲜度 · fresh ${data.freshCount} · stale '
                    '${data.staleCount} · deprecated ${data.deprecatedCount} · '
                    'unknown ${data.unknownCount}',
                  ),
                  if (data.reasons.isEmpty)
                    const Text('OKF 调整原因 · 尚未运行 OKF SHADOW')
                  else ...[
                    const SizedBox(height: 6),
                    const Text('为什么改变排序：'),
                    for (final reason in data.reasons.take(3)) Text('• $reason'),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _okfArm(
    BuildContext context, {
    required String title,
    required String detail,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(detail)),
      ],
    ),
  );

  Future<_OkfLabSnapshot> _loadOkfLabSnapshot(LineageTrace selected) async {
    final engine = widget.experimentEngine;
    if (engine is! OkfAwareRetrievalExperimentEngine) {
      return const _OkfLabSnapshot.empty();
    }
    final activeCandidates = await widget.store.candidatesForTrace(
      selected.traceId,
      strategyId: selected.activeStrategyId,
      lane: RetrievalLane.active,
    );
    final activeEvidence = await widget.store.evidenceForTrace(
      selected.traceId,
      strategyId: selected.activeStrategyId,
      lane: RetrievalLane.active,
    );
    final okfCandidates = await widget.store.candidatesForTrace(
      selected.traceId,
      strategyId: RetrievalStrategies.okfV02Structured.id,
      lane: RetrievalLane.shadow,
    );
    final okfEvidence = await widget.store.evidenceForTrace(
      selected.traceId,
      strategyId: RetrievalStrategies.okfV02Structured.id,
      lane: RetrievalLane.shadow,
    );
    final signals = await engine.okfStore.candidateSignals(
      traceId: selected.traceId,
      strategyId: RetrievalStrategies.okfV02Structured.id,
    );
    final documents = await engine.okfStore.documentsByIds(
      signals.map((item) => item.documentId),
    );
    final runs = await widget.store.experimentRunsForTrace(
      selected.traceId,
      strategyId: RetrievalStrategies.okfV02Structured.id,
      lane: RetrievalLane.shadow,
    );
    return _OkfLabSnapshot(
      activeCandidateCount: activeCandidates.length,
      activeEvidenceCount: activeEvidence.length,
      okfCandidateCount: okfCandidates.length,
      okfEvidenceCount: okfEvidence.length,
      okfDocumentCount: documents.length,
      runStatus: runs.isEmpty ? 'NOT RUN' : runs.first.status.name.toUpperCase(),
      verifiedCount: documents
          .where((item) => item.trustTier == OkfTrustTier.verified)
          .length,
      generatedCount: documents
          .where((item) => item.trustTier == OkfTrustTier.generated)
          .length,
      provenanceCount: documents
          .where((item) => item.trustTier == OkfTrustTier.provenance)
          .length,
      freshCount: documents
          .where((item) => item.freshness == OkfFreshness.fresh)
          .length,
      staleCount: documents
          .where((item) => item.freshness == OkfFreshness.stale)
          .length,
      deprecatedCount: documents
          .where((item) => item.freshness == OkfFreshness.deprecated)
          .length,
      unknownCount: documents
          .where((item) => item.freshness == OkfFreshness.unknown)
          .length,
      reasons: signals
          .map((item) => '${item.documentId} · ${item.reason} · '
              '${item.baseScore.toStringAsFixed(3)} → '
              '${item.finalScore.toStringAsFixed(3)}')
          .toList(growable: false),
    );
  }

'''
text = ui.read_text(encoding="utf-8")
if text.count(marker) != 1:
    raise SystemExit(f"{ui}: promotion marker missing or duplicated")
ui.write_text(text.replace(marker, methods + marker), encoding="utf-8")

snapshot_marker = "extension _FirstOrNull<T> on Iterable<T> {\n"
snapshot = r'''class _OkfLabSnapshot {
  const _OkfLabSnapshot({
    required this.activeCandidateCount,
    required this.activeEvidenceCount,
    required this.okfCandidateCount,
    required this.okfEvidenceCount,
    required this.okfDocumentCount,
    required this.runStatus,
    required this.verifiedCount,
    required this.generatedCount,
    required this.provenanceCount,
    required this.freshCount,
    required this.staleCount,
    required this.deprecatedCount,
    required this.unknownCount,
    required this.reasons,
  });

  const _OkfLabSnapshot.empty()
    : activeCandidateCount = 0,
      activeEvidenceCount = 0,
      okfCandidateCount = 0,
      okfEvidenceCount = 0,
      okfDocumentCount = 0,
      runStatus = 'NOT RUN',
      verifiedCount = 0,
      generatedCount = 0,
      provenanceCount = 0,
      freshCount = 0,
      staleCount = 0,
      deprecatedCount = 0,
      unknownCount = 0,
      reasons = const <String>[];

  final int activeCandidateCount;
  final int activeEvidenceCount;
  final int okfCandidateCount;
  final int okfEvidenceCount;
  final int okfDocumentCount;
  final String runStatus;
  final int verifiedCount;
  final int generatedCount;
  final int provenanceCount;
  final int freshCount;
  final int staleCount;
  final int deprecatedCount;
  final int unknownCount;
  final List<String> reasons;
}

'''
text = ui.read_text(encoding="utf-8")
if text.count(snapshot_marker) != 1:
    raise SystemExit(f"{ui}: extension marker missing or duplicated")
ui.write_text(text.replace(snapshot_marker, snapshot + snapshot_marker), encoding="utf-8")

print("R4.7 OKF Gallery source integration applied")
