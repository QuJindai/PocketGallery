import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../lineage/trace_report_exporter.dart';
import '../../lineage/trace_snapshot.dart';

class TraceComparison {
  const TraceComparison({
    required this.candidateDelta,
    required this.evidenceDelta,
    required this.citationDelta,
    required this.knownDurationDeltaUs,
  });

  final int candidateDelta;
  final int evidenceDelta;
  final int citationDelta;
  final int knownDurationDeltaUs;

  factory TraceComparison.between(
    TraceSnapshot baseline,
    TraceSnapshot comparison,
  ) {
    int knownDuration(TraceSnapshot snapshot) => snapshot.events.fold<int>(
      0,
      (sum, event) => sum + (event.durationUs ?? 0),
    );
    return TraceComparison(
      candidateDelta: comparison.candidates.length - baseline.candidates.length,
      evidenceDelta: comparison.evidence.length - baseline.evidence.length,
      citationDelta: comparison.citations.length - baseline.citations.length,
      knownDurationDeltaUs: knownDuration(comparison) - knownDuration(baseline),
    );
  }
}

Future<String> writeRedactedTraceReport(TraceSnapshot snapshot) async {
  final directory = await getApplicationDocumentsDirectory();
  final safeTraceId = snapshot.trace.traceId.replaceAll(
    RegExp(r'[^a-zA-Z0-9._-]'),
    '_',
  );
  final file = File(
    p.join(directory.path, 'pocketgallery-lineage-$safeTraceId.json'),
  );
  await file.writeAsBytes(
    TraceReportExporter.encodeRedacted(snapshot),
    flush: true,
  );
  return file.path;
}

class TraceActionsCard extends StatelessWidget {
  const TraceActionsCard({
    super.key,
    required this.onRerun,
    required this.onCopy,
    required this.onCompare,
    required this.onExport,
    required this.rerunEnabled,
    required this.compareEnabled,
  });

  final VoidCallback? onRerun;
  final VoidCallback onCopy;
  final VoidCallback? onCompare;
  final VoidCallback onExport;
  final bool rerunEnabled;
  final bool compareEnabled;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Trace 操作', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: rerunEnabled ? onRerun : null,
                icon: const Icon(Icons.replay),
                label: const Text('重新运行本次 Trace'),
              ),
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制 Trace ID'),
              ),
              OutlinedButton.icon(
                onPressed: compareEnabled ? onCompare : null,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('对比历史 Trace'),
              ),
              OutlinedButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.download_outlined),
                label: const Text('导出脱敏报告'),
              ),
            ],
          ),
          if (!rerunEnabled) const Text('当前入口没有聊天运行器；可查看与导出，但不能重跑。'),
        ],
      ),
    ),
  );
}
