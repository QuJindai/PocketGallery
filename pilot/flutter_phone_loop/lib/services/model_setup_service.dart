import 'package:file_picker/file_picker.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'hf_oauth_device_service.dart';

enum ModelSetupPhase {
  checking,
  downloadingGemma,
  authorizationRequired,
  authorizing,
  downloadingEmbedding,
  downloadingTokenizer,
  ready,
  failed,
}

class ModelSetupSnapshot {
  const ModelSetupSnapshot({
    required this.phase,
    required this.message,
    this.progress,
  });

  final ModelSetupPhase phase;
  final String message;
  final int? progress;

  bool get ready => phase == ModelSetupPhase.ready;
  bool get authorizationRequired =>
      phase == ModelSetupPhase.authorizationRequired;
}

class ModelSetupService {
  ModelSetupService({HfOAuthDeviceService? oauth})
      : oauth = oauth ?? HfOAuthDeviceService();

  static const gemma4Url =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
  static const embeddingModelUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite';
  static const embeddingTokenizerUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model';

  final HfOAuthDeviceService oauth;

  Future<bool> hasPendingAuthorization() => oauth.hasPendingAuthorization();

  Future<ModelSetupSnapshot> prepareAutomatically({
    void Function(ModelSetupSnapshot state)? onProgress,
  }) async {
    ModelSetupSnapshot emit(
      ModelSetupPhase phase,
      String message, {
      int? progress,
    }) {
      final state = ModelSetupSnapshot(
        phase: phase,
        message: message,
        progress: progress,
      );
      onProgress?.call(state);
      return state;
    }

    emit(ModelSetupPhase.checking, '检查本机模型资产…');

    try {
      if (!FlutterGemma.hasActiveModel()) {
        await FlutterGemma.installModel(
          modelType: ModelType.gemma4,
          fileType: ModelFileType.litertlm,
        )
            .fromNetwork(gemma4Url, foreground: true)
            .withProgress((p) => emit(
                  ModelSetupPhase.downloadingGemma,
                  '自动下载 Gemma 4 · $p%',
                  progress: p,
                ))
            .install();
      }

      if (!FlutterGemma.hasActiveEmbedder()) {
        final token = await oauth.getValidAccessToken();
        if (token == null || token.isEmpty) {
          if (await oauth.hasPendingAuthorization()) {
            return emit(
              ModelSetupPhase.authorizing,
              '检测到未完成的 Hugging Face 官方授权；返回 App 后会自动领取令牌并继续下载。',
            );
          }
          return emit(
            ModelSetupPhase.authorizationRequired,
            'Gemma 4 已就绪；EmbeddingGemma 需要一次 Hugging Face 官方授权。',
          );
        }

        await FlutterGemma.installEmbedder()
            .modelFromNetwork(embeddingModelUrl, token: token)
            .tokenizerFromNetwork(embeddingTokenizerUrl, token: token)
            .withModelProgress((p) => emit(
                  ModelSetupPhase.downloadingEmbedding,
                  '自动下载 EmbeddingGemma · $p%',
                  progress: p,
                ))
            .withTokenizerProgress((p) => emit(
                  ModelSetupPhase.downloadingTokenizer,
                  '自动下载 Tokenizer · $p%',
                  progress: p,
                ))
            .install();
      }

      if (!FlutterGemma.hasActiveModel() ||
          !FlutterGemma.hasActiveEmbedder()) {
        return emit(
          ModelSetupPhase.failed,
          '模型文件已处理，但激活自检未通过。可直接重试，不需要重新下载已就绪模型。',
        );
      }

      return emit(
        ModelSetupPhase.ready,
        '本机模型 READY · Gemma 4 + EmbeddingGemma',
        progress: 100,
      );
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('401') || text.contains('unauthorized')) {
        await oauth.clearTokens();
        return emit(
          ModelSetupPhase.authorizationRequired,
          'Hugging Face 授权已失效，请重新完成一次官方授权。',
        );
      }
      if (text.contains('403') ||
          text.contains('forbidden') ||
          text.contains('gated')) {
        return emit(
          ModelSetupPhase.authorizationRequired,
          '账号已授权，但还需要接受 EmbeddingGemma 官方许可；接受后继续官方授权。',
        );
      }
      return emit(
        ModelSetupPhase.failed,
        '自动准备模型失败：$e',
      );
    }
  }

  Future<ModelSetupSnapshot> authorizeAndPrepare({
    void Function(ModelSetupSnapshot state)? onProgress,
  }) async {
    onProgress?.call(const ModelSetupSnapshot(
      phase: ModelSetupPhase.authorizing,
      message: '正在启动 Hugging Face 官方授权…',
    ));
    try {
      final authorization = await oauth.beginAuthorization(
        onDeviceCode: (authorization) {
          onProgress?.call(ModelSetupSnapshot(
            phase: ModelSetupPhase.authorizing,
            message:
                '浏览器已打开 · 授权码 ${authorization.userCode} · 完成后返回 App，系统会自动继续',
          ));
        },
      );
      final state = ModelSetupSnapshot(
        phase: ModelSetupPhase.authorizing,
        message:
            '等待 Hugging Face 完成授权 · ${authorization.userCode} · 返回 App 后自动领取令牌',
      );
      onProgress?.call(state);
      return state;
    } catch (e) {
      final state = ModelSetupSnapshot(
        phase: ModelSetupPhase.authorizationRequired,
        message: 'Hugging Face 官方授权未启动：$e',
      );
      onProgress?.call(state);
      return state;
    }
  }

  Future<ModelSetupSnapshot> resumePendingAuthorizationAndPrepare({
    void Function(ModelSetupSnapshot state)? onProgress,
  }) async {
    final current = await oauth.getValidAccessToken();
    if (current != null && current.isNotEmpty) {
      return prepareAutomatically(onProgress: onProgress);
    }

    if (!await oauth.hasPendingAuthorization()) {
      final state = const ModelSetupSnapshot(
        phase: ModelSetupPhase.authorizationRequired,
        message: '没有可恢复的 OAuth 授权，请使用 Hugging Face 官方授权。',
      );
      onProgress?.call(state);
      return state;
    }

    onProgress?.call(const ModelSetupSnapshot(
      phase: ModelSetupPhase.authorizing,
      message: '已返回 PocketGallery · 正在领取 Hugging Face OAuth 令牌…',
    ));

    try {
      final token = await oauth.resumePendingAuthorization(
        maxWait: const Duration(seconds: 30),
      );
      if (token == null || token.isEmpty) {
        final state = const ModelSetupSnapshot(
          phase: ModelSetupPhase.authorizing,
          message: 'Hugging Face 仍在确认授权；无需重新操作，App 下次恢复会自动继续。',
        );
        onProgress?.call(state);
        return state;
      }
      return prepareAutomatically(onProgress: onProgress);
    } catch (e) {
      final state = ModelSetupSnapshot(
        phase: ModelSetupPhase.authorizationRequired,
        message: 'Hugging Face 授权回收失败：$e',
      );
      onProgress?.call(state);
      return state;
    }
  }

  Future<ModelSetupSnapshot> continueAfterLicense({
    void Function(ModelSetupSnapshot state)? onProgress,
  }) async {
    final token = await oauth.getValidAccessToken();
    if (token != null && token.isNotEmpty) {
      return prepareAutomatically(onProgress: onProgress);
    }
    if (await oauth.hasPendingAuthorization()) {
      return resumePendingAuthorizationAndPrepare(onProgress: onProgress);
    }
    return authorizeAndPrepare(onProgress: onProgress);
  }

  Future<void> openEmbeddingLicensePage() => oauth.openEmbeddingLicensePage();

  Future<String?> pickFile(List<String> extensions) async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    return result?.path;
  }

  Future<void> installGemma4FromFile(String path) async {
    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromFile(path).install();
  }

  Future<void> installEmbedderFromFiles({
    required String modelPath,
    required String tokenizerPath,
  }) async {
    await FlutterGemma.installEmbedder()
        .modelFromFile(modelPath)
        .tokenizerFromFile(tokenizerPath)
        .install();
  }
}
