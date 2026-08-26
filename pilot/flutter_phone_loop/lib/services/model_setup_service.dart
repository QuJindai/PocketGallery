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
          '账号已授权，但还需要接受 EmbeddingGemma 官方许可；接受后点“已完成许可，自动继续”。',
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
      await oauth.authorize(
        onDeviceCode: (authorization) {
          onProgress?.call(ModelSetupSnapshot(
            phase: ModelSetupPhase.authorizing,
            message:
                '浏览器已打开 · 授权码 ${authorization.userCode} · 完成授权后 App 会自动继续',
          ));
        },
      );
      return prepareAutomatically(onProgress: onProgress);
    } catch (e) {
      final state = ModelSetupSnapshot(
        phase: ModelSetupPhase.authorizationRequired,
        message: 'Hugging Face 官方授权未完成：$e',
      );
      onProgress?.call(state);
      return state;
    }
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
