import 'package:file_picker/file_picker.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class ModelSetupService {
  Future<String?> pickFile(List<String> extensions) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    return result?.files.single.path;
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
