import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pocketgallery_phone_pilot/acceptance/device_diagnostics.dart';
import 'package:pocketgallery_phone_pilot/acceptance/pocketgallery_build_identity.dart';
import 'package:pocketgallery_phone_pilot/acceptance/preservation_probe.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_session_store.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/observability/vector_observation_store.dart';
import 'package:pocketgallery_phone_pilot/services/hf_oauth_device_service.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_engine.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';
import 'package:pocketgallery_phone_pilot/services/semantic_store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('private upgrade snapshots detect loss and expose only aggregates', () async {
    final lexicalDatabase = sqlite3.openInMemory();
    final vectorDatabase = sqlite3.openInMemory();
    final lineageDatabase = sqlite3.openInMemory();
    final chatDatabase = sqlite3.openInMemory();
    addTearDown(lexicalDatabase.close);
    addTearDown(vectorDatabase.close);
    addTearDown(lineageDatabase.close);
    addTearDown(chatDatabase.close);

    final lexicalStore = LexicalFtsStore(database: lexicalDatabase);
    final vectorStore = VectorObservationStore(database: vectorDatabase);
    final lineageStore = LineageStore(database: lineageDatabase);
    final chatStore = ChatSessionStore(database: chatDatabase);
    final semanticStore = SemanticStore(
      lexicalStore,
      observationStore: vectorStore,
    );
    final engine = KnowledgeEngine(
      lexicalStore: lexicalStore,
      semanticStore: semanticStore,
      lineageStore: lineageStore,
    );
    final oauthStorage = _FakeSecureStorage(<String, String>{
      'hf_oauth_access_token': 'hf_access_private_value',
      'hf_oauth_refresh_token': 'hf_refresh_private_value',
      'hf_oauth_expiry_epoch_ms': '${DateTime.utc(2030).millisecondsSinceEpoch}',
    });
    final oauth = HfOAuthDeviceService(
      storage: oauthStorage,
      client: MockClient((request) async {
        throw StateError('preservation capture must not use HTTP: ${request.url}');
      }),
      now: () => DateTime.utc(2026, 9, 1),
    );
    final probe = PreservationProbe(
      engine: engine,
      chatStore: chatStore,
      oauth: oauth,
      hasActiveModel: () => true,
      hasActiveEmbedder: () => true,
    );

    const document = ImportedDocument(
      documentId: 'private-document-id',
      sourceName: 'private-notes.pdf',
      sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      chunks: <PgChunk>[
        PgChunk(
          id: 'private-chunk-id',
          documentId: 'private-document-id',
          sourceName: 'private-notes.pdf',
          locator: 'page 1',
          ordinal: 0,
          text: 'private document body',
        ),
      ],
    );
    await lexicalStore.replaceDocument(document);
    await vectorStore.putChunkVector(
      chunkId: 'private-chunk-id',
      documentId: 'private-document-id',
      vector: const <double>[0.25, -0.5, 1.0],
      modelIdentity: 'EmbeddingGemma-private-model',
      updatedAt: DateTime.utc(2026, 9, 1),
    );
    final session = await chatStore.createSession(title: 'private chat title');
    await chatStore.appendMessage(
      ChatMessage.user(
        id: 'private-message-1',
        sessionId: session.id,
        text: 'private message alpha',
        createdAt: DateTime.utc(2026, 9, 1, 1),
      ),
    );
    await chatStore.appendMessage(
      ChatMessage.assistant(
        id: 'private-message-2',
        sessionId: session.id,
        text: 'private message beta',
        createdAt: DateTime.utc(2026, 9, 1, 1, 1),
      ),
    );
    await lineageStore.putTrace(_trace('private-trace-1'));

    final baseline = await probe.capture(_identity(versionCode: 2022));
    final candidate = await probe.capture(_identity(versionCode: 2023));

    expect(
      PreservationSnapshot.fromJson(baseline.toJson()).toJson(),
      baseline.toJson(),
    );

    expect(
      PreservationComparison.compare(
        baseline: baseline,
        current: candidate,
      ).passed,
      isTrue,
    );

    final sameVersion = await probe.capture(_identity(versionCode: 2022));
    expect(
      PreservationComparison.compare(
        baseline: baseline,
        current: sameVersion,
      ).reasonCodes,
      contains('BASELINE_VERSION_NOT_PREVIOUS'),
    );
    final wrongPackage = await probe.capture(
      _identity(versionCode: 2023, packageName: 'example.wrong.package'),
    );
    expect(
      PreservationComparison.compare(
        baseline: baseline,
        current: wrongPackage,
      ).reasonCodes,
      contains('PACKAGE_IDENTITY_MISMATCH'),
    );
    final wrongSigner = await probe.capture(
      _identity(versionCode: 2023, signerSha256: _wrongSigner),
    );
    expect(
      PreservationComparison.compare(
        baseline: baseline,
        current: wrongSigner,
      ).reasonCodes,
      contains('SIGNER_IDENTITY_MISMATCH'),
    );

    await lineageStore.putTrace(_trace('private-trace-2'));
    final withAdditionalLineage = await probe.capture(
      _identity(versionCode: 2023),
    );
    expect(
      PreservationComparison.compare(
        baseline: baseline,
        current: withAdditionalLineage,
      ).passed,
      isTrue,
    );

    final summary = baseline.reportSummary;
    expect(summary['knowledgeCount'], 1);
    expect(summary['chatSessionCount'], 1);
    expect(summary['chatMessageCount'], 2);
    expect(summary['embeddingObservationCount'], 1);
    expect(summary['lineageTraceCount'], 1);
    for (final key in <String>[
      'knowledgeDigest',
      'chatDigest',
      'embeddingObservationDigest',
      'lineageDigest',
    ]) {
      expect(summary[key], isA<String>());
      expect(summary[key], hasLength(64));
    }
    final publicJson = jsonEncode(summary);
    expect(publicJson.toLowerCase(), isNot(contains('vector')));
    for (final prohibited in <String>[
      document.documentId,
      document.sourceName,
      document.chunks.single.text,
      session.id,
      'private-message-1',
      'private message alpha',
      'hf_access_private_value',
      'hf_refresh_private_value',
      '0.25',
      'private-trace-1',
    ]) {
      expect(publicJson, isNot(contains(prohibited)));
    }

    await lexicalStore.removeDocument(document.documentId);
    final withoutDocument = await probe.capture(_identity(versionCode: 2023));
    expect(
      PreservationComparison.compare(
        baseline: baseline,
        current: withoutDocument,
      ).reasonCodes,
      contains('DOCUMENT_REMOVED'),
    );

    await lexicalStore.replaceDocument(document);
    await chatStore.clearMessages(session.id);
    final withoutMessages = await probe.capture(_identity(versionCode: 2023));
    expect(
      PreservationComparison.compare(
        baseline: baseline,
        current: withoutMessages,
      ).reasonCodes,
      contains('CHAT_HISTORY_REDUCED'),
    );
  });
}

DeviceIdentitySnapshot _identity({
  required int versionCode,
  String packageName = PocketGalleryBuildIdentity.packageName,
  String signerSha256 = PocketGalleryBuildIdentity.canonicalSignerSha256,
}) {
  return DeviceIdentitySnapshot.fromMap(<String, Object?>{
    'manufacturer': 'samsung',
    'model': 'SM-S9280',
    'sdkInt': 36,
    'refreshRateHz': 120.0,
    'packageName': packageName,
    'versionName': '0.5.0',
    'versionCode': versionCode,
    'signerSha256': signerSha256,
    'apkSha256': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'unavailableReasons': <String>[],
  });
}

LineageTrace _trace(String traceId) {
  return LineageTrace(
    traceId: traceId,
    sessionId: 'private-lineage-session',
    turnId: 'private-turn',
    queryText: 'private lineage query',
    requestedMode: 'auto',
    finalMode: 'knowledge',
    scopeJson: '{"type":"all"}',
    activeStrategyId: 'active.r50',
    startedAt: DateTime.utc(2026, 9, 1),
    completedAt: DateTime.utc(2026, 9, 1, 0, 0, 1),
    status: TraceStatus.complete,
    failureStage: null,
    failureCode: null,
  );
}

const String _wrongSigner =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

final class _FakeSecureStorage implements FlutterSecureStorage {
  _FakeSecureStorage(Map<String, String> values)
      : values = Map<String, String>.from(values);

  final Map<String, String> values;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.namedArguments[#key] as String?;
    if (invocation.memberName == #read) {
      return Future<String?>.value(key == null ? null : values[key]);
    }
    return super.noSuchMethod(invocation);
  }
}
