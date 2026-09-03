# PocketGallery Phone Pilot R4.8

这是 PocketGallery 的手机功能闭环 Pilot，核心链路为：

`TXT/MD/PDF → Chunk → FTS5 + EmbeddingGemma → Hybrid/Rerank → Evidence → Gemma 4 → Citation`

## 升级与模型复用

- 设置页会自动检查、下载并激活 Gemma 4、EmbeddingGemma 和 tokenizer，不再手工选择模型文件。
- 同包名、同签名的 R4.x APK 可原位升级；已保存的 Hugging Face OAuth、已接受的模型许可、本机模型文件、聊天与知识库数据会继续复用。
- 已完成授权且模型已下载时，升级后不会重复登录或重复下载。只有模型缺失、损坏或上游版本策略变化时才重新准备。

## 使用流程

1. 安装或原位升级 APK，打开“模型 / 设置”，等待 Gemma 4 与 EmbeddingGemma 显示 READY。
2. 导入 TXT、MD 或可提取文字的 PDF；扫描件需要先 OCR。
3. 在 Chat 中选择自动、本地知识或纯模型模式并提问。
4. 在“模型 / 设置 → 高级 / 诊断”运行 `Run Phone Golden Test`。
5. 查看确定性进度、当前关卡、已完成数量、耗时、逐关状态和最终 PASS/FAIL。

## Phone Golden Test F1–F7

| Gate | 真实验证内容 | 超时 |
|---|---|---:|
| F1 | 安装临时语料并验证导入/Chunk | 45 秒 |
| F2 | FTS5 精确工程码召回 | 30 秒 |
| F3 | Embedding 语义改写召回 | 90 秒 |
| F4 | Hybrid/Rerank 排序 | 90 秒 |
| F5 | Evidence 与 E1 锚点 | 20 秒 |
| F6 | 真实 `ChatOrchestrator → GemmaChatService` 回答与有效引用 | 240 秒 |
| F7 | 同一逻辑会话的重证据第二轮；必须读到第六个不同来源的 `PG_EVIDENCE_LAST_6` 并引用 E6 | 240 秒 |

状态包括等待、运行中、通过、失败、超时和已阻断。F1 失败会阻断 F2–F7；F6 失败会阻断 F7。任何超时、异常、阻断或清理失败都会令总体结果失败。

每次状态变化都会先保存，再更新界面。最新检查点位于 App Documents 的 `PG_GOLDEN_LAST.json`（schemaVersion 2）；写入使用临时文件和备份切换，中断后可从主文件或 `.bak` 恢复。测试结束会移除全部 `pg_golden_*` 临时语料。

F6/F7 必须在已激活真实模型的实体手机执行。GitHub Actions 负责验证状态机、报告恢复、严格断言、Widget UI、静态分析、回归测试和 APK 构建，不能替代实体手机上的 LiteRT 推理结果。

## Chunk 与向量说明

Chunk 是可引用、可排序的文本单元；向量是该文本的数值表示，两者不是同一概念。当前实现通常为每个 Chunk 生成一条向量 observation，但这只是当前索引映射，不应把“一个 Chunk”等同于“一个向量”。

## 构建

使用 Flutter 3.44 或更高版本：

```bash
bash scripts/build_debug_apk.sh
```

GitHub Actions 会构建仅包含 `arm64-v8a` 的 Phone Pilot 更新 APK，并验证包名、versionCode、ABI、固定签名证书和 SHA-256。
