# 摩梭套装 Wiki 原型生成提示词

历史生成记录：以下保留当时实际使用的提示词，便于追溯。2026-10-29 用户已澄清紫色米珠串属于头饰、手持物是玫红镶边鞋垫、腰部有宽腰带；当前档案以 `record-plan.zh-CN.md` 和本地 Wiki 为准。旧提示词中的“用途待查／暂不认定腰带”不再代表当前结论。

生成方式：内置 image_gen，参考图驱动的新界面生成。

主参考：source-user-upload.png（用户上传原图的未修改副本）。
视觉参考：../02-evidence-record.png（上一轮界面风格，不作为服饰资料）。
输出：04-mosuo-ensemble-breakdown.png。

Use case: ui-mockup. Generate a high-fidelity desktop W&W Wiki interface screenshot showing how the SPECIFIC USER-SUPPLIED OUTFIT PHOTOGRAPH is accessioned, visually decomposed into component records, and researched.
INPUT IMAGE 1 is the PRIMARY photographic evidence: a smiling woman standing before a dark blue doorway wearing a black rounded headdress with multicolor wrapped cords and a red tuft, vivid red floral/patterned long-sleeve upper garment, pale turquoise/light blue ankle-length densely pleated skirt with light patterned surface and a fine reddish horizontal line near the lower skirt, long purple hanging strands at her right (viewer right), dark shoes partly visible. She holds a small gray-centered pink-edged object. A SECOND person is partially visible at the far right; EXCLUDE that second person's garments from this ensemble.
INPUT IMAGE 2 is ONLY a visual language reference for the existing W&W Wiki interface: cream paper background, dark ink text, indigo active states, fine rules, serif Chinese titles. DO NOT copy its indigo skirt, invented garment, doll, metadata or its record identity into this new screen.
The primary photograph must remain recognizably the SAME supplied photograph, same woman's face and pose, exact main garment silhouettes, vivid red jacket, blue pleated skirt, headwear and architectural background. Do not beautify, reinterpret, stylize, reconstruct, relight, recolor or replace the person or outfit. Preserve full-body view from headdress to shoes. Retain photographic surroundings in the main source view; show the main subject prominently. No invented alternate views or recovered hidden garment parts. All detail images are crops of input image 1, with original surroundings and occlusions; NEVER flattened reconstructed isolated garments.

FORMAT: single wide landscape screenshot approximately 2400x1600, full-bleed flat browser app UI without device frame, no poster framing, no diagram slide. Elegant contemporary textile research archive, warm off-white #F4F1E9, charcoal #242B2B, indigo #314A62, tiny brick #9A5449. Light fine dividers, no chunky rounded cards, no big shadows or gradients, spacious readable Chinese typography, 14-16px conceptual UI text. Clean realistic professional tool with large photographic content, no marketing headline.

HEADER: interwoven thread mark and "W&W Wiki", nav "资料库" "专题" "工坊", search "搜索图像、名称、来源…", research mode.
Very slim LEFT navigation rail with "收件箱" "全部资料" "服装" "饰品" "布艺" "玩具". Active 服装.
MAIN PAGE HEADER: breadcrumb "资料库 / 服装 / 套装档案"; title EXACT "摩梭服饰套装"; small status "待考证"; subtitle "名称与文化归属由用户提供 · 单张照片记录"; ID "WW-MOS-001"; button "编辑记录". Do not assert the person's ethnicity. The title is a user-supplied outfit label, not an independently authenticated classification.
Tabs "套装总览" "部件拆解" "来源与证据" "数字转译", active "部件拆解".

MAIN BODY has THREE balanced working columns:
LEFT about 34%: large tall whole source photograph (input image 1), from top of headwear to feet. Header "来源图像" and photo ID "IMG-001". Main photo must be the dominant unified visual anchor.
Add only small unobtrusive indigo numbered markers and extremely fine short leaders, placed around the main woman's relevant areas, not across her face:
01 headwear,
02 red upper garment,
03 blue pleated skirt,
04 long purple strands,
05 visible dark shoes,
06 hand-held pink-edged object.
Under the photo a source caption "用户上传 · 原始出处待补", modest image toolbar "原图" "区域标注" "对照". Do not call the generated overall UI itself an original archival source. Small lower note "仅分析画面中央人物的服饰".

MIDDLE about 35%: heading "部件与观察" with subline "独立记录，共用来源图像". A refined TWO-COLUMN by THREE-ROW grid of six photo crop cards. Crop images are large and authentic pieces of input photograph, consistent with main photo; no synthetic product photos.
Card 01 crop headwear, title "头饰", subtitle "黑色主体 · 彩色缠绕装饰", status "描述性暂名".
Card 02 crop upper garment, title "红色花纹上衣", subtitle "长袖 · 领口与衣襟有饰边", status "名称待核".
Card 03 crop blue long pleated skirt, title "浅蓝色长褶裙", subtitle "竖向密褶 · 下段细红横线", indigo selected outline and label "已选中".
Card 04 crop purple strands hanging along the subject's right side, title "紫色垂饰", subtitle "连接与佩戴关系待查", status "观察记录".
Card 05 crop actual visible shoes partly obscured by skirt hem, title "深色鞋履", subtitle "局部可见 · 形制待查", status "局部记录".
Card 06 crop the actual held object with hand occlusion maintained, title "手持物", subtitle "用途待查 · 暂不归入套装", muted neutral status "独立线索".
Under cards, a single small structured note "腰部被手部与上衣遮挡，暂不单独认定腰带。".

RIGHT about 27%: clear open inspector for selected item "03 浅蓝色长褶裙", ID "WW-MOS-001-C03". Small label "服装 / 下装".
Section "图中可见": three concise well-spaced rows "浅蓝底与浅色纹样", "密集竖向褶裥", "裙下段可见细红横线". These are observations, not verified manufacturing techniques.
Section "仍需考证": rows "当地名称  待查", "纤维与织造  待查", "制作年代  未知", "拍摄地点  未记录". No silk/cotton/polyester material assertion, no specific date/village/ritual.
Section "来源链": compact linked text "IMG-001 → 区域 03 → 本部件"; small "用户提供归属：摩梭", "原始出处：待补", "图像授权：待确认", "公开状态：内部研究".
Bottom section "下一步研究" with a modest indigo button "建立结构研究", neutral button "补充文献依据". Small note "结构推测与参考证据分别保存".

BOTTOM FOOTER: restrained relationship strip "来源照片 → 套装母条目 → 部件记录 → 数字资产 / 题库", with one annotation "审核后发布". Persistent clearly readable footer "基于用户参考图的界面示意 · 部件采用描述性暂名".
Do not depict a completed 3D recreation or imply factual metadata is verified. Never fabricate historical or museum sources. Keep this a striking, clear, photo-centered Wiki breakdown page. The exact supplied outfit and the photo-to-parent-to-child relationship are the essential content.

