# 百褶裙设计协议 v1

同一份 JSON 用于正式 `D:/CodexWorkspace/papercut-editor` 画板和 Godot 百褶裙组件。旧 `asset-workbench`（片语）保留为实验品，不是后续主入口。画布只是同一设计的不同投影：成品梯形平铺、圆弧展开、圆环俯视。三种投影共享归一化 UV，切换画布不重采样或丢弃笔迹。

平铺图只展示一个固定梯形，腰宽及下摆宽为对应周长的一半，高度为裙长。拖动循环展示裙子的不同周向面，一键反面转半圈；观察角度不改变设计 UV。默认同步新笔迹，可独立绘制。圆弧角度和半径由腰围、裙摆及裙长计算，横纵等比例，不含透视。筒裙展开使用矩形极限；圆环是顶视投影，不假设任意裙型都是整圆裙。图纸不包含缝份或褶内裁布余量。完整原生图层、Item 和裙子参数保存在 `.weave.json`，单独裙子 JSON 不包含原画板图层；Godot 包的 PNG 包含合成后的原生绘画。

- `schema`: `weave-pleated-skirt`，`version`: `1`。
- `design_id`、`item_id`、`component_id`、`collection_id`：持久身份；编辑和往返导出不重建身份。
- `template_id`: `plain`、`mosuo_reference`、`yi_reference`、`wax_reference`。模板是依据本轮用户照片的设计起点，不是某一族群全部服饰的标准。
- `canvas_view`: `front`、`sector`、`ring`。
- `source`: `{note: string, references: [{title: string, path: string}]}`。参考照片只记录出处，不嵌入商品纹理。
- `parameters`: `length_cm` [40,120]、`waist_cm` [50,110]、`hem_cm` [100,360]、`pleat_count` [16,128]、`pleat_depth_cm` [0.2,4]、`sharpness` [0,1]、`thickness_mm` [0.2,3]、`fabric` (`cotton`/`linen`/`silk`/`wool`)、`base_color` (#RRGGBB)。`hem_cm` 为展开外轮廓周长，不包含折入褶内的布长。
- 可选 `drape`: `{mode: "auto"|"manual", weight: number, bending: number, opening: number}`，数值均在 [0,1]。缺省时编辑器按面料和几何计算。导入器严格验证并保留此字段；游戏独立裙子组件目前不据此进行动态布料模拟。
- 可选 `silhouette`: `relaxed`、`a_line`、`bell`、`trumpet`，缺省自然垂落。
- 可选 `shape`: 必须完整含 `relaxed: {fullness, taper}`、`a_line: {flare, curve}`、`bell: {volume, peak}`、`trumpet: {fit, flare_start, flare}`、`hem: {mode, ratio}`。数值一般为 [0,1]，`peak` / `flare_start` 为 [0.2,0.85]；`hem.mode` 为 `body`（自然椭圆）、`circle`、`wide`（左右长轴）、`deep`（前后长轴），`ratio` 是短长轴比 [0.35,1]。各廓形参数独立保留，默认分别为 (0.5,0.5)、(0.5,0.5)、(0.5,0.6)、(0.5,0.5,0.6)，下摆默认 body / 0.7。旧文件省略字段时往返仍不补写。设置作用于三维自然垂落，不重写纹样 UV 或二维尺寸；游戏导入器验证和保留，独立裙子组件尚未实现对应形变。
- `bands`: 最多 32 条 `{id, start, end, color, pattern, repeat}`；`start/end` 沿裙长 [0,1]，从腰到下摆，`end-start >= 0.005`；`pattern` 为 `solid`、`dash`、`diamond`、`wax`；`repeat` [4,64]。数组顺序为绘制叠层顺序。
- `patches`: 最多 64 片 `{id, u0, u1, v0, v1, color, pattern, repeat}`，所有 UV 在 [0,1]，u1>u0、v1>v0。用于标注周向拼色和未来拼接片；当前不计算裁片缝份。
- `strokes`: 最多 256 条 `{id, color, width, points}`；`width` 为 UV 比例 [0.001,0.05]，`points` 为 `[u,v]` 数组，合计最多 40000 点。笔迹存为矢量折线，可回编。
- `pattern_uv`: `{origin: "waist", seam: "back", u: "circumference", v: "waist_to_hem"}`。

几何规范：Y 向上；单位由 cm 换算为米；腰在 y=length，裙摆在 y=0；u=0/1 的缝位在 -Z；三角波与余弦波之间按 sharpness 混合；每褶 8 个周向采样，纵向至少 24 段；内外层及腰/下摆的薄边形成真实厚度，腰孔与下摆开口保留。v=0 时褶深为设定的 15%，v=1 时为 100%；褶深上限为当前周长/褶数的 45%，避免失控尖刺。

Godot 导入器读取设计 JSON，并可读取同名 `.png` 展开纹样图。编辑器导出包包含 JSON、PNG、SVG 模板和来源；JSON 保留全部 band/patch/stroke 数据。新网格是独立可编辑组件，接入现有角色蒙皮及躺姿前需另做姿态兼容验收。

浏览器试衣固定腰口，约束纵向材料线长度，并用姿态包络及褶形松弛调整坐躺外形；裙内腿部用覆盖阈值裁去，不等同于通用布料碰撞。长椅几何与基色由 `tools/export_preview_bench.gd` 从实际 `components/rest_bench.gd` 导出为 bench.json/bench.bin。

浏览器裙摆展示先触碰手边布料，再向两侧滑开，松手阻尼回落；转圈采用固定步进的角向扭转与径向展摆惯性。所有廓形与椭圆设置进入同一形变链，腰口和纵向材料线长度约束保持。此模型尚无完整横向/剪切约束、自碰撞和真实接触摩擦，也尚未移植为 Godot 游戏角色的服装骨骼动画。

下摆图形编辑扩展：`shape.hem.mode` 增加 `custom`，可选 `angle_deg` 为 [0,180]，表示俯视长轴从左右轴向前后轴旋转的角度，编辑器归一化至 [0,180)。`ratio` 保持短长轴比，`parameters.hem_cm` 决定椭圆周长；三者都是连续参数。原 body/circle/wide/deep 文件不被强制迁移，用户修改下摆后才转为 custom。导入器完整保留朝向，拒绝未知字段及越界角度。
