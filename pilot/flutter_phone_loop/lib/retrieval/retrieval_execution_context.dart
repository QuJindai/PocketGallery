import '../lineage/lineage_models.dart';
import '../lineage/runtime_lineage_recorder.dart';

class RetrievalExecutionContext {
  const RetrievalExecutionContext({
    required this.traceId,
    required this.sessionId,
    required this.turnId,
    this.strategyId = RuntimeLineageRecorder.activeStrategyId,
    this.lane = RetrievalLane.active,
    this.requestedMode = 'auto',
  });

  final String traceId;
  final String sessionId;
  final String turnId;
  final String strategyId;
  final RetrievalLane lane;
  final String requestedMode;

  bool get isKnowledgeMode => requestedMode == 'knowledge';
}
