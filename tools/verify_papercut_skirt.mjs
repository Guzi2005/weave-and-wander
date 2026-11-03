import {createRequire} from 'node:module';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
const require=createRequire('D:/GodotProjects/weave-and-wander/asset-workbench/package.json');
const {chromium,expect}=require('@playwright/test');
const {unzipSync,strFromU8}=require('fflate');
const output=new URL('../captures/pleated_editor/',import.meta.url);await mkdir(output,{recursive:true});
const browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-swiftshader']});
const page=await browser.newPage({viewport:{width:1600,height:1050},deviceScaleFactor:1});
const errors=[];page.on('pageerror',e=>errors.push(e.message));
try{
  await page.goto('http://127.0.0.1:3119/');
  await expect(page.getByRole('button',{name:'工作模式：剪贴画板',exact:true})).toBeVisible();
  await page.screenshot({path:new URL('native-board.png',output).pathname.slice(1)});
  await page.getByRole('button',{name:'工作模式：剪贴画板',exact:true}).click();await page.getByRole('menuitemradio',{name:'Weave & Wander 资产',exact:true}).click();await page.getByRole('button',{name:/参数化百褶裙/}).click();
  await expect(page.locator('.skirt-native-status')).toContainText('已同步');
  await expect(page.locator('.skirt-preview-error')).toHaveCount(0);
  await expect(page.getByTestId('skirt-preview')).toHaveAttribute('data-avatar','ready',{timeout:30000});
  await page.screenshot({path:new URL('native-sector.png',output).pathname.slice(1)});
  for(const [action,name] of [['walk','行走'],['sit','坐下'],['lie','躺下']]){await page.getByRole('button',{name,exact:true}).click();await page.getByRole('slider',{name:'动作进度',exact:true}).evaluate(el=>{el.value='1';el.dispatchEvent(new Event('input',{bubbles:true}));});await page.screenshot({path:new URL('native-action-'+action+'.png',output).pathname.slice(1)});}
  await page.getByRole('button',{name:'站立',exact:true}).click();
  const download=async(name,file)=>{const waiting=page.waitForEvent('download');await page.getByRole('button',{name,exact:true}).click();const dl=await waiting;await dl.saveAs(new URL(file,output).pathname.slice(1));return readFile(new URL(file,output));};
  const snapshot=async()=>JSON.parse((await download('保存完整原稿','source.weave.json')).toString()).project;
  const ready=()=>expect(page.locator('.skirt-native-status')).toContainText('已同步');
  const range=async(label,value)=>{await page.getByRole('slider',{name:label,exact:true}).evaluate((el,v)=>{el.value=String(v);el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));},value);await ready();};
  const initial=await snapshot();
  await range('裙长 / cm',101);expect((await snapshot()).pleatedSkirt.parameters.length_cm).toBe(101);
  await page.locator('.skirt-native-toolbar').getByRole('button',{name:'撤销',exact:true}).click();await ready();expect((await snapshot()).pleatedSkirt.parameters.length_cm).toBe(88);
  await range('裙摆大小 / cm',360);expect((await snapshot()).pleatedSkirt.parameters.hem_cm).toBe(360);
  await page.getByRole('spinbutton',{name:'裙长 / cm 数值',exact:true}).fill('120');await page.getByRole('spinbutton',{name:'裙长 / cm 数值',exact:true}).press('Tab');await ready();
  const wide=await snapshot();expect(wide.pleatedSkirt.parameters.length_cm).toBe(120);expect(wide.pleatedSkirt.parameters.hem_cm).toBe(360);
  await page.screenshot({path:new URL('native-long-wide.png',output).pathname.slice(1)});
  await page.locator('.skirt-native-toolbar').getByRole('button',{name:'撤销',exact:true}).click();await ready();
  await page.locator('.skirt-native-toolbar').getByRole('button',{name:'撤销',exact:true}).click();await ready();
  expect((await snapshot()).pleatedSkirt.parameters).toEqual(initial.pleatedSkirt.parameters);
  // Use the real host theme picker and verify the skirt inherits its panel/accent tokens.
  for(const skin of ['扎染蓝印','松烟墨','宣纸素白','亚麻织布']){
    await page.getByRole('button',{name:'设置',exact:true}).click();await page.locator(`button[data-tip="${skin}"]`).click();await page.getByRole('button',{name:'设置',exact:true}).click();
    const colors=await page.locator('.skirt-controls').evaluate(el=>{const s=getComputedStyle(el),probe=document.createElement('span');el.append(probe);const panels=['--ui-panel','--ui-panel-2'].map(token=>{probe.style.color=`var(${token})`;return getComputedStyle(probe).color;});probe.style.color='var(--ui-raised)';const raised=getComputedStyle(probe).color;probe.remove();return {background:s.backgroundColor,panels,raised};});expect(colors.panels).toContain(colors.background);
    await expect(page.getByRole('button',{name:'保存设计 JSON',exact:true})).toHaveCSS('background-color','rgba(0, 0, 0, 0)');
    if(skin==='扎染蓝印')await page.screenshot({path:new URL('native-dark.png',output).pathname.slice(1)});
  }
  await page.getByRole('button',{name:'画笔',exact:true}).click();
  const box=await page.getByTestId('skirt-canvas').boundingBox();
  await page.mouse.move(box.x+box.width*.45,box.y+box.height*.51);await page.mouse.down();await page.mouse.move(box.x+box.width*.55,box.y+box.height*.55,{steps:8});await page.mouse.up();await ready();
  const drawn=await snapshot();expect(drawn.pleatedSkirt.strokes.length).toBe(1);
  await page.getByRole('tab',{name:'圆环俯视',exact:true}).click();await ready();expect((await snapshot()).pleatedSkirt.strokes).toEqual(drawn.pleatedSkirt.strokes);
  await page.getByRole('button',{name:'回到画板细绘',exact:true}).click();
  await expect(page.getByRole('complementary',{name:'画板实时裙子预览'})).toBeVisible();
  // The native tool is selected by the workbench; drag on the native SVG canvas.
  const svg=page.locator('svg[viewBox="0 0 1024 1024"]').first();const native=await svg.boundingBox();
  await page.mouse.move(native.x+native.width*.33,native.y+native.height*.4);await page.mouse.down();await page.mouse.move(native.x+native.width*.42,native.y+native.height*.5,{steps:12});await page.mouse.up();
  await page.screenshot({path:new URL('native-painting.png',output).pathname.slice(1)});
  await page.getByRole('button',{name:'百褶裙 · 参数与展开 ↗',exact:true}).click();await ready();
  const beforeNudge=await snapshot();
  await page.getByRole('button',{name:'回到画板细绘',exact:true}).click();await page.getByRole('button',{name:'选择',exact:true}).click();
  await svg.locator('g[data-layer-id] path').last().click({force:true});await page.keyboard.press('ArrowRight');
  await page.getByRole('button',{name:'百褶裙 · 参数与展开 ↗',exact:true}).click();await ready();
  const painted=await snapshot();expect(painted.layers).not.toEqual(beforeNudge.layers);expect(Object.values(painted.layers).flatMap(l=>l.drawings||[]).length).toBeGreaterThan(0);
  await page.keyboard.press('ArrowRight');await page.keyboard.press('Delete');expect((await snapshot()).layers).toEqual(painted.layers);
  expect(painted.items[0].id).toBe(initial.pleatedSkirt.item_id);expect(painted.pleatedSkirt.design_id).toBe(initial.pleatedSkirt.design_id);
  const files=unzipSync(await download('导出 Godot 包','native-skirt.zip'));
  expect(JSON.parse(strFromU8(files['skirt.json']))).toEqual(painted.pleatedSkirt);
  const fixture=new URL('../assets/designs/pleated_skirt/native_painted/',import.meta.url);await mkdir(fixture,{recursive:true});
  for(const key of ['skirt.json','skirt.png'])await writeFile(new URL(key,fixture),files[key]);
  // Workbench uses native serialization and browser workspace restore.
  await page.getByRole('button',{name:'立即保存工作区',exact:true}).click();
  await expect(page.getByRole('button',{name:'立即保存工作区',exact:true})).toHaveAttribute('data-tip',/已保存/);
  await page.reload();await page.getByRole('button',{name:'工作模式：剪贴画板',exact:true}).click();await page.getByRole('menuitemradio',{name:'Weave & Wander 资产',exact:true}).click();await ready();
  const recovered=await snapshot();expect(recovered.pleatedSkirt).toEqual(painted.pleatedSkirt);expect(recovered.layers).toEqual(painted.layers);expect(recovered.items).toEqual(painted.items);
  // Every reference template and the exported circular guide renders in the real host.
  await page.getByLabel('参考起点',{exact:true}).selectOption('yi_reference');await ready();
  await page.getByRole('tab',{name:'圆弧展开',exact:true}).click();await ready();
  await page.screenshot({path:new URL('native-yi-sector.png',output).pathname.slice(1)});
  await page.setViewportSize({width:800,height:1000});await page.getByRole('tab',{name:'圆环俯视',exact:true}).click();await ready();
  const tablet=await page.getByTestId('skirt-canvas').boundingBox();expect(Math.abs(tablet.width-tablet.height)).toBeLessThan(2);
  await page.screenshot({path:new URL('native-tablet.png',output).pathname.slice(1)});
  await page.setViewportSize({width:1600,height:1050});
  const thin=structuredClone(initial.pleatedSkirt);thin.design_id='thin-patch-regression';thin.patches=[{id:'draft-patch',u0:.2,u1:.2005,v0:.1,v1:.9,color:'#123456',pattern:'solid',repeat:8}];
  const chooser=page.waitForEvent('filechooser');await page.getByRole('button',{name:'导入设计',exact:true}).click();await (await chooser).setFiles({name:'thin.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(thin))});await ready();
  for(const tool of ['画笔','拼色片']){await page.getByRole('button',{name:tool,exact:true}).click();const bounds=await page.getByTestId('skirt-canvas').boundingBox();await page.mouse.move(bounds.x+bounds.width*.45,bounds.y+bounds.height*.51);await page.mouse.down();await page.mouse.move(bounds.x+bounds.width*.55,bounds.y+bounds.height*.55,{steps:8});await page.mouse.up();await ready();expect((await snapshot()).pleatedSkirt.patches).toContainEqual(thin.patches[0]);}
  expect(errors).toEqual([]);console.log(JSON.stringify({passed:true,nativeLayers:Object.keys(painted.layers).length,nativeDrawings:Object.values(painted.layers).flatMap(l=>l.drawings||[]).length,errors}));
}finally{await browser.close();}
