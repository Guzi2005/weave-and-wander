2026-11-10：Wiki 已迁至独立 Git 工程 `D:/workspace/W&W Wiki`；下方历史路径仅供追溯。

# 独立游戏工程交接入口

2026-11-10：游戏及 Git 根目录是 `D:/workspace/weave-and-wander`。从本目录启动 `project.godot`。历史总交接已复制到本目录的 `WORKSPACE_HANDOFF_2026-11-09.md`；开发日志在 `DEVELOPMENT_LOG.md`。本文件现在是独立游戏工程的当前交接，不再跳到旧工作区。

## 当前目标与红线

2026-11-11 补充：用户已另行授权机制扩张与美术改进，桌面物件、箭头翻折、后街耗材摊、杂志、成长、日账和稳定点存档的首版已接入。详细范围、验证与剩余内容见 `DEVELOPMENT_LOG.md` 的本日记录及根目录 `DEVELOPMENT_STATUS.md`。下文服装实验仍保持原裁决；本轮没有把失败实验替换为默认衣物，也没有修改冻结素体。

用户已解除暂停，要求对齐迁移地址后继续服装升级。先让衣物正确穿在同一副骨架上，再做碰撞、叠层和裙摆惯性；不能继续以碰撞膨胀来补偿错误穿着。保留已认可的简单、平滑圆锥衣形与调试台样式。裙子围住双腿，不是两根裤筒。参考 `reference-body/accepted-clothing-20261110.png`。

严禁改变已确认素体/身高/肩袖锚点来掩盖衣物问题。迁移后再次核对的冻结 SHA256：

- `scripts/accepted_body_v20.gd`: `6F2E31D49DD5CE940FC06D3A9BEC77CD0116306F780CB246F4FEA7A07875E002`
- `scripts/shorter_arm_body.gd`: `DCA12562669786418A195EC5D087EB8A0E634F3D2DD27C1A777875596A9B3A3E`
- `scripts/doll_rig.gd`: `E8E8AC3EE5D2FCEAB3A7EC340E421F8FEF68122CDB40CE7E054D3E21984365B5`

当前工作树有大量来自用户和其他 agent 的未提交修改，包括发型工作。不要 reset/clean、批量提交或改动无关模块；不要向仍指向旧共享仓库的 remote 推送。旧 `D:/GodotProjects/weave-and-wander` 是另一套 2D 工程，不是本游戏的默认写入位置。

## 最新视觉裁决：侧面保留current，只借native的裙口角度

### 额度保留停工点 / 2026-11-10

用户要求留下15%账户额度。最新实际工具读数为周窗口剩余16%（没有独立5小时窗口读数），本线程提前留出收尾缓冲，不再启动长模拟。当前任务未完成、默认游戏未更换。继续前先确认额度与用户是否解除停工条件。

新增隔离工具`tools/current_hem_study_blender.py`和回归`tools/test_current_hem_blender.py`。固定current中上段，只让下摆朝native裙口法向转动的首轮`.011`，180帧已结束，输出`captures/wearing_seamed_simulation_nap0_blender_current_local_hem.json`。它保留上段位移<=1.34e-7，但有273对自交、左右腿相交264/260对，明确拒绝，不是可用新衣形，也未生成可宣称改善的截图。

新独立边长检查暴露旧current接触修正自身的大拉伸：同一1106点拓扑，以站立网格为参考，全局最长边比12.858、裙口区域5.121；新局部候选分别14.116、5.124，未改善。1.1只是筛查阈值，不是实测面料弹力上限；这些是3D网格边长比，不是二维纸样经纬应变。应保留current的视觉轮廓，而非锁死所有已畸变三角形。

**续做卡点**：Blender4.2.2源码中rest shape index0/Basis不读取独立静止形态。试验工具新增非零`FabricRestMetric`请求，但实际小布片回归仍失败：从宽2、静止宽1开始，无重力60帧，两种设置都仍宽2。缓存有效；有重力诊断能下落，证明并非整个仿真没运行。加无拓扑变化的Triangulate仍未解决。不能把非零键设置成功当成静止布长已生效，更不能盲跑完整衣裙。回归3项应变计算通过、1项实际solver失败，记录`captures/current_hem_regression.json`。新输出标记`rest_metric_validated=false`；旧`.011`没有启用新请求，旧报告关于静止布长的说明不构成证据。

下一步先修复/验证原生静止长度传递的最小布片回归，必要时用真实静止首帧再连续穿着的路径对比；查明后再做current轮廓约束与局部布长重分配。必须同时检查裙口角度、圆润侧面、应变、身体/布层碰撞和动作过渡；不要再次整版替换为native。此前45/62运行时接触问题仍未消失。三个冻结素体SHA再次一致。本线程无后台模拟/子进程，Blender恢复用户`Scene`且未保存用户blend；其他agent的日志、UI与模型修改未覆盖。

用户最新原话：**“侧面睡姿current完胜了，除了裙摆开口角度native那个更合理（不硬拉伸面料超过弹力范围）但圆润、整体程度依旧current胜”**。

这是本线程当前最高优先级的外观判据。不能把下方`silhouette_review`或其他native候选当成新的已认可外形；数值无交叠也不能抵消它在圆润、整体感上的退步。侧面以**生产current/A**为主，保留腰胯体积、圆润贴垫下缘、连续完整的一体裙身。native只用于借鉴**裙摆开口的倾角与自然余量**。此前四处红线仍作局部参考，但不表示用户同意采用整版native。

下一次改动必须缩小为**下摆开口附近的局部转折/垂落**：保持current腰胯与中段的视觉轮廓，不将整条裙子压成native的斜直轮廓，不改身体/腿脚/睡姿。先检查现有面料参数与网格静止边长，再约束局部拉伸；通过转动、折叠、布长重新分配形成合理开口，不用拉长面料硬凑角度。不能承诺CLO等效物理。验收同时包含与current的侧面轮廓对比、材料伸长限制、身体/布面相交检查。此局部方案尚未实现，本轮只记录了新的明确取舍，未再更换默认游戏。

下方候选、截图及失败数据保留作为诊断，不删除不覆盖；最新用户裁决也已追加本地DEVLOG与完整开发日志。

## 前一条用户标注：四处轮廓组合，不是A/B二选一

2026-11-10。本节优先于下方历史。用户原图已原样保存在`reference-body/sleep-silhouette-guidance-20261110.png`，SHA256 `73cde963cf59f14e350829c5806a10a310eb63e251fed7e25984c39d6d411a22`。四个红线都代表希望采纳的优点：左上腰胯到屈膝的弯曲背侧，左下圆润转折且贴垫的下缘，右上宽松连续弧形下摆，右下有内部空间/自然露出小腿的裙口。**不能简单选整版A或B，也不能将相交清零等同视觉验收。素体与已确认姿势不改。**

### 当前可看候选

`captures/wearing_seamed_simulation_nap0_blender_silhouette_review_surface_layers_proof.png`，左原A、右新候选，上俯视下侧视。新背侧更随屈膝弯曲，保留开口，但贴垫下缘仍不完全达到左下标线的圆润感，用户尚未验收。默认游戏没有启用此候选。

`tools/shape_sleep_silhouette_blender.py`从原A真实渲染等价几何提取背侧/下缘投影包络，作为B布面的形状引导；不是把A的碎褶复制过来。直接改顶点会与两腿相交243对，且HemRibbon接缝不收敛，已拒绝。新方案从无交叠B快照开始，身体固定在原nap0，用Blender原生Cloth对目标轮廓做柔性拟合：back=.65、seat=.85，最终guide=.35，quality30/collision5，顺序180帧。**这是固定睡姿中的重新拟合，不是站立到睡觉的180帧动画。**源Scene目前`.010`，默认恢复用户`Scene`且未保存blend；重启后不能假设缓存/名称仍存在。

- 最终`silhouette_review.json`及真实GPU回导的主裙、HemRibbon、FineHemRibbon、WaistRibbon自交/相互交叠/身体及坐垫面相交均0。静态审计文件为`..._surface_layers_proof_geometry_blender_layer_audit.json`。腿截面中心16/16仅是辅助包含检查，不是全部体积/CCD保证。
- 导出守卫验证身体仍为原nap0、首帧确实从原安全B网格开始（均<=1e-6）；三个冻结SHA未变，原A mesh/morph/material完整恢复。实际GPU由Godot CLI/RTX4060执行，MCP项目查询仍Errno22；Blender MCP可用。
- 较弱guide=.06的`silhouette_fitted`只有很小视觉变化，且HemRibbon仍1对自交，不采用。`.35`旧标签`silhouette_fitted35`与`silhouette_review`几何相同，后者补齐首帧/身体守卫，是当前证据入口。不是继续提高刚性pin或改变身体。

### 过渡测试揭示的真实未完成项

新增`tests/native_wearing_transition.gd`，从真实bench入口位置开始，用现有`support_actor/release/simulate`进行起身/躺下，62个采样、6张GPU图。**测试PASS只表示流程/不变量正常，不表示碰撞通过。**`waist_review_runtime_transition.json`独立审计仍45/62采样有衣物相交，峰值self17/layer37/body184/cushion374；身体自身与坐垫最多153对，说明支撑位移过渡另有问题，不应改素体/终态睡姿掩盖。静止睡姿端点仍0，站立端点饰带仍31对。新silhouette_review尚未做其自己的起身往返验收。

修复实验饰带只含一个RestNap却被rig按5个姿态通道访问的错误：`native_layer_transfer.gd`现在按源顺序继承全部morph及UV2，新增12项回归，接缝总26项通过。首次runtime运行即使打印PASS也有引擎错误，已作废并重跑；最新`captures/waist_runtime_transition.log`无ERROR。测试必须同时检查日志与退出码。

其他拒绝试验：移动腰框内对称时间滤波仍13/180自交且5帧越位移守卫，保持默认关闭；quality60/collision10仍90/180自交，拒绝。不要把这些再当作下一基线。新`test_sleep_silhouette_blender.py`8组覆盖轮廓/滤波/几何检查守卫，既有attachment7组、cache7组、Godot26项和惯性10949项复跑通过。

### 下一步

1. 对照用户四处红线继续收敛贴垫转折和背侧曲线，保持宽松裙口与素体不变；这次不是四处已全部完成。
2. 将最终衣形与真实起坐/躺起的支撑轨迹分开验收，修饰带站立及中间姿态，不直接线性混合终态就接回默认NPC。
3. 再覆盖其他睡姿、坐姿、走路、多层袖片与库存穿脱。旧15/180原生动态自交报告仍保留，不与本次静态拟合混称。

复现最新截图：沿用下方命令，将proof换成`res://captures/wearing_seamed_simulation_nap0_blender_silhouette_review.json`。所有实验仅在本工程`tests/`、`tools/`、`captures/`，没有改生产身体/默认服装；本地DEVLOG及完整日志同步更新。

## 前一轮：最终姿态的裙面与三条饰带通过，连续动作仍未通过

2026-11-10。本节优先于下面的历史试验。新增`tools/attach_waist_seam_blender.py`，保留已验证的原生布料结果，在真实腰线新增点接回Hips，再只对自由布面做局部原生整理。它是**原生模拟加局部后处理的混合候选**，不是新一轮完整物理模拟，也没有接入默认NPC。素体三个冻结SHA、生产GameBodyDoll及已认可骨架不变。

最新候选是`captures/wearing_seamed_simulation_nap0_blender_waist_review.json`。它从完整动作中已有的自交面建立固定修整邻域296点，factor=.25、3次，不随帧临时换邻域。最终最大整理位移.007797模型单位；固定腰口误差5.96e-8。不要把下面已经拒绝的更强平滑作为下一基线。

- **最终姿态实测通过的范围**：style0/nap0，主裙、HemRibbon、FineHemRibbon、WaistRibbon的自交和相互交叠均0，与真实躯干/双腿/坐垫均0。真实Godot RTX4060图为`captures/wearing_seamed_simulation_nap0_blender_waist_review_surface_layers_proof.png`，左侧生产A，右侧实验B，上俯视下侧视。独立几何审计为同名前缀`_surface_layers_proof_geometry_blender_layer_audit.json`。没有覆盖上衣袖片、其他衣装或所有时间点。
- **连续动作未通过**：`_waist_review_motion_audit.json`逐一检查180个有效缓存帧。主裙身体/坐垫交叠0，位移守卫无失败，末帧复现静态结果误差0；仍有15帧布面自交：103、104、112、113、114、120、122、124、125、129、150、151、161、162、167。仅检查主裙动态，没有动态饰带、CCD或全体积保证。输入是站立到躺下及静置，不是完整起身往返。
- **拒绝候选**：相同296点改factor=.4、4次，虽剩4帧自交，但95/96/101帧碰到坐垫，92/99/100帧超.02位移守卫；最大.026881。保留`_motion_attached_f4{,_audit}.json`作失败记录，严禁默认使用或提高容差掩盖。
- **工具修复**：新建Blender场景后，同一次脚本内`frame_set(1)`可能仍让Pose_1=0、Pose_2=1。此前审计错误地反复读末帧，179个保护点位移失败是工具缺陷，不是真实布料表现。检查器改为单个显式值1的形态键、无F-curve，并显式更新数据；必须验证末帧与独立静态proof完全复现。旧的33接触帧/179守卫失败数据作废。
- **验证**：新增`tools/test_waist_attachment_blender.py`7组通过，覆盖新场景首轮/连续形态键更新及失效种子拒绝；缓存7组、Godot腰线细分2836、surface接缝14、裙摆惯性10949检查均复跑通过。Godot桥仍Errno22，实际GPU截图用CLI；Blender MCP真实执行，恢复用户Scene，未保存blend。

重现最终截图：

```powershell
& 'D:/Godot/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe' --path 'D:/workspace/weave-and-wander' --script res://tests/native_wearing_capture.gd -- --proof=res://captures/wearing_seamed_simulation_nap0_blender_waist_review.json --layers --bind-ribbons --surface-ribbons
```

Blender内原生来源仍是`WW_Wearing_Physics_Experiment.005`的完整缓存；先核对source/SHA/缓存，不要假设重启后仍有同名场景。动态检查调用`attach_waist_seam_blender.py::audit_motion(proof_reference, native_scene_name, output_tag)`。proof依赖base_native_proof及motion_seed的SHA；不要覆盖被引用的旧报告，后续产物使用新后缀。下一步先把上述15帧按实际相交面和中间姿态出图定位，解决修整与碰撞约束的冲突，不再盲加平滑/扩大固定区。再验证动态饰带、坐姿/其他睡姿和库存穿脱，最后才允许进入默认游戏。

## 前一轮：真实腰带边界细分（模拟仍未通过）

2026-11-10，保持三个冻结SHA、生产GameBodyDoll和默认角色不变。新增`tests/experiments/garment_seam_split.gd`，只在隔离导出/回导中沿实际WaistRibbon下边界切分跨界三角形：原1025顶点不移动，新增81点，1106渲染顶点/1080焊接模拟顶点。原静态表面面积不变；新点继承4骨蒙皮、UV/UV2、材质及全部normalized morph。拒绝不支持的custom stream和跨切线手性接缝，不静默丢数据。

`tests/garment_seam_split_test.gd` 2836检查通过，覆盖原站立位置、表面面积、原站/走/坐/睡姿顶点轨迹、morph插值、UV2惯性坐标、权重、幂等；ArrayMesh重新编码带来法线/切线约7.79e-5/4.05e-5的量化误差，单独检查而非宣称bitwise一致。导出158081检查通过，新增命令：

```powershell
& 'D:/Godot/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe' --headless --path 'D:/workspace/weave-and-wander' --script res://tests/export_wearing_simulation.gd -- --bone-targets --attach-waist --split-waist
```

源为`captures/wearing_seamed_simulation_nap0.json`。A/B回导识别mesh_seam后仅对B细分，A原始快照完整还原。上轮local_fold_validated旧proof仍GPU回导通过。14项surface接缝测试也通过。

**以下新增模拟均拒绝，未替代上轮候选**（全部真实顺序180帧、有缓存校验、身体/坐垫交叠0）：

| 新源输出后缀 | 最终主裙自交 | 有交叠帧数 | 说明 |
| --- | ---: | ---: | --- |
| `_blender_waist_seam` | 110 | 74/180 | 精确腰线、guide0、原三角形、self gap .008 |
| `_blender_waist_seam_finish` | 98 | 72/180 | 加局部整理180点，未解决 |
| `_blender_waist_seam_gap4` | 63 | 98/180 | 只把self gap改.004，无整理，过渡反而更差 |

`.006`为前两者（目前含整理且缓存完成），`.007`为gap4。scene名仅是当前观察，不保证跨重启；用户原Scene恢复且未保存blend。全帧报告为各输出加`_full_motion_audit.json`。精确边界使surface-ribbons不再触发最大偏移拒绝，但独立几何审计原waist_seam仍182对（主裙自交110+裙/腰带72）；两条下摆饰带0、身体/坐垫0。GPU截图`wearing_seamed_simulation_nap0_blender_waist_seam_surface_layers_proof.png`不能当作验收。

另有只读方向检查`captures/wearing_waist_attachment_diagnostic.json`：保留上轮1025个模拟点，仅把81个新增腰线点约束到真实hip目标，最大调整.009897，最终4对局部自交、身体/坐垫0；不是新物理结果，也未做GPU/过渡验收。21个身体/坐垫输入采样未发现相交，因此不能把问题归罪于未经证实的身体穿椅路径。下一步应处理腰口到柔性裙身的局部过渡/约束，检查这4对的根部关系，并保持原模拟主体；不继续以扩大pin或降低碰撞间距作盲调。之前16/180帧的local_fold_validated仍保留，默认游戏仍不读这些proof。

## 上轮续作：局部折返改善与缓存校验（仍未默认接入）

2026-11-10，本轮继续使用新根目录，三个冻结SHA与上文完全一致，未改素体、生产服装或其他agent的发型/帽子工作。Blender MCP 4.2.2可用，Godot MCP项目查询仍报Errno22；实际GPU截图来自本项目CLI/RTX4060。

1. `tools/audit_wearing_targets_blender.py`新增输入轨迹审计。one-row和bound引导均有12/21个采样帧自身相交；whole-cell固定方案还有3个采样帧的全固定面与身体相交。弱引导相交不等于模拟一定失败，但全固定面/身体冲突不能靠提高布料质量解决。报告为各源文件的`_blender_target_audit.json`。
2. 新`.005`为one-row原三角拓扑、guide_weight=0、dynamic_rest=false。完整180帧最终仍4对自交，60帧存在交叠，故单纯关闭弱引导无效。精确定位发现主要折返面来自restY=1.082..1.128，折回到腰带附近；不是简单把腰带固定得更宽即可修复。
3. `tools/refine_wearing_folds_blender.py`新增隔离的原生CORRECTIVE_SMOOTH局部整理：由相交面生成固定rest邻域，排除所有全固定顶点，factor=.25、3次、4圈，实际影响73顶点。最终最大位移.006476（模型单位），全固定顶点和邻域外位移均0。它是后处理试验，不是实时碰撞求解器。
4. **重要缓存坑已修工具**：改modifier/顶点组会使Blender布料缓存过期。此前只看`last_simulated_frame=180`不足以保证有效，跳帧会读到停在旧姿态的布料。`simulate_wearing_blender.py`现在检查`is_outdated`、`is_frame_skip`、实际帧和顺序计数，拒绝无效导出；新增显式`restart(scene)`。安装整理后必须restart并顺序advance，不得只改参数后直接finish。7项缓存守卫测试通过；实际非最终帧导出被正确拒绝。旧无cache_validation证据只能作为历史候选，复用前重验。
5. **已重新从1顺序跑到180并逐帧审计**：`captures/wearing_attached_simulation_nap0_blender_local_fold_validated.json`，末帧主裙自交0、身体/坐垫0、腿中心16/16；全程仍16帧自交（此前60），全程身体/坐垫三角交叠0。包含中心点不是全体积保证，逐帧检查也不是连续碰撞保证。
6. 当前GPU对照：同前缀`_bound_layers_proof.png`，三条饰带保留可见、都有绑定，A恢复原状。**仅回导流程PASS，不是衣物验收**：独立审计普通绑定仍有饰带/裙面交叠61对（Hem/Fine/Waist为22/11/28），身体/坐垫0；`--surface-ribbons`在腰带处超过位移守卫而拒绝出图，不能提高阈值掩盖它。新图右侧主裙轮廓改善，但饰带和过渡仍不合格。61对与上轮surface模式8对不是相同条件，不得作为总改善宣称。接缝14项单测通过。

当前`.005`缓存重算到180且有效，最后恢复用户原`Scene`，未保存blend。不要相信scene后缀跨重启稳定。局部整理权重/seed与参数已写入proof的post_simulation_finish；此为seed姿态推导的固定邻域，尚未证明通用性。下一步优先处理真实腰带边界落在网格单元中间所导致的折叠和饰带厚度，再修102..114等过渡帧；需要考虑沿真实腰带边界分网格，而非把整排下移固定。仍不动素体、不隐藏饰带、不以单帧通过替代全流程。

当前截图复现：
```powershell
& 'D:/Godot/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe' --path 'D:/workspace/weave-and-wander' --script res://tests/native_wearing_capture.gd -- --proof=res://captures/wearing_attached_simulation_nap0_blender_local_fold_validated.json --layers --bind-ribbons
```

## 上轮服装续作：接缝厚度修正，腰部仍未通过

本轮在 `tests/experiments/native_layer_transfer.gd` 新增 `surface_follow`，在源三角形接缝处统一求解各相邻面的最小厚度约束。厚度取现有 rendering_thickness 和 fabric collision_margin 的较大值，并保留更厚的原有正向偏移；不改裙面、不隐藏饰带、不挪身体。48次有限迭代，有残差/最大位移拒绝门槛；无法同时满足的约束直接失败。

在原 fixed-rest 候选上加 `--surface-ribbons`，重新GPU截图并用Blender审计：HemRibbon和FineHemRibbon的交叠由22/11降至0/0；WaistRibbon仍与裙面交叠7对、自交1，总52降为8。主裙面自身及身体/坐垫仍0。证据为 `captures/wearing_bound_simulation_nap0_blender_fixed_rest_surface_layers_proof.png` 及相邻geometry/audit/manifest。仅style0/nap0最终帧；不是全服装或过渡验收。14项接缝单测通过，惯性10949项回归通过；三个冻结SHA一致。截图/审计现记录所用脚本SHA，防止把不同版本混为一次验证。

腰带问题不能靠继续增加刚性固定解决。原base mesh每排约.045，旧pin实际只全固定最顶圈；下一排能偏离约.091（模型坐标）。新增 `export_wearing_simulation -- --bone-targets --attach-waist` 读真实WaistRibbon范围，导出穿着锚定候选，不改站立顶点/身体/22骨rest。**以下四次均被拒绝，不能接默认游戏**：

| 候选输入/输出标识 | 最终主裙自交 | 最终身体交叠 | 180帧有交叠帧数 |
| --- | ---: | ---: | ---: |
| attached / attached_waist（quad，腰带顶点固定、下1排释放） | 4 | 0 | 79 |
| waist_edge / waist_edge（固定含腰带边界的整排单元） | 99 | 20 | 97 |
| attached_blend / attached_blend（下2排渐变释放） | 91 | 0 | 74 |
| attached / attached_triangles（与渲染一致的triangles） | 4 | 0 | 60 |

输入名形式 `captures/wearing_<标识>_simulation_nap0.json`；输出加 `_blender_<标识>.json`，全帧报告加 `_full_motion_audit.json`。全部180帧真实顺序模拟完成，Blender原Scene恢复且未保存blend。第一版最终4对集中在腰带下方原始y=1.22..1.31的网格；surface接缝求解对该候选触发最大位移守卫，正确拒绝出图。强行固定到1.22还与大腿活动冲突；不要再重复扩大刚性pin范围或只增加质量。

当前 `--attach-waist` 导出的是 `wearing_attached_blend_*` 两排释放试验（已拒绝），不是推荐解。下一步先校准腰口与实际身体/衣身的穿着对应及活动区，而不是继续以更强pin补偿；需要检查真实身体空间、腰带边界落在单元中的影响和过渡路径。保留已有fixed-rest+surface候选及未通过证据。实际全服装接口、所有姿态和库存连续性仍需通过。

本线程Kimi Harness只读审阅返回月额度429并结束，未产生修改；没有转额外计费API。本轮末观察Blender隔离scene `.001`..`.004` 均已模拟到180帧，缓存可供定位，但再次使用前仍应查实，不假设跨重启存在。并行agent正在写入发型/参数化服装台工作，未纳入本线程验收，不能覆盖或结束它的进程。

## 迁移轮证据与未通过项（52对是修接缝前基线）

- 默认游戏未加载任何新 Blender native proof。最近修改局限于 `tests/`、`tools/`、截图和交接文档。
- 暂停前的 fixed-rest 候选：`captures/wearing_bound_simulation_nap0_blender_fixed_rest.json`。同骨架引导、原生 Blender Cloth、真实坐垫，quad / bending12 / guide .005 / quality30 / dynamic_rest=false。最终主裙面自交0、身体/坐垫交叠0、腿中心包含16/16，但不是全体积/CCD证明。
- **完整180帧审计有47帧自相交**，见同名前缀 `_full_motion_audit.json`。三角模拟最终仍4对，quality60/collision10最终仍1对且过程中有坐垫交叠，均未取代该候选。不得把最终一帧无交叠称为过渡完成。
- `tests/experiments/native_layer_transfer.gd` 能从 LongSkirt 的源三角形派生并传递 HemRibbon/FineHemRibbon/WaistRibbon，三条均有来源、无未绑定饰带。它只证明绑定及数值有效，不保证碰撞。
- **新目录真实 Godot GPU + Blender MCP 独立审计**：`captures/wearing_bound_simulation_nap0_blender_fixed_rest_bound_layers_proof.png` 左A生产接触、右B候选，两行俯视/侧视。A完整还原，身体与骨骼不变。候选主裙面与身体/坐垫仍0；裙面与三条饰带候选交叠22/11/18，腰带自交1，总计52。几何证据是相邻的 `_geometry.json` 与 `_geometry_blender_layer_audit.json`，所以仍不能默认接入。
- 饰带旧径向偏移可能为负；关闭旧 contact shader 同时取消了 `cloth_surface_lift`。这是待检查的来源，不是已证明的唯一原因。不能直接无限加 offset 或隐藏饰带。实际截图仍有腰口锯齿、裙摆粗折，未达到用户认可轮廓。
- 原严格 `layer_skinning_test` 的 Apron/Pocket/OpenWaistcoat/FrontBinding 四类失败仍开放，本轮没有重跑或放宽它。袖子与独立多层衣物的通用接触尚未解决。

## 迁移后的工具与复现

所有 shell 命令明确指定新根目录；当前对话默认 cwd 仍可能指向旧 2D 工程。不要依赖它。

```powershell
Set-Location 'D:/workspace/weave-and-wander'
& 'D:/Godot/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe' --headless --path . --script res://tests/wearing_proof_paths_test.gd
& 'D:/Godot/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe' --path . --script res://tests/native_wearing_capture.gd -- --proof=res://captures/wearing_bound_simulation_nap0_blender_fixed_rest.json --layers --bind-ribbons
```

- 新 `tests/experiments/wearing_proof_paths.gd` 只从当前项目读取依赖。历史 proof 的旧绝对路径只能映射到当前 proof 的同目录同名文件，并要求 SHA 一致；不回读退休工程。14项检查通过。无坐垫旧 proof 分支也已 GPU 复跑通过。
- 新 `tools/wearing_proof_paths.py` 限定 Blender 输入在项目内、输出在 captures。新记录统一 `res://`，旧 scene 必须调用 `rebind_scene_sources(scene_name, source, support_source)` 显式重新绑定；所有输入（包括坐垫）哈希通过后才修改路径。8组 Python 测试通过。
- Blender MCP 4.2.2已重新连接。用户原 `Scene` 的 Cube/Camera/Light 没变，未保存 blend。迁移前内存里的模拟缓存不再存在，不能假定 `.009` 等 scene 仍在。当前仅有新建的 `WW_Wearing_Physics_Experiment` 输入验证场景，未重跑180帧；需从新目录脚本创建/顺序 advance。磁盘旧 proof 和审计仍保留。
- Blender MCP 只读几何审计：`runpy.run_path('<新根>/tools/audit_native_layers_blender.py')['audit']('res://captures/wearing_bound_simulation_nap0_blender_fixed_rest_bound_layers_proof_geometry.json')`。会校验来源哈希、写本项目报告，不修改 Blender 场景。
- Godot MCP editor info 与静态验证本轮均返回 `[Errno 22] Invalid argument`，因此实际运行/截图用新项目 CLI RTX4060。不能声称编辑器桥已修好。

## 后续顺序

1. 先修饰带与主裙面的真实贴合/层间厚度及腰口连续性，用新几何导出和 BVH 审计防止只看侧面；生产素体不动。
2. 解决 fixed-rest 候选的中间帧自交、真实长椅世界轨迹，保持有松量的单裙筒与平滑轮廓；逐帧验证，不只测最终姿态。
3. 再扩展到坐姿、四睡姿、走路抬手及多层袖片。通过严格层测试和外观检查后，接库存穿脱/折叠/镜子/物品连续性，最后才进入默认 NPC。
4. 保留已有类骨骼裙摆惯性和面料参数接口；质量、厚度、抗弯、抗拉、阻尼、褶深都是游戏近似，不宣称等同 CLO。完成这些门槛后回到 `MVP_PLAN.md` 的30顾客经营闭环，不无界扩展模拟器。

本线程没有运行中的测试子进程或委派 agent；其他线程的调试台与agent不在此承诺范围。历史第9轮及更早细节看 `WORKSPACE_HANDOFF_2026-11-09.md`，最新事实看本页和 `DEVELOPMENT_LOG.md`；本地简要索引在 `../DEVLOG.md`。

# 迁移前历史说明（非当前路径）

2026-11-09：请先读 [总工作区 HANDOFF](../../../HANDOFF.md)。本页是游戏子工程中的发现入口，不重复维护第二份状态。

完整本机路径：`D:/GodotProjects/weave-and-wander/HANDOFF.md`。
历史开发日志：`D:/GodotProjects/weave-and-wander/Docs/DEVELOPMENT_LOG.md`。

最新局部专题仍保留：`HANDOFF_2026-11-05.md`、`UKRAINIAN_HANDOFF_2026-11-06.md`。它们不是全部系统均已验收的承诺。

注意：当前Git根仅为游戏子目录，克隆本仓库不一定包含上级HANDOFF与日志，也不包含独立的 `D:/CodexWorkspace/papercut-editor`。四人协作初始化时必须明确总文档与跨应用版本管理并将它们一并交付，不能留下只有作者电脑可读的链接。
