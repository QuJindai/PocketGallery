# PocketGallery 2.0 — A 路线设计规格

- 日期：2026-08-21
- 状态：Approved
- 路线：Google AI Edge Gallery 上游 + PocketGallery 下游知识增强发行版
- 目标仓库：`QuJindai/PocketGallery`（Public）
- Android 目标：Android 12+，首轮以 arm64-v8a 真机为主
- 首要目标：稳定产出可安装 APK，而不是先堆功能

## 1. 项目目标

PocketGallery 2.0 是一个以 Google AI Edge Gallery / LiteRT-LM 为推理底座、以本地知识库为核心增量的 Android 端侧知识助手。

核心原则：

1. **最大化复用 Google 上游**：模型管理、LiteRT-LM、会话、流式推理、Agent/Tool 基础能力尽量不自行重写。
2. **PocketGallery 的价值集中在 Knowledge Layer**：文档导入、解析、索引、检索、RAG、Evidence、Markdown 导出。
3. **模型与知识均可离线运行**：联网只作为模型/Skill 下载等可选能力；已导入的模型、资料和索引在断网状态可使用。
4. **持续跟随上游**：不做一次性源码拷贝；保留明确 upstream 基线和同步策略。
5. **APK 优先**：每个阶段都必须能编译、测试并通过 GitHub Actions 产出 APK artifact。
6. **公开仓安全边界**：公开仓只允许代码、合成测试资料、文档和 CI；真实业务资料、模型权重、token、签名密钥不得提交。

## 2. 上游基线

首个设计基线锁定 Google AI Edge Gallery 当前 `main` 的提交：

`ec7fee19e3b7aad9991105e549d544233ea0b97f`

理由：

- 上游仍高频演进；2026-08-20 刚引入新的 `LlmSessionManager` 会话编排层。
- `LlmSessionManager` 已经把 session lifecycle、history persistence、model config、inference、tools 等抽象在接口中，适合作为 PocketGallery 的 LLM Adapter 接入点。
- Gallery 已经存在 Agent Skills、模型管理、自定义模型加载等能力，无需重复造轮子。

后续仓库中维护：

- `UPSTREAM.md`：记录上游仓库、基线 commit、同步日期、已知冲突。
- `upstream-sync/*` 分支：仅用于跟踪 Google 上游更新。
- PocketGallery 自有功能尽量集中在独立 package/module，降低 rebase/merge 冲突。

## 3. 总体架构

```text
Google AI Edge Gallery upstream
          │
          ▼
┌─────────────────────────────┐
│ PocketGallery Android App   │
├─────────────────────────────┤
│ Google Runtime Layer        │
│ - LiteRT-LM                 │
│ - Model Manager             │
│ - LlmSessionManager         │
│ - Agent / Tool infrastructure│
├─────────────────────────────┤
│ PocketGallery Adapter Layer │
│ - LlmProvider               │
│ - ModelBridge               │
│ - SessionBridge             │
├─────────────────────────────┤
│ Knowledge Layer             │
│ - DocumentImporter          │
│ - Parser                    │
│ - Chunker                   │
│ - SHA-256 / dedupe          │
│ - Room / SQLite             │
│ - FTS5                      │
│ - Retriever                 │
│ - Evidence                  │
├─────────────────────────────┤
│ RAG Layer                   │
│ - QueryRouter               │
│ - Retrieval                 │
│ - ContextBuilder            │
│ - AnswerComposer            │
│ - Citation resolver         │
├─────────────────────────────┤
│ UI                          │
│ - 我的资料                  │
│ - 搜索                      │
│ - 提问                      │
│ - 来源/Evidence             │
│ - 模型                      │
│ - Markdown 导出             │
└─────────────────────────────┘
```

## 4. 代码边界

PocketGallery 新增代码默认放入独立命名空间，避免大面积修改 Gallery 原代码：

```text
Android/src/app/src/main/java/
  .../pocketgallery/
    runtime/
    knowledge/
      intake/
      parser/
      chunk/
      db/
      search/
      evidence/
    rag/
    export/
    ui/
```

首版不强行修改 Gallery 的所有 package 名；先减少上游冲突。等功能稳定后，再评估品牌/package 重构。

关键适配接口：

```kotlin
interface LlmProvider {
    suspend fun createSession(...): String
    suspend fun generate(...)
    fun stop(...)
}
```

实际实现由 Gallery `LlmSessionManager` 适配。Knowledge/RAG 层只依赖 `LlmProvider`，不直接依赖 LiteRT-LM 内部实现。

## 5. 知识库数据流

```text
Android SAF URI
  ↓
MIME + metadata
  ↓
SHA-256
  ↓
去重 / 版本判断
  ↓
Parser
  ↓
Normalized Document
  ↓
Chunker
  ↓
Room / SQLite
  ↓
FTS5 index
  ↓
Retriever
  ↓
Evidence Pack
  ↓
LlmProvider / Gemma
  ↓
Answer + Source citation
```

### 5.1 首版文件类型

P0：TXT、Markdown、PDF。

P1：DOCX、XLSX、PPTX。

先确保解析、索引、Evidence 闭环稳定，再扩大 Office 格式，避免解析依赖拖慢第一个 APK。

### 5.2 文档实体

至少包含：`document_id`、`uri`、`display_name`、`mime_type`、`sha256`、`size_bytes`、`imported_at`、`modified_at`、`parse_status`、`parse_error`。

### 5.3 Chunk 实体

至少包含：`chunk_id`、`document_id`、`ordinal`、`page_or_section`、`text`、`char_start`、`char_end`、`token_estimate`。

## 6. 全文检索实现

第一版采用 **Room 3 + BundledSQLiteDriver + FTS5**。

设计原因：

- Android 官方当前 Room 3 已提供 `@Fts5`。
- FTS5 的可用性依赖数据库 driver；使用 `BundledSQLiteDriver` 可以避免依赖不同厂商 Android 系统 SQLite 编译选项。
- 第一版先保证关键词/精确检索、Evidence 回溯和数据库稳定性。

中文首版先使用可验证的 tokenizer 策略和 query normalization；如果 FTS5 对连续中文分词召回不足，则第二阶段加入 trigram / n-gram 路径或 EmbeddingGemma 语义检索，不让中文分词问题阻塞 P0 APK。

## 7. Embedding 设计

EmbeddingGemma 不作为第一个 APK 的硬依赖，而作为 P1 增强。

P0：

```text
Query → FTS5 → Top-K → Evidence → Gemma
```

P1：

```text
                ┌─ FTS5/BM25
Query → Router ─┤
                └─ EmbeddingGemma
                     ↓
                Vector Top-K
                     ↓
                Hybrid Fusion
                     ↓
                  Evidence
```

Embedding 层必须定义独立接口：

```kotlin
interface EmbeddingProvider {
    suspend fun embedQuery(text: String): FloatArray
    suspend fun embedDocuments(texts: List<String>): List<FloatArray>
}
```

## 8. RAG 与 Evidence 规则

PocketGallery 的回答默认遵循“证据优先”：

1. 对知识库问题先检索。
2. 检索结果构造成结构化 Evidence Pack。
3. Prompt 明确要求优先使用 Evidence；没有证据时必须说明未在本地资料中找到。
4. 每个 Evidence 保留：文档、页码/段落、chunk id、原文片段。
5. 回答中的来源卡片可点击进入原文位置或对应 chunk。

首版不做复杂 Agentic RAG，不做自循环检索，不做模型自动修改知识库。

## 9. Agent Skills 的定位

Gallery Agent Skills 保留，但 PocketGallery 知识库核心能力**不首先依赖 JS Skill/WebView**。

理由：本地数据库访问、SAF URI、Room、文件解析属于 Android 原生能力；Native Knowledge Tool 更容易做权限、性能、错误处理和测试。后续可以再为 Agent 暴露 `search_local_knowledge` Tool。

演进顺序：

1. 普通 RAG 明确调用 Retriever。
2. Retriever 稳定后封装成 Native ToolProvider。
3. 再接 Agent Skills / Agent Chat 自动工具调用。

## 10. UI 最小闭环

P0 只增加必要页面：

### 我的资料

导入文档、文件列表、解析状态、chunk 数、删除、重建索引。

### 搜索

查询框、Top-K 结果、文档名、页码/章节、命中原文。

### 知识问答

用户问题、召回 Evidence、Gemma 流式回答、来源卡片。

### 模型

优先复用 Gallery 模型管理能力，不重复实现完整 Model Manager。

### 导出

当前回答导出 Markdown，回答 + 引用来源一并导出。

## 11. 本地与网络边界

### Offline Ready

模型、资料已导入后，搜索、Embedding、RAG、Gemma 推理、文档解析、Markdown 导出均离线完成。

### Optional Online

只用于 Hugging Face / Google 支持的模型下载、Agent Skill URL 导入、上游模型目录更新。真实知识库内容不得因为模型下载或在线 Skill 自动上传。

## 12. GitHub 仓库结构

```text
PocketGallery/
├── Android/
├── docs/
│   ├── superpowers/specs/
│   ├── architecture/
│   ├── research/
│   └── test/
├── scripts/
│   ├── build/
│   ├── verify/
│   └── package/
├── testdata/
│   └── synthetic/
├── .github/workflows/
├── UPSTREAM.md
├── SECURITY.md
├── LICENSE
├── NOTICE
└── README.md
```

公开仓许可证采用 Apache-2.0，并保留 Google 上游版权/NOTICE；Gemma、EmbeddingGemma 等模型权重遵循各自模型条款，模型文件不提交进仓库。

## 13. 分支与上游同步

- `main`：可编译、可安装、CI 通过。
- `develop`：阶段集成。
- `feature/*`：单功能开发。
- `upstream-sync/*`：Google 上游同步验证。

每次上游同步必须输出基线 old/new commit、变更摘要、Runtime/API 影响、冲突文件、APK build 结果、S24/S24U 实机回归结果。

## 14. CI / APK 产线

P0 GitHub Actions 必须至少完成：checkout → JDK / Android SDK → Gradle dependency validation → unit tests → lint → assembleDebug → APK artifact upload。

后续增加 emulator smoke test、database migration test、parser fixture test、retrieval golden test、release APK/AAB。

CI 不下载需要用户接受额外许可的大模型作为普通测试依赖；Runtime 单元测试使用 mock/fake provider，真模型由真机测试阶段完成。

## 15. 首轮验收标准 P0

P0 必须同时满足：

1. GitHub Actions 绿色。
2. APK artifact 可下载并安装。
3. App 正常启动，无 fatal crash。
4. 可导入本地 `.litertlm` 模型或使用 Gallery 当前支持的模型加载链路。
5. 模型 Runtime 初始化成功。
6. 本地文本问答正常流式输出。
7. TXT/MD/PDF 可导入。
8. SHA-256 去重工作。
9. 文档解析后可见 chunk 数量。
10. FTS5 查询可返回命中文档和原文。
11. Knowledge Q&A 能把 Top-K Evidence 注入 Gemma。
12. 回答能显示来源。
13. Markdown 能导出。
14. 关闭网络后，已导入模型和资料仍能完成 7–13。

## 16. P0 明确不做

全量 Office 格式、EmbeddingGemma、向量数据库复杂优化、Agent 自动工具选择、MCP、云同步、多设备知识同步、OCR、知识自动写回、模型微调、多用户、大规模 UI 重构全部延后。

## 17. 主要风险与控制

- **上游持续快速变化**：独立 Knowledge Layer + Adapter + 固定 upstream commit + 定期 sync report。
- **Gallery 本地开发需要 Hugging Face OAuth 配置**：CI 与运行时拆分；不提交 client secret/token；模型下载与本地模型导入分别测试。
- **中文 FTS 召回不够**：P0 先实现稳定 FTS；P1 加 EmbeddingGemma Hybrid Search。
- **真模型 CI 成本高/许可复杂**：CI 用 fake provider + 小型 fixture；真正 LiteRT-LM/Gemma 验证放到真机测试资产中。
- **Fork 过深导致无法跟上游**：优先新增 package/module；任何修改 Gallery 原文件的 PR 都必须解释为何不能通过 Adapter/extension 实现。

## 18. 实施进入条件

1. 用户确认本设计规格。
2. `QuJindai/PocketGallery` Public 仓库存在且 GitHub Connector 可访问。
3. 首个提交记录 Google upstream 基线和 Apache-2.0 NOTICE。

以上条件已于 2026-08-21 满足，进入 Implementation Plan。
