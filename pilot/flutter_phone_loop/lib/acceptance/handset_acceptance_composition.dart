import 'package:flutter_gemma/flutter_gemma.dart';

import '../chat/chat_session_store.dart';
import '../eval/retrieval_benchmark_fixture.dart';
import '../services/gemma_service.dart';
import '../services/golden_test_runner.dart';
import '../services/hf_oauth_device_service.dart';
import '../services/knowledge_engine.dart';
import 'device_diagnostics.dart';
import 'device_resource_sampler.dart';
import 'handset_acceptance_runner.dart';
import 'handset_acceptance_store.dart';
import 'preservation_probe.dart';
import 'vector_acceptance.dart';

final class HandsetAcceptanceComposition {
  const HandsetAcceptanceComposition._(this.runner);

  final HandsetAcceptanceController runner;

  static HandsetAcceptanceComposition create(
    KnowledgeEngine engine,
    ChatSessionStore chatStore,
  ) {
    const diagnostics = MethodChannelDeviceDiagnostics();
    final golden = GoldenTestRunner(engine);
    final preservation = PreservationProbe(
      engine: engine,
      chatStore: chatStore,
      oauth: HfOAuthDeviceService(),
      hasActiveModel: FlutterGemma.hasActiveModel,
      hasActiveEmbedder: FlutterGemma.hasActiveEmbedder,
    );
    const vectorCapture = VectorAcceptanceCapture();
    final runner = HandsetAcceptanceRunner(
      diagnostics: diagnostics,
      persistence: FileHandsetAcceptancePersistence(
        HandsetAcceptanceStore(),
      ),
      capturePreservation: preservation.capture,
      runGolden: golden.run,
      interruptGolden: golden.interrupt,
      cleanupKnownFixtures: () =>
          RetrievalBenchmarkFixture.removeKnownFixtures(engine),
      captureVectorArtifact: (traceId) =>
          vectorCapture.capture(engine, traceId),
      verifyVectorTruth: VectorTruthVerifier.verify,
      probeModelReadiness: probeInstalledModelReadiness,
      resources: DeviceResourceSampler(diagnostics: diagnostics),
    );
    return HandsetAcceptanceComposition._(runner);
  }

  static Future<ModelReadinessResult> probeInstalledModelReadiness() async {
    if (!FlutterGemma.hasActiveModel() ||
        !FlutterGemma.hasActiveEmbedder()) {
      return const ModelReadinessResult.blocked(
        'MODEL_PREREQUISITE_MISSING',
      );
    }
    await FlutterGemma.getActiveEmbedder();
    final model = GemmaService();
    try {
      await model.ensureLoaded();
    } finally {
      await model.close();
    }
    return const ModelReadinessResult.passed();
  }
}
