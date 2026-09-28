import 'package:flutter/material.dart';

import '../../lineage/lineage_models.dart';
import '../../lineage/trace_snapshot.dart';

class LineageDetailScaffold extends StatelessWidget {
  const LineageDetailScaffold({
    super.key,
    required this.pageKey,
    required this.title,
    required this.snapshot,
    required this.children,
    this.truthKinds = const <TruthKind>{TruthKind.real},
    this.lane = RetrievalLane.active,
  });

  final String pageKey;
  final String title;
  final TraceSnapshot snapshot;
  final List<Widget> children;
  final Set<TruthKind> truthKinds;
  final RetrievalLane lane;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: ValueKey<String>(pageKey),
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    snapshot.trace.traceId,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final truth in truthKinds)
                        Chip(label: Text(truth.dbValue)),
                      Chip(label: Text(lane.dbValue)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ...children,
        ],
      ),
    ),
  );
}

class LineageMetric extends StatelessWidget {
  const LineageMetric(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 94),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class LineageSectionCard extends StatelessWidget {
  const LineageSectionCard({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class EmptyFact extends StatelessWidget {
  const EmptyFact(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(message),
  );
}
