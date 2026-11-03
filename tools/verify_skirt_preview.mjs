import {createRequire} from 'node:module';
import {mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const require=createRequire('D:/GodotProjects/weave-and-wander/asset-workbench/package.json');
const {chromium,expect}=require('@playwright/test');
const output=new URL('../captures/pleated_editor/',import.meta.url);await mkdir(output,{recursive:true});
const browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-swiftshader']});
const page=await browser.newPage({viewport:{width:1600,height:1050}}),errors=[];
page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||/GL_INVALID|WebGL.*error/.test(m.text()))errors.push(m.text());});
try{
 await page.goto('http://127.0.0.1:3119/');await page.getByRole('button',{name:'工作模式：剪贴画板',exact:true}).click();await page.getByRole('menuitemradio',{name:'Weave & Wander 资产',exact:true}).click();await page.getByRole('button',{name:/参数化百褶裙/}).click();
 const canvas=page.getByTestId('skirt-preview');await expect(canvas).toHaveAttribute('data-avatar','ready',{timeout:30000});
 await page.getByRole('tab',{name:'圆弧展开',exact:true}).focus();await page.keyboard.press('ArrowRight');await expect(page.getByRole('tab',{name:'圆环俯视',exact:true})).toBeFocused();await page.keyboard.press('Home');await expect(page.getByRole('tab',{name:'梯形平铺',exact:true})).toBeFocused();
 await expect(page.getByRole('spinbutton',{name:'裙长 / cm 数值',exact:true})).toHaveCSS('width','42px');
 await expect(page.locator('.skirt-stage')).toHaveCSS('background-color','rgba(0, 0, 0, 0)');
 await page.getByRole('button',{name:'行走',exact:true}).click();await expect.poll(()=>canvas.getAttribute('data-progress')).not.toBe('0.000');
 await page.getByRole('button',{name:'播放或暂停动作',exact:true}).click();const paused=await canvas.getAttribute('data-progress');await page.waitForTimeout(180);expect(await canvas.getAttribute('data-progress')).toBe(paused);
 await page.getByRole('button',{name:'播放或暂停动作',exact:true}).click();await expect.poll(()=>canvas.getAttribute('data-progress')).not.toBe(paused);
 const progress=async(value)=>page.getByRole('slider',{name:'动作进度',exact:true}).evaluate((el,v)=>{el.value=String(v);el.dispatchEvent(new Event('input',{bubbles:true}));},value);
 const number=async(label,value)=>{const el=page.getByRole('spinbutton',{name:label+' 数值',exact:true});await el.fill(String(value));await el.press('Tab');await expect(page.locator('.skirt-native-status')).toHaveText('已同步');};
 for(const [length,hem] of [[40,100],[120,360]]){
  await number('裙长 / cm',length);await number('裙摆大小 / cm',hem);
  for(const [action,name] of [['stand','站立'],['walk','行走'],['sit','坐下'],['lie','躺下']]){await page.getByRole('button',{name,exact:true}).click();await progress(action==='walk'?.3:1);await page.screenshot({path:fileURLToPath(new URL(`preview-${length}-${hem}-${action}.png`,output))});}
 }
 await page.getByRole('button',{name:'穿着',exact:true}).click();await expect(page.locator('.skirt-action-tabs')).toBeHidden();await expect(page.getByRole('slider',{name:'动作进度',exact:true})).toBeDisabled();await page.screenshot({path:fileURLToPath(new URL('preview-standalone.png',output))});
 await page.getByRole('button',{name:'单裙',exact:true}).click();await expect(page.locator('.skirt-action-tabs')).toBeVisible();
 const stats=await canvas.evaluate(el=>{const gl=el.getContext('webgl2');return {glError:gl.getError(),renderer:gl.getParameter(gl.RENDERER)};});expect(stats.glError).toBe(0);expect(errors).toEqual([]);console.log(JSON.stringify({passed:true,playback:true,keyboardTabs:true,extremePoses:8,stats,errors}));
}finally{await browser.close();}
