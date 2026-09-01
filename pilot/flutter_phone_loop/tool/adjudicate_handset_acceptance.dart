import 'dart:convert';
import 'dart:io';

import 'package:pocketgallery_phone_pilot/acceptance/release_readiness_adjudicator.dart';

const String _usage =
    'Usage: dart run tool/adjudicate_handset_acceptance.dart '
    '--device-report <PG_HANDSET_ACCEPTANCE.json> '
    '--automated-evidence <PG_AUTOMATED_EVIDENCE.json> '
    '--apk-sha256 <candidate.apk.sha256> '
    '--output <PG_MERGE_READINESS.json>';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 &&
      (arguments.single == '--help' || arguments.single == '-h')) {
    stdout.writeln(_usage);
    return;
  }

  try {
    final options = _parseArguments(arguments);
    final device = DeviceAcceptanceEvidence.fromJson(
      await _readJsonObject(options.deviceReport),
    );
    final automated = AutomatedReleaseEvidence.fromJson(
      await _readJsonObject(options.automatedEvidence),
    );
    final sidecar = await _readSidecarDigest(options.apkSha256Sidecar);
    final decision = ReleaseReadinessAdjudicator.adjudicate(
      device,
      automated,
      sidecar,
    );
    await _writeAtomicJson(options.output, decision.toJson());
    stdout.writeln('MERGE_READY=${decision.mergeReady}');
    if (!decision.mergeReady) exitCode = 2;
  } on FormatException catch (error) {
    stderr.writeln('Invalid input: ${error.message}');
    stderr.writeln(_usage);
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('Invalid input file: ${error.message}');
    stderr.writeln(_usage);
    exitCode = 64;
  }
}

_CliOptions _parseArguments(List<String> arguments) {
  const flags = <String>{
    '--device-report',
    '--automated-evidence',
    '--apk-sha256',
    '--output',
  };
  if (arguments.length != flags.length * 2) {
    throw const FormatException('Exactly four flag/value pairs are required');
  }
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final flag = arguments[index];
    final value = arguments[index + 1];
    if (!flags.contains(flag)) {
      throw FormatException('Unknown argument: $flag');
    }
    if (values.containsKey(flag)) {
      throw FormatException('Duplicate argument: $flag');
    }
    if (value.trim().isEmpty || value.startsWith('--')) {
      throw FormatException('Missing value for $flag');
    }
    values[flag] = value;
  }
  if (!values.keys.toSet().containsAll(flags)) {
    throw const FormatException('Every required argument must be supplied');
  }
  return _CliOptions(
    deviceReport: values['--device-report']!,
    automatedEvidence: values['--automated-evidence']!,
    apkSha256Sidecar: values['--apk-sha256']!,
    output: values['--output']!,
  );
}

Future<Map<String, dynamic>> _readJsonObject(String path) async {
  final decoded = jsonDecode(await File(path).readAsString());
  if (decoded is! Map) {
    throw FormatException('$path must contain one JSON object');
  }
  return Map<String, dynamic>.from(decoded);
}

Future<String> _readSidecarDigest(String path) async {
  final contents = (await File(path).readAsString()).trim();
  if (contents.isEmpty) {
    throw FormatException('$path is empty');
  }
  return contents.split(RegExp(r'\s+')).first;
}

Future<void> _writeAtomicJson(String path, Map<String, Object?> value) async {
  final destination = File(path);
  await destination.parent.create(recursive: true);
  final temporary = File('$path.tmp');
  final backup = File('$path.bak');
  final encoded = const JsonEncoder.withIndent('  ').convert(value);
  await temporary.writeAsString('$encoded\n', flush: true);
  final verified = jsonDecode(await temporary.readAsString());
  if (verified is! Map) {
    await temporary.delete();
    throw const FormatException('Generated readiness output is invalid');
  }

  if (await backup.exists()) await backup.delete();
  if (await destination.exists()) await destination.rename(backup.path);
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

final class _CliOptions {
  const _CliOptions({
    required this.deviceReport,
    required this.automatedEvidence,
    required this.apkSha256Sidecar,
    required this.output,
  });

  final String deviceReport;
  final String automatedEvidence;
  final String apkSha256Sidecar;
  final String output;
}
