import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/release_version.dart';

void main() {
  test('R4.x remains an in-place R3-signed upgrade without model redownload', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final bootstrap = await File('scripts/bootstrap_android.sh').readAsString();
    final setup = await File('lib/services/model_setup_service.dart').readAsString();

    final version = parseReleaseVersion(pubspec);
    expect(
      isReleaseVersionAtLeast(version, major: 0, minor: 4, patch: 0),
      isTrue,
    );
    expect(version.build, greaterThanOrEqualTo(11));
    expect(bootstrap, contains('com.qujindai.pocketgallery_phone_pilot.r3'));
    expect(setup, contains('if (!FlutterGemma.hasActiveModel())'));
    expect(setup, contains('if (!FlutterGemma.hasActiveEmbedder())'));
  });

  test('R4.1 persistence migrations are additive', () async {
    final chat = await File('lib/chat/chat_session_store.dart').readAsString();
    final traces =
        await File('lib/observability/retrieval_trace_store.dart').readAsString();
    final vectors = await File(
      'lib/observability/vector_observation_store.dart',
    ).readAsString();

    expect('$chat\n$traces\n$vectors', isNot(contains('DROP TABLE')));
    expect(chat, contains('ALTER TABLE chat_messages ADD COLUMN trace_id'));
    expect(traces, contains('CREATE TABLE IF NOT EXISTS pg_retrieval_traces'));
    expect(vectors, contains('CREATE TABLE IF NOT EXISTS pg_vector_observations'));
  });
}
