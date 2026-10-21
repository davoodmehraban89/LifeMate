#!/usr/bin/env python3
"""Rasterize the exported PDF and create its contact sheet; no browser screenshots."""
from pathlib import Path
import hashlib,json,subprocess
from PIL import Image,ImageOps,ImageDraw
here=Path(__file__).resolve().parent
out=here/'pages'
out.mkdir(exist_ok=True)
subprocess.run(['pdftoppm','-png','-r','96',str(here/'LifeGuide-Owner-Guide-v1.pdf'),str(out/'page')],check=True)
files=sorted(out.glob('page-*.png'))
assert len(files)==12,len(files)
thumbs=[]
for i,f in enumerate(files,1):
    im=Image.open(f).convert('RGB')
    assert 790<=im.width<=800 and 1120<=im.height<=1130,im.size
    im.thumbnail((238,337),Image.Resampling.LANCZOS)
    thumb=Image.new('RGB',(258,371),'#fffaf2')
    thumb.paste(im,((258-im.width)//2,10))
    ImageDraw.Draw(thumb).text((120,351),f'{i:02}',fill='#463856')
    thumbs.append(thumb)
sheet=Image.new('RGB',(4*278+20,3*391+20),'#e5dfd6')
for i,thumb in enumerate(thumbs):sheet.paste(thumb,(20+(i%4)*278,20+(i//4)*391))
sheet.save(here/'overview.png',optimize=True)
p=here/'verification.json'
v=json.loads(p.read_text())
v['checks']['raster']={'method':'pdftoppm -png -r 96','pages':12,'overview':'overview.png','source':'LifeGuide-Owner-Guide-v1.pdf'}
v['artifactSha256']={f:hashlib.sha256((here/f).read_bytes()).hexdigest() for f in ['index.html','LifeGuide-Owner-Guide-v1.pdf','overview.png']}
p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
print('PASS: PDF rasterized to 12 page PNGs at 96dpi; overview generated; artifact SHA256 recorded.')
