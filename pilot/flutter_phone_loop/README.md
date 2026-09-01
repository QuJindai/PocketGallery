# PocketGallery Phone Pilot R5.0

这是 PocketGallery 的手机功能闭环 Pilot，核心链路为：

`TXT/MD/PDF → Chunk → FTS5 + EmbeddingGemma → Hybrid/Rerank → Evidence → Gemma 4 → Citation`

## 升级与模型复用

- 设置页会自动检查、下载并激活 Gemma 4、EmbeddingGemma 和 tokenizer，不再手工选择模型文件。
- 同包名、同签名的 R4.x/R5.0 APK 可原位升级；已保存的 Hugging Face OAuth、已接受的模型许可、本机模型文件、聊天、知识库、向量 observation 与血缘数据会继续复用。
- 已完成授权且模型已下载时，升级后不会重复登录或重复下载。只有模型缺失、损坏或上游版本策略变化时才重新准备。

## 使用流程

1. 安装或原位升级 APK，打开“模型 / 设置”，等待 Gemma 4 与 EmbeddingGemma 显示 READY。
2. 导入 TXT、MD 或可提取文字的 PDF；扫描件需要先 OCR。
3. 在 Chat 中选择自动、本地知识或纯模型模式并提问。
4. 在“模型 / 设置”直接打开醒目的“手机一键验收”；入口不因模型未就绪而消失，模型前置条件只在开始后如实判定。
5. 到 H6 时，在真实高维向量的 `768D → 3D PCA` 图中完成单指旋转、双指缩放、点选与界面确认。
6. 查看 H1–H10、嵌套 F1–F10、帧 P95、PSS、可用内存、电池温度与 Android thermal status，并在终态导出脱敏报告。
7. `Run Phone Golden Test` 仍保留在“高级 / 诊断”，用于只运行聚焦的 F1–F10 功能闭环。

## 手机一键验收 H1–H10

| Gate | 实体手机验收内容 |
|---|---|
| H1 | Samsung Galaxy S24 Ultra 目标机型（`SM-S928*`） |
| H2 | 包名、版本、固定签名、APK SHA-256 与编译提交 |
| H3 | 低版本私有升级基线 |
| H4 | 嵌套 Phone Golden Test F1–F10 |
| H5 | 同次 F6 trace 的真实高维向量、Query/Chunk 身份与三分量 PCA 真值 |
| H6 | 实体旋转、缩放、点选、视口确认与 15 秒帧采样 |
| H7 | 持续渲染门槛 |
| H8 | PSS、系统可用内存、低内存状态、电池温度与 thermal status |
| H9 | 模型、OAuth、知识、聊天、向量与血缘的同次/跨版本保全 |
| H10 | 脱敏报告完整性与原子持久化 |

App 只输出 `DEVICE_ACCEPTANCE` 与 `MERGE_CANDIDATE`，绝不自行宣称 `MERGE_READY`。最终结果必须在仓库侧用设备报告、`PG_AUTOMATED_EVIDENCE.json` 和 candidate APK SHA-256 sidecar 做同提交裁决。
设备报告只在用户点击导出后保存到用户选定的位置，App 不会自动上传。

## Phone Golden Test F1–F10

| Gate | 真实验证内容 | 超时 |
|---|---|---:|
| F1 | 安装临时语料并验证导入/Chunk | 45 秒 |
| F2 | FTS5 精确工程码召回 | 30 秒 |
| F3 | Embedding 语义改写召回 | 90 秒 |
| F4 | Hybrid/Rerank 排序 | 90 秒 |
| F5 | Evidence 与 E1 锚点 | 20 秒 |
| F6 | 真实 `ChatOrchestrator → GemmaChatService` 回答与有效引用 | 240 秒 |
| F7 | 同一逻辑会话的重证据第二轮；必须读到第六个不同来源的 `PG_EVIDENCE_LAST_6` 并引用 E6 | 240 秒 |
| F8 | 校验 F6 的 ACTIVE 运行时血缘事件闭环 | 10 秒 |
| F9 | 校验 F6 持久化查询向量的 ID、模型、维度、SHA 与向量检索事件一致 | 10 秒 |
| F10 | 校验 F6 上下文预算各分量、预填充、输出预留与剩余容量守恒 | 10 秒 |

状态包括等待、运行中、通过、失败、超时和已阻断。F1 失败会阻断 F2–F7；F6 失败会阻断 F7–F10。任何超时、异常、阻断或清理失败都会令总体结果失败。

每次状态变化都会先保存，再更新界面。最新检查点位于 App Documents 的 `PG_GOLDEN_LAST.json`（schemaVersion 2）；写入使用临时文件和备份切换，中断后可从主文件或 `.bak` 恢复。测试结束会移除全部 `pg_golden_*` 临时语料。

F6/F7 必须在已激活真实模型的实体手机执行，F8–F10 随后读取 F6 留下的真实持久化事实。GitHub Actions 负责验证状态机、报告恢复、严格断言、Widget UI、静态分析、回归测试和 APK 构建，不能替代实体手机上的 LiteRT 推理结果。

## Chunk 与向量说明

Chunk 是可引用、可排序的文本单元；向量是该文本的数值表示，两者不是同一概念。当前实现通常为每个 Chunk 生成一条向量 observation，但这只是当前索引映射，不应把“一个 Chunk”等同于“一个向量”。

## 构建

使用 Flutter 3.44 或更高版本：

```bash
bash scripts/build_debug_apk.sh
```

R5.0 的普通 TDD 工作流会发布非 canonical 的 `PocketGallery-R50-handset-acceptance-debug.apk`，仅用于自动化与安装烟测，不能证明可原位升级。

canonical 工作流在同一源码提交上构建并逐个验证：

- `PocketGallery-R50-baseline-v2022.apk`（Android versionCode 2022）；
- `PocketGallery-R50-candidate-v2023.apk`（Android versionCode 2023）；
- 两个 SHA-256 sidecar；
- `PG_AUTOMATED_EVIDENCE.json`。

两 APK 都必须仅含 `arm64-v8a`、保持包名 `com.qujindai.pocketgallery_phone_pilot.r3`，并使用固定签名证书 `81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541`。缺少 canonical 凭据时工作流以 `SIGNING_IDENTITY_MISSING` 失败，不会生成替代密钥。完整实体机步骤见 `docs/phone-pilot/r50-s24u-handset-acceptance-runbook.md`。
