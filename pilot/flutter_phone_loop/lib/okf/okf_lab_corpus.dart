import 'okf_models.dart';
import 'okf_parser.dart';

const Map<String, String> _frTestDocuments = <String, String>{
  'lines/line1-r18.md': '''
---
type: ProcessVersion
title: FR-Test 1线 R18（旧版）
description: 2026-09-01 前使用的旧版测试时间。
tags: [fr-test, line-1, timing, legacy]
status: deprecated
generated: { by: process:legacy-import, at: 2026-08-01T00:00:00Z }
stale_after: 2026-09-01T00:00:00Z
sources:
  - id: spec-r18
    resource: spec://FR-Test/SPEC-R18
    title: SPEC-R18
---
# 工位时间
A工序 = 71秒。
B工序 = 49秒。
C工序 = 83秒。

# 生命周期
R18 已被 [R19](/lines/line1-r19.md) 取代。
''',
  'lines/line1-r19.md': '''
---
type: ProcessVersion
title: FR-Test 1线 R19（当前版）
description: 2026-09-01 起生效的1线测试时间。
tags: [fr-test, line-1, timing, current]
status: stable
generated: { by: compiler/openwiki, at: 2026-09-01T00:00:00Z }
verified: { by: human:lab-expert, at: 2026-09-01T01:00:00Z }
stale_after: 2027-09-01T00:00:00Z
sources:
  - id: spec-r19
    resource: spec://FR-Test/SPEC-R19
    title: SPEC-R19
    author: human:lab-expert
---
# 生效范围
SPEC-R19 自 2026-09-01 起取代 SPEC-R18，适用于 FR-Test 1线。

# 工位时间
A工序 = 71秒。
B工序 = 49秒。
C工序 = 76秒。

# 关联
车型路线见 [X7](/vehicles/x7.md)。瓶颈判断见 [瓶颈规则](/rules/bottleneck.md)。
''',
  'vehicles/x7.md': '''
---
type: Route
title: X7 检测路线
description: X7 在 FR-Test 1线的实际过站路线。
tags: [x7, fr-test, route]
status: stable
generated: { by: process:mes-export, at: 2026-09-01T00:10:00Z }
verified: { by: human:route-owner, at: 2026-09-01T01:10:00Z }
sources:
  - id: route-x7-r7
    resource: mes://FR-Test/routes/X7/R7
    title: X7 Route R7
---
# 路线
X7 必须经过 A工序，然后经过 C工序。
X7 不经过 B工序。

# 关联
当前1线时间采用 [R19](/lines/line1-r19.md)。
瓶颈判断采用 [最大节拍规则](/rules/bottleneck.md)。
''',
  'rules/bottleneck.md': '''
---
type: Playbook
title: FR-Test 瓶颈判断规则
description: 对给定车型实际经过的工序，取测试时间最大的工序作为瓶颈。
tags: [fr-test, capacity, bottleneck]
status: stable
generated: { by: human:industrial-engineer, at: 2026-08-20T00:00:00Z }
verified: { by: human:industrial-engineer, at: 2026-08-20T00:30:00Z }
sources:
  - id: rule-bottleneck-v1
    resource: rule://FR-Test/BOTTLENECK-V1
    title: Bottleneck Rule V1
---
# 定义
先按车型路线确定实际经过的工序。
只比较这些工序的测试时间。
测试时间最大的实际经过工序就是瓶颈。

# X7
X7 的路线来自 [X7 Route](/vehicles/x7.md)，1线当前时间来自 [R19](/lines/line1-r19.md)。
''',
};

OkfBundle buildFrTestOkfBundle() =>
    const OkfParser().parseBundle(_frTestDocuments);

List<OkfOrdinaryChunk> buildFrTestOrdinaryChunks() => const <OkfOrdinaryChunk>[
      OkfOrdinaryChunk(
        id: 'raw-line1-r18',
        documentId: 'raw-line1-history',
        sourceName: 'line1-history.txt',
        text: '旧记录：FR-Test 1线 A工序71秒，B工序49秒，C工序83秒。来源 SPEC-R18。',
      ),
      OkfOrdinaryChunk(
        id: 'raw-line1-r19',
        documentId: 'raw-line1-history',
        sourceName: 'line1-history.txt',
        text: '新记录：2026-09-01 起 FR-Test 1线 A工序71秒，B工序49秒，C工序76秒。来源 SPEC-R19。',
      ),
      OkfOrdinaryChunk(
        id: 'raw-x7',
        documentId: 'raw-routes',
        sourceName: 'routes.txt',
        text: 'X7 路线：A工序 -> C工序，不经过B工序。',
      ),
      OkfOrdinaryChunk(
        id: 'raw-bottleneck',
        documentId: 'raw-rules',
        sourceName: 'rules.txt',
        text: '瓶颈规则：只比较车型实际经过工序，测试时间最大的工序为瓶颈。',
      ),
    ];

const List<OkfBenchmarkCase> frTestBenchmarkCases = <OkfBenchmarkCase>[
  OkfBenchmarkCase(
    id: 'single-fact-route',
    question: 'X7是否经过B工序？',
    expectedAnswerFragments: <String>['不经过', 'B工序'],
    expectedSourceIds: <String>['route-x7-r7'],
    note: '单事实：验证专有路线知识。',
  ),
  OkfBenchmarkCase(
    id: 'multi-hop-bottleneck',
    question: 'X7在1线的瓶颈是什么？',
    expectedAnswerFragments: <String>['C工序'],
    expectedSourceIds: <String>['route-x7-r7', 'spec-r19', 'rule-bottleneck-v1'],
    note: '多跳：路线 + 当前工位时间 + 瓶颈规则。',
  ),
  OkfBenchmarkCase(
    id: 'version-conflict',
    question: '2026年9月5日，1线C工序应使用多少秒？',
    expectedAnswerFragments: <String>['76', '秒'],
    expectedSourceIds: <String>['spec-r19'],
    note: '版本冲突：R18=83秒已废止，R19=76秒为当前版。',
  ),
  OkfBenchmarkCase(
    id: 'source-grounding',
    question: '1线C工序的76秒来自哪个规范？',
    expectedAnswerFragments: <String>['SPEC-R19'],
    expectedSourceIds: <String>['spec-r19'],
    note: '证据：要求回答可回溯到规范来源。',
  ),
];
