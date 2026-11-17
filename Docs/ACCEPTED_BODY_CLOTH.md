# 已确认 V20 短臂素体：游戏接入与服装适配

2026-11-10。实现状态，不是用户视觉验收或“全部穿模清零”声明。

## 最新裁决：current整体优先，native仅借裙口角度

用户明确侧面睡姿的圆润、整体程度以current为胜，仅native裙摆开口角度更合理，不应硬拉面料超过弹性范围。**不采用整版native/silhouette_review作为外形基线。**后续以current腰胯、中段、贴垫下缘为视觉锚点，只处理裙口附近的倾角、转折与垂落；素体与已确认睡姿不改。该局部改动尚未实现，现有native零相交快照仅为诊断，不是用户视觉认可。

## 前一轮：按用户四处红线组合衣形

用户标注原图为`Docs/reference-body/sleep-silhouette-guidance-20261110.png`。目标是左上随屈膝弯曲的背侧、左下圆润贴垫的下缘，加右上连续弧形下摆、右下有体积的开放裙口，不是整版A/B二选一。素体与终态姿势继续冻结。

当前`captures/wearing_seamed_simulation_nap0_blender_silhouette_review_surface_layers_proof.png`是固定nap0的Blender原生柔性拟合候选，真实Godot回导4件布面的自交/层间/身体/坐垫面相交均0；身体和初始B形状守卫通过。但贴垫下缘尚未完全达到红线视觉目标，也未通过新候选的起身/躺下过渡，不能默认启用。原生180帧在本次只代表固定身体下的布面拟合，不代表动作180帧。

实际游戏路径的`waist_review_runtime_transition`揭示旧终态线性混合仍45/62采样有交叠，另有身体与坐垫的中间支撑轨迹冲突。实验饰带morph通道缺失已修，继承源5通道/UV2，26项接缝回归通过；通道正确不等于全部姿态无穿模。完整复现与下一步看HANDOFF首节。

## 前一轮：腰线衔接与最终姿态叠层通过

`tools/attach_waist_seam_blender.py`将已验证原生裙面接到精确腰线，再在固定自由布面邻域做局部整理。最新`captures/wearing_seamed_simulation_nap0_blender_waist_review_surface_layers_proof.png`的右侧B，在style0/nap0最终姿态中主裙与3条饰带自交、层间交叠及身体/坐垫面交叠均0。它是隔离混合候选，不是游戏默认效果；不能以这一张图宣称全部服装/动作通过。素体和骨架保持冻结。

同源180帧站立到躺下检查仍15帧主裙自交，身体/坐垫0，保护点及局部位移守卫通过，末帧与静态proof一致。更强平滑导致坐垫碰撞和位移越界，已拒绝。动态饰带、其他睡姿和全套衣装未过验收。新增审计回归7组通过，修正新场景F-curve尚未求值却读取末帧的假数据；本轮Godot细分2836、接缝14、惯性10949检查复跑通过。参数、文件与下一步以HANDOFF最新节为准。

## 前一轮：精确腰带边界切分

隔离导出新增`--split-waist`，沿真实WaistRibbon底边切分裙面，原1025点/衣形及原站走坐睡轨迹保持，新81点继承蒙皮、UV2、morph。2836项检查与158081项导出检查通过，生产身体和服装未改。ArrayMesh法线/切线重新编码误差已单独测量，不能宣称所有属性bitwise一致。

精确腰线解决了surface饰带偏移守卫越界，但新模拟仍失败：原8mm self gap最终110对自交，局部整理98对，4mm gap63对且过渡更差。三者均未采用，完整数值/文件见HANDOFF首节。不要把表面绑定正确当作物理已经正确。上轮local_fold_validated仍为保留的部分改善候选；下一步处理腰口与柔性区域的局部过渡，而非继续扩大固定区。

## 最新：局部折返整理，完整过渡和饰带仍开放

本轮冻结素体与默认游戏不变。新`tools/refine_wearing_folds_blender.py`使用原生局部Corrective Smooth，固定邻域73点、不动全固定腰口和邻域外顶点，最终最大位移.006476模型单位。真实顺序重算180帧后，主裙末帧自交/身体/坐垫均0，整段自交帧60降至16；仍不能接入默认角色。

截图`captures/wearing_attached_simulation_nap0_blender_local_fold_validated_bound_layers_proof.png`为真实GPU A/B，三条饰带可见并绑定，但普通绑定仍交叠，surface厚度模式在腰带处正确拒绝。不要把回导PASS当作穿模清零。新缓存守卫检查Blender过期/跳帧状态；修改modifier后必须restart并顺序advance，不能直接导出。7项守卫及14项接缝测试通过，最新proof附cache_validation。完整参数、限制与后续见HANDOFF首节。

## 接缝续作：两条下摆饰带已改善，仍未默认接入

隔离候选新增 `--surface-ribbons`，对同一源面接缝统一求解厚度约束，保留原正向厚度、修正内陷，残差或偏移越界则拒绝。新14项单测通过，既有裙摆惯性10949项通过。fixed-rest最终nap0的总候选交叠52->8：两条下摆饰带0，腰带与裙面7、腰带自交1，主裙面/身体/坐垫0。图为 `captures/wearing_bound_simulation_nap0_blender_fixed_rest_surface_layers_proof.png`。仍是单姿态、试验入口，不能声称通用层接触完成。

读取实际WaistRibbon边界的四次腰部固定试验均失败：最终自交4/99/91/4，对应全180帧有交叠79/97/74/60帧；整排固定还产生20对身体交叠。详细源文件和复现见HANDOFF最新节。更强pin或更宽固定区不能替代正确穿着对应，不继续盲调这条路径。所有失败证据独立保留，素体和默认游戏不改。

## 迁移续作：下方52对为修接缝前记录

现工程根为 `D:/workspace/weave-and-wander`，当前入口 `Docs/HANDOFF.md`；旧3D子目录已退休。素体三个冻结文件SHA完全一致，默认游戏服装未被本轮试验替换。

固定静止形状（dynamic_rest=false）候选减轻了旧向上尖角，最终主裙面自交/身体/坐垫候选交叠0、腿中心16/16。但完整180帧有47帧自相交，不能宣称过渡已通过。此审计在暂停前完成，本轮未重新模拟180帧。

三条饰带现能按实际裙面三角形绑定，不再独立保持旧睡姿。新目录 GPU 图 `captures/wearing_bound_simulation_nap0_blender_fixed_rest_bound_layers_proof.png` 与几何导出再次验证身体/骨架不变、A恢复完整。新增 Blender MCP 只读审计检出裙面与HemRibbon/FineHemRibbon/WaistRibbon分别22/11/18对候选交叠，腰带自交1，共52；主裙面/身体/坐垫0。故饰带虽绑定成功，仍未通过接触或外观验收。

输入读取已改为项目内+SHA校验；历史绝对路径不再访问旧副本，新Blender输出使用res://。Godot路径14项、Python路径8组、两组真实GPU流程通过。Godot MCP本轮报Errno22，Blender MCP4.2.2已恢复；未保存/改动用户原blend场景。下一步优先真实层间贴合及过渡自交，不继续改变素体，也不把纹饰隐藏当修复。详细复现/限制见当前HANDOFF。

## 第9轮：同骨架穿着引导与坐垫，仍为候选

`export_wearing_simulation -- --bone-targets --nap=0`使用真实Hips/双Thigh/双Shin引导一个裙筒，原身体、22骨rest、基础pin和站立网格不变；132776检查通过。`export_bench_cloth_support`导出实际支持位置的坐垫，静态最终nap0用途，不是完整起坐路径。

Blender MCP原生Cloth+真实坐垫后，`captures/wearing_bound_simulation_nap0_blender_supported.json`在原渲染三角形上的非相邻自交0、身体/坐垫交叠0、腿中心包含16/16。相应`_proof.png`为真实Godot对照：双方仅主裙面，未传递包边。几何候选通过不等于外观通过，仍有裙摆凸角；默认角色未加载它，冻结素体hash保持。

粗代理回传81对自交、旧RestCloth引导+坐垫209对自交，均拒绝。新增`--preserve-sections`四元数截面保持试验导出154303检查通过，但模拟34对自交，亦不采用。禁止把“无身体交叠”单独当作穿着完成。完整来源/复现/局限见根HANDOFF第9轮；下一步依附层同步、轮廓保形、坐卧与过渡验证，旧4类严格层失败仍开放。

## 第8轮：正确穿着的原生验证，未默认接入

本轮生产身体/服装算法未改。失败的中心跟随修形移至 `tests/experiments/rejected_centroid_pose_binding.gd`，只供诊断；它引入自交，禁止默认启用。原隔离截图/JSON已恢复为生产基线，实验另用前缀。

`export_wearing_simulation.gd`导出原1025顶点裙面和实际身体动画：腰口随真实骨架，其余由Blender原生布料求解，不再先使用旧坐卧衣形。nap0/nap3各88633检查通过，身体数组、22骨rest、源文件hash保持，逆蒙皮误差2.39e-7。Blender MCP通过 `simulate_wearing_blender.py` 创建独立Scene，顺序180帧；未改用户原Scene、未保存用户blend。

原生nap0最终身体三角面交叠0，虚拟封口裙体内16/16腿截面中心；仍有8对非相邻自交，存在碎褶与腰部衔接问题。包含抽样不等于全体积/连续碰撞，且没有长椅碰撞体。普通平滑及后续Outside Shrinkwrap都重新引入身体交叠，已拒绝、不接入。这里只证明同骨架带动的物理穿着值得继续验证，不能作为已完成通用衣物物理。

Godot实际回导对照 `captures/native_wearing_proof.png`，左生产、右原生试验，双方暂排除裙饰。`native_wearing_capture.gd`是唯一读取新native数据的入口；默认角色不读。下一步先做包覆/开口/关节对应与活动余量约束，然后在接触约束内保形，补bench支撑及各姿态和叠层。根HANDOFF详列复现步骤与所有拒绝结果。

## 用户纠偏：正确穿着优先于碰撞补偿

用户明确指出核心是小人没有正确穿进衣服。当前衣物有蒙皮，但旧`rest_cloth.point()`生成的坐卧衣形与新素体真实骨骼运动未统一，不能再以事后逐顶点推出解决基础穿着错位。冻结素体与已认可站立外形，先建立肩口/袖根/腰口对应与关节活动余量，服装随同一骨架运动；裙子保持包住双腿的松量空间，再接惯性/重力/叠层接触。

隔离证据：`rest_contact_isolation_capture.gd`完成12张三套服装四睡姿GPU图，raw裙面完整但腿穿出，原contact产生碎面；最近出口也不能保证正确穿着。LongSkirt焊缝重复顶点未分离（约7.75e-17），现有shader已双面。Blender MCP原生BVH对CPU等价导出检查，sleep0自交对0->532、最大边长比46.98，见`captures/rest_contact_blender_before.json`。原方向接触会发生近表面点跳到胶囊远侧的问题，不能只禁用背面阴影或加厚裙子掩盖。

此轮生产脚本未改，仅诊断；新ring膨胀helper的委托已要求停止且不接入。下一步应先修穿着/姿态对应，不能将这一诊断通过误写成修复完成。通用自碰撞、连续碰撞及CLO等效仍未实现。

## 第6轮：轮廓张力与接触包络一致

`garment_shape_profile.bridge_tension`为0时沿用局部传播，增大后将外扩修正沿根/末端间的轮廓传播，不向内削素体，也不把布贴进身体凹处。Resource默认0，游戏默认裙筒0.85、身筒0.8。前后侧松量及contour_strength仍分别控制；根/下摆锚定，袖片不参加本轮修形。预览台新增Contour reach/tension，真实控件、切装及预设回填已测试。

`cloth_body_contact.build_rest_envelopes()`提取原14个碰撞包络供绑定拟合共享，尺寸和骨点未改。`accepted_body_fit`先对非袖筒区域考虑该包络，再应用轮廓传播；关闭张力恢复旧顺序。它不是每帧全网格解算，更不是以改变身体来适配衣物。张力是美术参数；布料抗弯/抗拉/阻尼仍属于fabric资源，不能将该0..1张力宣称为CLO标定物理。

诊断及截图：`garment_contour_diagnostic.gd`18记录/71779检查0失败；`garment_contour_capture.gd`在同相机下展示旧0/0与新0.85/0.8。`captures/contour_bridge_manifest.json`记录源SHA、真实RTX4060、417143检查及空失败列表，文件写入检查另计。腹前抱手style0侧部截面回缩约2.43到0.20、后侧5.49到0.21，单位仅为模型坐标换算毫米；不是CLO测量或碰撞穿透深度。A/B分别查看idle、hands_abdomen、walk，不以单图代表全姿态。

本轮形状10550、法线13、惯性10949、接触148、库存休息131525、身体/换装2166666项与材质连续性全部通过；GPU操作台11图/64帧、常用姿态13图/39组完成，动图重编码。三个素体/rig冻结源码SHA保持一致。截图有限值/身体一致检查不等于衣物接触全过。

**明确未通过**：严格layer_skinning完整256姿态/3385344顶点仍4类失败，exit1，未放宽检查。站立手臂挤压处仍有内凹；实际`layered_sleep_0.png`俯视可见裙摆破面，侧视较好不能掩盖此问题。下轮先隔离睡姿morph/接触/层偏移，核对内层位移与最近面；任意轴控制、通用自碰撞和连续碰撞均未完成。Godot MCP静态校验可用但bridge不通，GPU图来自CLI。

## 第5轮：衣形曲线与裙摆惯性

审查修正：固定步长内累计帧输入，支持240/480FPS短促加速；禁用/坐卧保持速度历史，恢复不额外冲击。法线重算合并平滑UV缝、保留硬边。新增`garment_shape_normals_test.gd`13项0失败，惯性10949项0失败。预设FileDialog保存/读取、数值/开关同步已通过GPU回归。上述测试仍不是全姿态零穿模证明。

库存衣物的坐卧morph现与折叠4目标共存，构建时插值保留、穿着时同步当前权重，挂衣/折叠时清除休息权重。`garment_inventory_rest_test.gd`131525项通过，包含绝对/相对morph、切分、源数据不变、实际顾客坐姿/四睡姿及混合、穿脱与UV2。完整身体回归和材质连续性已复跑通过。用户已认可调试菜单样式，后续工具沿用大预览、侧边参数和曲线直接操控；不扩大为服装美术验收。

- 调节入口：`res://scenes/garment_lab.tscn`，静止/转圈/启停/步行、三套衣服、拖动曲线和数值框。保存/读取`garment_lab_preset`资源包含衣形与布料参数；它是预览预设，不会自动覆盖NPC默认资产。
- `GameBodyDoll.skirt_shape/shell_shape`是`garment_shape_profile`资源，提供前/后/侧松量与保形Curve、根/末端高度和局部扩散范围。只对衣物非袖网格做绑定姿势修形，再传播到原有叠层。当前竖直筒实现不等于任意路径编辑器；袖子的轴向控制与3D截面柄待做。
- `skirt_fabric`与库存`GarmentDefinition.fabric_physics`支持密度g/m2、厚度mm、抗弯/抗拉/阻尼0..1、褶数/褶深与运动自由度Curve。厚度独立于面密度；褶内面积参与质量和可展开余量。参数方向借鉴[CLO抗弯](https://support.clo3d.com/hc/en-us/articles/115000483187-Adjust-Bending-Weft-Warp)、[内部阻尼](https://support.clo3d.com/hc/en-us/articles/115000512908-Adjust-Internal-Damping)、[面料指南](https://support.clo3d.com/hc/en-us/articles/360001436227-CLO-Fabric-Guide)，数值没有宣称对应CLO单位或实测材料。
- `garment_secondary_motion`以真实body_rig世界变换差计算输入，固定120Hz求9圈扭转/张开/平移；转身时重定位现有摆动的坐标框架。采用已有PleatedSkirtDynamics的弹簧思想，不调用会重置身体动作的旧`pose_on_doll`。不重复积分，不用预设spin时间假装真实NPC惯性。
- UV2.x是绑定姿势的根至裙摆坐标，UV2.y标记启用；GarmentForms切分时插值保留。三种cloth shader在身体接触前应用同一变形，CPU诊断及接触代理同步，法线由变形后的切向更新。腰口固定，坐卧状态平滑关闭惯性、保留已验收方向的休息morph。裤子/素体/肩袖不套裙摆运动。
- 验证和截图见根HANDOFF最新条目。`garment_upgrade_manifest.json`、11张操作台/三服装静动截图及64帧动图均来自实际Godot GPU；`layered_*`覆盖抬手、四步相、坐下和四睡姿。本阶段不宣称任意多层穿模已解决：站立局部鼓起、既有四类层间距失败、袖子任意轴编辑、百褶资产管线完全统一、低端设备性能基准仍待完成。

## 续作：层接触与开放裙摆

本轮基线三个文件（accepted_body_v20、shorter_arm_body、doll_rig）SHA256均未变。以下更新优先于后文第一阶段说明：

- LongSkirt/Trouser去掉实心封盖，真实腰口和下摆开口。原先的封盖在坐卧时横切腿部，不属于可用的布料拓扑。原始姿态导出检查确认裙网格有两个开放边界圈。
- `cloth_body_contact`现为14个身体接触包络，补手掌；裙侧沿衣面法线退出躯干/腿部，避免最近出口落在两腿之间；手臂一侧向内压让，不把裙布包到手上。
- `cloth_surface_proxy`使用内层LongSkirt/TailoredShell的12圈实际网格采样，随骨骼、重力morph更新。袖子绕开内层、外层及二级口袋/门襟分开层距；肩根锚定，仅在肘/袖口逐渐释放。通过几何SHA缓存采样，穿上库存衣物时切换真实来源；弱引用避免持有已释放节点。
- `rest_cloth.fit_layer`的折叠面约束位移限幅，避免矛盾平面反复推出马甲尖角。
- `cloth_body_contact.evaluate_vertices`是对应GPU接触的CPU诊断路径，不用于每帧全网格更新；包括休息法线和层间偏移。它仍不是GPU顶点回读。
- `layered_cloth_capture.gd`输出13张/39姿态/78视角GPU图及manifest；walking/raised_reach/hands_abdomen/bench_sit/sleep_0..3已查。`game_body_rest_0..3`是双人近景，`game_body_shop`仍是临时展示站位。
- `export_accepted_rest_contact.gd`输出5种RAW休息姿态，1025裙顶点/1920三角形/3身体部件；前向误差2.41e-7、逆变换误差4.87e-7。供未来Blender离线修形，**本轮没有加载新的烘焙资产**。

参考[CLO Layer](https://support.clo3d.com/hc/en-us/articles/115012381588-Layer)和[CLO碰撞厚度](https://support.clo3d.com/hc/en-us/articles/115002798068-Adjust-Collision-Thickness)的分层与厚度原则。实现仍是游戏实时近似，不是CLO求解器；没有通用连续碰撞/布料自碰撞保证。Blender对最新325组网格/姿态仍有候选交叠，报告包括隐藏内层，必须结合实际截图判断。

最新严格层诊断：256姿态/3,385,344顶点检查完整执行，Apron坐姿、Pocket睡姿混合、OpenWaistcoat行走下缘、FrontBinding坐姿四类签名平面间距失败，退出码1，不是全绿。绑定三角形的平面在接触后可能发生滑移/折向，负值不等于最近面的穿透深度。下一步是精确底层位移传递/最近面接触验证与对应中间姿态截图，不能靠放宽测试或不断增加offset掩盖。

## 不可改的基线

`accepted_body_v20.gd` + `shorter_arm_body.gd`，`arm_shortening=0.045`。本轮这两个文件未改。身体、掌形、肩胯、头发、鞋及身体蒙皮数组都与已确认素体精确比较；没有缩小身体或隐藏真实人体来回避穿模。

游戏使用 `game_body_doll.gd` 继承此基线。员工、顾客、路人、邮递员、Catalog、摩梭及乌克兰入口已接入。独立裸模场景 `accepted_mannequin.tscn` 仍可查看基线，不要将实验素体当默认。

## 衣物如何适配

- `accepted_body_shell.gd` 保留获认可的身筒加两只内嵌袖片的构造，三块蒙皮面板，不是新雕刻肩球，也不声称已经焊成一张拓扑。仅增加有限细分，缓存未拟合几何。
- `accepted_body_fit.gd` 从真实素体环截面读取包络，将衣物推出体表，袖长随已确认短臂量同步。衣物层通过三角形/重心坐标跟随底层；肩带重新贴合，纽扣保持刚性外形。
- `game_body_doll.gd` 从袖口边界生成包边、补齐默认裤装腰胯遮盖。坐姿在保留臂长的前提下调整手部IK目标，让掌心放到裙面上；未改共享休息骨架。
- `cloth_body_contact.gd` / `cloth_contact.gdshaderinc` 在蒙皮后用12个随骨骼运动的椭圆/锥形胶囊约束衣物。上衣接触手臂，裙子不被放在膝上的手臂挤成鼓包。外层与包边有独立层间距。
- 工坊新布料材质也支持接触参数。挂衣、折叠、提取状态关闭人体接触；穿上后同步当前顾客的骨架和接触场。纽扣、花饰不做逐顶点径向膨胀。
- 原有休息裙摆重力修形、Blender重力烘焙和姿势混合继续保留，没有改成贴腿的两根筒。

## CLO 借鉴与边界

按 CLO 区分 Avatar Skin Offset、Collision Thickness、Rendering Thickness 的思路，`cloth_contact_profile.gd` 分开导出 `skin_offset`、`collision_thickness`、`rendering_thickness`、`layer_gap`。在角色 configure/重建前配置 Resource；不是运行中即时重新打版的滑杆。

参考：[CLO碰撞厚度](https://support.clo3d.com/hc/en-us/articles/115002798068-Adjust-Collision-Thickness)、[Particle Distance](https://support.clo3d.com/hc/en-us/articles/115000414447-Particle-Distance-Setting)、[Simulation Properties](https://support.clo3d.com/hc/en-us/articles/30201166554649-Edit-Simulation-Properties)。这是游戏侧实现选择，不等同于复刻 CLO 的求解器。

**尚无通用连续碰撞检测、自碰撞、任意叠层布料求解。** 当前是静态拟合、蒙皮后接触投影、既有重力修形的组合。Blender BVH诊断仍检出候选交叠，尤其静止手臂/裙侧及内藏的身筒/袖片；不得把接入成功或有限姿态通过说成绝对无穿模。

## 验证与截图

- `tests/accepted_game_body_test.gd`：2,152,310 checks，93,772顶点检查，36姿态，6轮换装，0失败。验证素体所有数组、22骨rest、显隐、权重、穿脱连续性、换布料保留接触参数、折叠关闭接触。
- `tests/postal_clothing_test.gd`：240姿态，原有大衣对裤装采样接触测试0失败。不是全身所有表面的碰撞证明。
- `tests/garment_material_state_test.gd`：0失败，修掉测试自身未释放的colored_part，复跑退出无泄漏告警。
- `tests/ukrainian_wardrobe_test.gd`：UKRAINIAN_WARDROBE_PASS。民族服装全套多角度新素体美术验收仍未完成。
- `tests/game_body_fit_capture.gd`：站立、行走、抬手三套基础服装真实Godot GPU截图 `captures/game_body_idle.png`、`game_body_walk.png`、`game_body_work.png`。
- `tests/game_body_rest_capture.gd`：真实长椅支撑的四种睡姿和坐姿，`captures/game_body_rest_0.png`到`_3.png`。未覆盖用户原来认可的`rest_refined_top.png`。
- `tests/game_body_room_capture.gd`：加载真正main场景，临时将三位现有员工摆在前店展示，保存`captures/game_body_shop.png`。不是自然经营流程截图；未改存档或默认员工位置。
- Blender MCP执行`tools/check_accepted_cloth_blender.py`，读取`game_body_contact_input.json`并输出带输入SHA256的`game_body_contact_report.json`。27个网格/姿态组合中23个仍有候选交叠。诊断忽略渲染法线偏移、包含被外层遮住的内部表面，不替代GPU观感，也不是零穿模验收。

Godot4.7.1 CLI GPU出图；Godot MCP本轮编辑器bridge不可达，未冒称MCP截图。Blender MCP真实连通并使用native BVH，未覆盖用户Blender场景。Kimi/DeepSeek本轮不可用；已完成本地代理测试后主代理复核。

## 后续优先级

1. 先由用户确认此次穿衣外观，不再改已确认素体。肩袖连续性/跨身动作应继续以真实近景检查。
2. 对静止手臂与裙侧、极端抬臂、手提商品、贴身外套及所有民族套装增加逐姿态接触验证；要区分内部遮蔽交叠与可见穿模。
3. 把任意新服装的低分辨率碰撞代理、层级、自碰撞约束及Blender离线服装修形烘焙做成资产管线，不能靠无限加大offset。
4. 启动仍偏慢。本轮细分从4次/.06边长降到3次/.10后，同机两次主场景初始化从81965ms到41518ms；非严格基准。还需程序化服装/绑定缓存与库存惰性初始化，不能说性能已解决。
5. Hosiery对新`LegMannequin`的覆盖适配未完成，不要悄悄改素体UV2或裁掉腿来修袜子。

早期本轮诊断图`game_body_work_cpu.png`、`game_body_sit.png`、`game_body_nap.png`不是最终验收截图，不要用于交接或替代上述最新图。
