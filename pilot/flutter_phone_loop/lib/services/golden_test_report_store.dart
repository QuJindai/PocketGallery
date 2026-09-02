import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'golden_test_state.dart';

typedef GoldenReportDirectoryProvider = Future<Directory> Function();

class GoldenTestReportStore {
  GoldenTestReportStore({GoldenReportDirectoryProvider? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? getApplicationDocumentsDirectory;

  static const String fileName = 'PG_GOLDEN_LAST.json';

  final GoldenReportDirectoryProvider _directoryProvider;

  Future<File> save(GoldenTestSnapshot snapshot) async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final destination = File(p.join(directory.path, fileName));
    final temporary = File('${destination.path}.tmp');
    final backup = File('${destination.path}.bak');
    final encoded = const JsonEncoder.withIndent('  ')
        .convert(snapshot.toJson());

    await temporary.writeAsString(encoded, flush: true);
    _decodeSnapshot(await temporary.readAsString());

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
    return destination;
  }

  Future<GoldenTestSnapshot?> readLast() async {
    final directory = await _directoryProvider();
    final destination = File(p.join(directory.path, fileName));
    final backup = File('${destination.path}.bak');

    for (final candidate in [destination, backup]) {
      try {
        if (!await candidate.exists()) continue;
        return _decodeSnapshot(await candidate.readAsString());
      } catch (_) {
        // A process can stop between the two same-directory renames. Ignore a
        // malformed candidate and try the other complete generation.
      }
    }
    return null;
  }

  GoldenTestSnapshot _decodeSnapshot(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Golden Test report must be an object');
    }
    return GoldenTestSnapshot.fromJson(Map<String, dynamic>.from(decoded));
  }
}
