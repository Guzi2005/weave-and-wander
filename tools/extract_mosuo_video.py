"""Read local reference video only; create timestamped research contact sheets."""
import sys, pathlib, json
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'captures/video_runtime'))
import cv2
from PIL import Image, ImageDraw, ImageFont
source=pathlib.Path(r'D:\Eagle库\纯纯素材仓库.library\images\MVSWN5ENLXBNP.info\什么是真正的摩梭？ - 时差岛.mp4')
out=ROOT/'captures/mosuo_video';out.mkdir(parents=True,exist_ok=True)
cap=cv2.VideoCapture(str(source));fps=cap.get(cv2.CAP_PROP_FPS);frames=cap.get(cv2.CAP_PROP_FRAME_COUNT)
meta=dict(source=str(source),fps=fps,duration=frames/fps,width=cap.get(3),height=cap.get(4))
(out/'metadata.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
times=list(range(0,int(meta['duration']),30)) if len(sys.argv)==1 else [float(x) for x in sys.argv[1:]]
images=[]
for sec in times:
    cap.set(cv2.CAP_PROP_POS_MSEC,sec*1000);ok,frame=cap.read()
    if not ok: continue
    im=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB));im.save(out/f'frame-{sec:06.1f}.jpg',quality=92)
    im.thumbnail((400,225));tile=Image.new('RGB',(400,252),'#ece9df');tile.paste(im,((400-im.width)//2,0));ImageDraw.Draw(tile).text((10,229),f'{int(sec)//60:02}:{sec%60:04.1f}',fill='#222222');images.append(tile)
for page in range(0,len(images),12):
    subset=images[page:page+12];sheet=Image.new('RGB',(1600,252*((len(subset)+3)//4)),'#ece9df')
    for i,im in enumerate(subset): sheet.paste(im,((i%4)*400,(i//4)*252))
    sheet.save(out/f'contact-{page//12:02}.jpg',quality=92)
cap.release();print(json.dumps(meta,ensure_ascii=False));print('FRAMES',len(images))
