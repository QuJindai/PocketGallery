import 'dart:math' as math;

class VectorCamera {
  const VectorCamera({
    this.yaw = -0.58,
    this.pitch = 0.34,
    this.zoom = 1,
  });

  static const double minPitch = -1.25;
  static const double maxPitch = 1.25;
  static const double minZoom = 0.62;
  static const double maxZoom = 2.2;

  final double yaw;
  final double pitch;
  final double zoom;

  VectorCamera clamped() => VectorCamera(
        yaw: yaw.isFinite ? yaw : -0.58,
        pitch: (pitch.isFinite ? pitch : 0.34)
            .clamp(minPitch, maxPitch)
            .toDouble(),
        zoom: (zoom.isFinite ? zoom : 1)
            .clamp(minZoom, maxZoom)
            .toDouble(),
      );

  VectorCamera copyWith({double? yaw, double? pitch, double? zoom}) =>
      VectorCamera(
        yaw: yaw ?? this.yaw,
        pitch: pitch ?? this.pitch,
        zoom: zoom ?? this.zoom,
      ).clamped();

  @override
  bool operator ==(Object other) =>
      other is VectorCamera &&
      other.yaw == yaw &&
      other.pitch == pitch &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(yaw, pitch, zoom);
}

enum VectorInteractionType { rotation, zoom, selection }

class VectorInteractionEvent {
  const VectorInteractionEvent({
    required this.type,
    required this.cameraBefore,
    required this.cameraAfter,
    required this.pointId,
  });

  final VectorInteractionType type;
  final VectorCamera cameraBefore;
  final VectorCamera cameraAfter;
  final String? pointId;
}

class VectorInteractionAccumulator {
  VectorInteractionAccumulator({
    required Iterable<String> knownPointIds,
  }) : knownPointIds = Set<String>.unmodifiable(knownPointIds);

  static const double minimumYawDelta = 0.25;
  static const double minimumPitchDelta = 0.15;
  static const double minimumZoomRatio = 1.12;

  final Set<String> knownPointIds;
  bool rotationComplete = false;
  bool zoomComplete = false;
  bool selectionComplete = false;
  bool viewportConfirmed = false;
  String? selectedPointId;
  double rotationYawDelta = 0;
  double rotationPitchDelta = 0;
  double zoomRatio = 1;
  double? _minimumZoom;
  double? _maximumZoom;

  bool get complete =>
      rotationComplete &&
      zoomComplete &&
      selectionComplete &&
      viewportConfirmed;

  void record(VectorInteractionEvent event) {
    switch (event.type) {
      case VectorInteractionType.rotation:
        final yawDelta =
            (event.cameraAfter.yaw - event.cameraBefore.yaw).abs();
        final pitchDelta =
            (event.cameraAfter.pitch - event.cameraBefore.pitch).abs();
        if (yawDelta.isFinite) {
          rotationYawDelta = math.max(rotationYawDelta, yawDelta);
        }
        if (pitchDelta.isFinite) {
          rotationPitchDelta = math.max(rotationPitchDelta, pitchDelta);
        }
        rotationComplete = rotationComplete ||
            rotationYawDelta >= minimumYawDelta ||
            rotationPitchDelta >= minimumPitchDelta;
        break;
      case VectorInteractionType.zoom:
        _recordZoom(event.cameraBefore.zoom);
        _recordZoom(event.cameraAfter.zoom);
        final minimum = _minimumZoom;
        final maximum = _maximumZoom;
        if (minimum != null && maximum != null && minimum > 0) {
          zoomRatio = maximum / minimum;
        }
        zoomComplete = zoomComplete || zoomRatio >= minimumZoomRatio;
        break;
      case VectorInteractionType.selection:
        final pointId = event.pointId;
        if (pointId != null && knownPointIds.contains(pointId)) {
          selectionComplete = true;
          selectedPointId = pointId;
        }
        break;
    }
  }

  void confirmViewport() {
    viewportConfirmed = true;
  }

  void _recordZoom(double value) {
    if (!value.isFinite || value <= 0) return;
    _minimumZoom = math.min(_minimumZoom ?? value, value);
    _maximumZoom = math.max(_maximumZoom ?? value, value);
  }
}
