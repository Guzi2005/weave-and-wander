# 乌克兰套装接续记录（2026-11-06）

本轮用实际 Blender MCP 建模，再导入共享 VolumeDoll 实机检查。用户尚未验收造型；不要把导出测试通过当作视觉验收。

## 最新要求及实现

- 腰线略降低；腰带是一条连通的布带，绕两圈、压缩打结、展开成宽垂带。截面加厚，裙顶、围裙顶和内衬上端按同一腰围收压，避免露白圈。随共享骨架变形，并非实时布料压力模拟。
- 衬衫前胸留松量、后背减薄，左右褶皱采用对称输入。袖子从袖口扫掠到身筒，接缝共用顶点，肩部过渡平滑。前领降低、有前襟开口，去掉独立锁边。
- 每侧流苏由九簇组成，每簇三十根纱线，根部收束、向下伞形散开，紫金交错。
- 珠子放大、数量减少、间距按路径弧长采样；三串在后颈以 0.017 间距向下排列，正面保留原有垂挂高度。贴合衬衫/颈部的静态接触面，不是动态珠链解算。
- 发片从头顶引出，与发壳融合、平滑、减面，避免相交表面形成明显贴片。原版发型的相似度仍应由用户验收。
- 本轮未更改共享素体；保留已接受的裙摆、围裙下部、鞋子。

## 编辑源和运行

工作目录：`D:/GodotProjects/weave-and-wander/prototypes/dollhouse-3d`。

- 主作者脚本：`tools/blender_ukrainian_rebuild.py`。
- 腰带/流苏：`tools/ukrainian_sash.py`；头发：`tools/ukrainian_bob.py`。
- 可编辑 Blender：`Docs/ukrainian-model/ukrainian-fit-refinement.blend`。
- 已接受下装基线：`Docs/ukrainian-model/accepted-lower-garments.json`。不要拿新生成文件覆盖基线，否则腰线变换会累积。
- 游戏数据：`assets/collections/ukrainian_photo_001/blender_rebuild.json`，12 部件、140428 顶点。
- 游戏读取：`scripts/ukrainian_blender_mesh.gd`、`scripts/ukrainian_outfit.gd`。
- 验收场景：`res://scenes/ukrainian_asset_preview.tscn`，支持转台、近景和动作。
- Wiki 导出：`tools/export_ukrainian_assets.gd`；封面：`tools/render_wiki_covers.gd -- ukrainian_`。

通过 Blender MCP 执行主作者脚本，不能只修改导出的 JSON。Blender 偶有断连/退出，已保存源文件；可用 `captures/start_blender_mcp.py` 启动本机 Blender 后重连。

## 验证与边界

- `captures/fit_refinement.log`：正、侧、背、细节及三组走动截图成功；图在 `captures/ukrainian_preview/`。
- `captures/fit_wardrobe.log`：UKRAINIAN_WARDROBE_PASS。
- `captures/fit_export.log`：六套 GLB/TSCN 导出及回读骨架动画检查通过。
- `captures/fit_covers.log`：六张 Wiki 封面已更新；已查看导出套装封面。本轮未在浏览器页面视觉验收。
- 数值检查通过：顶点有限、索引有效、UV/颜色/法线数组齐全；腰带网格为单一连通分量。未做全表面自交证明。
- 走动三帧未见腰带与裙顶分离；坐姿、极端动作、所有体型参数没有全面复测。
- 已知后续项：ReferenceBob 当前直接使用 Blender 顶点颜色，传入的 base_color 尚未应用，应后续补全换发色而保留参考默认色。袜子的专用着色器在通用 GLB 材质转换中仍需单独验证纹样导出。

工作区有大量用户/Gemini/早前任务的未提交改动；不要重置、清理或整体提交。本记录补充 `Docs/HANDOFF_2026-11-05.md`，不代表历史经营、家具、坐姿等任务全部闭环。
