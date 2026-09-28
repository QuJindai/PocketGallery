import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'handset_acceptance_models.dart';
import 'preservation_probe.dart';

typedef HandsetReportDirectoryProvider = Future<Directory> Function();

final class HandsetAcceptanceStore {
  HandsetAcceptanceStore({HandsetReportDirectoryProvider? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? getApplicationDocumentsDirectory;

  static const String checkpointFileName = 'PG_HANDSET_ACCEPTANCE_LAST.json';
  static const String baselineFileName = 'PG_HANDSET_BASELINE.json';

  final HandsetReportDirectoryProvider _directoryProvider;

  Future<File> saveCheckpoint(HandsetAcceptanceSnapshot snapshot) async {
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(snapshot.toJson());
    return _writeAtomicString(checkpointFileName, encoded, _decodeCheckpoint);
  }

  Future<HandsetAcceptanceSnapshot?> readLast() async {
    return _readWithBackup(checkpointFileName, _decodeCheckpoint);
  }

  Future<File> saveBaseline(PreservationSnapshot snapshot) async {
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(snapshot.toJson());
    return _writeAtomicString(baselineFileName, encoded, _decodeBaseline);
  }

  Future<PreservationSnapshot?> readBaseline() async {
    return _readWithBackup(baselineFileName, _decodeBaseline);
  }

  Future<File> saveFinalReport(Uint8List bytes, String runId) async {
    final safeRunId = _sanitizeRunId(runId);
    final fileName = 'PG_HANDSET_ACCEPTANCE_$safeRunId.json';
    return _writeAtomicBytes(fileName, bytes, _validateFinalReport);
  }

  Future<File> _writeAtomicString<T>(
    String fileName,
    String encoded,
    T Function(String) validate,
  ) async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final destination = File(p.join(directory.path, fileName));
    final temporary = File('${destination.path}.tmp');
    final backup = File('${destination.path}.bak');

    await temporary.writeAsString(encoded, flush: true);
    try {
      validate(await temporary.readAsString());
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    await _replaceValidatedGeneration(
      destination: destination,
      temporary: temporary,
      backup: backup,
    );
    return destination;
  }

  Future<File> _writeAtomicBytes(
    String fileName,
    Uint8List bytes,
    void Function(Uint8List) validate,
  ) async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final destination = File(p.join(directory.path, fileName));
    final temporary = File('${destination.path}.tmp');
    final backup = File('${destination.path}.bak');

    await temporary.writeAsBytes(bytes, flush: true);
    try {
      validate(await temporary.readAsBytes());
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    await _replaceValidatedGeneration(
      destination: destination,
      temporary: temporary,
      backup: backup,
    );
    return destination;
  }

  Future<void> _replaceValidatedGeneration({
    required File destination,
    required File temporary,
    required File backup,
  }) async {
    if (await backup.exists()) await backup.delete();
    if (await destination.exists()) {
      await destination.rename(backup.path);
    }
    try {
      await temporary.rename(destination.path);
    } catch (_) {
      if (!await destination.exists() && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
    if (await backup.exists()) await backup.delete();
  }

  Future<T?> _readWithBackup<T>(
    String fileName,
    T Function(String) decode,
  ) async {
    final directory = await _directoryProvider();
    final destination = File(p.join(directory.path, fileName));
    final backup = File('${destination.path}.bak');
    for (final candidate in <File>[destination, backup]) {
      try {
        if (!await candidate.exists()) continue;
        return decode(await candidate.readAsString());
      } catch (_) {
        // An interrupted same-directory swap can leave one invalid generation.
      }
    }
    return null;
  }

  HandsetAcceptanceSnapshot _decodeCheckpoint(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Handset checkpoint must be an object');
    }
    return HandsetAcceptanceSnapshot.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  PreservationSnapshot _decodeBaseline(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Handset baseline must be an object');
    }
    return PreservationSnapshot.fromJson(Map<String, Object?>.from(decoded));
  }

  void _validateFinalReport(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map ||
        decoded['schema'] != 'pocketgallery.r50.handset-acceptance.v1' ||
        decoded['schemaVersion'] != 1) {
      throw const FormatException('Invalid R5.0 handset report');
    }
  }

  String _sanitizeRunId(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'run' : normalized;
  }
}
