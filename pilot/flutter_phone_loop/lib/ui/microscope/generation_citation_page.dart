import 'package:flutter/material.dart';

import '../../lineage/trace_snapshot.dart';
import 'lineage_formatters.dart';
import 'lineage_stage_widgets.dart';

class GenerationCitationPage extends StatelessWidget {
  const GenerationCitationPage({super.key, required this.snapshot});

  final TraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final generation = snapshot.generation;
    return LineageDetailScaffold(
      pageKey: 'generation-citation-page',
      title: '生成与引用 / Gemma + Citation',
      snapshot: snapshot,
      children: [
        LineageSectionCard(
          title: '生成指标 · REAL',
          child: Text(
            formatGenerationSummary(
              generation,
              citationCount: snapshot.citations.length,
            ),
          ),
        ),
        LineageSectionCard(
          title: 'Citation → Evidence → Chunk → Section/Page → Document',
          child: snapshot.citations.isEmpty
              ? const EmptyFact('引用记录未捕获。')
              : Column(
                  children: [
                    for (final citation in snapshot.citations)
                      Builder(builder: (context) {
                        final chunk = citation.chunkId == null
                            ? null
                            : snapshot.chunksById[citation.chunkId!];
                        final section = citation.sectionId == null
                            ? null
                            : snapshot.sectionsById[citation.sectionId!];
                        final document = citation.documentId == null
                            ? null
                            : snapshot.documentsById[citation.documentId!];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(child: Text(citation.anchor)),
                          title: Text(
                            document?.sourceName ??
                                citation.documentId ??
                                'document 未解析',
                          ),
                          subtitle: Text(
                            '${citation.citationStatus} · '
                            'Evidence ${citation.evidenceId ?? 'missing'} → '
                            'Chunk ${chunk?.chunkId ?? citation.chunkId ?? 'missing'} → '
                            'Section ${section?.heading ?? citation.sectionId ?? 'missing'} · '
                            '${citation.pageNo == null ? '页码未捕获' : '第 ${citation.pageNo} 页'}',
                          ),
                          isThreeLine: true,
                        );
                      }),
                  ],
                ),
        ),
        LineageSectionCard(
          title: 'Grounding 诊断',
          child: Text(
            snapshot.citations.any(
              (citation) => citation.citationStatus != 'resolved',
            )
                ? '存在 missing/invalid 引用，请逐项检查。'
                : '已记录引用均可解析；Lineage 不存储回答正文副本，请从聊天消息查看完整回答。',
          ),
        ),
      ],
    );
  }
}
