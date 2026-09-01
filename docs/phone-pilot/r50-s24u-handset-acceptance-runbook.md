# PocketGallery R5.0 · S24 Ultra 实体机验收手册

## 目标与硬边界

本手册只用于 Samsung Galaxy S24 Ultra，Android 型号必须匹配 `SM-S928*`（例如 `SM-S9280`）。canonical 包名固定为 `com.qujindai.pocketgallery_phone_pilot.r3`，签名证书 SHA-256 固定为 `81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541`。

整个升级序列不得卸载 App、不得清除数据、不得改包名或换签名。卸载会破坏本次验收要证明的 OAuth、模型、知识库、聊天、向量 observation 与血缘保全事实。

## 所需产物

从同一次 canonical Actions 运行下载并保留：

- `PocketGallery-R50-baseline-v2022.apk` 与其 `.sha256`；
- `PocketGallery-R50-candidate-v2023.apk` 与其 `.sha256`；
- `PG_AUTOMATED_EVIDENCE.json`。

先核对两个 sidecar，再核对 APK 仅含 `arm64-v8a`、包名与固定签名。`SIGNING_IDENTITY_MISSING` 表示发布被阻断，不能改用普通 debug APK 或现场生成新钥匙。

## 阶段 A：建立 versionCode 2022 私有基线

1. 在保留当前 R3/R4.x 数据的前提下，原位安装 `PocketGallery-R50-baseline-v2022.apk`；不得卸载。
2. 启动 App，确认已有 Hugging Face OAuth、Gemma 4、EmbeddingGemma、聊天与知识库仍在；不要为了通过测试而清空或重建用户数据。
3. 打开“模型 / 设置 → 手机一键验收”，开始 H1–H10。
4. 到 H6 时，在真实高维到三维投影中完成单指旋转、双指缩放、点选真实点和“界面完整并继续”。保持 App 在前台至少完成 15 秒帧采样。
5. 首次结构化基线不存在时，候选资格可以如实显示 BLOCKED；在其余必要门通过且清理成功后，App 保存 versionCode `2022` 私有基线。不要导出或手工编辑该私有文件。

## 阶段 B：测量 versionCode 2023 原位升级

1. 不得卸载，直接把 `PocketGallery-R50-candidate-v2023.apk` 安装到同一 App。
2. 启动后确认无需重新 OAuth、无需重新接受许可、无需重新下载已存在模型，原知识、聊天、向量与血缘仍可用。
3. 再次运行“手机一键验收”，完成 H6 的旋转、缩放、点选、视口确认和持续帧采样。
4. 要求 H1–H10 全部 PASS，嵌套 F1–F10 全部 PASS，`PHONE_FUNCTION_LOOP = PASS`、`DEVICE_ACCEPTANCE = PASS`、`MERGE_CANDIDATE = true`。
5. 若出现热状态 SEVERE、内存压力、帧性能失败、后台中断或用户动作不完整，按界面建议处理后执行“完整重跑”；不得只重写报告。
6. 点击“导出脱敏报告”，保存 `PG_HANDSET_ACCEPTANCE_*.json`。报告不得包含 OAuth token、Authorization、原始向量、完整私有文档或未审核堆栈。

## 最终同提交裁决

在仓库 `pilot/flutter_phone_loop` 目录执行：

```bash
dart run tool/adjudicate_handset_acceptance.dart \
  --device-report /path/to/PG_HANDSET_ACCEPTANCE.json \
  --automated-evidence /path/to/PG_AUTOMATED_EVIDENCE.json \
  --apk-sha256 /path/to/PocketGallery-R50-candidate-v2023.apk.sha256 \
  --output /path/to/PG_MERGE_READINESS.json
```

退出码 `0` 表示 `MERGE_READY=true`；`2` 表示证据完整但不匹配；`64` 表示参数或输入结构不合法。必须查看 `reasons`，不得把 App 的 `MERGE_CANDIDATE` 或 CI 绿色状态单独当成最终放行。

## 立即停止条件

- 型号不匹配 `SM-S928*`；
- 任一 APK 的包名、versionCode、arm64 ABI、固定签名或 SHA-256 不符；
- Android 拒绝原位安装；
- 升级后要求重新下载已存在模型、重新 OAuth，或用户数据缺失；
- H/F 任一必要门不是 PASS，清理失败，或报告脱敏验证失败；
- 自动证据、设备报告和 sidecar 的源码提交或 APK 摘要不一致。

出现以上任一情况时保留证据并报告 BLOCKED/FAIL，不得卸载后重试来掩盖升级问题。
