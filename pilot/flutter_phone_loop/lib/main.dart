import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';

import 'chat/chat_orchestrator.dart';
import 'chat/chat_session_store.dart';
import 'observability/retrieval_trace_store.dart';
import 'services/gemma_chat_service.dart';
import 'services/knowledge_engine.dart';
import 'ui/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterGemma.initialize(
    inferenceEngines: [LiteRtLmEngine()],
    embeddingBackends: [LiteRtEmbeddingBackend()],
    vectorStore: SqliteVectorStore(),
  );

  final engine = KnowledgeEngine();
  await engine.initialize();

  final chatStore = ChatSessionStore();
  await chatStore.initialize();
  final traceStore = RetrievalTraceStore();
  await traceStore.initialize();
  final chatModel = GemmaChatService();
  final orchestrator = ChatOrchestrator(
    store: chatStore,
    retriever: engine.retriever,
    model: chatModel,
    traceStore: traceStore,
    lineageRecorder: engine.runtimeLineageRecorder,
    lineageStore: engine.lineageStore,
  );

  runApp(PocketGalleryPilot(
    engine: engine,
    chatStore: chatStore,
    orchestrator: orchestrator,
  ));
}

class PocketGalleryPilot extends StatelessWidget {
  const PocketGalleryPilot({
    super.key,
    required this.engine,
    required this.chatStore,
    required this.orchestrator,
  });

  final KnowledgeEngine engine;
  final ChatSessionStore chatStore;
  final ChatOrchestrator orchestrator;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PocketGallery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: MainShell(
        engine: engine,
        store: chatStore,
        orchestrator: orchestrator,
      ),
    );
  }
}
