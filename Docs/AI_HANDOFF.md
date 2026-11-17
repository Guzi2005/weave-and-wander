# Weave & Wander 本地 AI 交接说明

> 当前总交接入口为 [HANDOFF.md](../HANDOFF.md)（2026-11-09）。本页保留为 2026-11-02 乌克兰资产专题历史；腰线、作者源与验收状态应再对照游戏目录 `Docs/UKRAINIAN_HANDOFF_2026-11-06.md`，不要用本页覆盖后续工作。

更新：2026-11-02。当前工作区：`D:\GodotProjects\weave-and-wander`。所有模型、参考图、参数配方、wiki 数据与源码均已在本地；不需要 Tripo、model3d_generation 或云端服务即可继续。

## 1. 当前可接手成果

乌克兰参考套装 `WW-UKR-001` 已完成参数化建模并接入 wiki。包含：

- `WW-UKR-001-C01`：白色长衬衫衬裙、蓬松灯笼袖、红丝带；
- `WW-UKR-001-C02`：黄／紫／绿条纹罩裙；
- `WW-UKR-001-C03`：紫色围裙；
- `WW-UKR-001-C04`：黄色三圈缠绕腰带、黄紫毛线团流苏；
- `WW-UKR-001-C05`：四圈黑白珠串；
- `WW-UKR-001-M01`：条纹布料 motif；
- `WW-UKR-001-M02`：毛线团流苏 motif。

套装与五个部件均有 GLB、Godot TSCN 和 wiki 封面。六个 GLB 已回读验证骨骼、待机和行走动画；wiki 69 项自动测试通过。模型截图已目检，浏览器交互视觉验收未完成。

## 2. 不可破坏的约束

- **不得修改小人身体、头、头发、四肢、小腿、手腕位置或鞋。** 只能替换服装；沿用 `MosuoDoll` 的 `_strip_base_costume()` 约定。
- 腰带中心保持 `y=1.42`，罩裙腰口保持 `y=1.44`（模型米）。不要降低腰线。
- 裙子必须遵循 `Docs/PLEATED_SKIRT_CONTRACT.md`：Y 向上、每褶 8 采样、至少 24 纵段、三角／余弦 sharpness 混合、褶深 15%→100%、深度上限、真实内壁和薄边、缝位 -Z。
- `StripeMotif.sequence.u0/u1` 是一个重复单元内的**绝对 u 偏移**。`patches()` 只加 `cell`，不得再次除以 `repeat_count`。
- 原始参考图只作为该案例的来源。不得自行补写地区、年代、材料工艺或文化普遍性；照片作者、时间、地点和授权仍为待补。
- 不要直接覆盖 `D:/workspace/W&W Wiki/data/records.json`。通过本地 API 的幂等导入补充，保留用户笔记、来源与媒体。

## 3. 关键文件

### 模型与参数

- `scripts/ukrainian_doll.gd`：共享身体上的服装装配。
- `components/ukrainian_costume.gd`：全部服装几何、腰线与裙子实现。
- `components/motifs/stripe_motif.gd`：条纹 motif。
- `components/motifs/tassel_motif.gd`：流苏 motif。
- `assets/collections/ukrainian_photo_001/`：原图、裙子 JSON、两个 `.tres` 配方与机器可读交接清单。
- `tools/export_ukrainian_assets.gd`：整套及分件导出与 GLB 回读验证。
- `tests/ukrainian_capture.gd`：五视角截图。

### wiki

- `D:/workspace/W&W Wiki/public/assets/models/`：模型 GLB／TSCN。
- `D:/workspace/W&W Wiki/public/assets/motifs/`：motif manifest、预览图和下载配方。
- `D:/workspace/W&W Wiki/public/motifs.js`：motif 参数页。
- `D:/workspace/W&W Wiki/public/motif-recipe.js`：浏览器配方规范化及 `.tres` 序列化。
- `D:/workspace/W&W Wiki/public/motif-preview.js`：实时二维参数示意。
- `D:/workspace/W&W Wiki/import-ukrainian-research.mjs`：种子和本地记录的幂等导入。
- `D:/workspace/W&W Wiki/data/records.json`：个人运行库，已由 API 写入八条乌克兰记录。

## 4. 本地运行与验证

在 `D:/workspace/weave-and-wander` 中运行（Godot 路径为本机当前安装位置）：

```bash
"D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe" --path . --script tools/export_ukrainian_assets.gd --log-file captures/ukrainian_export.log
"D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe" --path . --script tests/ukrainian_capture.gd --log-file captures/ukrainian_capture.log
"D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe" --path . --script tools/render_wiki_covers.gd --log-file captures/ukrainian_wiki_covers.log
python tools/prepare_ukrainian_motif_previews.py
```

在 `D:/workspace/W&W Wiki` 中运行：

```bash
"D:\NodeJS\node.exe" --test tests/*.test.mjs
npm run dev -- --host 127.0.0.1 --port 4318
"D:\NodeJS\node.exe" import-ukrainian-research.mjs
```

打开 `http://127.0.0.1:4318/#/record/WW-UKR-001` 查看套装，`#/motifs` 调整 motif。默认端口为 4318；本地预览卡可由 `npm run dev` 转发 `--host` 和 `--port`。

## 5. 修改参数后的落地流程

1. 在 wiki 调整参数并下载修改后的 `.tres`。页面画布是二维示意，**不会自动改写三维模型**。
2. 若要应用到游戏，将配方内容核对后替换 `assets/collections/ukrainian_photo_001/` 中相应 `.tres`，同时更新 wiki 下载副本。当前 Godot 默认实例与磁盘配方数值一致；若后续改为显式加载磁盘配方，需重新跑完整渲染验证。
3. 重新执行模型导出、封面与 motif 预览生成。
4. 跑全部 Node 测试和 GLB 回读；再次目检正面、四分之三、背面、腰部和领口。
5. 只通过导入脚本补档案，保留个人运行数据。

## 6. 已知边界与下一步

- wiki 的 motif 实时预览是参数驱动的二维示意，不等同于 Godot 网格或布料模拟。
- 条纹、流苏可以改色、尺寸和数量；更复杂的立体材质、物理和动画适配仍在 Godot 侧。
- 身体适配是静态游戏模型，不代表原物实测尺寸或工艺鉴定。
- 若修改裙子几何，必须重新检查袖口、腰带、围裙及罩裙的接触和高位腰线，不得为修穿插而移动身体。
