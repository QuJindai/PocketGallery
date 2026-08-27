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

  static const _pendingDeviceCodeKey = 'hf_oauth_pending_device_code';
  static const _pendingUserCodeKey = 'hf_oauth_pending_user_code';
  static const _pendingVerificationUriKey =
      'hf_oauth_pending_verification_uri';
  static const _pendingVerificationCompleteKey =
      'hf_oauth_pending_verification_complete';
  static const _pendingIntervalKey = 'hf_oauth_pending_interval_seconds';
  static const _pendingExpiryKey = 'hf_oauth_pending_expiry_epoch_ms';

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

  Future<bool> hasPendingAuthorization() async {
    final pending = await _loadPendingAuthorization();
    return pending != null;
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

  Future<HfDeviceAuthorization> beginAuthorization({
    void Function(HfDeviceAuthorization authorization)? onDeviceCode,
  }) async {
    final authorization = await requestDeviceCode();

    // Persist the device transaction before leaving the app. Android may pause
    // or reclaim the Flutter activity while the external browser is open.
    await _savePendingAuthorization(authorization);
    onDeviceCode?.call(authorization);

    final launched = await launchUrl(
      Uri.parse(authorization.verificationUriComplete),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      await clearPendingAuthorization();
      throw StateError('Unable to open Hugging Face authorization page');
    }
    return authorization;
  }

  Future<String> authorize({
    void Function(HfDeviceAuthorization authorization)? onDeviceCode,
  }) async {
    await beginAuthorization(onDeviceCode: onDeviceCode);
    final token = await resumePendingAuthorization(
      maxWait: const Duration(seconds: 30),
    );
    if (token == null) {
      throw StateError(
        'Hugging Face authorization is still pending; return to the app to continue',
      );
    }
    return token;
  }

  Future<String?> resumePendingAuthorization({
    Duration maxWait = const Duration(seconds: 30),
  }) async {
    final existing = await getValidAccessToken();
    if (existing != null && existing.isNotEmpty) {
      await clearPendingAuthorization();
      return existing;
    }

    final pending = await _loadPendingAuthorization();
    if (pending == null) return null;

    final pendingExpiryMs = int.tryParse(
      await _storage.read(key: _pendingExpiryKey) ?? '',
    );
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (pendingExpiryMs == null || pendingExpiryMs <= nowMs) {
      await clearPendingAuthorization();
      return null;
    }

    var interval = pending.intervalSeconds;
    final pendingDeadline =
        DateTime.fromMillisecondsSinceEpoch(pendingExpiryMs);
    final localDeadline = DateTime.now().add(maxWait);
    final deadline = pendingDeadline.isBefore(localDeadline)
        ? pendingDeadline
        : localDeadline;

    while (DateTime.now().isBefore(deadline)) {
      Map<String, dynamic>? data;
      int? statusCode;
      try {
        final response = await _client.post(
          Uri.parse('$endpoint/oauth/token'),
          body: {
            'grant_type': deviceGrantType,
            'device_code': pending.deviceCode,
            'client_id': deviceClientId,
          },
        );
        statusCode = response.statusCode;
        if (response.body.isNotEmpty) {
          data = jsonDecode(response.body) as Map<String, dynamic>;
        }
      } catch (_) {
        data = null;
      }

      final accessToken = data?['access_token'] as String?;
      if (accessToken != null && accessToken.isNotEmpty) {
        await _saveTokenResponse(data!);
        await clearPendingAuthorization();
        return accessToken;
      }

      final error = data?['error'] as String?;
      if (error == 'access_denied') {
        await clearPendingAuthorization();
        throw StateError('Hugging Face authorization was denied');
      }
      if (error == 'expired_token') {
        await clearPendingAuthorization();
        throw StateError('Hugging Face authorization code expired');
      }
      if (error == 'slow_down') interval += 5;

      // authorization_pending is expected until the browser approval finishes.
      // Unknown 4xx responses are surfaced instead of being hidden for minutes.
      if (statusCode != null &&
          statusCode >= 400 &&
          statusCode < 500 &&
          error != null &&
          error != 'authorization_pending' &&
          error != 'slow_down') {
        throw StateError('Hugging Face token exchange failed: $error');
      }

      await Future<void>.delayed(Duration(seconds: interval));
    }

    // Keep the persisted pending transaction if HF still reports pending. A
    // later lifecycle resume or app restart can continue the same exchange.
    return null;
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

  Future<void> _savePendingAuthorization(
    HfDeviceAuthorization authorization,
  ) async {
    final expiryMs = DateTime.now()
        .add(Duration(seconds: authorization.expiresInSeconds))
        .millisecondsSinceEpoch;
    await _storage.write(
      key: _pendingDeviceCodeKey,
      value: authorization.deviceCode,
    );
    await _storage.write(
      key: _pendingUserCodeKey,
      value: authorization.userCode,
    );
    await _storage.write(
      key: _pendingVerificationUriKey,
      value: authorization.verificationUri,
    );
    await _storage.write(
      key: _pendingVerificationCompleteKey,
      value: authorization.verificationUriComplete,
    );
    await _storage.write(
      key: _pendingIntervalKey,
      value: '${authorization.intervalSeconds}',
    );
    await _storage.write(key: _pendingExpiryKey, value: '$expiryMs');
  }

  Future<HfDeviceAuthorization?> _loadPendingAuthorization() async {
    final deviceCode = await _storage.read(key: _pendingDeviceCodeKey);
    final userCode = await _storage.read(key: _pendingUserCodeKey);
    final verificationUri =
        await _storage.read(key: _pendingVerificationUriKey);
    final verificationUriComplete =
        await _storage.read(key: _pendingVerificationCompleteKey);
    final interval = int.tryParse(
      await _storage.read(key: _pendingIntervalKey) ?? '',
    );
    final expiryMs = int.tryParse(
      await _storage.read(key: _pendingExpiryKey) ?? '',
    );

    if (deviceCode == null ||
        deviceCode.isEmpty ||
        userCode == null ||
        verificationUri == null ||
        verificationUriComplete == null ||
        interval == null ||
        expiryMs == null) {
      return null;
    }

    final remainingMs = expiryMs - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) {
      await clearPendingAuthorization();
      return null;
    }

    return HfDeviceAuthorization(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri,
      verificationUriComplete: verificationUriComplete,
      intervalSeconds: interval,
      expiresInSeconds: (remainingMs / 1000).ceil(),
    );
  }

  Future<void> clearPendingAuthorization() async {
    await _storage.delete(key: _pendingDeviceCodeKey);
    await _storage.delete(key: _pendingUserCodeKey);
    await _storage.delete(key: _pendingVerificationUriKey);
    await _storage.delete(key: _pendingVerificationCompleteKey);
    await _storage.delete(key: _pendingIntervalKey);
    await _storage.delete(key: _pendingExpiryKey);
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
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 28800;
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
