import 'package:flutter/material.dart';

import '../../lineage/lineage_models.dart';
import '../../lineage/lineage_store.dart';
import '../../lineage/trace_snapshot.dart';
import '../../services/knowledge_engine.dart';
import 'lineage_formatters.dart';
import 'lineage_stage_widgets.dart';

class EmbeddingMicroscopePage extends StatelessWidget {
  const EmbeddingMicroscopePage({
    super.key,
    required this.engine,
    required this.snapshot,
  });

  final KnowledgeEngine engine;
  final TraceSnapshot snapshot;

  Future<List<({LineageEmbedding embedding, VectorIndexEntryRecord? entry})>>
  _load() async {
    final byId = <String, LineageEmbedding>{};
    final query = snapshot.queryEmbedding;
    if (query != null) byId[query.embeddingId] = query;
    for (final candidate in snapshot.candidates) {
      final embeddingId = candidate.embeddingId;
      if (embeddingId == null || byId.containsKey(embeddingId)) continue;
      final embedding = await engine.lineageStore.embeddingById(embeddingId);
      if (embedding != null) byId[embeddingId] = embedding;
    }
    for (final chunkId in snapshot.chunksById.keys) {
      final embeddings = await engine.lineageStore.embeddingsForChunk(chunkId);
      for (final embedding in embeddings) {
        byId[embedding.embeddingId] = embedding;
      }
    }
    final rows =
        <({LineageEmbedding embedding, VectorIndexEntryRecord? entry})>[];
    for (final embedding in byId.values) {
      rows.add((
        embedding: embedding,
        entry: await engine.lineageStore.vectorIndexEntryForEmbedding(
          embedding.embeddingId,
          snapshot.trace.activeStrategyId,
          RetrievalLane.active,
        ),
      ));
    }
    rows.sort((a, b) {
      final representation = a.embedding.representation.index.compareTo(
        b.embedding.representation.index,
      );
      return representation != 0
          ? representation
          : a.embedding.embeddingId.compareTo(b.embedding.embeddingId);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) => LineageDetailScaffold(
    pageKey: 'embedding-microscope-page',
    title: 'Embedding 表征',
    snapshot: snapshot,
    children: [
      const LineageSectionCard(
        title: 'Chunk ≠ Vector',
        child: Text(
          'Chunk 是文本对象；Chunk → Embedding 是显式一对多关系。'
          'body / heading / sentence 是不同数值表征，查询向量没有 chunk_id。',
        ),
      ),
      LineageSectionCard(
        title: 'Embedding 状态与身份',
        child: FutureBuilder(
          future: _load(),
          builder: (context, value) {
            if (value.hasError) {
              return Text('Embedding 读取失败：${value.error}');
            }
            if (!value.hasData) return const LinearProgressIndicator();
            final rows = value.data!;
            if (rows.isEmpty) {
              return const EmptyFact('当前 Trace 没有持久化 Embedding 事实。');
            }
            return Column(
              children: [
                for (final row in rows)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(row.embedding.embeddingId),
                    subtitle: Text(
                      '${row.embedding.chunkId ?? 'Query'} → '
                      '${row.embedding.representation.name} · '
                      '${row.embedding.dimension} dims · '
                      'norm ${formatNumber(row.embedding.norm)}',
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Chunk → Embedding · model ${row.embedding.modelIdentity}\n'
                          'task ${row.embedding.taskMode} · '
                          'generation ${row.embedding.generationMs} ms\n'
                          'sha256 ${row.embedding.vectorSha256}\n'
                          'Generated YES · Persisted YES · Indexed '
                          '${row.entry?.commitStatus.name ?? '未捕获'}',
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}
