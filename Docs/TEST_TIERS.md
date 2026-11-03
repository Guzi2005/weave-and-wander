# 《针脚与远方》 (`Weave&Wander`) 自动化回归测试分级守则 (`TEST_TIERS.md`)

为守护项目现有的高价值自动化测试资产，同时保证日常开发迭代速度，所有无头测试脚本按职责与耗时分为三级（Tier 1 / Tier 2 / Tier 3），通过 [`tools/run_tiered_tests.ps1`](../tools/run_tiered_tests.ps1) 统一执行。

---

## 一、 三级测试划分

### Tier 1：秒级契约与几何/动态池化测试（每次修改必跑，< 15 秒）
聚焦独立组件的数据契约、网格拓扑不变量、Toolkit 骨骼/物理对齐以及 24 档网格池化：
- `tests/pleated_skirt_test.gd`：验证百褶裙 JSON/PNG 契约、24×8 拓扑闭合性、Toolkit 四种廓形 + 五种下摆形状、经向等弧长投影（`DrapeConstraint`）、120Hz 旋转离心惯性（`SkirtInertia`）及 `VolumeDoll` 穿戴六态（`stand`/`walk`/`sit`/`lie`/`display`/`spin`）。
- `tests/wrapped_fabric_test.gd`：验证书本式缠布 `ArrayMesh` 连续圆角脊、两端连续阿基米德螺旋与 24 档厚度缓存池。
- `tests/material_package_test.gd`：验证 5 种包装形态（`book`/`roll`/`spool`/`ribbon`/`yarn`）与台账只读不变性。
- `tests/parametric_flower_test.gd`：验证参数化胸花/头花的确定性几何与法线闭合性。
- `tests/parametric_adornments_test.gd`：验证米珠花环与参数化饰品的切向排列与无穿模契约。

### Tier 2：工坊仿真工序状态机与角色交互测试（工坊/AI 逻辑改动必跑）
聚焦「乐高砖 + 薄胶水」低耦合模块、统一工位协议（`WorkStationSequence`）、工坊 ASMR 音频与多工位流转：
- `tests/workshop_architecture_and_audio_test.gd`：验证 `WorkStationSequence` 单次扣料幂等保护、`BusinessSession`/`WorkDispatcher` 解耦、`ThreadSpool` 动态缩放、7 种程序化 ASMR 工坊音效合成及工位微距/标本明信片拍摄。
- `tests/material_handling_test.gd`：验证取布、裁剪、缝制、中断泊车（`park`/`recover`）与归库的完整物理搬运闭环。
- `tests/dye_flow_test.gd`：验证整匹染色、定制色卡染色、染缸锁与归库。
- `tests/loom_production_test.gd`：验证织布机梭口、踏板、经纬推进与布匹下机。
- `tests/inventory_flow_test.gd`：验证前店陈列、试衣间、收银台与补货闭环。

### Tier 3：全场景渲染、外层工作台 LOD 与视觉回归（里程碑/发布前跑）
- `tests/workbench_test.gd`：验证外层真实工作台材质、昼夜光照、阴影掩码与距离/焦点 LOD。
- `tests/street_glass_capture.gd`：验证街景橱窗玻璃反射视口分帧轮询与截图输出。

---

## 二、 运行方式

```powershell
# 运行 Tier 1（秒级契约）
powershell -ExecutionPolicy Bypass -File tools/run_tiered_tests.ps1 -Tier Tier1

# 运行 Tier 2（工坊仿真与架构解耦）
powershell -ExecutionPolicy Bypass -File tools/run_tiered_tests.ps1 -Tier Tier2

# 运行 Tier 3（全场景与工作台/玻璃反射）
powershell -ExecutionPolicy Bypass -File tools/run_tiered_tests.ps1 -Tier Tier3
```
