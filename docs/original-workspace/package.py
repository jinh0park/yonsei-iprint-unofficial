#!/usr/bin/env python3
"""Create a local DMG, with matching source materials and a simple guide."""
from pathlib import Path
import shutil,subprocess,hashlib,json,html,os
HERE=Path(__file__).resolve().parent;OUT=HERE.parent;ROOT=HERE.parents[2]
STAGE=ROOT/'work/native-build/dmg-stage';shutil.rmtree(STAGE,ignore_errors=True);STAGE.mkdir(parents=True)
APP=Path(os.environ.get('IPRINT_NATIVE_PACKAGE_APP',str(OUT/'연세 iPrint Native (비공식).app')));shutil.copytree(APP,STAGE/APP.name,symlinks=True)
(STAGE/'Applications').symlink_to('/Applications')
shutil.copytree(OUT/'Source Materials',STAGE/'Source Materials')
shutil.copytree(HERE,STAGE/'Native Client Source',ignore=shutil.ignore_patterns('__pycache__'))
raw=(OUT/'사용 안내.md').read_text();page='<!doctype html><meta charset="utf-8"><title>연세 iPrint Native 사용 안내</title><style>body{font:16px/1.7 -apple-system,sans-serif;max-width:760px;margin:48px auto;padding:0 24px;white-space:pre-wrap}h1{font-size:26px}</style><h1>연세 iPrint Native</h1>'+html.escape(raw)
(STAGE/'사용 안내.html').write_text(page)
version=json.loads((OUT/'build.json').read_text())['version'];image=OUT/f'연세-iPrint-Native-{version}-AppleSilicon.dmg'
subprocess.run(['hdiutil','create','-ov','-volname','Yonsei iPrint Native','-fs','HFS+','-format','UDZO','-srcfolder',str(STAGE),str(image)],check=True)
subprocess.run(['hdiutil','verify',str(image)],check=True)
sha=hashlib.sha256(image.read_bytes()).hexdigest();(OUT/'SHA256.txt').write_text(f'{sha}  {image.name}\n')
print(json.dumps({'image':str(image),'bytes':image.stat().st_size,'sha256':sha}))
