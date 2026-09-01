abstract final class GoldenReasonCodeContract {
  static final RegExp _stableReasonCode = RegExp(
    r'^[A-Z][A-Z0-9_]*(?:\|[A-Z][A-Z0-9_]*)*$',
  );

  static const Map<String, String?> _fallbackByStatus = <String, String?>{
    'PENDING': 'GATE_INCOMPLETE',
    'RUNNING': 'GATE_INCOMPLETE',
    'PASSED': null,
    'FAILED': 'GATE_FAILED',
    'TIMEDOUT': 'GATE_TIMEOUT',
    'BLOCKED': 'GATE_BLOCKED',
  };

  static const Set<String> _genericReasonCodes = <String>{
    'GATE_INCOMPLETE',
    'GATE_FAILED',
    'GATE_TIMEOUT',
    'GATE_BLOCKED',
  };

  static String? forExport(String status, String detail) {
    if (!_fallbackByStatus.containsKey(status)) {
      throw ArgumentError.value(status, 'status', 'unsupported Golden status');
    }
    final fallback = _fallbackByStatus[status];
    if (fallback == null) return null;
    final normalized = detail.trim();
    return accepts(status, normalized) ? normalized : fallback;
  }

  static bool accepts(String status, Object? reasonCode) {
    if (!_fallbackByStatus.containsKey(status)) return false;
    final expectedGeneric = _fallbackByStatus[status];
    if (expectedGeneric == null) return reasonCode == null;
    if (reasonCode is! String || !_stableReasonCode.hasMatch(reasonCode)) {
      return false;
    }
    return reasonCode.split('|').every(
      (code) =>
          !_genericReasonCodes.contains(code) || code == expectedGeneric,
    );
  }
}
