# PocketGallery Phone Pilot R1 · Drop-in

目标仓库：`QuJindai/PocketGallery`

把本包内容直接合并到仓库根目录，不覆盖原生 `overlay/Android`。

新增：
- `pilot/flutter_phone_loop/`：独立手机功能闭环 Pilot
- `.github/workflows/pocketgallery-phone-pilot-apk.yml`：Pilot APK CI

原有 PocketGallery P0A/native upstream/materialize/overlay 流程不修改。

Push 后 GitHub Actions 产物：
`PocketGallery-Phone-Pilot-debug-apk`

Pilot 验证通过后，再把已验证的 Chunk / FTS5 / Embedding / Hybrid / Evidence / Citation
结构回填原生 PocketGallery Knowledge Layer。
