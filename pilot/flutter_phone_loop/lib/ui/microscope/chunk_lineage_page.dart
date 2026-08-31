import 'package:flutter/material.dart';

import '../../lineage/trace_snapshot.dart';
import '../../services/knowledge_engine.dart';
import 'lineage_stage_widgets.dart';

class ChunkLineagePage extends StatelessWidget {
  const ChunkLineagePage({
    super.key,
    required this.engine,
    required this.snapshot,
  });

  final KnowledgeEngine engine;
  final TraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final chunks = snapshot.chunksById.values.toList()
      ..sort((a, b) {
        final document = a.documentId.compareTo(b.documentId);
        return document != 0 ? document : a.ordinal.compareTo(b.ordinal);
      });
    return LineageDetailScaffold(
      pageKey: 'chunk-lineage-page',
      title: '切片 / Chunk',
      snapshot: snapshot,
      children: [
        const LineageSectionCard(
          title: '对象关系',
          child: Text('Document → Page/Section → Chunk（文本对象）→ Embedding（数值表征）'),
        ),
        LineageSectionCard(
          title: 'Chunk 策略与相邻关系',
          child: chunks.isEmpty
              ? const EmptyFact('当前 Trace 未关联持久化 Chunk lineage。')
              : Column(
                  children: [
                    for (var index = 0; index < chunks.length; index++)
                      FutureBuilder(
                        future: engine.lexicalStore.getChunk(
                          chunks[index].chunkId,
                        ),
                        builder: (context, value) {
                          final chunk = chunks[index];
                          final text = value.data?.text;
                          return ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              '${chunk.chunkId} · ${chunk.locator}',
                            ),
                            subtitle: Text(
                              '${chunk.charCount} chars · '
                              '${chunk.tokenCount ?? 'tokens 未捕获'} · '
                              'overlap ${chunk.overlapFromPrevious} · '
                              '${chunk.boundaryReason ?? 'boundary 未捕获'}',
                            ),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  text ?? 'Chunk 正文未能从 FTS 存储读取。',
                                ),
                              ),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'offset ${chunk.startOffset ?? '未捕获'}–'
                                  '${chunk.endOffset ?? '未捕获'} · '
                                  'strategy ${chunk.chunkStrategy} · '
                                  'previous ${index == 0 ? '无' : chunks[index - 1].chunkId} · '
                                  'next ${index + 1 == chunks.length ? '无' : chunks[index + 1].chunkId}',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
