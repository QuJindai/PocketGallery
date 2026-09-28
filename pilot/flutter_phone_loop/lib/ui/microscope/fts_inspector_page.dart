import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../../observability/fts_inspector.dart';
import '../../observability/retrieval_trace.dart';
import '../../services/knowledge_engine.dart';

class FtsInspectorPage extends StatefulWidget {
  const FtsInspectorPage({
    super.key,
    required this.engine,
    required this.trace,
  });

  final KnowledgeEngine engine;
  final RetrievalTrace trace;

  @override
  State<FtsInspectorPage> createState() => _FtsInspectorPageState();
}

class _FtsInspectorPageState extends State<FtsInspectorPage> {
  FtsInspectionResult? current;
  Object? error;
  bool loading = true;
  double topK = 12;

  @override
  void initState() {
    super.initState();
    _load();
  }

  KnowledgeScope get _scope => widget.trace.scopeDocumentIds.isEmpty
      ? const KnowledgeScope.all()
      : KnowledgeScope.documents(widget.trace.scopeDocumentIds);

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.engine.lexicalStore.inspect(
        widget.trace.query,
        scope: _scope,
        topK: topK.round(),
      );
      if (!mounted) return;
      setState(() => current = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = current;
    return Scaffold(
      appBar: AppBar(title: const Text('FTS5 显微镜')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              widget.trace.query,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(label: Text('REAL · SQLite bm25()')),
                Chip(label: Text('DERIVED · affinity')),
              ],
            ),
            if (result != null) ...[
              const SizedBox(height: 8),
              SelectableText('Normalized query · ${result.normalizedQuery}'),
              const SizedBox(height: 4),
              Text(
                result.diagnostics,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Top K'),
                Expanded(
                  child: Slider(
                    value: topK,
                    min: 5,
                    max: 30,
                    divisions: 5,
                    label: '${topK.round()}',
                    onChanged: (v) => setState(() => topK = v),
                    onChangeEnd: (_) => _load(),
                  ),
                ),
                Text('${topK.round()}'),
              ],
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('FTS 检查失败：$error'),
                ),
              ),
            if (result != null && result.hits.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('当前索引范围没有命中。'),
                ),
              ),
            if (result != null)
              for (final hit in result.hits) _hitCard(context, hit),
            if (widget.trace.lexicalHits.isNotEmpty) ...[
              const Divider(height: 28),
              Text(
                '本次回答 Trace · 历史排名',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              for (final hit in widget.trace.lexicalHits.take(10))
                ListTile(
                  dense: true,
                  leading: Text('#${hit.rank}'),
                  title: Text(
                    hit.sourceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${hit.locator} · ${hit.channel}'),
                  trailing: Text(
                    hit.rawScore == null
                        ? 'BM25 —'
                        : 'BM25 ${hit.rawScore!.toStringAsFixed(4)}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hitCard(BuildContext context, FtsInspectionHit hit) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 15, child: Text('${hit.rank}')),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hit.chunk.sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(hit.matchMode),
            ],
          ),
          const SizedBox(height: 6),
          Text('${hit.chunk.locator} · ${hit.chunk.id}'),
          const Divider(),
          _snippet(context, hit.snippet),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                hit.rawBm25 == null
                    ? 'REAL BM25 · —'
                    : 'REAL BM25 · ${hit.rawBm25!.toStringAsFixed(6)}',
              ),
              Text('DERIVED affinity · ${hit.affinity.toStringAsFixed(6)}'),
              if (hit.matchedTerms.isNotEmpty)
                Text('terms · ${hit.matchedTerms.join(' · ')}'),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _snippet(BuildContext context, String source) {
    final spans = <TextSpan>[];
    var cursor = 0;
    final pattern = RegExp(r'<mark>(.*?)</mark>', dotAll: true);
    for (final match in pattern.allMatches(source)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: source.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1) ?? '',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < source.length) {
      spans.add(TextSpan(text: source.substring(cursor)));
    }
    return SelectableText.rich(
      TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: spans.isEmpty ? [TextSpan(text: source)] : spans,
      ),
    );
  }
}
