# PocketGallery 可旋转三维向量空间设计

- 状态：**用户确认，可进入实现**
- 日期：2026-09-01
- 基线：`codex/r46-full-microscope@59891a8667caf2e012e1030c5a301a941d01bd73`
- 产品范围：Android 手机端 Flutter Phone Pilot
- 用户确认方向：保留“答案 + 证据”双层信息架构，将现有二维/斜投影关系图升级为真实高维向量到三维空间的投影，并支持手机旋转查看。

## 1. 问题

当前 `VectorSpacePage` 和旧版 `VectorMicroscopePage` 虽然已经计算 PC1、PC2、PC3，但所谓“3D”画法只是把 `z` 以固定比例叠加到屏幕 `x/y`：

```text
screenX = x + z * constant
screenY = y - z * constant
```

它没有相机、旋转、透视、深度排序或点选联动，因此用户看到的只是固定斜投影，不能从不同方向检查高维关系。散点也缺少原文、来源、入选原因等人类可读信息。

## 2. 目标

本轮 SHALL：

1. 使用真实持久化 Embedding 作为 PCA 输入；Trace 页面不得重新调用 Embedding。
2. 将高维向量确定性降维到 PC1、PC2、PC3，并明确标记为 `DERIVED`。
3. 在手机上支持单指旋转、双指缩放、点按散点和重置视角。
4. 使用透视相机和深度排序真实呈现三维坐标，不再使用固定 `z` 偏移伪装 3D。
5. 区分 Query、已选 Evidence、检索候选和邻域语料；同时使用颜色、形状、尺寸，不能只靠颜色。
6. 点按后展示来源名、定位信息、切片原文、召回通道、排名/余弦以及入选或拒绝原因。
7. 显示原始维度、PC1/PC2/PC3 实际解释方差、采样覆盖和有效主成分数量。
8. 对有效主成分少于 3、空数据、非有限坐标等情况如实降级，不制造三维结构。
9. 在 360 px 宽手机上无横向溢出；旋转期间不持续触发 PCA 或数据库读取。
10. 旧版向量显微镜和 Trace 向量空间共用同一三维交互组件，消除两套不一致的“3D”。

## 3. 非目标

本轮 SHALL NOT：

- 引入 UMAP 或 t-SNE 占位坐标。
- 把 PCA 空间距离称作语义真相或真实检索排序。
- 为了渲染再次计算 Embedding。
- 引入通用游戏/模型渲染引擎、OpenGL 包装层或网络资源。
- 在拖动手势之外运行持续动画。
- 改变 ACTIVE 检索、Evidence 选择或答案生成逻辑。
- 自动合并到 `main`。

## 4. 数据真实性

### 4.1 Trace 页面

`TraceVectorSpaceService` 的输入顺序保持：

1. 本轮 ACTIVE 候选；
2. 本轮 SHADOW 候选；
3. 按文档分层、确定性补齐的持久化 body vectors；
4. 本轮持久化 Query vector。

所有向量必须与 Query 的 `dimension` 和 `modelIdentity` 一致。页面只读取 `TraceSnapshot.queryEmbedding` 与 `LineageStore` 已保存向量，`usedCapturedQuery` 必须为 `true`。

手机默认最多采样 128 个语料向量；Query 作为额外参照点。PCA 只在页面 Future 首次构建时执行一次，旋转仅处理三个坐标。

### 4.2 旧版即时显微镜

旧版 `VectorMicroscopePage` 仍属于即时观测路径，其 Query vector 由该页面的现有观测服务生成，因此 UI 必须继续说明它不是历史 Trace 的精确查询向量。它可以复用三维交互组件，但不得冒充 Trace 捕获事实。

### 4.3 有效维度

PCA 输出保留三个坐标槽位，但 `effectiveComponentCount` 只统计解释方差大于 `1e-9` 的主成分。少于三维时：

- 显示“有效主成分 N/3”；
- 明确提示数据只支撑 N 维结构；
- 不把零方差轴描述为有效关系。

## 5. 三维投影与相机

新增纯 Dart 投影层：

```dart
enum VectorPlotKind { query, evidence, candidate, context }

class VectorPlotPoint {
  const VectorPlotPoint({
    required this.id,
    required this.x,
    required this.y,
    required this.z,
    required this.kind,
    this.label,
  });
}

class VectorCamera {
  const VectorCamera({
    this.yaw = -0.58,
    this.pitch = 0.34,
    this.zoom = 1,
  });
}

class VectorProjection3d {
  const VectorProjection3d();

  VectorProjectionFrame project({
    required List<VectorPlotPoint> points,
    required Size size,
    required VectorCamera camera,
  });
}
```

投影过程：

1. 以 PCA 原点为中心，使用最大三维半径归一化；退化半径按 1 处理。
2. 依次应用 yaw（绕 Y 轴）与 pitch（绕 X 轴）。
3. 使用固定相机距离的透视缩放，避免近点无界放大。
4. 根据相机空间 `z` 深度排序，远点先画、近点后画。
5. 根据当前相机同步投影 PC1、PC2、PC3 坐标轴。
6. 忽略或安全归零非有限坐标，任何情况下不得向 Canvas 传入 NaN/Infinity。

相机约束：

- `pitch`：`[-1.25, 1.25]` 弧度；
- `zoom`：`[0.62, 2.20]`；
- yaw 可连续旋转；
- 默认视角与确认效果图一致；
- 重置恢复默认视角。

## 6. 手机交互

统一组件：

```dart
class InteractiveVectorPlot extends StatefulWidget {
  const InteractiveVectorPlot({
    super.key,
    required this.points,
    required this.explainedVarianceRatios,
    this.initialSelectedId,
    this.onPointSelected,
  });
}
```

行为：

- 单指拖动：更新 yaw/pitch。
- 双指：以手势开始时的 zoom 为基准缩放。
- 点按：在屏幕坐标 22 dp 半径内选择最接近且视觉上最靠前的点。
- 重置按钮：恢复默认相机，不改变已选数据点。
- 旋转/缩放只调用 `setState` 与三维投影；不调用存储、PCA 或 Embedding。
- Canvas 具备可读语义说明：“单指旋转、双指缩放、点按查看证据”。

## 7. 视觉编码

| 对象 | 颜色角色 | 形状/尺寸 | 文本标签 |
|---|---|---|---|
| Query | error/accent | 菱形、最大 | Query |
| 已选 Evidence | tertiary/green | 大圆点 + 外环 | Evidence |
| 检索候选 | primary/blue | 中圆点 | 点选时显示 |
| 邻域语料 | outline/gray | 小圆点、较低透明度 | 点选时显示 |

坐标轴分别显示 `PC1`、`PC2`、`PC3` 和对应实际解释方差。深色/浅色主题均从 `ColorScheme` 取色，禁止硬编码只适配单一主题的背景。

## 8. 人类可读详情

`TraceVectorPoint` 增加：

- `text`
- `candidateId`
- `sourceChannels`
- `selectedForEvidence`
- `selectionReason`
- `dropReason`
- `ftsRank`
- `vectorRank`
- `finalRank`

点选详情卡优先显示：

1. 来源名 + locator；
2. 完整可选择的切片原文；
3. “为何入选”或“为何未入选”的中文说明；
4. REAL cosine 与捕获排名；
5. 技术 ID 放在折叠的“开发者详情”中。

Query 点显示本轮查询文本与“本轮持久化 Query vector”说明，不伪造 chunk 来源。

## 9. 性能与稳定性

- Trace 页最多 129 个绘制点（128 语料 + Query）。
- PCA 不在 `paint()` 或手势回调中执行。
- 绘制复杂度为 O(n log n)，排序上限固定。
- 不添加第三方 3D 依赖；使用 Flutter Canvas 和纯 Dart 三角函数。
- `CustomPainter.shouldRepaint` 比较 points、camera、selection、theme colors。
- 页面销毁后不保留动画控制器或监听器。

## 10. 验收

自动化必须证明：

1. yaw/pitch 改变实际三维投影，不能退化回固定 z 偏移。
2. 透视与深度排序稳定、退化数据不产生非有限坐标。
3. 单指拖动、双指缩放、点按与重置均改变预期状态。
4. 360×800 无 Flutter overflow exception。
5. Trace 点携带真实原文、通道、Evidence/拒绝原因和排名。
6. 页面显示 `原始维度D → 3D PCA`、解释方差、采样覆盖和降级提示。
7. 两个向量页面均不再调用固定斜投影 painter。
8. 全量 Flutter 分析与回归通过，Android arm64 debug APK 构建通过。
