import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'R3 replaces pasted Hugging Face token with OAuth Device Code flow',
    () async {
      final home = await File('lib/ui/home_page.dart').readAsString();
      final oauthFile = File('lib/services/hf_oauth_device_service.dart');

      expect(home, isNot(contains('Hugging Face Read Token')));
      expect(home, contains('Hugging Face 官方授权'));
      expect(oauthFile.existsSync(), isTrue);

      if (oauthFile.existsSync()) {
        final oauth = await oauthFile.readAsString();
        expect(oauth, contains('/oauth/device'));
        expect(oauth, contains('/oauth/token'));
        expect(oauth, contains('urn:ietf:params:oauth:grant-type:device_code'));
        expect(oauth, contains('refresh_token'));
        expect(oauth, contains('FlutterSecureStorage'));
        expect(oauth, contains('launchUrl'));
      }
    },
  );

  test(
    'R3 model setup consumes OAuth access token without exposing it in UI',
    () async {
      final setup = await File(
        'lib/services/model_setup_service.dart',
      ).readAsString();
      final home = await File('lib/ui/home_page.dart').readAsString();

      expect(setup, contains('HfOAuthDeviceService'));
      expect(setup, contains('getValidAccessToken'));
      expect(home, isNot(contains('hfToken')));
    },
  );
}
