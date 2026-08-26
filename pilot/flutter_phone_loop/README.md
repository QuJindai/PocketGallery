# PocketGallery Phone Pilot R1

这是一个**手机功能闭环 Pilot**，目标不是替代原生 PocketGallery，而是最快把核心链路在手机上跑通：

`TXT/MD/PDF -> Chunk -> FTS5(trigram/BM25) + EmbeddingGemma -> Hybrid/Rerank -> Evidence -> Gemma 4 -> Citation`

## 为什么单独做 Pilot

PocketGallery 主仓目前是 Google AI Edge Gallery 下游基线，Knowledge Layer 尚未落地。
为了不被原生 Embedding/JNI 接口整合拖慢，Pilot 使用当前成熟开源组件验证完整功能，再把已验证的数据结构和检索算法回填原生 `overlay/Android`。

## 组装组件

- `flutter_gemma`：模型管理、Gemma API
- `flutter_gemma_litertlm`：LiteRT-LM + `LiteRtEmbeddingBackend`
- `flutter_gemma_rag_sqlite`：sqlite-vec/vec0 语义向量检索
- `sqlite3`：独立 FTS5 trigram/BM25 关键词检索
- `pdfrx`：PDF 文本提取
- `file_picker`：Android 文件选择
- PocketGallery 自有：Chunk、RRF/Hybrid、轻量 rerank、Evidence、Citation、Golden Test

## 本机需要的三个模型文件

1. Gemma 4 E2B `.litertlm`（第一轮推荐 E2B）
2. EmbeddingGemma `.tflite`
3. EmbeddingGemma `sentencepiece.model`

在 App 内各选择一次，点击“初始化本机模型”。

## 功能操作

1. 初始化 Gemma + EmbeddingGemma
2. 导入 TXT / MD / PDF
3. 输入问题，点击“检索并回答”
4. UI 同时显示 FTS5、Embedding、Hybrid 命中数量和 Evidence 来源
5. 点击 `Run Phone Golden Test`，程序自动判定核心 Gate，无需人工判断答案好坏

Golden Test 自动覆盖：

- F1 文档导入/Chunk
- F2 FTS5 精确工程码召回
- F3 Embedding 语义改写召回
- F4 Hybrid/Rerank
- F5 Evidence
- F6 本机 Gemma + Citation

结果保存到 App Documents 的 `PG_GOLDEN_LAST.json`。

## 构建

已有 Flutter >= 3.44：

```bash
bash scripts/build_debug_apk.sh
```

或者直接把工程放到 GitHub，Actions 会生成 `PocketGallery-Phone-Pilot-debug-apk` artifact。

## 边界

R1 不把温度、TTFT、长期稳定性、断网压力作为阻塞 Gate。当前只证明功能链路。
FTS5 和 Embedding 都是真实执行路径；没有 embedding 时不会退化成“伪语义检索”。
