# PocketGallery Rotatable 3D Vector Space Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace both fixed oblique vector plots with one truthful, phone-rotatable high-dimensional-to-3D PCA viewer linked to human-readable evidence details.

**Architecture:** Keep PCA and persisted-vector selection in the existing observability services. Add a dependency-free pure-Dart camera/projection layer and one reusable stateful Flutter plot; both vector pages map their existing data into that plot, while the Trace service enriches points with persisted candidate/evidence/chunk facts.

**Tech Stack:** Flutter 3.44+, Dart 3.12+, Canvas/CustomPainter, GestureDetector scale gestures, existing SQLite lineage and FTS stores, flutter_test.

**Spec:** `docs/superpowers/specs/2026-09-01-pocketgallery-rotatable-3d-vector-space-design.md`

## Global Constraints

- Android `applicationId` remains `com.qujindai.pocketgallery_phone_pilot.r3`.
- No new third-party 3D, OpenGL, network, model or embedding dependency.
- Trace projection reads only persisted vectors and never invokes an embedder.
- Trace plot caps corpus points at 128 plus one Query point.
- PCA, storage and embedding calls never occur from paint or gesture callbacks.
- UMAP/t-SNE remain disabled unless backed by real coordinates in a later version.
- Existing retrieval, Evidence selection, chat generation, OAuth, model-cache and signing behavior remain unchanged.
- Implementation stays on `codex/r46-full-microscope`; do not merge to `main` without explicit user approval.

---

### Task 1: Pure 3D Camera and Projection Mathematics

**Files:**
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/vector_space_3d.dart`
- Test: `pilot/flutter_phone_loop/test/r49_vector_space_3d_math_test.dart`

**Interfaces:**
- Consumes: `dart:math`, Flutter `Offset` and `Size` value types.
- Produces: `VectorPlotKind`, `VectorPlotPoint`, `VectorCamera`, `ProjectedVectorPoint`, `VectorProjectionFrame`, and `VectorProjection3d.project(...)`.

- [ ] **Step 1: Write failing projection tests**

```dart
test('yaw rotates PC1 depth into the screen plane', () {
  const projector = VectorProjection3d();
  const point = VectorPlotPoint(
    id: 'x', x: 1, y: 0, z: 0, kind: VectorPlotKind.candidate,
  );
  final front = projector.project(
    points: const [point],
    size: const Size(300, 300),
    camera: const VectorCamera(yaw: 0, pitch: 0, zoom: 1),
  );
  final turned = projector.project(
    points: const [point],
    size: const Size(300, 300),
    camera: const VectorCamera(yaw: math.pi / 2, pitch: 0, zoom: 1),
  );
  expect(front.points.single.screen.dx, greaterThan(150));
  expect(turned.points.single.screen.dx, closeTo(150, 1e-6));
  expect(turned.points.single.depth, isNot(closeTo(front.points.single.depth, 1e-6)));
});

test('degenerate and non-finite input never reaches canvas coordinates', () {
  const projector = VectorProjection3d();
  final frame = projector.project(
    points: const [
      VectorPlotPoint(id: 'a', x: 0, y: 0, z: 0, kind: VectorPlotKind.context),
      VectorPlotPoint(id: 'b', x: double.nan, y: 0, z: double.infinity, kind: VectorPlotKind.context),
    ],
    size: const Size(320, 240),
    camera: const VectorCamera(),
  );
  expect(frame.points.every((p) => p.screen.dx.isFinite && p.screen.dy.isFinite), isTrue);
});
```

- [ ] **Step 2: Run RED and record the expected missing-library failure**

Run: `flutter test test/r49_vector_space_3d_math_test.dart`

Expected: FAIL because `vector_space_3d.dart` and its types do not exist.

- [ ] **Step 3: Implement the minimal pure projection API**

```dart
enum VectorPlotKind { query, evidence, candidate, context }

class VectorCamera {
  const VectorCamera({this.yaw = -0.58, this.pitch = 0.34, this.zoom = 1});
  final double yaw;
  final double pitch;
  final double zoom;

  VectorCamera clamped() => VectorCamera(
    yaw: yaw.isFinite ? yaw : -0.58,
    pitch: (pitch.isFinite ? pitch : 0.34).clamp(-1.25, 1.25),
    zoom: (zoom.isFinite ? zoom : 1).clamp(0.62, 2.20),
  );
}
```

Implement yaw-Y rotation, pitch-X rotation, bounded perspective, maximum-radius normalization, axis projection and far-to-near sorting exactly as specified.

- [ ] **Step 4: Run GREEN and format**

Run: `dart format lib/ui/microscope/vector_space_3d.dart test/r49_vector_space_3d_math_test.dart && flutter test test/r49_vector_space_3d_math_test.dart`

Expected: PASS with finite coordinates, stable depth ordering and changed projection after rotation.

- [ ] **Step 5: Commit Task 1**

```bash
git add pilot/flutter_phone_loop/lib/ui/microscope/vector_space_3d.dart pilot/flutter_phone_loop/test/r49_vector_space_3d_math_test.dart
git commit -m "feat(r49): add deterministic 3d vector projection"
```

### Task 2: Reusable Mobile Interactive Plot

**Files:**
- Modify: `pilot/flutter_phone_loop/lib/ui/microscope/vector_space_3d.dart`
- Test: `pilot/flutter_phone_loop/test/r49_interactive_vector_plot_test.dart`

**Interfaces:**
- Consumes: Task 1 projection types.
- Produces: `InteractiveVectorPlot`, `VectorSpace3dPainter`, reset control, point hit testing and `ValueChanged<String>? onPointSelected`.

- [ ] **Step 1: Write failing widget tests for rotation, pinch, point selection and reset**

```dart
testWidgets('single finger drag rotates and reset restores the camera', (tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: InteractiveVectorPlot(
      points: [
        VectorPlotPoint(id: 'q', x: 0, y: 0, z: 0, kind: VectorPlotKind.query),
        VectorPlotPoint(id: 'a', x: 1, y: 0, z: 0, kind: VectorPlotKind.candidate),
      ],
      explainedVarianceRatios: [0.5, 0.3, 0.2],
    )),
  ));
  final before = tester.widget<CustomPaint>(find.byKey(const ValueKey('vector-3d-canvas'))).painter as VectorSpace3dPainter;
  await tester.drag(find.byKey(const ValueKey('vector-3d-gesture-surface')), const Offset(70, 30));
  await tester.pump();
  final moved = tester.widget<CustomPaint>(find.byKey(const ValueKey('vector-3d-canvas'))).painter as VectorSpace3dPainter;
  expect(moved.camera.yaw, isNot(before.camera.yaw));
  await tester.tap(find.byKey(const ValueKey('vector-3d-reset')));
  await tester.pump();
  final reset = tester.widget<CustomPaint>(find.byKey(const ValueKey('vector-3d-canvas'))).painter as VectorSpace3dPainter;
  expect(reset.camera, const VectorCamera());
});
```

Add a two-pointer scale test, center Query tap callback test, semantics text test and a 360×800 no-overflow test.

- [ ] **Step 2: Run RED**

Run: `flutter test test/r49_interactive_vector_plot_test.dart`

Expected: FAIL because `InteractiveVectorPlot` and `VectorSpace3dPainter` are absent.

- [ ] **Step 3: Implement gestures, hit testing and painter**

```dart
GestureDetector(
  key: const ValueKey('vector-3d-gesture-surface'),
  onScaleStart: _handleScaleStart,
  onScaleUpdate: _handleScaleUpdate,
  onTapUp: _handleTap,
  child: CustomPaint(
    key: const ValueKey('vector-3d-canvas'),
    painter: VectorSpace3dPainter(...),
    child: const SizedBox.expand(),
  ),
)
```

Paint PC axes and variance labels; draw Query as a diamond, Evidence with a ring, candidates as medium dots and context as small translucent dots. Sort projected points by depth. Use theme colors passed into the painter. Keep selection when reset is pressed.

- [ ] **Step 4: Run GREEN and focused regression**

Run: `dart format lib/ui/microscope/vector_space_3d.dart test/r49_interactive_vector_plot_test.dart && flutter test test/r49_vector_space_3d_math_test.dart test/r49_interactive_vector_plot_test.dart`

Expected: PASS; no overflow or gesture exception.

- [ ] **Step 5: Commit Task 2**

```bash
git add pilot/flutter_phone_loop/lib/ui/microscope/vector_space_3d.dart pilot/flutter_phone_loop/test/r49_interactive_vector_plot_test.dart
git commit -m "feat(r49): add rotatable mobile vector plot"
```

### Task 3: Enrich Trace Points with Human-Readable Evidence Facts

**Files:**
- Modify: `pilot/flutter_phone_loop/lib/observability/trace_vector_space_service.dart`
- Modify: `pilot/flutter_phone_loop/test/r46bc_trace_vector_space_test.dart`

**Interfaces:**
- Consumes: existing `TraceSnapshot.candidates`, `TraceSnapshot.evidence`, `LexicalFtsStore.getChunk`, persisted embeddings.
- Produces: enriched `TraceVectorPoint` fields and `TraceVectorSpaceSnapshot.originalDimension/effectiveComponentCount`; default `maxCorpusPoints = 128`.

- [ ] **Step 1: Extend the existing service test before production code**

```dart
final active = result.points.singleWhere((p) => p.embeddingId == 'emb-c-active');
expect(active.text, 'active candidate');
expect(active.sourceChannels, 'vector');
expect(active.selectedForEvidence, isTrue);
expect(active.finalRank, 1);
expect(active.selectionReason, isNotEmpty);
expect(result.originalDimension, 2);
expect(result.effectiveComponentCount, inInclusiveRange(1, 2));
```

Persist an `EvidenceRecord` in the fixture with selection reason `direct_support`; give the rejected candidate `dropReason: 'max_evidence'` and assert both survive into the point.

- [ ] **Step 2: Run RED**

Run: `flutter test test/r46bc_trace_vector_space_test.dart`

Expected: FAIL because the enriched fields are undefined.

- [ ] **Step 3: Implement candidate/evidence joins and dimensional metadata**

Add one candidate metadata map keyed by embedding ID and one Evidence map keyed by candidate ID. Populate chunk text from the existing lexical row. Query and stratified-fill points use explicit empty/non-applicable metadata rather than invented reasons.

- [ ] **Step 4: Run GREEN**

Run: `dart format lib/observability/trace_vector_space_service.dart test/r46bc_trace_vector_space_test.dart && flutter test test/r46bc_trace_vector_space_test.dart test/r41_pca_projector_test.dart`

Expected: PASS and `usedCapturedQuery == true` remains unchanged.

- [ ] **Step 5: Commit Task 3**

```bash
git add pilot/flutter_phone_loop/lib/observability/trace_vector_space_service.dart pilot/flutter_phone_loop/test/r46bc_trace_vector_space_test.dart
git commit -m "feat(r49): expose readable trace vector evidence"
```

### Task 4: Integrate the Shared 3D Plot into Both Vector Pages

**Files:**
- Modify: `pilot/flutter_phone_loop/lib/ui/microscope/vector_space_page.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/microscope/vector_microscope_page.dart`
- Delete: `pilot/flutter_phone_loop/lib/ui/microscope/vector_map_painter.dart`
- Create: `pilot/flutter_phone_loop/test/r49_vector_space_page_test.dart`
- Modify: `pilot/flutter_phone_loop/test/r41_microscope_ui_test.dart`

**Interfaces:**
- Consumes: `InteractiveVectorPlot`, enriched Trace points, existing `VectorMicroscopeSnapshot`.
- Produces: phone-readable 3D cards, selected-point details and consistent interaction across both pages.

- [ ] **Step 1: Write failing page contracts**

```dart
expect(find.textContaining('→ 3D PCA'), findsOneWidget);
expect(find.byType(InteractiveVectorPlot), findsOneWidget);
expect(find.textContaining('解释方差'), findsWidgets);
expect(find.textContaining('单指旋转'), findsOneWidget);
expect(find.text('切片原文'), findsOneWidget);
expect(find.text('开发者详情'), findsOneWidget);
```

At 360×800, pump each page and assert `tester.takeException()` is null. Assert the old `2D PCA` / `3D PCA` segmented control is absent.

- [ ] **Step 2: Run RED**

Run: `flutter test test/r49_vector_space_page_test.dart test/r41_microscope_ui_test.dart`

Expected: FAIL because pages still use fixed painters and do not show selected-point details.

- [ ] **Step 3: Replace fixed painters and add readable detail card**

Trace mapping:

```dart
VectorPlotKind kindFor(TraceVectorPoint point) {
  if (point.isQuery) return VectorPlotKind.query;
  if (point.selectedForEvidence) return VectorPlotKind.evidence;
  if (point.candidateId != null) return VectorPlotKind.candidate;
  return VectorPlotKind.context;
}
```

Show original dimension, 3D PCA, actual PC variance, effective components and sample coverage before the plot. Below it, show source/locator, selectable chunk text, human-readable selection status, cosine and ranks; keep IDs/fingerprints in a collapsed `ExpansionTile(title: Text('开发者详情'))`.

For the old live microscope, map Query and top neighbors into the same plot, retain its explicit live-observation truth label, and remove the obsolete fixed painter file.

- [ ] **Step 4: Run GREEN and relevant UI suite**

Run: `dart format lib/ui/microscope/vector_space_page.dart lib/ui/microscope/vector_microscope_page.dart test/r49_vector_space_page_test.dart test/r41_microscope_ui_test.dart && flutter test test/r49_vector_space_page_test.dart test/r41_microscope_ui_test.dart test/r46_lineage_ui_test.dart`

Expected: PASS at 360 px with the shared plot present on both pages.

- [ ] **Step 5: Commit Task 4**

```bash
git add pilot/flutter_phone_loop/lib/ui/microscope pilot/flutter_phone_loop/test/r49_vector_space_page_test.dart pilot/flutter_phone_loop/test/r41_microscope_ui_test.dart
git commit -m "feat(r49): ship readable rotatable vector space"
```

### Task 5: Version, Regression, Android Build and Delivery Evidence

**Files:**
- Modify: `pilot/flutter_phone_loop/pubspec.yaml`
- Modify: `pilot/flutter_phone_loop/MANIFEST.sha256`
- Modify: `DROPIN_MANIFEST.sha256`
- Modify: `docs/phone-pilot/verification-matrix.md`
- Modify: `docs/phone-pilot/release-checklist.md`
- Modify if needed for branch execution: `.github/workflows/pocketgallery-r46-tdd.yml`

**Interfaces:**
- Consumes: Tasks 1–4 and all existing R2–R4.8 regression gates.
- Produces: version `0.4.18+21`, passing analysis/tests, arm64 debug APK and verifiable hashes.

- [ ] **Step 1: Add the release contract and bump version**

Update `pubspec.yaml` to:

```yaml
version: 0.4.18+21
```

Update the release matrix with: exact captured vector, 128-point cap, actual PCA variance, 3D rotation, pinch zoom, point selection, readable evidence sheet, 360 px layout and no fixed oblique projection.

- [ ] **Step 2: Regenerate manifests and run formatting/analyze/full tests**

Run:

```bash
cd pilot/flutter_phone_loop
bash scripts/generate_manifests.sh inner
bash scripts/generate_manifests.sh outer
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Expected: analysis clean and the full suite passes with zero failures.

- [ ] **Step 3: Build and verify Android arm64 debug APK**

Run:

```bash
cd pilot/flutter_phone_loop
bash scripts/bootstrap_android.sh
flutter build apk --debug --target-platform android-arm64 --split-per-abi
```

Verify package `com.qujindai.pocketgallery_phone_pilot.r3`, versionCode `21`, ABI `arm64-v8a`, APK non-empty and SHA-256 recorded.

- [ ] **Step 4: Commit release evidence**

```bash
git add pilot/flutter_phone_loop/pubspec.yaml pilot/flutter_phone_loop/MANIFEST.sha256 DROPIN_MANIFEST.sha256 docs/phone-pilot/verification-matrix.md docs/phone-pilot/release-checklist.md .github/workflows/pocketgallery-r46-tdd.yml
git commit -m "chore(r49): verify rotatable vector release"
```

- [ ] **Step 5: Verify before completion and prepare branch handoff**

Use `superpowers:verification-before-completion`, then `superpowers:finishing-a-development-branch`. Do not claim canonical upgrade signing when the known signing cache is unavailable. Supply the verified debug APK separately and preserve the canonical signer gate.

## Self-review

- Spec coverage: Tasks 1–4 cover truthful PCA, real 3D camera, mobile gestures, visual encoding, readable evidence, degradation, performance cap and both vector pages. Task 5 covers regression and delivery.
- Placeholder scan: every step contains a concrete command, API, assertion or expected result.
- Type consistency: `VectorPlotPoint`, `VectorCamera`, `VectorProjection3d`, `InteractiveVectorPlot`, `VectorSpace3dPainter` and enriched `TraceVectorPoint` names are consistent across tasks.
