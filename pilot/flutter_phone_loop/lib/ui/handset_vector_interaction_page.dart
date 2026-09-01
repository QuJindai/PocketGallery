import 'dart:async';

import 'package:flutter/material.dart';

import '../acceptance/frame_timing_sampler.dart';
import '../acceptance/handset_acceptance_runner.dart';
import '../acceptance/vector_acceptance.dart';
import '../acceptance/vector_interaction_evidence.dart';
import 'microscope/vector_space_page.dart';

class HandsetVectorInteractionPage extends StatefulWidget {
  const HandsetVectorInteractionPage({
    super.key,
    required this.artifact,
    required this.frameTimingSampler,
    required this.interruption,
    this.minimumDuration = const Duration(seconds: 15),
    this.timeout = const Duration(seconds: 90),
  });

  final VectorAcceptanceArtifact artifact;
  final FrameTimingSampler frameTimingSampler;
  final ValueListenable<String?> interruption;
  final Duration minimumDuration;
  final Duration timeout;

  @override
  State<HandsetVectorInteractionPage> createState() =>
      _HandsetVectorInteractionPageState();
}

class _HandsetVectorInteractionPageState
    extends State<HandsetVectorInteractionPage>
    with SingleTickerProviderStateMixin {
  late final VectorInteractionAccumulator interactions;
  late final AnimationController animation;
  Timer? timeoutTimer;
  FrameTimingSummary? frameSummary;
  Duration elapsed = Duration.zero;
  bool samplerStarted = false;
  bool finishing = false;

  Duration get minimumDuration => widget.minimumDuration.isNegative
      ? Duration.zero
      : widget.minimumDuration;

  @override
  void initState() {
    super.initState();
    interactions = VectorInteractionAccumulator(
      knownPointIds: widget.artifact.vectorSpace.points.map(
        (point) => point.embeddingId,
      ),
    );
    animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )
      ..addListener(_handleAnimationFrame)
      ..repeat();
    widget.interruption.addListener(_handleInterruption);
    final timeout = widget.timeout.isNegative ? Duration.zero : widget.timeout;
    timeoutTimer = Timer(
      timeout,
      () => _finishBlocked('USER_ACTION_INCOMPLETE'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || finishing) return;
      widget.frameTimingSampler.start();
      samplerStarted = true;
      if (minimumDuration == Duration.zero) _completeFrameWindow();
      _handleInterruption();
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = frameSummary;
    final canConfirm = !finishing &&
        interactions.rotationComplete &&
        interactions.zoomComplete &&
        interactions.selectionComplete &&
        summary?.available == true &&
        elapsed >= minimumDuration;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '高维关系 · 物理交互验收',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: _InteractionStatusPanel(
                dimension: widget.artifact.vectorSpace.originalDimension,
                interactions: interactions,
                elapsed: elapsed,
                minimumDuration: minimumDuration,
                frameSummary: summary,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey<String>('handset-vector-scroll'),
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: TraceVectorSpaceView(
                  data: widget.artifact.vectorSpace,
                  onInteraction: _recordInteraction,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('handset-vector-confirm'),
                  onPressed: canConfirm ? _confirmViewport : null,
                  child: const Text('界面完整并继续'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAnimationFrame() {
    if (!mounted || finishing) return;
    final nextElapsed = animation.lastElapsedDuration ?? Duration.zero;
    if (nextElapsed == elapsed) return;
    setState(() => elapsed = nextElapsed);
    if (frameSummary == null && elapsed >= minimumDuration) {
      _completeFrameWindow();
    }
  }

  void _recordInteraction(VectorInteractionEvent event) {
    if (finishing) return;
    setState(() => interactions.record(event));
  }

  void _completeFrameWindow() {
    if (!samplerStarted || frameSummary != null) return;
    final summary = widget.frameTimingSampler.stop();
    if (!mounted || finishing) {
      frameSummary = summary;
      return;
    }
    setState(() => frameSummary = summary);
  }

  void _confirmViewport() {
    final summary = frameSummary;
    if (summary == null || finishing) return;
    interactions.confirmViewport();
    _finish(
      VectorInteractionResult(
        rotationComplete: interactions.rotationComplete,
        zoomComplete: interactions.zoomComplete,
        selectionComplete: interactions.selectionComplete,
        viewportConfirmed: interactions.viewportConfirmed,
        frameTiming: summary,
      ),
    );
  }

  void _handleInterruption() {
    final reason = widget.interruption.value?.trim();
    if (reason == null || reason.isEmpty || finishing) return;
    _finishBlocked(reason);
  }

  void _finishBlocked(String reasonCode) {
    if (finishing || !mounted) return;
    final summary = _stopFrameSampler();
    _finish(
      VectorInteractionResult(
        rotationComplete: interactions.rotationComplete,
        zoomComplete: interactions.zoomComplete,
        selectionComplete: interactions.selectionComplete,
        viewportConfirmed: false,
        frameTiming:
            summary ?? VectorInteractionResult.unavailableFrameTiming,
        reasonCode: reasonCode,
      ),
    );
  }

  FrameTimingSummary? _stopFrameSampler() {
    final existing = frameSummary;
    if (existing != null) return existing;
    if (!samplerStarted) return null;
    final summary = widget.frameTimingSampler.stop();
    frameSummary = summary;
    return summary;
  }

  void _finish(VectorInteractionResult result) {
    if (finishing || !mounted) return;
    finishing = true;
    timeoutTimer?.cancel();
    animation.stop();
    Navigator.of(context).pop<VectorInteractionResult>(result);
  }

  @override
  void dispose() {
    widget.interruption.removeListener(_handleInterruption);
    timeoutTimer?.cancel();
    animation
      ..removeListener(_handleAnimationFrame)
      ..dispose();
    _stopFrameSampler();
    widget.frameTimingSampler.dispose();
    super.dispose();
  }
}

class _InteractionStatusPanel extends StatelessWidget {
  const _InteractionStatusPanel({
    required this.dimension,
    required this.interactions,
    required this.elapsed,
    required this.minimumDuration,
    required this.frameSummary,
  });

  final int dimension;
  final VectorInteractionAccumulator interactions;
  final Duration elapsed;
  final Duration minimumDuration;
  final FrameTimingSummary? frameSummary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${dimension}D → 3D · 持续帧采样',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 6,
              children: <Widget>[
                _TaskChip(
                  complete: interactions.rotationComplete,
                  completeLabel: '已旋转',
                  pendingLabel: '待旋转',
                ),
                _TaskChip(
                  complete: interactions.zoomComplete,
                  completeLabel: '已缩放',
                  pendingLabel: '待缩放',
                ),
                _TaskChip(
                  complete: interactions.selectionComplete,
                  completeLabel: '已点选',
                  pendingLabel: '待点选',
                ),
              ],
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: <Widget>[
                _StatusMetric(
                  label: '采样',
                  value:
                      '${_seconds(elapsed)}/${_seconds(minimumDuration)} 秒',
                ),
                _StatusMetric(
                  label: '有效帧',
                  value: frameSummary == null
                      ? '采样中'
                      : '${frameSummary!.eligibleFrameCount}',
                ),
                _StatusMetric(
                  label: 'P95',
                  value: _p95(frameSummary?.p95),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskChip extends StatelessWidget {
  const _TaskChip({
    required this.complete,
    required this.completeLabel,
    required this.pendingLabel,
  });

  final bool complete;
  final String completeLabel;
  final String pendingLabel;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        complete ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 17,
      ),
      label: Text(complete ? completeLabel : pendingLabel),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text(
        '$label $value',
        style: Theme.of(context).textTheme.bodySmall,
      );
}

int _seconds(Duration value) => (value.inMilliseconds / 1000).ceil();

String _p95(Duration? value) {
  if (value == null) return '采样中';
  return '${(value.inMicroseconds / 1000).toStringAsFixed(1)} ms';
}
