# W&W 总交接 / HANDOFF

更新时间：2026-11-10（Asia/Shanghai）。读者无需本对话上下文。
这是当前接续入口，不是“全部已完成”的声明。新对话先读本页，再读专题文档和当前代码。

### 最新续作：同骨架穿着引导与真实坐垫（第9轮）

本节优先于下面第8轮的旧结果。用户纠偏仍是“先穿进去，再处理物理”，不是要求继续增加碰撞偏移。**默认游戏、认可的素体和站立衣形均未替换。** V20、shorter_arm_body、doll_rig三文件SHA再次与冻结值一致。

- `G/tests/export_wearing_simulation.gd` 新增互斥的 `--shape-targets` / `--bone-targets`。前者导出旧RestCloth偏好衣形；后者从同一真实Hips、双Thigh、双Shin的skin变换得到一个共享裙筒，不把裙子拆成两条腿。nap0独立检查分别110180、132776项通过。基础零morph pin、身体数组和骨rest保持；原默认导出仍可用。
- `G/tests/export_bench_cloth_support.gd` 导出真实Bench的StripedLinenSeat/TailoredCushion，共14400顶点，实际支持后的坐垫转换到角色骨架空间。输出`captures/wearing_bench_support.json`。它是最终nap0的静态支撑，不代表站立到躺下的完整世界空间路径；身体与该支撑自身无面交叠。
- Blender MCP4.2.2原生Cloth现支持quad模拟、形状引导及真实坐垫。**诊断改为原Godot的1920个渲染三角形**，不是模拟quad/cage；旧quad统计不能直接与新统计等同。只做8次法线平滑，不做顶点Smooth或Shrinkwrap。
- 最有进展的候选：`captures/wearing_bound_simulation_nap0_blender_supported.json`，同骨架引导+坐垫，最终nap0非相邻自交0，身体/坐垫三角面交叠均0，16/16腿截面中心在虚拟封口裙内。输入SHA为`357bdc140b58b15492f73c4ba45bb29fd7a24b68d591b0824ccc19ebd38bc0b2`。**这只是单姿态几何候选，裙摆仍有不自然凸角，没有美术验收。** 中心包含抽样不等于全表面/连续碰撞。
- 拒绝记录：240点粗代理转回渲染面有81对自交；旧RestCloth引导+坐垫有209对自交、身体76/42对及坐垫16对交叠。不能用旧衣形当动态目标就宣称穿着统一。保留截面半径的四元数引导（`--bone-targets --preserve-sections`）导出154303检查通过，但原生结果又有34对自交，未采用。它存为`wearing_section_simulation_nap0_blender_supported.json`，不覆盖较好的bound候选。单独使用`--preserve-sections`按预期拒绝退出1。
- 真实Godot截图：`captures/wearing_bound_simulation_nap0_blender_supported_proof.png`，左生产contact、右候选，上俯视下侧视。`native_wearing_capture.gd -- --proof=res://captures/wearing_bound_simulation_nap0_blender_supported.json`可复现；脚本校验来源/几何hash，截图manifest明确“主裙面、排除裙饰、无运行时接入”。section候选亦有同名proof图。GPU均为RTX4060，完整运行退出0，PASS不是外观验收。

Blender复现：runpy加载`G/tools/simulate_wearing_blender.py`，`create(source, use_quads=True, shape_guided=True, support_source=实际坐垫JSON)`，顺序`advance(scene,60/120/180)`，`finish(scene,normal_smoothing=8,output_tag='supported')`。本轮`.006`为bound，`.007`为section；MCP调用间普通Python变量不持久。创建隔离Scene、每次恢复用户原Scene，未保存/覆盖其blend。所有CLI与MCP求解已收尾。

**下一步**：先在正确包覆基础上解决候选裙摆凸角和腰部衔接，不以盲目平滑/扩张代替穿着；将同一变形传到包边、围裙等依附层，再验证坐姿、四睡姿、过渡和真实库存穿脱。随后才接默认角色和已实现的惯性。旧4类严格层测试失败仍开放，通用自碰撞/连续碰撞和CLO等效未完成。可复用调试UI，不重做身体。

### 第8轮：穿着原生验证，默认游戏未替换

本节接续下方用户纠偏。先用真实身体运动验证衣服是否仍包覆身体，不能把“三角形不相交”直接当成“穿对了”。素体、肩胯、22骨rest及已认可站立衣形不改；本轮没有生产服装算法修改。

- **拒绝实验**：截面中心跟随腿部的helper产生新自交，已移动到 `G/tests/experiments/rejected_centroid_pose_binding.gd`；只由 `tests/garment_wearing_capture.gd` 引用。不要重新移回scripts或默认install。失败图和JSON用 `rejected_wearing_*`，原隔离脚本增加 `experiment_prefix`；生产 `layered_isolate_*` / `rest_contact_geometry.json` 已重跑恢复，旧基线报告仍是 `rest_contact_blender_before.json`。
- **实际导出**：`G/tests/export_wearing_simulation.gd -- --nap=0..3`，Godot CLI headless。已独立验证nap0与nap3各88633检查0失败。输出1025裙顶点、torso/legL/legR共1205身体顶点，21帧（1、30、35..120、180），同一rig从站立到nap。仅腰口目标使用零morph的骨骼变形；未调用失败helper/接触修正。最后一帧包含加权蒙皮矩阵的逆，误差2.39e-7；身体数组/骨rest和源hash不变。其余nap尚未独立运行。
- **Blender原生Cloth**：`G/tools/simulate_wearing_blender.py` 通过MCP运行。`create(绝对JSON路径)`返回新Scene名；`advance(scene_name,180)`顺序求解；`finish(scene_name)`导出 `wearing_simulation_napN_blender_native.json`。MCP调用不保留普通Python变量，每次runpy加载并传Scene名。原用户Scene保持，未保存其blend。Godot+Y转换Blender+Z；仅模拟代理焊接重复UV缝，输出恢复1025索引；固定腰口、自碰撞、原生材质参数，非CLO标定值。
- **结果与限制**：nap0最终身体面交叠0，腿截面中心三方向射线16/16在虚拟封口裙体内，非相邻自交仍8对。中心抽样不能证明全腿表面包覆，有自交时parity也有局限。画面碎褶、腰部衔接不合已认可风格；没有长椅碰撞体，也未验证所有中间帧。因此 `experimental_not_accepted=true`，**不接入生产**。
- **避坑**：直接Smooth会重新压入双腿（59/83对候选交叠）；其后Outside Shrinkwrap仍未通过（97/19身体对、36自交）。拒绝证据 `wearing_simulation_nap0_postfit_rejected.json`。新增的这两个modifier已经从试验cloth移除，最终native JSON是原生Cloth单modifier结果。不能只看零自交或中心包含就判成功。
- **截图**：`G/tests/native_wearing_capture.gd`读取native输出，以实际GameBodyDoll+bench支持导回nap0，生成 `captures/native_wearing_proof.png` 及manifest。左生产contact、右实验；两边均排除裙饰以隔离主裙面，其他服装并非新物理。RTX4060实际渲染，身体hash不变。测试PASS仅表示导入/截图/身体一致，不是外观通过。独立预览测试才读取native JSON，默认游戏未读取。

下一步：以“身体穿在衣服内部”的包含性、腰口/袖口/领口归属及活动余量为基础，先让原站立版型随真实骨架得到可用的姿态形状；物理解算可提供离线运动/接触参考，但要在接触约束下保持低频衣形，不能事后普通平滑。补长椅支撑、多层传递、坐/走/抬手与所有nap及中间帧，之后才考虑接入库存/角色。此前4类严格层测试失败仍开放，不得用这次单裙单姿势诊断替代。活动目标未完成，当前委派/CLI进程均已结束。

### 最新用户纠偏：先让素体正确穿着，再处理物理

用户指出“最大的麻烦不是小人没有‘穿’进衣服吗”。后续优先级按本节执行，不能继续用碰撞膨胀代替穿着适配。衣服不是完全没有蒙皮：与素体共享rig，但旧`rest_cloth.point()`独立生成坐卧弯曲，未按新素体腿部的真实运动重建一致的衣物活动空间。其后法线方向的胶囊远侧出口又可能放大错误。

本轮仅新增诊断`tests/rest_contact_isolation_capture.gd`及`tools/analyze_rest_contact_blender.py`，**未改生产身体/服装算法**。真实GPU三服装四睡姿，关闭接触、最近出口、原方向出口共12图；关闭接触时裙面完整但小腿穿出，原方向接触产生折面碎裂。LongSkirt重合缝顶点误差约7.75e-17，排除明显UV缝分离；不是删掉面或背面剔除，现有shader本就cull_disabled。

已真实连接Blender MCP，用mathutils BVH读取Godot导出，没有修改Blender场景：sleep0原裙非相邻自交对0，原方向接触后532，最大边长比约46.98；其他睡姿亦增加。`captures/rest_contact_blender_before.json`及`rest_contact_geometry.json`是证据；BVH/CPU导出是诊断，不能替代GPU或连续碰撞验收。当前算法局部顶点可被推到胶囊另一侧，邻点不动，造成折叠。最近出口模式又暴露腿部，所以不能直接用它作为修复。

执行顺序：冻结已确认素体及站立衣形；统一服装穿着基准、肩口/袖根/腰口的骨骼从属和关节活动余量；用同一骨架运动生成服装基础变形和修正量，不再让裙子与腿采用互不一致的姿势曲线；在正确穿着上再叠加已实现的裙摆惯性、重力和层间接触。裙子是包住双腿的一张有松量布面，不变成两根贴腿筒。先验证无补偿性大位移时的穿着与姿态，再验证开启物理后的连续性。

既有子agent曾获委托尝试纯ring包络helper，但用户纠偏后已停止，核实没有创建helper/测试或启动后台任务，**不允许默认接入膨胀helper充当穿衣修复**。本轮全部GPU诊断已自然完成退出0。三冻结源码hash仍一致。目标保持active，尚未完成正确穿着适配，更不能宣称通用CLO物理已实现。

### 最新增补：衣形保形张力，2026-11-10 第2阶段

本节优先于下方第1阶段的旧数值。活动目标仍未完成；用户只认可调试UI，尚未验收这一轮新衣形。V20、shorter_arm_body和doll_rig三个冻结文件SHA256再次完全一致，原rest_refined_top未覆盖。

- `garment_shape_profile.bridge_tension`在根/下摆之间传播外扩量，避免紧贴臀部小凸起；Resource默认0兼容此前算法，GameBodyDoll裙筒0.85、身筒0.8。`accepted_body_fit`在绑定时使用`cloth_body_contact.build_rest_envelopes()`共享的原14个包络，随后再保形，不改包络尺寸、素体、肩袖与裤装。工作发生在configure/重建，不新增每帧全衣网模拟；尚未做正式性能基准。
- 预览台保留认可样式，新增Contour reach/tension数值框；真实输入与tres回填已验证。张力是美术保形参数，不是CLO物理抗弯的直接数值，也不替代已有惯性fabric参数。
- 新`tests/garment_contour_diagnostic.gd`区分原始/蒙皮/接触结果，18记录71779检查通过。A/B脚本`garment_contour_capture.gd`输出三套服装的idle/hands_abdomen/walk，顶排张力0、底排0.85/0.8，相同相机，约49度斜侧视；manifest记录RTX4060、源SHA、417143检查、失败空。CPU截面测量不是GPU顶点回读或最近面碰撞检查。style0腹前抱手侧部局部回缩2.43到0.20、后部5.49到0.21，单位是模型坐标换算毫米，不是实物面料测量。
- 最新通过：形状10550、法线13、惯性10949、接触148、库存休息131525、身体/换装2166666检查，材质连续性0失败；操作台11图/64帧、layered13图/39姿态，64帧动图已重编码。MCP脚本校验通过；编辑器bridge仍不可达，GPU由CLI启动。DeepSeek Harness余额不足，无修改；既有子agent仅负责诊断/截图，Codex审阅并独立复跑。
- **仍需修**：站立手臂挤压造成局部内凹；`layered_sleep_0.png`俯视下可见裙摆破面，不得只展示较好的侧视图就当作睡姿已验收。严格`layer_skinning_test`本轮完整256姿态/3385344顶点，仍4类失败、exit1（Apron/Pocket/OpenWaistcoat/FrontBinding），没有放宽阈值。签名平面负值不等于最近面的穿透深度。

下一步：先分离睡姿破面的morph/层偏移/接触投影来源，保留原骨架与身体；精确传播内层位移并做滑移后的最近面诊断；再把手臂接触沿低分辨率衣面传播。任意袖轴/裤轴曲线、三维控制环、全百褶资产管线、连续/自碰撞、性能基准依旧未完成。不要把本节的保形张力当成通用CLO求解器。

### 活动目标：可视化衣形曲线与裙摆惯性（2026-11-10，第1阶段）

用户同意用部件根到末端的曲线控制衣形，并要求借鉴已有百褶裙编辑器的转圈惯性，保持认可的圆锥裙、肩袖与素体。目标仍active，没有宣布完整完成。固定身体仍是V20+短臂0.045；accepted_body_v20、shorter_arm_body、doll_rig未改。

复查修正：惯性先按时间累计输入再固定步长积分，240/480FPS不丢短促起步；禁用/支撑期间仍维护速度历史，避免启用时假冲量。最新惯性10949项0失败。衣形修改后的法线按同位置/同原法线合并UV接缝，保留硬边，13项0失败。预设保存/加载已通过实际FileDialog信号及临时tres验证，加载后开关显示同步。库存形态构建现保留坐卧morph并随切分插值；挂衣/折叠清零，穿着同步，且在接触代理采样前同步以免晚一帧。inventory_rest新回归131525项0失败，完整身体/换装2166666项与材质连续性再次通过；仍不等于库存所有衣物GPU美术验收。

**用户已认可本轮调试界面样式**（“这调试菜单样式真漂亮，可以延续下去”）：后续衣物/工坊工具延用大预览、侧边紧凑参数、可直接拖拽曲线的布局。此确认只针对调试UI，不能当作新衣形/物理效果验收。

- 新入口 `G/scenes/garment_lab.tscn`：独立原生Godot预览台，三套服装、静止/转圈/启停/走路、鼠标旋转观察；数值控制密度、厚度、抗弯、抗拉、阻尼、褶数/褶深。可拖动侧/前/后松量、保形、运动自由度曲线，双击增加控制点；支持独立关闭曲线拟合或惯性、保存/加载tres预设。不替换主游戏入口，预览实例调整不会自动覆盖全店角色默认值。
- `components/garment_shape_profile.gd` 用32x32固定网格汇集体表拟合的向外增量，再沿布面长度局部传播；原始衣形作为基底，绝不向内削身体。已接LongSkirt和TailoredShell的非袖区域，派生围裙/马甲沿原层绑定跟随；法线只更新受影响区域。当前只支持竖直身筒/裙筒，任意袖轴、三维截面控制柄、完整起止轨迹编辑尚未实现。
- `components/garment_fabric_profile.gd` + `scripts/garment_secondary_motion.gd`：9圈轻量控制状态，固定120Hz积分；真实body_rig世界转向/平移驱动，不是固定循环摆动。质量由面密度和褶内面积近似，厚度不重复算质量；厚度用于接触，抗弯/阻尼独立，抗拉用于限制展开时经向伸长。参数是游戏归一化近似，非CLO标定材料。停步有余晃、腰口固定，坐卧渐隐惯性并保留原重力morph；还没有坐卧布料的动态支撑求解。
- UV2保存固定根到下摆坐标；挂衣/折叠的三角形切分插值保留UV2，换材质保留cloth_secondary_enabled。GPU运动、CPU诊断和内层接触代理共用同一套状态。库存衣物支持独立fabric_physics资源，穿着时取实际下装参数；附件更新仅复制状态，不重复积分。旧百褶裙预览驱动未改，不能声称两套任意资产管线已完全统一。
- 本轮GPU `garment_upgrade_lab.png`、`garment_upgrade_curve_edit.png`、三套still/turn/stop及64帧 `garment_turn_stop.gif`；`garment_upgrade_manifest.json`记录真实RTX4060输出。曲线指针拖拽、数值输入、身体一致性和非空像素均有自动检查。`layered_*`再次覆盖3套×13姿态。图仍待用户验收，尤其手置腹前时的局部臀侧鼓起尚未完全消除。
- 实测：形状曲线6383检查0失败；惯性10941检查0失败（30/60/120Hz、左右转、停步、暂停、瞬移、休息切换、参数敏感性）；完整身体/换装2166666检查、36姿态、6穿脱循环0失败，含UV2与换材质标志；既有材质连续性0失败。旧严格层间距四类失败仍开放，本轮没有用这些新测试替代它。

后续优先：把运行时局部接触也沿低分辨率衣面传播，消除裙侧鼓起而不改身体；补袖/裤的任意轴部件和三维控制环；验证真实换装后转身、裙饰层间距与坐卧过渡；统一百褶裙导入的参数/绑定协议；补性能基准与移动端等级。当前还不是布料自碰撞、连续碰撞或CLO求解器。Godot MCP静态校验可用、editor bridge仍不可达，GPU走CLI；Blender MCP连接检查成功，本阶段没有改Blender模型。Kimi Harness尝试返回429会员额度耗尽，未切付费API；改用既有子agent实现独立曲线Resource并由Codex复核/复跑。

### 当前续作：裙侧、层叠衣物接触（2026-11-10）

最新用户要求：保持已确认素体不变，修裙侧、多层衣物和袖子相互嵌入，检查走路/抬手/坐下/睡觉并截图。本轮没有改 `accepted_body_v20.gd`、`shorter_arm_body.gd`、`doll_rig.gd`，三文件SHA256与开工前完全一致。

- 衣物改动：裙子/裤脚去掉实心封盖，保留真实开口；裙侧沿衣面外侧退出身体接触，并向手臂内侧退让。新增 `cloth_surface_proxy.gd`，从实际内层衣服的网格、骨骼和休息morph采样12圈低分辨率接触面，袖子在肘/袖口让位、肩根保持锚定。外层按依赖图分层，口袋和门襟不再与第一层共用间距；换装后更换接触来源，折叠/挂衣仍关闭接触。采样按几何SHA缓存，不对整张衣网每帧做CPU求解。
- `rest_cloth.fit_layer` 对互相矛盾的折叠面偏移约束增加位移上限，修马甲坐卧时的尖刺。仅改变衣物修形，未改休息骨骼姿态。
- 实际GPU验证脚本 `tests/layered_cloth_capture.gd`：三种服装，静止、工作、抬高双手、手放腹前、4个步相、坐姿、4种睡姿，13张双视角图/39组姿态。`layered_capture_manifest.json` 记录实际GPU、有限值/构图/像素检查及素体一致性。这些检查不是零穿模证明。
- 最新图在 `G/captures/layered_*.png`；`game_body_rest_0..3.png` 为双人长椅近景；`game_body_shop.png` 为真实主场景的临时展示站位。用户认可的 `rest_refined_top.png` 未覆盖。
- Blender MCP已真实连接并用BVH检查325个网格/姿态组合，候选接触仍存在（含内部面/夹层），不要宣称CLO级连续碰撞、自碰撞或任意服装无穿模。`tests/export_accepted_rest_contact.gd` 已验证5种休息姿态的原始导出及可逆蒙皮，生成 `accepted_rest_contact_raw.json`，**没有据此烘焙或应用新的物理资产**。
- 核心回归结果：accepted_game_body 2,152,254 checks/36姿态/6次穿脱，0失败；接触数学148项，0失败；材质连续性0失败。层绑定测试由旧VolumeDoll迁移到真实GameBodyDoll并检查实际接触后几何，完整结果见后续条目/开发日志，不能沿用历史旧模型的通过结论。

后续仍优先修复杂叠层/极端姿态的实际可见接触；不要再动身形。Godot MCP静态校验可用，编辑器bridge不可达，截图由Godot CLI GPU完成。启动测试与其他测试并行时约87秒，不能和此前单次42秒直接比较；尚无帧率优化结论。

**本轮最终未通过项**：迁移后的严格 `layer_skinning_test` 完整执行256姿态/3,385,344顶点检查，最终4类签名平面间距失败：Apron（坐姿）、Pocket（睡姿混合）、OpenWaistcoat（行走下缘）、FrontBinding（坐姿），退出码1。曾准备在已知失败后停止长扫，但身份检查时进程已经自然结束，没有实际终止。该检查仍基于原始绑定三角形，接触造成滑移/折面反向时，数值不是最近表面的真实穿透深度；既不能直接用其绝对值推断肉眼穿透，也不能无视失败。下一步应做精确底层位移传递及滑移后的最近面接触校验，针对这4处补GPU中间姿态图，不再加大整件衣服offset。

### 当前任务：已确认素体接回游戏，衣物适配第一阶段

用户最新要求是“把这版素体接回游戏，适配好衣服，注意肩袖衔接和穿模。别再改身形了，做好截图给我看。防穿模&衣物物理学学clo3D”。已执行游戏入口接入；下文“尚未替换NPC”是此前阶段历史，不再是当前状态。

**绝对基线仍是V20 + arm_shortening=0.045，两个基线脚本本轮未改。** 新`G/scripts/game_body_doll.gd`继承它。员工、顾客、路人、邮递员、Catalog、摩梭和乌克兰入口改用同一基线；只处理服装拟合、材质接触和必要的坐姿手部IK，不重塑身形、不隐藏完整身体。

实现和边界详见`G/Docs/ACCEPTED_BODY_CLOTH.md`。关键新模块：`accepted_body_fit.gd`（体表包络/层三角形绑定）、`components/accepted_body_shell.gd`（原有内嵌袖片的有限细分）、`cloth_body_contact.gd` + shader include（蒙皮后轻量接触）、`cloth_contact_profile.gd`（碰撞/渲染厚度与层间距）。挂衣/折叠关闭人体接触，穿上后跟随真实顾客；工坊材质替换保留这些参数。

**已测试而非用户视觉验收**：accepted_game_body_test 2,152,310 checks / 36姿态 / 6轮换装 / 0失败，包含身体全部数组与22骨rest精确一致；邮递员240姿态原有接触测试0失败；材质连续性0失败；UKRAINIAN_WARDROBE_PASS。截图是Godot4.7.1实际GPU：`game_body_shop.png`（真正主场景、员工临时展示站位）、`game_body_idle/work/walk.png`、`game_body_rest_0..3.png`。用户原认可的`rest_refined_top.png`未覆盖。

**未完成/不能宣称**：通用布料自碰撞、连续碰撞、任意复杂服装绝对无穿模；新LegMannequin的袜子适配；全部民族服装多角度美术验收。Blender MCP原生BVH诊断27个网格/姿态组合里23个有候选交叠，含内藏面、手臂与裙侧，报告是诊断而非验收。Godot MCP bridge本轮不可达，GPU截图走CLI，不冒称MCP成功。初始化从本轮中间态约82秒减到约42秒，仍待进一步性能治理。

下一步先让用户看本次真实游戏截图，保持已确认素体不动；按可见穿模优先检查裙侧/袖肩/跨身动作，然后完善碰撞代理与离线修形烘焙管线、库存服装缓存。不要恢复失败的复杂肩网格、强制把上身权重全部转给手臂、无限细分或只调大碰撞间距；这些本轮试过，已撤掉对应实验。`game_body_work_cpu/sit/nap.png`是早期诊断，不是最新有效图。

本地`W/DEVLOG.md`（供D:/dev-diary读取）、`W/Docs/DEVELOPMENT_LOG.md`同步。Git工作树原先大量其他agent修改和暂存改动保留，未reset/checkout或整树提交。文档里的文件根别名：W为D:/GodotProjects/weave-and-wander，G为W/prototypes/dollhouse-3d。

### 此前有效决定：V20 短臂版已获用户确认，固定身形基准

用户查看短臂前后对照后回复“ok。”，确认 `arm_shortening=0.045` 的右侧版本。此版是后续素体基准；不要继续自行修改肩、掌、胯、腿或再询问是否认可这次短臂幅度。原版与归零回退保留。本次确认只更新验收记录，没有自动替换正式穿衣NPC，也没有扩大到衣物/全部动作验收。

用户于2026-11-10明确确认上一轮截图：“这版是好的。在此基础上，稍微收短手”。**V20原版已验收，不要再追错版本或重塑肩、胯、腿。** 项目内固定源为 `G/scripts/accepted_body_v20.gd`，除类名外与step2310源码一致；外部原始快照保持不变。

本轮新增独立子类 `G/scripts/shorter_arm_body.gd`：`arm_shortening=0.045`，约肩到手尖长度的5%，Inspector范围0到0.09、步长0.005，归零即原版。肩部Y>=1.69保持不动，Y<=1.17的手掌与拇指刚性上移，中段平滑消化长度；所有顶点X/Z与掌形不变。只对这个实例重设肘/手的rest并重建Skin，未修改共享rig。节点场景 `G/scenes/accepted_mannequin.tscn` 可用于查看该参数。

实际GPU对照为 `G/captures/accepted_body_shorter_arm_front.png` 和 `_quarter.png`，左原版、右已确认短臂版。`shorter_arm_body_test.gd` 67247 checks/0 failures，验证几何变化范围、掌形刚性上移、其他身体不变、骨点同步、12动作有限值以及归零/重建恢复。MCP脚本校验通过；MCP编辑器bridge不可达，因此截图由CLI GPU取得。视觉确认来自用户本次回复，不是由测试通过推断。

**范围：已确认的独立素体，尚未替换游戏里的穿衣NPC。** 活动experimental_full_body_doll、VolumeDoll、共享rig、服装与袜子代码未动。后续接入任务应以此身形处理服装适配；不得把全身连续裸模直接替换有分段遮罩的穿衣版本，或宣称衣物物理已解决。

### 历史：V20 原版独立恢复与来源核对

用户否定了“今天首笔修改前”的版本，要求“这也不是啊。。再前一个版本”。现已从 Antigravity 原始写入记录找回更早的 V20 素体，外部隔离脚本为 `W/prototypes/snapshots/body-work-20261109-before-rollback/historical_body_v20.gd`；原文为同目录 `recovered_v20_not_applied.gd.txt`。只更改类名，没有重塑网格或调整比例。实际 Godot GPU 截图为 `G/captures/historical_v20_front.png` 和 `_quarter.png`，已查看，肩颈/手腕恢复连续轮廓。源码一致性检查通过。

**重要来源更正：V20 截图对应 step2310 的素体源码，加 step2324 的鞋跟修改；不是 step2360。** 按原执行顺序，step2328 渲染 V20、step2330 保存截图；step2360 改形体后，step2362 已渲染 V21。此前取出的 step2360 被误标 V20，造成肩线和小腿仍不对；已更正存档，旧内容保留为 `historical_step2360_v21.gd.txt`。不要再次按文件名猜版本。

当前仅独立恢复并展示，**尚未覆盖活动游戏，等待用户认版**，符合本轮“确认前不覆盖”的承诺。活动 `experimental_full_body_doll.gd` 仍是下节的297行版本。预览仍依赖当前共享 VolumeDoll/rig，不是整个历史工程冻结；没有宣称衣物物理或动态穿模已修复。Godot MCP bridge 本轮不可达，实际截图来自 Godot4.7.1 CLI GPU，不得写成 MCP 截图成功。

### 上一轮回退：撤回今天的素体工作，用户已否定此回退点

用户最新明确要求：**“改回今天和你的对话发生前的样子”**。已经执行，不继续V20恢复或重新建模。回退边界为2026-11-09本轮素体首笔修改前（首笔补丁19:39:27，Asia/Shanghai），不是Git HEAD，不是11月5日的近似候选。恢复`G/scripts/experimental_full_body_doll.gd`的原297行版本（含原shared_hand和原袜子显隐逻辑），只从`G/scripts/doll_rig.gd`撤掉本轮新增的比例映射与authored skin实验接口；其余原有蒙皮、袜子、步态、坐姿等修改保留。

恢复依据：当前对话19:38源码读取、20:26完整源码读取，以及三份先前补丁的逆向还原。前180行与首次读取逐字一致；全部源码与保存的回退前目标快照核对通过。核对的27个其他已修改文件SHA256前后完全一致，未操作Git暂存区。今天新增的模型/物理/测试/生成脚本与实验JSON、blend已从活动工程移出，原样备份在`W/prototypes/snapshots/body-work-20261109-before-rollback/`；不要自动移回。

验证：Godot MCP两个脚本静态检查通过；`verify_rollback.gd`实际GPU59186 checks/0 failures；原`skinning_test.gd`96姿态0失败（clearance_vertices=0，不证明所有衣物无穿插）。截图`G/captures/rollback_before_today_front.png`为实际回退后状态，左穿衣右素体；腕缘/领口等旧问题未趁回退改造。检查脚本和目标源码也留在上述备份目录，不作为新的游戏功能。

追溯时在Antigravity对话`5f98a330-d5ca-4e58-9a01-26631b9dde29`找到更早的V20完整源码与多轮截图，但用户随后选择撤回今天工作，**V20未接入**，只存`recovered_v20_not_applied.gd.txt`。不要把下文历史恢复计划当成当前指令。DEVLOG保留失败与回退记录，不删除历史来伪装完成。

### 历史记录：找回用户亲自调整的完整素体，尚未精确恢复

用户再次给出完整素体图，指出此前恢复错了版本。**不能将旧穿衣VolumeDoll的衣下结构缺失，推论为用户没有完整素体；此前这一判断错误。** 当前要追回用户版本，不是再造一个类似人体。下文“恢复原穿衣版”记录的是已执行操作，不等于恢复了用户素体。

原图已无改动存为 `G/Docs/reference-body/user-tuned-body-2026-11-09.png`，与此前65ec附件SHA256完全一致。找到11月5日完整源码记录，原文存 `G/Docs/reference-body/experimental_full_body_2026-11-05.gd.txt`，仅改类名的可运行候选为 `G/scripts/recovered_early_full_body_doll.gd`。没有重塑网格，没有接入主游戏，没有启用失败实验。

**状态：早期候选找回，目标版尚未精确找回。** 实际GPU `G/captures/recovered_early_body_front.png` 与 `_quarter.png` 仍有不同的肩部突点/小腿轮廓，不能说就是用户那张。另查明后加袜子shader会在裸模模式下仍裁掉腿；预览只解除材质遮罩，不改几何。源码一致性及12个身体部件验证通过；原穿衣模型2245项回归仍0失败。这些不是目标版视觉验收。

已询问用户亲自调整的入口（Godot/Blender模型还是先调整截图），据此继续找保存历史。来源、哈希与操作记录见 `G/Docs/reference-body/RECOVERY.md`。禁止凭图再次重塑；将用户完整素体、旧穿衣模型、被否定实验分开管理。

### 此前操作记录：撤回新素体，恢复最左侧原穿衣版

用户随后要求查看现用素体。本轮仅新增 `G/tests/current_underbody_capture.gd`，在临时预览中隐藏外衣并解除现有小腿的裙摆遮罩，没有补建任何身体，也没有启用实验体。实际确认：原VolumeDoll只有头颈/部分胸部、手掌、小腿等网格，腰胯、上臂/前臂、大腿并非完整衣下人体。截图 `G/captures/current_underbody_front.png`（左现穿衣版、右实际衣下结构）与 `_quarter.png`；空缺是真实缺失，不能将穿衣轮廓称作完整素体。正式游戏文件未修改。

**用户明确否定下述肩臂手改造，并要求恢复对照截图最左边的原穿衣版。不要再把后文的网格测试通过当作美术验收，也不要主动重启新素体。** 当前外形基线是 `G/scripts/volume_doll.gd`，即 `reference_silhouette_capture.gd` 中原来的左侧 Original，不是实验版归零、也不是重做一个类似版本。

已执行：`ExperimentalFullBodyDoll` 默认直接走原VolumeDoll构建，完全跳过新素体、旧融合体、肩/手/胯高度映射、覆盖隐藏及实验碰撞；原手掌/肩颈/服装/骨架恢复。新素体变量仅留作非Inspector的历史记录，`enable_full_body_study=false`。旧裸模切换不再将默认角色换成实验体。正式VolumeDoll、乌克兰服装资产及其他agent的修改没有回滚或覆盖。

新的默认验收是 `G/tests/reference_dressed_restore_test.gd`：Godot4.7.1 GPU **2245 checks / 0 failures**，三套基础服装逐项比较原网格、法线/UV/权重、显隐、骨架rest和5类动作变形，且旧比例值/裸模调用不影响默认模型。Godot MCP静态检查通过；共享骨架96姿态0失败。实际截图 `G/captures/reference_dressed_restored.png` 已查看，保存了恢复后的单人原穿衣版。

本会话新建的旧手部/肩部/比例/融合/身体接触试验与截图入口已加 `--archived-body-study` 显式门槛；默认输出SKIP，不是“物理失败已修好”。历史代码和资产仅保留追溯，不应作为继续默认建模的入口。根DEVLOG、完整开发日志、专题文档均已标明这次否定及回退。

### 最新增补：按 p1/p2 修正肩高、溜肩与手掌尺度

用户否定上一轮肩部与手掌比例：肩根凸出、连接位置低，手臂粗细变化太大。最新依据为 `codex-clipboard-205b2788-2038-4768-b6da-7c1f54670809.png`（穿衣全身与手掌）及 `codex-clipboard-a598eb78-f891-4e19-af4f-a15e45d96e08.png`（肩颈轮廓）。本轮未启用旧全身融合，不重塑头、胯、腿。

当前新素体：肩根末端向身筒内收，肩部曲线局部加密；`shoulder_raise=0.055` 对肩部网格、袖子和骨架rest走同一高度映射；手臂主要截面约0.060-0.064半径，不再从0.046扩大到0.084。肩根顶端完全绑定Spine，中段向UpperArm渐变，腕缘仍与Forearm共享变换。颈部Z偏移收回，修复旧预览里颈肉从立领前面顶出的现象。

通过Blender MCP生成 `G/assets/reference_hand_small.json`：相对上轮手掌X/Y为72%、Z为78%，长度约0.2016；掌根/拇指连通结构保留。源为 `G/tools/blender_reference_hand_fit.py`、`G/Docs/ukrainian-model/reference-hand-fit.blend`。旧reference_hand.json与blend保留作源，不再是运行时默认手的尺寸。

实测：reference_silhouette_test 26222 checks/0 failures（18姿态、1080肩根封口样本留在身体内）；reference_hand_test 35927 checks/0 failures；手/胯高度回归295212 checks/0 failures；共享骨架96姿态0失败。旧高度测试现在将shoulder_raise固定为0，以隔离手/胯变量；新肩高另测，不是取消肩部检查。Godot MCP静态验证通过。实际截图 `G/captures/shoulder_refined_front.png`、`_quarter.png`、`_side.png`、`_neck.png`、`_action.png` 已查看；三人排布左为原穿衣版对照、中为修正素体、右为修正后穿衣。`shoulder_before_*` 保留本轮修改前证据。造型仍由用户确认，测试不替代美术验收。

本轮只收拢肩臂手比例，不推进或宣称完成下述衣物物理；相关已知失败仍开放。所有DEVLOG已追加。

### 最新增补：连续拇指已接入；通用衣物物理未完成

用户最新要求是自然的拇指/掌根衔接，以及参考CLO思路的通用衣物防穿模。当前仅修改新素体的手，不再重塑肩、胯或身体轮廓。Blender MCP已生成894顶点的闭合连通手掌：拇指根部与掌内融合，手腕原环线保留，腕缘法线与前臂一致，前臂到手掌有渐变蒙皮。源为 `G/Docs/ukrainian-model/reference-hand.blend`，导出 `G/assets/reference_hand.json`，生成器 `G/tools/blender_reference_hand.py`。正式VolumeDoll的另一份shared_hand未覆盖。

当前实测：`reference_hand_test.gd` 35927 checks / 0 failures，18姿态含显式转腕；比例回归283554 checks / 0 failures；共享骨架96 poses / 0 failures。截图 `G/captures/reference_hand_detail.png` 已查看，是实际Godot正面/斜侧面手部近景；审美仍待用户确认。

**衣物没有完成“杜绝穿模”，不能报完成。** 新的原生SoftBody3D封装和Inspector参数资源是可复用实验接口，尚未接入正式小人的服装。隔离Jolt测试220 checks / 0 failures；当前游戏DEFAULT/GodotPhysics3D的远离初始表面碰撞用例仍有2失败。未切换共享project.godot。另一个GDScript顶点投影实验虽消除了六姿态84450次顶点检查中的穿入，却留下418次面内穿入采样，单次29-79ms，`body_contact_enabled`现默认false；`garment_body_contact_test.gd`应返回1。不要为了绿灯移除面内断言、隐藏身体或全员启用。

详见 `G/Docs/HAND_CLOTH_2026-11-09.md`，含实际命令、已知失败、源码与后续路线。下一步应从一条裙子的低模模拟网格、固定点和身体代理碰撞开始，验证Jolt动态人体/姿态切换，再加入高模映射、衣物层间接触和LOD；不是继续叠加耗时的逐顶点“推出”来冒充物理。旧设施重叠/MVP任务仍保留。本轮Kimi额度用尽、DeepSeek余额不足，回退到有明确三文件边界的本地子agent；主代理审阅并复跑了结果，未暴露凭据。

### 最新增补：只抬高手和胯，禁止再次重塑身形

用户最新纠正：基于 `codex-clipboard-65ec0fcf-ac33-42a0-b9a3-d098f901c2c5.png` 的素体，仅整体提高手和胯。此前缩腕/移肩/Blender 体素融合并横向加宽的方案被用户否定，不是美术验收成果。

当前 `G/scripts/experimental_full_body_doll.gd` 已恢复参考版原来的手臂环线、与前臂同截面的长手掌和拇指。原手掌代码从 11 月 5 日源码读取记录核对，不能把后来替换的 shared_hand 当成截图原版。仅新增 Y 向比例映射：`hand_raise=0.10`、`hip_raise=0.10`（约身高的3.7%）；Inspector 可调整并重建，归零恢复原始网格。肩、头、脚固定，全部顶点 X/Z 不改。骨架绑定点、服装在绑定前走同一高度映射；无此元数据的正式 VolumeDoll 不改变比例。

本轮实际 Godot 4.7.1 GPU：`G/tests/mannequin_arm_proportion_test.gd` 272535 checks / 0 failures，验证原网格保留、手掌刚性上移、胯位上移、X/Z/头肩脚不变、关节随比例移动、9个活动采样有限值、运行时归零精确恢复。`skinning_test.gd` 96 poses / 0 failures；clearance_vertices=0，不能宣称证明所有衣物无穿插。截图 `G/captures/mannequin_height_only_front.png` 和 `_quarter.png`：左为原比例、右为高度调整；已经查看，仍待用户审美确认。日志同目录 `mannequin_height_only.log`、`mannequin_shared_rig_regression.log`。Godot MCP 本轮脚本验证成功，截图为实际 CLI GPU 渲染。

被拒绝的融合资产 `mannequin_upper_body.json`、`mannequin-junctions.blend` 暂留作历史实验，`use_continuous_junctions` 默认 false，运行时不加载其 JSON。`mannequin_junction_test.gd` 显式 opt-in，仅用于旧实验，不作为当前比例版验收。不要重新启用它或自动运行其 Blender 生成器覆盖基准。

本地 DEVLOG 已定位：`D:/dev-diary`，按项目 `repo_path` 自动读取根目录 `DEVLOG.md` 的 `## YYYY-MM-DD` 段落。已新增 `W/DEVLOG.md` 供它读取，`Docs/DEVELOPMENT_LOG.md` 保留完整追加历史。未改 DEVLOG 工具的配置，也未声称已在它的界面刷新验收。

## 1. 一分钟理解项目与最新委托

项目为 **Weave&Wander 针脚与远方**：以民族服饰与小物文创为主题的娃娃屋店铺经营游戏，连通资料 Wiki、2D 图纸/剪纸编辑、参数化 3D 服装与人物展示。资产编辑器系列称“百工坊”。不能把项目简化成换装展示器，也不能只剩没有学习内容的经营数值。

用户长期独自开发，现将与 **3 位计算机队员**协作，共四人。下一次对话需要重新讨论、追索和构思整体的严肃游戏、Wiki、2D 图纸、3D 模型方案，以及多人、多 agent 工作方式。不要未经讨论就大规模重构或让 agent 各自扩张功能。

用户目标：**2027 年 1 月以软件形式参加软件创新大赛“AI+学习”赛道**。这是目标月份，不是已核实的官方提交日。赛事全称、组别、资格、截止日、交付格式、联网要求、评分标准、AI 使用与版权规定均待用户提供/查证，当前不能宣称符合赛事规则。

最近尚未关闭的游戏请求：**人物使用设施，尤其长椅/沙发时不能叠在一起**。此前一轮完成 B 卡通打光、生产材料一致性、布书输出及停工原因提示。本轮重读工作区、核对后续文档并完成交接；未修改游戏逻辑，未将重叠问题冒充已修复。

## 2. 工作区、仓库与入口（重要）

| 对象 | 路径/入口 | 注意 |
| --- | --- | --- |
| 总工作区 | `D:/GodotProjects/weave-and-wander` | 根目录不是 Git 仓库；也有旧 Godot 工程，别误启动 |
| 当前游戏及 Git 根 | `D:/GodotProjects/weave-and-wander/prototypes/dollhouse-3d` | `project.godot` → `res://main.tscn`；Godot 4.7、GL Compatibility |
| Wiki | 游戏目录下 `tools/ww-wiki` | Node 本地服务，常用 `http://127.0.0.1:4318/`；不是在线服务存活承诺 |
| 正确的 2D 编辑器 | `D:/CodexWorkspace/papercut-editor` | 独立应用；不要误接总工作区内的 `asset-workbench` 老实验 |
| 总开发历史 | `D:/GodotProjects/weave-and-wander/Docs/DEVELOPMENT_LOG.md` | 追加式 DEVLOG，历史测试不代表今天仍通过 |
| 当前总交接 | 本 `HANDOFF.md` | 滚动维护当前事实、任务、风险和下一步 |
| 游戏截图/测试 | 游戏目录的 `captures/`、`tests/` | 图片修改时间可能来自复制，不能据此推断测试日期 |

2026-11-09 核对：游戏 Git 有大量修改、未跟踪文件和 `MM`（暂存/未暂存并存），涉及共享素体、主场景、乌克兰服装、Blender、声音和镜子等，来自用户及其他 agent。**禁止 reset、清理未跟踪文件、整包覆盖、盲目提交所有文件。** 用 `git -C prototypes/dollhouse-3d status --short`，而不是只在总目录运行 Git 就认定没有版本控制。

根目录 HANDOFF 和 Docs 不在当前游戏子仓库版本控制范围内。组队后必须先决定总仓库/多仓库边界，将文档、编辑器和 Wiki 的版本关联纳入团队可获得的交付；不要认为“克隆游戏仓库”已经包含全部项目。当前不擅自初始化父级仓库或迁移历史。

## 3. 推荐阅读顺序与冲突处理

以下游戏目录相对路径记为 `G/`，总工作区相对路径记为 `W/`。

1. 本文件：当前总目标、事实边界、最先要处理的问题。
2. `G/Docs/HANDOFF_2026-11-05.md`：较新的经营、生产、UI、Wiki 全局审计。
3. `G/Docs/UKRAINIAN_HANDOFF_2026-11-06.md`：最新乌克兰套装 Blender 源、已接受下装、导出及验收边界。
4. `W/Docs/DEVELOPMENT_LOG.md`：本会话历史与本轮审计记录。
5. `G/DEVELOPMENT_STATUS.md`、`W/Docs/MVP_PLAN.md`：重要历史，但含 10 月状态，不能照抄为当前清单。
6. 对应专题：`G/Docs/PLEATED_SKIRT_CONTRACT.md`、`MATERIAL_PRODUCTION_2026-10-27.md`、`GARMENT_MATERIAL_PIPELINE.md`、`LOOM_INTEGRATION_REVIEW.md`、`BASIC_PATTERN_ACCEPTANCE.md`、`WIKI_REFERENCES.md`、`WIKI_REDESIGN_PLAN.md`、`WIKI_PHYSICS_2026-10-30.md`。
7. 编辑器：`D:/CodexWorkspace/papercut-editor/PROJECT_WORKFLOW.md`、`docs/PLEATED_SKIRT.md`。

`W/Docs/AI_HANDOFF.md` 是 11 月 2 日乌克兰参数化资产交接，并非当前总入口。其“固定高腰线”等旧要求已被 11 月 6 日的服装贴合调整更新；不得用旧文档覆盖新源文件。冲突时核对明确的最新用户决定、当前源码、对应测试/截图，再追加更正，不删历史来制造一致。

## 4. 产品与美术约束

- 游戏是可玩体验，按钮浮于画面上；PC/平板横屏优先。Wiki 则应现代、学术、信息清晰，不照搬游戏装饰。
- 用户喜欢无描边、印刷插画、小人约四头身、圆锥形服装轮廓。纸偶版本应保留，不能为了新实验覆盖旧版本。
- A/B 是游戏本体画风实验，不只是 Wiki 查看器。B 更卡通的明暗和投影，有透视力度调节；昼夜及室内灯光仍存在；A 可恢复，不擅自定为永久 B。
- 大世界“大窗前手工工作台”与娃娃屋应有材质层次差异；不是所有东西一起抹平阴影。不要重启一轮无止境的场景重建占用 MVP 时间。
- 衣物是有松量、厚度与重力效果的布，不是裹腿的硬壳；保留已获认可睡姿，优先解决占位而非再改整个人体。
- 商品、材料、装饰应可组合且保持身份：单件衣物、同衣架多件、帽子组件、实际拿取/试穿/退回/结账/打包；不能缩放商品塞进袋子，帽子在折叠衣物之上。
- 文化资料要有来源和不确定性标注；照片示例不自动代表整个民族/地区。授权未明不能当可公开商用素材。
- 2D 预览、3D 网格、游戏物品与 Wiki 内容不是同一件事。导出成功不等于运行时穿戴链已打通，更不等于学习有效性已验证。

## 5. 已有成果与证据等级

### 5.1 本会话上一阶段已实现、当时测试通过

日期记录见 DEVLOG 2026-11-03；2026-11-09 已检查关键实现仍在，但**未重跑最新工作区全部测试**。

- `G/scripts/render_ab.gd`：B 运行时替换光照函数，分档法线明暗/灯光衰减/投影，保留灯色；A 恢复原 shader，透视力度可调。
- `G/components/sewing_machine.gd` 与 `scripts/production_flow.gd`：装线时读取订单材料快照，修复针下布仅在进度 <2% 更新的问题；明确命名四段 `ThreadPath`，同步线轴颜色，卸线隐藏。
- `G/components/working_loom.gd`：梭芯用当前批次色；织成布为同一库存批次的 book 包装，有木架承托，不再悬空。
- `G/components/material_package.gd`、`fabric_wrap_mesh.gd`：布书尾端展开/合拢，外形随余量变化；裁剪账本仍负责扣料。
- 接单失败不再进入假的普通工作计时；员工详情显示等待原因。`auto_stock_target` 默认 2，布架容量 3 批；缺料/满库存是有效停工条件，不应无限凭空生产。
- 当时 `render_ab_test.gd`、`loom_production_test.gd`、`material_handling_test.gd` 通过；`wrapped_fabric_test.gd` 85 checks / 0 failures。实际截图为 `captures/game_ab_flat.png`、`production_consistency_loom.png`、`production_consistency_sewing.png`。
- 缝制姿势/袖口穿插并未随材料一致性一起解决。不要称整套生产动画验收完成。

### 5.2 已有系统，但需新团队实测建立基线

参考 11 月 5 日审计：已有实体材料账本、预留扣料、订单/目录/随机安排、采购相关入口、染色、顾客挑选/试衣/镜子/收银/打包、体力/个性/休息、营业/打烊/工坊时段、灯光耗电等。具体完整性须逐条核查，旧 MVP 计划中的“尚未实现”也可能已过时。

参考 11 月 6 日专题：乌克兰套装改用可编辑 Blender 源与共享骨架，已有导出/回读、封面与三帧走动检查。造型未获最终用户验收，坐姿/极端动作/所有体型参数未全面复测。当前导入数据约 14 万顶点，不能据“低多边形风格”假设性能廉价。

Wiki 已有资料、来源、模型和 motif 查看/编辑工作；11 月 2 日旧文档记录过 69 项测试通过，不是当前测试数量或今天的通过结论。其二维 motif 预览不能当成已实时更新 Godot 成衣。

2D 编辑器历史已支持褶裙参数、原生文档/图层、撤销/保存与三维预览，并有数据契约。历史状态明确：预览 retarget 不含通用碰撞/重力求解；运行时完整穿戴与单件商品链仍需复核。

## 6. 未关闭问题：设施人物重叠（下一项工程优先）

用户原话：“小人使用设施尤其是那个沙发时不要叠在一起”。尚无本轮成功复现录像与修复提交。

已读源码：

- `G/components/rest_bench.gd`：三座，`SEAT_SPACING=1.22`；小睡占相邻两座；`reservations` 存弱引用、entry、support、seats、mode；释放时在 `_rest_blend > 0` 标记 departing，清理条件是 blend 归零。
- `G/scripts/staff_behavior.gd`：选择休息位与体力恢复；通常 <=25% 休息，<=15% 请求小睡，恢复到85%离开，个性可能调整触发条件。两座不连续时当前会退为坐姿。
- `G/scripts/main.gd`：`_assign_staff`、`_release_staff_facility`、`_on_doll_arrived`、`_process_staff_jobs`。
- `G/scripts/volume_doll.gd`：`rest_support`、`rest_departing`、`_rest_blend` 与姿势偏移/起身。
- `G/tests/rest_bench_test.gd`：三人坐、一睡一坐、座号不重叠、姿势过渡、家具移动、删除角色及恢复。它没有充分证明起身/接班过程的实体不重叠。

**待验证风险，不是已确认唯一根因：**

1. 对已占本长椅的同一人重复指派，会先 release 再 reserve；旧 departing 记录可能被重新返回，却不能再 support，产生错误中间态。
2. 单人设施当前可把原 occupant 设 idle 后立刻接纳新人，缺少“原人起身并离开使用空间后才交接”的保障。
3. 长椅仅凭 blend=0 释放座号，不代表原人已走离入口；新旧人可能在相同 entry 重叠。原导航未见通用角色避让，不能以座号不同推断过渡不相交。
4. 当身体/服装在其他任务变更后，座距和小睡实际轮廓可能已不匹配；应在当前共享素体上截图测量。

建议最小修复：先复现，再让重复同目标指派幂等；容量/占位在完整“预留→接近→使用→起身→离开”生命周期内有效；失败指派不得赶走别人或丢失本人的任务；让满位者在独立可达位置等待。不要直接扩大长椅、传送角色、关闭碰撞/缩人来掩盖。

验收矩阵：三人坐；一睡一坐；第4人/满位请求；碎片空位；重复点击同目标；起身中有人补位；单人织机/缝纫设施换人；0/1/4/10倍速；取消/删除角色；移动长椅；体力休息中断与恢复。检查 reservation、行为状态、真实身体位置及视频，不只断言 seats 数组唯一。

本会话此前启动的 `rest_bench_test.gd` GPU 进程已不可恢复，旧 session id 无效；未得到可确认的完成输出，**不能计为通过**。本轮没有新的运行中验证会话需要接管。

## 7. 运行、测试与工具避坑

PowerShell，从总工作区执行（本机路径需先确认存在）：

```powershell
git -C prototypes/dollhouse-3d status --short
git -C prototypes/dollhouse-3d diff --stat
git -C prototypes/dollhouse-3d diff --cached --stat
& 'D:/Godot/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe' --path prototypes/dollhouse-3d
& 'D:/Godot/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe' --headless --path prototypes/dollhouse-3d --script tests/rest_bench_test.gd --log-file captures/rest_bench_20261109.log
```

GPU 测试去掉 `--headless`。先读测试脚本，防止截图工具误作主场景。F5 是项目，F6 是当前场景。`--quit-after` 超时退出的 code 0 不等于测试成功，必须看到测试完成标记且没有脚本错误；断言中断后进程可能仍在。

Wiki：进入 `G/tools/ww-wiki` 后 `npm run dev -- --host 127.0.0.1 --port 4318`，另运行 `npm test`、`npm run check`。端口占用先查现有实例，不杀未知进程。`#/record/WW-MOS-001`、`#/record/WW-UKR-001` 是已使用过的页面。不得覆盖 `data/records.json` 破坏笔记；使用已有 API/幂等导入。

优先 Godot/Blender MCP；先确认连接的工程。项目包装器为 `W/tools/Invoke-ProjectGodotMcp.ps1`。本会话最后一次 9349 bridge 连接超时；不是永久不可用结论。全局 MCP 曾指向其他工程，不要运行其专属测试。MCP 不通可诚实改用本地 CLI，不能宣称 MCP 验证完成。

Blender 乌克兰源见 11 月 6 日文档：`tools/blender_ukrainian_rebuild.py`、`tools/ukrainian_sash.py`、`tools/ukrainian_bob.py`、`Docs/ukrainian-model/ukrainian-fit-refinement.blend`。保护 `accepted-lower-garments.json`，不要覆盖基线造成变换累积；不要只修改导出 JSON 而丢失作者源。

其他踩坑：Godot shader 的 light() 不能靠非法 return 拼补；同名子节点可能被自动改名，按名称找材质会漏段；测试通过还必须看渲染；截图不能用 AI 生成图替代；无来源的文化事实不要让模型补写；大资源不应每帧重复构造；不要为修服装随意改共享人体。

## 8. 四人团队与多 agent 协作（建议，待共同确认）

先问清每位队员专长、每周投入、期末安排、平台/设备及代码熟悉度，再分工。可讨论的责任边界：用户负责产品/文化内容/视觉及最终验收；三位队员分别牵头游戏运行与行为、Wiki/数据与AI检索、2D/3D资产管线。此分配不是已经商定的岗位表。

1. 建立共享远程、分支/PR、代码所有者和 issue 看板；源资产使用适合大文件的管理，提交导出配方与来源清单。先解决游戏、Wiki、编辑器和总文档的仓库边界，不擅自强行合仓。
2. 用版本化契约串联 `record_id/source_id/design_id/material_batch_id/item_id/recipe_version` 等身份；具体字段沿用现有实现后再确定，不能凭此文强行改名。明确每种数据唯一写入者和迁移策略。
3. 每张任务卡包含目标、允许改动目录、接口/依赖、验收测试、截图、未覆盖项和交接。一个模块同一时间只给一个写入者；大 `.blend`、共享 rig、`main.gd` 尤其要锁定所有权。
4. Agent 做有界子任务，不能多 agent 同写文件。人类/主 agent 负责架构、文化正确性、隐私、集成与验收；生成结果一律审 diff 后跑测试，不以自报完成合并。
5. 用户委派规则：小而明确任务优先 `C:/Users/16152/.codex/tools/Invoke-DeepSeekHarness.ps1`；多文件上下文任务优先 `Invoke-KimiHarness.ps1`，传绝对 WorkingDirectory 与完整 Task。不要替换为 OpenCode relay；不要泄漏凭证、自动改用另行计费 API。此前出现额度不足不是今天必然不可用，需适度核验，失败不反复消耗。
6. 建立最低 CI：Wiki 测试、2D 类型/契约测试、Godot 无头关键回归、GLB 导入验证；GPU 验收另存人工检查截图，不把无头测试叫视觉验收。
7. 每周整合一条端到端可演示切片，不让三条技术线到最后一周才首次相接。把“已实现/自动测试/视觉验收/用户接受”分列。

## 9. 下一次对话先讨论什么

建议先完成一次产品与技术启动讨论，而非继续零碎美术修补：

- 学习者是谁：年龄、既有知识、使用场景、每次可投入时长？是服饰文化理解、材料工艺、图纸空间认知还是设计能力？选一个主目标。
- 游戏中的哪些决定真正要求调用知识？“逛 Wiki 后答题”和“制作中查证来源、选择材料并解释设计”哪个更适合？经营是学习载体还是另一个平行产品？
- AI 带来什么可验证的收益：有引用的资料检索、讲解/提问、设计反馈、辅助结构化？哪些内容必须由人审定？不将虚构民族知识包装成权威。
- 用户怎样留下学习证据：前后测、作品与设计理由、来源引用准确度、迁移任务、误解修正？不能只统计点击与游戏时长作为学会证明。
- Wiki、2D、3D、游戏是否是同一软件中的工作流，或三个独立模块加明确导入？Windows 桌面/浏览器/混合方案、离线演示与网络故障降级需要取舍。
- 参赛希望展示哪一个有来源许可的服饰案例？摩梭/乌克兰已有资产但不能自动视作内容完备、性能合格或授权可用。
- 首次演示的最小“知识→设计→试穿→任务反馈”链条怎样用10–15分钟讲清楚？指标和验收由四人共同确认。

可供讨论的垂直切片：从一条可靠 Wiki 档案理解一种服装结构 → AI 基于批准来源解释并提出有针对性的问题 → 在已有2D模板调整纹样/结构 → 3D试穿并看到约束反馈 → 通过一个店铺委托做出有理由的选择 → 保存设计、引用与评价记录。**这是建议，不是已实现或已决定的学习方案。** 不承诺任意图纸自动生成任意服装、通用布料物理或无限民族资料覆盖。

## 10. 到2027年1月的候选里程碑

按赛事真实日期倒排后再定，预留缓冲；以下是提议：

| 时段 | 交付门槛 |
| --- | --- |
| 11月上中旬 | 确认赛事/学习目标/平台，四人跑起同一版本，盘点来源许可与仓库，关闭设施重叠等阻塞缺陷 |
| 11月中下旬 | 打通一个数据契约驱动的 Wiki→2D→3D→游戏样本；AI引用与失败降级可演示 |
| 12月上半月 | 完成可玩的学习任务、制作/库存闭环、保存恢复与学习记录，进行小规模用户试用 |
| 12月下半月 | 修问题、性能与平板/PC验证、独立打包、离线方案、许可清单及演示材料；冻结大改 |
| 2027年1月 | 按正式节点提交；保留可重复安装包、演示视频、架构/学习评价证据与答辩稿 |

本项目已有很多表现层，但团队阶段应以“稳定可运行且确有学习反馈的一个切片”为最先验收，不再把新增房间/服装数量等同于 MVP 进展。

## 11. 文档维护与接续动作

HANDOFF 负责“现在”，DEVLOG 负责“发生过什么”。每次阶段结束同时更新：任务状态/阻塞/下一步、修改范围、运行命令、测试完成标记、截图与未覆盖范围；有提交时记 commit，未提交时直说工作区快照。不要复制旧通过数字冒充新测试；更正历史用追加条目。

下一位 agent 的起步清单：

1. 阅读本页与11月5/6日专题，检查三个应用实际路径与 Git 暂存/未暂存 diff，确认没有并行写同文件者。
2. 向用户确认优先：先修设施重叠，还是先组织四人项目启动讨论；不再要求用户复述整段历史。
3. 工程线优先复现长椅的完整交接过程，保存失败证据，窄范围修复后再跑矩阵；本任务尚未完成。
4. 产品线索取赛事资料与队员能力/时间，围绕第9节共同定学习目标、软件形态和一个垂直切片。
5. 形成经用户确认的团队任务板、接口约定和里程碑后再分派 agent。不要从这份建议文档直接宣布架构定案。

本轮交接未上传、发布、推送或建立远程协作服务，未改变现有资产和运行数据。
