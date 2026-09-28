# PocketGallery R4 Chat-first 设计

## 1. 目标

R4 将 PocketGallery 从“RAG 功能验证器”升级为可日常使用的本机 AI 助手。首要能力是直接与本机 Gemma 4 进行连续多轮聊天，并在需要时外挂本地知识库。

R4 必须继续复用 R3 已建立的 Android 身份、固定签名、模型目录、OAuth 凭据、本地 FTS5/Embedding 索引和已导入文档。升级过程中不得要求卸载 App，不得因为升级重新下载已经存在的 Gemma 4 或 EmbeddingGemma。

## 2. 用户体验

主界面采用底部三页结构：

1. `聊天`
2. `知识库`
3. `模型 / 设置`

App 启动后默认进入“聊天”，不再先展示模型准备、Golden Test 和 Pilot 状态。

### 2.1 聊天页

聊天页提供正常的多轮对话界面：用户消息、模型消息、输入框、新建会话、清空当前会话、会话历史入口。

每个会话保存独立上下文，并提供三种知识库模式：

- `纯模型`：不做任何本地检索，直接由 Gemma 4 基于会话历史回答。
- `自动`：默认模式。先执行低成本本地检索；只有达到相关性门槛时才注入 Evidence，否则按纯模型聊天处理。
- `强制知识库`：必须基于本地资料回答。若没有足够 Evidence，应明确说明本地资料不足，不允许退化为无依据回答。

聊天页可选择知识库范围：

- 全部知识库；
- 指定文档；
- 指定集合。

R4 首版至少实现“全部知识库”和“指定文档”，集合能力的数据结构同时预留，但可以在后续小版本开放完整集合 UI。

当回答使用本地资料时，正文显示 `[E1] [E2]` 等引用；点击引用可展开来源文件、页码/locator、chunk 文本。纯模型回答不显示伪引用。

### 2.2 知识库页

知识库页负责文档资产管理，不承担聊天 UI：

- 导入 TXT / MD / PDF；
- 显示文档名、chunk 数量；
- 显示 FTS5 状态；
- 显示 Embedding 状态；
- 标识 0 chunks / 扫描件 PDF；
- 删除文档；
- 对单文档或全部文档重建 Embedding 索引；
- 选择文档作为聊天检索范围。

已有 R3 数据不得迁移丢失。

### 2.3 模型 / 设置页

R3 当前首页中的模型准备、Hugging Face OAuth、模型状态、存储信息、诊断功能迁入此页。

普通用户只看到：

- Gemma 4：READY / 下载中 / 未安装；
- EmbeddingGemma：READY / 授权中 / 下载中 / 未安装；
- 模型占用空间；
- 自动准备 / 授权状态。

Golden Test、FTS5/Embedding 诊断、索引重建和详细运行信息放在“高级 / 诊断”区域。

## 3. 核心架构

R4 在现有 `GemmaService` 与 `KnowledgeEngine` 之上新增一个明确的聊天编排层，避免 UI 直接拼装 RAG 流程。

新增核心组件：

### 3.1 `ChatSessionStore`

本地 SQLite 持久化：

- `chat_sessions`
  - session_id
  - title
  - mode
  - knowledge_scope
  - created_at
  - updated_at
- `chat_messages`
  - message_id
  - session_id
  - role
  - text
  - created_at
  - retrieval_mode
  - evidence_json
  - cited_anchors_json

会话数据全部本地保存，不依赖网络。

### 3.2 `ChatOrchestrator`

这是 R4 的主业务入口。UI 只调用它，不直接操作 `GemmaService` / `KnowledgeEngine`。

每次用户发送消息时流程如下：

1. 保存用户消息；
2. 根据当前 ChatMode 决定是否检索；
3. 若检索，按当前 knowledge scope 执行 FTS5 + Embedding + Hybrid/Rerank；
4. 自动模式根据融合结果与相关性门槛决定是否采用 Evidence；
5. 组织系统指令、近期会话历史和本轮 Evidence；
6. 调用 Gemma 4；
7. 若本轮使用 Evidence，解析并校验引用；
8. 保存模型回答、Evidence 和引用；
9. 返回 UI 展示。

### 3.3 `GemmaChatService`

现有 `GemmaService.answer()` 目前每次都创建新 chat，R4 将其拆为真正的会话式模型服务。

职责：

- 维护当前活跃会话的 FlutterGemma chat；
- 多轮追加用户/助手消息；
- App 重启或切换会话时从 SQLite 恢复最近上下文；
- 控制上下文预算；
- 不负责知识检索。

R4 不把整个无限聊天历史塞入 8192 token 上下文。采用固定预算：保留 system instruction、最近若干轮消息、本轮 Evidence 和输出空间；超出预算时优先淘汰最旧轮次。R4 首版不额外调用模型做历史摘要，以避免增加推理负担和复杂度。

### 3.4 `KnowledgeRetriever`

从现有 `KnowledgeEngine.ask()` 中拆出“检索”与“生成”两部分。

`KnowledgeRetriever.retrieve(query, scope)` 只负责：

- FTS5；
- Embedding；
- Hybrid/Rerank；
- Evidence Pack；
- 文档范围过滤。

这样聊天编排器可以在纯模型、自动和强制知识库三种模式之间清晰切换。

## 4. 三种聊天模式的精确定义

### 4.1 纯模型

- 不触发 FTS5；
- 不触发 Embedding；
- 不读取本地文档；
- 保留多轮上下文；
- 不生成 `[E#]` 引用。

### 4.2 自动

默认执行本地检索，但只有 Evidence 达到门槛时才注入模型上下文。

门槛采用确定性规则，不再额外调用 Gemma 做“是否检索”分类：

- FTS5 或 Embedding 至少一条有效命中；
- Hybrid 融合后 top hit 达到最低相关性；
- 命中内容不是空 chunk；
- 命中落在当前 scope 内。

若未达到门槛，则直接按纯模型回答。

如果 EmbeddingGemma 尚未 READY，自动模式允许只用 FTS5 判断；不会因为 Embedding 未就绪阻塞普通聊天。

### 4.3 强制知识库

- 必须执行检索；
- 有 Evidence：Gemma 只能根据 Evidence 回答，并要求引用；
- 无 Evidence：直接返回“本地资料不足”，不允许纯模型补充事实；
- Embedding 不可用时允许 FTS5 降级，但 UI 必须标识当前为 lexical-only retrieval。

## 5. 文档范围检索

R4 为 FTS5 与 Semantic Store 增加一致的 scope 参数。

检索范围采用 document_id，而不是 UI 文件名。

首版范围：

- `all`；
- `documents: [document_id...]`。

FTS5 在 SQL 查询阶段限制 document_id；Semantic Store 必须在候选生成阶段或足够大的候选集合中执行 document_id 过滤，不能只在最终 top-8 后简单删掉不属于 scope 的结果，以避免目标文档命中被其他文档挤掉。

## 6. 多轮上下文与 RAG 的关系

会话历史与知识 Evidence 是两个独立输入源：

- 历史用于理解“它、这个、刚才那个”等上下文指代；
- Evidence 用于回答本地事实。

每一轮 Evidence 都是临时的，不自动继承上一轮 `[E1]` 编号。每条助手消息保存自己的 Evidence snapshot 和引用映射，因此历史消息里的引用在后续仍可查看且不会指向错误 chunk。

## 7. UI 状态

聊天页顶部只显示轻量状态：

- `Gemma READY`；
- 当前模式：纯模型 / 自动 / 强制知识库；
- 当前知识范围；
- 若正在使用本地资料，显示 `Knowledge ON`。

模型下载、OAuth 和详细状态不在聊天主区域长期占位。

当 Gemma 尚未 READY 时：

- 输入框可用但发送按钮给出“模型准备中”；
- 知识库页仍可导入和建立 FTS5；
- 不删除或阻塞已有索引。

## 8. 数据兼容与升级约束

R4 必须保持：

- Android applicationId：`com.qujindai.pocketgallery_phone_pilot.r3`；
- R3 固定签名证书；
- 现有 App Documents 模型目录；
- 现有 FTS5 / Semantic 数据库；
- 现有 Hugging Face OAuth secure storage；
- 已导入文档。

R4 只允许 additive schema migration：创建新表或新增兼容字段，不允许 drop/recreate 现有数据表。

已安装模型检测仍保持幂等：`hasActiveModel()` / `hasActiveEmbedder()` 为真时禁止重新走网络下载路径。

## 9. 错误处理

- Gemma 加载失败：保留会话和知识库，允许重试模型，不清数据；
- Embedding 失败：自动模式退到 FTS5，纯模型不受影响；
- 强制知识库无 Evidence：明确返回资料不足；
- PDF 0 chunks：知识库页标识扫描件/图片型 PDF，不假装索引成功；
- OAuth 失败：只影响 Embedding 下载，不影响纯模型聊天和 FTS5；
- App 被系统回收：聊天消息已持久化，重启后恢复；
- 模型上下文超限：淘汰最旧历史，不清空当前会话。

## 10. 测试与 Gate

R4 必须新增自动化 Gate：

1. Model-only chat 无知识库也能多轮回答；
2. 第二轮问题能读取第一轮上下文；
3. 自动模式无相关 Evidence 时退化为纯模型；
4. 自动模式有相关 Evidence 时注入 RAG；
5. 强制知识库无 Evidence 时不允许模型自由补充；
6. 强制知识库有 Evidence 时必须产生可解析 citation；
7. document scope 在 lexical 与 semantic 两路都生效；
8. 会话与消息重启后可恢复；
9. R3 已有文档和索引迁移后仍存在；
10. 已安装 Gemma / Embedding 不触发重复下载；
11. applicationId 保持 R3；
12. APK 签名指纹保持 R3 固定证书；
13. APK 仍为 arm64-v8a；
14. 原 Phone Golden Test 迁入高级诊断后仍可执行。

## 11. R4 首版完成标准

R4 只有同时满足以下条件才算完成：

- App 打开默认进入聊天页；
- 可以直接和 Gemma 4 连续多轮聊天；
- 可以在同一个聊天框切换纯模型 / 自动 / 强制知识库；
- 自动模式可在普通聊天和本地 RAG 之间自动切换；
- 可以选择全部知识库或指定文档；
- RAG 回答显示可点击引用；
- 知识库和模型管理从聊天首页分离；
- 升级不丢模型、不丢文档、不丢索引、不丢 OAuth；
- CI、arm64、固定签名、SHA256 全部通过。

R4 的定位是“可日常使用的本机 Chat + Local Knowledge Assistant”，不再以 Pilot 验证页面作为主交互。