# 人偶服装组件

默认路线是简单分件人偶，以旧 `dolls_3d_turntable.gif` 为视觉基准。不要继续把默认模型改成复杂肩袖曲面。

## 使用

1. 在 Godot 打开 `garment_template.tscn`，选择 `Shell` 调整腰线、宽度、袖长和袖口宽度。
2. 选择 `Buttons` 调整数量、间距、半椭球尺寸和颜色；上衣改变后纽扣会重新贴合。
3. `waistcoat_template.tscn` 添加独立短褂，可调前襟开口和袖窿裁切。
4. 部件的材质使用 `doll_volume.gdshader`；`pigment` 控制颜色，`tone_steps` 控制分色层数。

`simple_garment.gd` 是默认生成器，复用 `garment_shell.gd` 的参数接口，但覆写曲面生成。身筒与两袖为三个简单分件，袖根内藏，不是焊接网格。`garment_shell.gd` 的连续肩袖生成方法仅保留为未采用实验。

不要手动改生成后的顶点或纽扣子节点，下次重建会覆盖。短褂与上衣须作为同坐标系、单位变换的兄弟节点；纽扣行通过 `mount_surface` 指向上衣。

运行时人偶生成后会烘焙蒙皮并移除生成脚本，避免后续重建清空权重。`models/` 中的 TSCN/GLB 是烘焙结果，不是参数化源模板。用 `tests/export_models.gd` 重新导出。

参数可用来制作独立上衣变体，但完整人偶的手、袖口和骨骼尚未自动适配任意尺寸。超出默认比例后须重新检查搭配和动作；这里不是通用布料仿真或完整服装编辑器。

## 商品陈列组件

`garment_hanger.gd` 提供实木肩式、双木夹板一字裤架、肩带式支撑，挂钩原点位于横杆轴心。`display(items)` 接收同架商品数组，读取 `GarmentDefinition.hanger_profile()` 并生成逐件挂点；`item_mount(item)` 返回挂点。`occupant_ids` 记录每件库存 ID，取走单件不移走衣架或其他衣物。类型、叠放兼容性和容量由 `ShopInventory.can_display()` 决定。

`thread_spool.gd` 的 `build(radius,height,color)` 生成连续螺旋绕线、圆边端盘、中空芯轴和底层线体；同尺寸复用缓存网格，颜色通过材质独立设置。店内线架、工坊桌面和缝纫机共用此组件，不再用光滑圆柱代替全部线材。

`sewing_machine.gd` 是可复用的场景道具组件，包含开放机喉、针杆、压脚、针板、手轮和线轴路径。使用场景纸艺材质，不改变人物的扁平印刷材质。
