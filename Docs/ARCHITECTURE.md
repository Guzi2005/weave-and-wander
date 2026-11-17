# 模拟经营架构（针脚与远方）

> 版本：3.0 · 最后更新：2026-06-27  
> **参考（同一套方法论 · 中英两版）**  
> - [【搬运】最好的独立游戏代码架构](https://www.bilibili.com/video/BV1VjvNz6EMJ)（Jonas Tyroller · [YouTube 原片](https://youtu.be/8WqYQ1OwxJ4)）  
> - [告别屎山代码！模块化 / 可复用 / 高效](https://www.bilibili.com/video/BV1soRCBvEWX)（Jonas 架构 · 中文解读，强调模块化与可维护性）

---

## 一、为什么要先架构、后拼装

实验结论：**在店铺视觉与玩法感觉没定之前，用形状占位把循环拼起来 → 既不像你的游戏，也难迭代。**

对**美术出身**的制作者，更合理的路径是：

```
定视觉场景（View 稿） → 定 Game Database（JSON） → 写 Simulation 模块 → 胶水连接 → 把场景挂上去
```

不是：先写 Manager → 用 ColorRect 冒充美术 → 希望之后能替换。

Jonas 的第一句实话：**大多数独游底层都是面条代码，能跑就行。** 架构不是为了炫技，是为了你这种「要迭代很多版视觉 + 数值」的项目**少返工**。

---

## 二、Jonas 五件套（本项目的准绳）

| # | 原则 | 本项目落地 |
|---|------|-----------|
| 1 | **避免面条代码** | 一个脚本不要又管 UI 又管数值又管存档 |
| 2 | **可重用系统 + 胶水** | 时间、经济、生产、订单 = 独立模块；场景脚本只做连接 |
| 3 | **Game Database** | `Resources/Data/*.json` + pm_board 编辑，逻辑只读 ID |
| 4 | **单一时间源** | 一个 Clock + **一条 tick 管道**（`GameSession.tick_simulation`） |
| 5 | **Simulation ↔ View 分离** | **模拟不知道 Sprite 长什么样；View 把 Simulation 当实时数据库读** |

---

## 三、模块化比例：乐高砖 vs 胶水（70 / 30）

Jonas 的经验比例（做得好的话）：

| 类型 | 约占比 | 特征 | 本项目目录 |
|------|--------|------|-----------|
| **可重用模块** | ~70% | 可跨场景、甚至跨项目复用；模块内可乱，但**不伸出模块外** | `Scripts/Simulation/`、`Scripts/Database/`、`Scripts/View/` |
| **胶水** | ~30% | **明知不会复用**，只负责连接；要短、要专 | `Scripts/Glue/`、`Scripts/Services/` |

**关键区分 — 什么不是胶水：**

```
❌ HealthSystem 直接 get_node MovementSystem  — 这是耦死，不是胶水
✅ ShopController 收到拖拽 → 发 AssignWorkerIntent → GameSession 处理
```

**分不开就合并：** 若两个系统必须强耦合（Jonas 举例：生命 + 攻击），就做成**一个** Simulation 模块，不要硬拆。

**写模块时假装要复用：** 即使只在本项目用一次，也按「未来会复用」的标准写 — 更整洁、更低复杂度。

**不要一个巨型 GameManager：** Thronefall 有约 30 个小 glue/manager，各管一件小事。我们等价物：`GameSession`（tick + 存档）+ 各场景 `XxxController`（输入），而不是一个文件包打天下。

---

## 四、四层结构 + 双数据库

```
┌─────────────────────────────────────┐
│  View 视图层                         │
│  场景 .tscn、Sprite、Presenter、动效   │  ← 你（美术）主导
├─────────────────────────────────────┤
│  Glue 胶水层                         │
│  输入 → GameIntent → GameSession      │  ← 短、薄、不可复用
├─────────────────────────────────────┤
│  Simulation 模拟层                   │
│  状态、规则、队列；只经 tick 管道推进    │  ← 无 Node 依赖为佳
├─────────────────────────────────────┤
│  Database 数据层                     │
│  策划 JSON（immutable 为主）            │  ← pm_board
└─────────────────────────────────────┘
```

**两套数据（Jonas · BV1soRCBvEWX 强调）：**

| 类型 | 放哪 | 例子 |
|------|------|------|
| **Immutable / 策划数据** | `Resources/Data/*.json` | 配方数值、角色名、技能树 |
| **Mutable / 运行态** | Simulation 对象字段 | 当前金币、队列进度、已收集图鉴 |

View 还有**第三套纯表现数据**：动画名、贴图路径、Parallax 系数 — 也在 Database/资源里集中存，**不要散在 20 个脚本 export 里**（Thronefall 踩过的坑）。

**数据流（单向）：**

```
输入/点击 → GameIntent → GameSession 校验并改状态 → EventBus 信号 → ViewPresenter 刷新
```

**View 读 Simulation 的心态：** Presenter 像在查实时数据库 — `ledger.get_balance("money")`，而不是 HUD 自己维护一份金币。

---

## 五、时间面条：唯一管道

每个系统都要接「时间」，最容易重新变成面条。Jonas 建议：

1. **一个**地方按**固定顺序**调用各系统 tick  
2. Gameplay 关键逻辑**不要**依赖引擎默认 `_process` 顺序或随机事件顺序  
3. EventBus **适合**驱动 View 刷新；**不适合**作为 gameplay 状态变更的唯一依据  

本项目落地：`GameSession.tick_simulation(delta)` — 顺序为 `clock → modifiers → production → orders`（后三项待实现，但**槽位已预留**）。

Glue 层 `_process` 只做：读输入、调 `tick_simulation`、把结果交给 Presenter。

---

## 六、美术先行的推荐顺序

| 阶段 | 谁 | 产出 | 不要做什么 |
|------|-----|------|-----------|
| **A** | 你 | 主菜单 ✓、店铺 **一张完整视觉稿**（PSD/Godot 静态场景） | 不写 OrderManager |
| **B** | 你 + Main | 工位/角色在画面里的 **命名规范**（层名 = 节点名） | 不做双向同步工具 |
| **C** | Core | JSON 字段定稿；pm_board 能改配方/角色 | 不碰 Parallax 参数 |
| **D** | Core | Simulation 模块（可先单测式验证） | 不做 HUD 皮肤 |
| **E** | Scene | 单个 `.tscn` 挂胶水：拖拽 → Intent | 不重构 Database |
| **F** | VisQA | 运行截图验收 | 不大改 Simulation |

**一次只拼装一个场景。** 店铺 STREET 定稿后再 TOP，再二楼。

**Database 可以先于玩法：** Jonas 有时会**先设计整张数据表**，再往上叠系统 — 我们已有 JSON 草稿 + pm_board，与之一致。

---

## 七、Game Database

| 文件 | 用途 |
|------|------|
| `characters.json` | 角色 |
| `recipes.json` | 配方 / 材料 / 产物 |
| `skill_trees.json` | 技能 |
| `maps.json` | 地点与场景路径（**场景做好后再填 `scene` 字段**） |
| `costumes.json` | 服装图鉴 |

编辑入口：`python tools/pm_board/server.py` → http://127.0.0.1:8765

**策划友好原则：** 一起设计的数据放一起；改一个配方不要翻五个 Prefab。

---

## 八、Simulation 模块清单（骨架已建 · 未接 Autoload）

| 模块 | 路径 | 状态 |
|------|------|------|
| `SimulationClock` | `Scripts/Simulation/SimulationClock.gd` | 骨架 |
| `EconomyLedger` | `Scripts/Simulation/EconomyLedger.gd` | 骨架 |
| `ModifierRegistry` | `Scripts/Simulation/ModifierRegistry.gd` | 骨架 |
| `ProductionQueue` | `Scripts/Simulation/ProductionQueue.gd` | stub |
| `OrderQueue` | `Scripts/Simulation/OrderQueue.gd` | stub |
| `SaveSnapshot` | `Scripts/Simulation/SaveSnapshot.gd` | 骨架 |
| `GameDatabase` | `Scripts/Database/GameDatabase.gd` | 可读 JSON |
| `GameIntent` | `Scripts/Glue/GameIntent.gd` | 基类 |
| `ViewPresenter` | `Scripts/View/ViewPresenter.gd` | 基类 |
| `EventBus` | `Scripts/Services/EventBus.gd` | 未 Autoload |
| `GameSession` | `Scripts/Services/GameSession.gd` | tick 管道 · 未 Autoload |

**Autoload 只在第一个店铺场景挂接后再加**；当前 project.godot **零 Autoload** 是故意的。

---

## 九、目录地图

```
weave-and-wander/
├── Docs/
├── Scenes/
│   ├── MainMenu/            # 当前唯一 runtime
│   ├── Shop/                # View 占位
│   └── World/
├── Scripts/
│   ├── Database/            # 策划 JSON 读取
│   ├── Simulation/          # 乐高砖 · 纯逻辑
│   ├── Services/            # GameSession · EventBus（未来 Autoload）
│   ├── Glue/                # Intent · XxxController · SceneRouter
│   └── View/                # UiMotion · HandDrawnSquiggle · ViewPresenter
├── Resources/
│   ├── Data/
│   └── Sprites/
└── tools/pm_board/
```

**脚本归属速查：**

| 层 | 放什么 | 禁止 |
|----|--------|------|
| Database | 读 JSON、解析 ID | 改游戏状态 |
| Simulation | 数值、队列、存档快照 | 引用 Sprite / 场景节点 |
| Services | tick 管道、聚合、发信号 | 直接操作 UI |
| Glue | 输入、Intent、调 GameSession | 长业务公式、系统互 get |
| View | Tween、Presenter 刷新、VFX 组件（如 HandDrawnSquiggleTarget） | 改金币/库存 |

---

## 十、反模式清单（面条在盘外）

| 症状 | 问题 | 正确做法 |
|------|------|----------|
| 一个脚本 500 行，又 UI 又算钱 | 面条出盘 | 拆 Simulation + Presenter |
| `StationMarker` 里扣材料 | View 改状态 | Intent → GameSession |
| 配方 cooldown 写死在 `.gd` | 策划找不到数 | 进 `recipes.json` |
| 5 个 Manager 互相 `@onready` | 假胶水真耦合 | 只通过 GameSession / EventBus |
| 每个工位自己 `_process` 计时 | 时间面条分叉 | 只走 `tick_simulation` |
| 为了架构先写 10 个空 Manager | 过度工程 | **能跑就行**，重复三次再抽 |

---

## 十一、《针脚与远方》特有决策

- 店铺：**STREET 街景 + TOP 俯视** 双视角（见 `.cursor/skills/weave-pseudo3d-shop/SKILL.md`）
- 定位：画家工会式场景派工 + 开罗式数据深度
- UI：不做 Cursor 规则层面的布局硬性规定；随视觉稿迭代

---

## 十二、Jonas 最终建议（两版视频共通）

1. **架构服务于「能做完」**，不服务于炫技  
2. **重复出现的逻辑**才抽成系统  
3. **先让游戏好玩**（静态场景里手动假玩），再自动化  
4. **内容管线**（持续产出场景/表）比多两个 Manager 重要  
5. **没有一次就懂** — 要靠项目实验；保持 organized，定义随项目微调  
6. **每做一款游戏应更快** — 乐高砖库越积越多  

---

## 参考时间轴（原片章节）

| 时间 | 主题 |
|------|------|
| 0:00 | 面条代码 · 「能跑就行」 |
| 0:45 | 乐高砖 + 胶水 · 70/30 · 禁止系统互引用 |
| 7:00 | Game Database · 先设计表 · immutable/mutable |
| 11:22 | 时间面条 · 显式 tick 顺序 |
| 12:46 | Simulation vs View · 双数据库 |
| 15:19 | 最终建议 · 别过度工程 |
