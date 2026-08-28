import 'package:file_picker/file_picker.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'hf_oauth_device_service.dart';

enum ModelSetupPhase {
  checking,
  downloadingGemma,
  authorizationRequired,
  licenseRequired,
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
  bool get licenseRequired => phase == ModelSetupPhase.licenseRequired;
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

  Future<String?> getPendingUserCode() => oauth.getPendingUserCode();

  Future<void> _retryCanceledDownload(
    Future<void> Function() operation, {
    required void Function(int attempt, int maxRestarts) onRetry,
    int maxRestarts = 3,
  }) async {
    var restartCount = 0;
    while (true) {
      try {
        await operation();
        return;
      } on DownloadException catch (e) {
        if (e.error is! CanceledError || restartCount >= maxRestarts) {
          rethrow;
        }
        restartCount++;
        onRetry(restartCount, maxRestarts);
        await Future<void>.delayed(Duration(seconds: restartCount * 2));
      }
    }
  }

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
        await _retryCanceledDownload(
          () async {
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
          },
          onRetry: (attempt, maxRestarts) => emit(
            ModelSetupPhase.downloadingGemma,
            'Gemma 4 下载被系统中断，正在自动恢复 $attempt/$maxRestarts · 无需重新登录',
          ),
        );
      }

      if (!FlutterGemma.hasActiveEmbedder()) {
        final token = await oauth.getValidAccessToken();
        if (token == null || token.isEmpty) {
          if (await oauth.hasPendingAuthorization()) {
            final code = await oauth.getPendingUserCode();
            return emit(
              ModelSetupPhase.authorizing,
              code == null
                  ? '检测到未完成的 Hugging Face 官方授权；返回 App 后会自动领取令牌并继续下载。'
                  : 'Hugging Face 授权码 $code 已复制到剪贴板；在网页粘贴后返回 App，系统会自动继续。',
            );
          }
          return emit(
            ModelSetupPhase.authorizationRequired,
            'Gemma 4 已就绪；EmbeddingGemma 只需要首次 Hugging Face 官方授权。后续原地升级会保留授权与模型。',
          );
        }

        await _retryCanceledDownload(
          () async {
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
          },
          onRetry: (attempt, maxRestarts) => emit(
            ModelSetupPhase.downloadingEmbedding,
            'EmbeddingGemma 下载被系统中断，正在自动恢复 $attempt/$maxRestarts · OAuth 已保留',
          ),
        );
      }

      if (!FlutterGemma.hasActiveModel() ||
          !FlutterGemma.hasActiveEmbedder()) {
        return emit(
          ModelSetupPhase.failed,
          '模型文件已处理，但激活身份自检未通过。可直接重试；已就绪模型与 OAuth 不会被清除。',
        );
      }

      // `hasActiveEmbedder()` only proves that the persisted active embedding
      // spec exists. RAG add/search needs flutter_gemma's runtime singleton as
      // well, so materialize it before reporting READY. This loads the already
      // installed files and never redownloads the model.
      emit(ModelSetupPhase.checking, 'Embedding runtime 自检…');
      await FlutterGemma.getActiveEmbedder();

      return emit(
        ModelSetupPhase.ready,
        '本机模型 READY · Gemma 4 + EmbeddingGemma · Embedding runtime READY',
        progress: 100,
      );
    } on DownloadException catch (e) {
      final error = e.error;
      if (error is UnauthorizedError) {
        await oauth.clearTokens();
        return emit(
          ModelSetupPhase.authorizationRequired,
          'Hugging Face 明确返回 401，OAuth 已失效；仅这种情况需要重新授权。',
        );
      }
      if (error is ForbiddenError) {
        return emit(
          ModelSetupPhase.licenseRequired,
          'OAuth 已保留，但 Hugging Face 拒绝 gated 文件访问。通常只需接受一次官方 Gemma License；返回 App 后自动继续，不会重新登录。',
        );
      }
      if (error is CanceledError) {
        return emit(
          ModelSetupPhase.failed,
          '下载连续被系统中断，已自动恢复 3 次。OAuth 与已下载模型均已保留；稍后重试不会要求重新登录。',
        );
      }
      return emit(
        ModelSetupPhase.failed,
        '模型下载暂时失败：${error.toUserMessage()}；OAuth 与已就绪模型均保留。',
      );
    } catch (e) {
      // Non-download runtime failures must never be interpreted as an OAuth
      // failure. In particular, do not clear credentials based on substring
      // matching of arbitrary exception text.
      return emit(
        ModelSetupPhase.failed,
        '自动准备模型失败：$e；OAuth 与已就绪模型均保留。',
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
                '浏览器已打开 · 授权码 ${authorization.userCode} 已复制到剪贴板 · 在网页粘贴并继续，完成后返回 App',
          ));
        },
      );
      final state = ModelSetupSnapshot(
        phase: ModelSetupPhase.authorizing,
        message:
            '等待 Hugging Face 完成授权 · ${authorization.userCode} 已复制到剪贴板 · 网页粘贴后返回 App 自动继续',
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

    final code = await oauth.getPendingUserCode();
    onProgress?.call(ModelSetupSnapshot(
      phase: ModelSetupPhase.authorizing,
      message: code == null
          ? '已返回 PocketGallery · 正在领取 Hugging Face OAuth 令牌…'
          : '授权码 $code 已复制到剪贴板 · 如果网页仍显示 8 位输入框，请粘贴并继续；App 正在等待授权完成…',
    ));

    try {
      final token = await oauth.resumePendingAuthorization(
        maxWait: const Duration(seconds: 30),
      );
      if (token == null || token.isEmpty) {
        final state = ModelSetupSnapshot(
          phase: ModelSetupPhase.authorizing,
          message: code == null
              ? 'Hugging Face 仍在确认授权；无需重新操作，App 下次恢复会自动继续。'
              : 'Hugging Face 仍在等待网页确认 · 授权码 $code 已复制到剪贴板；粘贴并完成后返回 App。',
        );
        onProgress?.call(state);
        return state;
      }
      return await prepareAutomatically(onProgress: onProgress);
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
