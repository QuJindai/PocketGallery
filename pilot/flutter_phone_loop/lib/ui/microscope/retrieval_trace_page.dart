import 'package:flutter/material.dart';

import '../../observability/retrieval_trace.dart';
import '../../services/knowledge_engine.dart';
import 'fts_inspector_page.dart';
import 'hybrid_rank_lab_page.dart';
import 'vector_microscope_page.dart';

class RetrievalTracePage extends StatelessWidget {
  const RetrievalTracePage({
    super.key,
    required this.trace,
    required this.engine,
  });

  final RetrievalTrace trace;
  final KnowledgeEngine engine;

  @override
  Widget build(BuildContext context) {
    final totalMs = trace.timings.lexicalMs +
        trace.timings.semanticMs +
        trace.timings.fusionMs +
        trace.timings.evidenceMs +
        trace.timings.generationMs;
    return Scaffold(
      appBar: AppBar(title: const Text('检索依据 · Trace')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(trace.query, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                const Chip(label: Text('REAL · runtime/index')),
                const Chip(label: Text('DERIVED · fusion/projection')),
                Chip(label: Text('${trace.mode} · $totalMs ms')),
              ],
            ),
            const SizedBox(height: 8),
            _stage(
              context,
              icon: Icons.manage_search,
              title: 'FTS5',
              subtitle: _stageSubtitle(
                trace.lexicalHits.length,
                trace.timings.lexicalMs,
                trace.lexicalHits.firstOrNull?.sourceName,
              ),
              truth: 'REAL BM25 / rank',
              enabled: true,
              onTap: () => _push(
                context,
                FtsInspectorPage(engine: engine, trace: trace),
              ),
            ),
            _stage(
              context,
              icon: Icons.scatter_plot_outlined,
              title: 'Embedding',
              subtitle: _stageSubtitle(
                trace.semanticHits.length,
                trace.timings.semanticMs,
                trace.semanticHits.firstOrNull?.sourceName,
              ),
              truth: 'REAL cosine / rank',
              enabled: true,
              onTap: () => _push(
                context,
                VectorMicroscopePage(engine: engine, trace: trace),
              ),
            ),
            _stage(
              context,
              icon: Icons.merge_type,
              title: 'Hybrid / RRF',
              subtitle: _stageSubtitle(
                trace.hybridHits.length,
                trace.timings.fusionMs,
                trace.hybridHits.firstOrNull?.sourceName,
              ),
              truth: 'DERIVED contributions / final rank',
              enabled: true,
              onTap: () => _push(
                context,
                HybridRankLabPage(trace: trace),
              ),
            ),
            _stage(
              context,
              icon: Icons.fact_check_outlined,
              title: 'Evidence',
              subtitle:
                  '${trace.evidenceAnchors.length} anchors · ${trace.timings.evidenceMs} ms · ${trace.evidenceAnchors.join(' · ')}',
              truth: 'REAL selected chunks',
            ),
            _stage(
              context,
              icon: Icons.auto_awesome,
              title: 'Gemma + Citation',
              subtitle:
                  '${trace.timings.generationMs} ms · citations ${trace.citations.isEmpty ? '—' : trace.citations.join(' · ')}',
              truth: 'REAL answer citation output',
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trace identity',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(trace.traceId),
                    Text(
                      '${trace.startedAt.toLocal()} → ${trace.completedAt.toLocal()}',
                    ),
                    Text(
                      trace.scopeDocumentIds.isEmpty
                          ? 'scope · 全部知识库'
                          : 'scope · ${trace.scopeDocumentIds.length} documents',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String truth,
    bool enabled = false,
    VoidCallback? onTap,
  }) =>
      Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text('$subtitle\n$truth'),
          isThreeLine: true,
          trailing: enabled ? const Icon(Icons.chevron_right) : null,
          onTap: enabled ? onTap : null,
        ),
      );

  String _stageSubtitle(int count, int ms, String? source) =>
      '$count hits · $ms ms${source == null ? '' : ' · top $source'}';

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
