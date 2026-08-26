import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class HfDeviceAuthorization {
  const HfDeviceAuthorization({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.intervalSeconds,
    required this.expiresInSeconds,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String verificationUriComplete;
  final int intervalSeconds;
  final int expiresInSeconds;
}

class HfOAuthDeviceService {
  HfOAuthDeviceService({
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  static const endpoint = 'https://huggingface.co';
  static const deviceClientId = '26be6b09-91c5-47da-9861-d2d2bb7a7e36';
  static const deviceGrantType =
      'urn:ietf:params:oauth:grant-type:device_code';
  static const embeddingLicenseUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m';

  static const _accessKey = 'hf_oauth_access_token';
  static const _refreshKey = 'hf_oauth_refresh_token';
  static const _expiryKey = 'hf_oauth_expiry_epoch_ms';

  final http.Client _client;
  final FlutterSecureStorage _storage;

  Future<String?> getValidAccessToken() async {
    final accessToken = await _storage.read(key: _accessKey);
    final expiryText = await _storage.read(key: _expiryKey);
    final expiryMs = int.tryParse(expiryText ?? '');
    if (accessToken != null && accessToken.isNotEmpty && expiryMs != null) {
      final refreshBefore = DateTime.now().millisecondsSinceEpoch + 60000;
      if (expiryMs > refreshBefore) {
        return accessToken;
      }
    }

    final refreshToken = await _storage.read(key: _refreshKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }
    try {
      return await _refresh(refreshToken);
    } catch (_) {
      await clearTokens();
      return null;
    }
  }

  Future<HfDeviceAuthorization> requestDeviceCode() async {
    final response = await _client.post(
      Uri.parse('$endpoint/oauth/device'),
      body: const {
        'client_id': deviceClientId,
        'scope': 'gated-repos',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Hugging Face device authorization failed: HTTP ${response.statusCode}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final verificationUri = data['verification_uri'] as String?;
    final deviceCode = data['device_code'] as String?;
    final userCode = data['user_code'] as String?;
    if (verificationUri == null || deviceCode == null || userCode == null) {
      throw const FormatException('Invalid Hugging Face device-code response');
    }
    return HfDeviceAuthorization(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri,
      verificationUriComplete:
          (data['verification_uri_complete'] as String?) ?? verificationUri,
      intervalSeconds: (data['interval'] as num?)?.toInt() ?? 5,
      expiresInSeconds: (data['expires_in'] as num?)?.toInt() ?? 900,
    );
  }

  Future<String> authorize({
    void Function(HfDeviceAuthorization authorization)? onDeviceCode,
  }) async {
    final authorization = await requestDeviceCode();
    onDeviceCode?.call(authorization);

    final launched = await launchUrl(
      Uri.parse(authorization.verificationUriComplete),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw StateError('Unable to open Hugging Face authorization page');
    }

    return _pollForToken(authorization);
  }

  Future<void> openEmbeddingLicensePage() async {
    final launched = await launchUrl(
      Uri.parse(embeddingLicenseUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw StateError('Unable to open EmbeddingGemma license page');
    }
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _expiryKey);
  }

  Future<String> _pollForToken(HfDeviceAuthorization authorization) async {
    var interval = authorization.intervalSeconds;
    final deadline = DateTime.now().add(
      Duration(seconds: authorization.expiresInSeconds),
    );

    while (DateTime.now().isBefore(deadline)) {
      Map<String, dynamic>? data;
      try {
        final response = await _client.post(
          Uri.parse('$endpoint/oauth/token'),
          body: {
            'grant_type': deviceGrantType,
            'device_code': authorization.deviceCode,
            'client_id': deviceClientId,
          },
        );
        if (response.body.isNotEmpty) {
          data = jsonDecode(response.body) as Map<String, dynamic>;
        }
      } catch (_) {
        data = null;
      }

      final accessToken = data?['access_token'] as String?;
      if (accessToken != null && accessToken.isNotEmpty) {
        await _saveTokenResponse(data!);
        return accessToken;
      }

      final error = data?['error'] as String?;
      if (error == 'access_denied') {
        throw StateError('Hugging Face authorization was denied');
      }
      if (error == 'expired_token') {
        throw StateError('Hugging Face authorization code expired');
      }
      if (error == 'slow_down') {
        interval += 5;
      }
      await Future<void>.delayed(Duration(seconds: interval));
    }
    throw StateError('Hugging Face authorization timed out');
  }

  Future<String> _refresh(String refreshToken) async {
    final response = await _client.post(
      Uri.parse('$endpoint/oauth/token'),
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': deviceClientId,
      },
    );
    final data = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String?;
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        accessToken == null ||
        accessToken.isEmpty) {
      throw StateError('Hugging Face token refresh failed');
    }
    await _saveTokenResponse(data, previousRefreshToken: refreshToken);
    return accessToken;
  }

  Future<void> _saveTokenResponse(
    Map<String, dynamic> data, {
    String? previousRefreshToken,
  }) async {
    final accessToken = data['access_token'] as String;
    final refreshToken =
        (data['refresh_token'] as String?) ?? previousRefreshToken;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
    final expiry = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .millisecondsSinceEpoch;

    await _storage.write(key: _accessKey, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshKey, value: refreshToken);
    }
    await _storage.write(key: _expiryKey, value: '$expiry');
  }
}
