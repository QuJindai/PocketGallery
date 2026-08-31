import 'package:flutter/material.dart';

import '../../lineage/import_lineage.dart';
import '../../lineage/trace_snapshot.dart';
import 'lineage_stage_widgets.dart';

class DocumentParseMicroscopePage extends StatelessWidget {
  const DocumentParseMicroscopePage({
    super.key,
    required this.snapshot,
  });

  final TraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final documents = snapshot.documentsById.values.toList()
      ..sort((a, b) => a.sourceName.compareTo(b.sourceName));
    return LineageDetailScaffold(
      pageKey: 'document-parse-page',
      title: '文档解析 / Parse',
      snapshot: snapshot,
      children: [
        LineageSectionCard(
          title: '文档身份与解析覆盖',
          child: documents.isEmpty
              ? const EmptyFact(
                  '当前 Trace 未关联可解析的文档记录；不会推断文件类型、页数或解析耗时。',
                )
              : Column(
                  children: [
                    for (final document in documents)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(document.sourceName),
                        subtitle: Text(
                          'SHA ${document.sha256} · ${document.fileType} · '
                          '${document.provenanceQuality.name} provenance\n'
                          'pages ${document.pageCount ?? '未捕获'} · '
                          'chars ${document.extractedCharCount} · '
                          'empty ${document.emptyPageCount} · '
                          'status ${document.parseStatus.dbValue}',
                        ),
                        isThreeLine: true,
                      ),
                  ],
                ),
        ),
        LineageSectionCard(
          title: 'Page / Section',
          child: snapshot.sectionsById.isEmpty
              ? const EmptyFact('没有与本 Trace 候选关联的 Page/Section 事实。')
              : Column(
                  children: [
                    for (final section in snapshot.sectionsById.values)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(section.heading ?? section.sectionType),
                        subtitle: Text(
                          'page ${section.pageNo ?? '未捕获'} · '
                          'offset ${section.startOffset ?? '未捕获'}–'
                          '${section.endOffset ?? '未捕获'} · '
                          '${section.charCount} chars · '
                          '${section.parseStatus.dbValue}',
                        ),
                      ),
                  ],
                ),
        ),
        LineageSectionCard(
          title: '解析诊断',
          child: documents.any((document) => document.parseErrorCode != null)
              ? Column(
                  children: [
                    for (final document in documents)
                      if (document.parseErrorCode != null)
                        Text(
                          '${document.sourceName}: ${document.parseErrorCode} · '
                          '${document.parseErrorDetail ?? '详情未捕获'}',
                        ),
                  ],
                )
              : const Text('未捕获解析错误；旧文档缺失的原始偏移不会补写为 0。'),
        ),
      ],
    );
  }
}
