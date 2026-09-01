import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketgallery_phone_pilot/services/hf_oauth_device_service.dart';

void main() {
  test('credential inspection is expired, local-only, and non-mutating', () async {
    final storage = _FakeSecureStorage(<String, String>{
      'hf_oauth_access_token': 'hf_access_private_value',
      'hf_oauth_refresh_token': 'hf_refresh_private_value',
      'hf_oauth_expiry_epoch_ms': '${DateTime.utc(2026, 8, 31).millisecondsSinceEpoch}',
    });
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{}', 500);
    });
    final before = Map<String, String>.from(storage.values);
    final service = HfOAuthDeviceService(
      client: client,
      storage: storage,
      now: () => DateTime.utc(2026, 9, 1),
    );

    final state = await service.inspectCredentialState();

    expect(state.accessPresent, isTrue);
    expect(state.refreshPresent, isTrue);
    expect(state.expiry, HfTokenExpiryState.expired);
    expect(storage.values, before);
    expect(storage.mutations, isEmpty);
    expect(requests, isEmpty);
  });

  test('credential inspection distinguishes missing, malformed, and valid expiry', () async {
    final cases = <(String?, HfTokenExpiryState)>[
      (null, HfTokenExpiryState.missing),
      ('not-an-epoch', HfTokenExpiryState.malformed),
      (
        '${DateTime.utc(2026, 9, 2).millisecondsSinceEpoch}',
        HfTokenExpiryState.valid,
      ),
    ];

    for (final (expiry, expected) in cases) {
      final values = <String, String>{};
      if (expiry != null) values['hf_oauth_expiry_epoch_ms'] = expiry;
      final service = HfOAuthDeviceService(
        storage: _FakeSecureStorage(values),
        now: () => DateTime.utc(2026, 9, 1),
      );

      expect((await service.inspectCredentialState()).expiry, expected);
    }
  });
}

final class _FakeSecureStorage implements FlutterSecureStorage {
  _FakeSecureStorage(Map<String, String> values)
      : values = Map<String, String>.from(values);

  final Map<String, String> values;
  final List<String> mutations = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.namedArguments[#key] as String?;
    if (invocation.memberName == #read) {
      return Future<String?>.value(key == null ? null : values[key]);
    }
    if (invocation.memberName == #write) {
      mutations.add('write:$key');
      final value = invocation.namedArguments[#value] as String?;
      if (key != null && value != null) values[key] = value;
      return Future<void>.value();
    }
    if (invocation.memberName == #delete) {
      mutations.add('delete:$key');
      if (key != null) values.remove(key);
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}
