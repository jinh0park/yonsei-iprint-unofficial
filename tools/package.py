#!/usr/bin/env python3
"""Create an installer DMG with an explicit corresponding-source URL."""
from pathlib import Path
import argparse, hashlib, html, json, shutil, subprocess
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source-url',required=True,help='Public URL for this exact source release')
    args=p.parse_args()
    if not args.source_url.startswith('https://'):raise SystemExit('Provide a public HTTPS source release URL.')
    version=(ROOT/'VERSION').read_text().strip();app=ROOT/'dist/연세 iPrint Native (비공식).app'
    if not app.is_dir():raise SystemExit('Run python3 tools/build.py first.')
    stage=ROOT/'build/dmg-stage'
    if stage.exists():shutil.rmtree(stage)
    stage.mkdir(parents=True)
    shutil.copytree(app,stage/app.name,symlinks=True);(stage/'Applications').symlink_to('/Applications')
    (stage/'소스 코드 및 라이선스.txt').write_text(f'연세 iPrint Native {version}\n전체 앱 소스·Ghostscript 원본·Mac 수정사항·빌드 방법:\n{args.source_url}\n\n앱과 Ghostscript는 GNU AGPL v3로 제공하며, 타사 구성물의 개별 고지는 보존합니다.\n라이선스 원문: 앱의 Contents/Resources/Licenses\n일반 사용자는 소스 파일을 내려받지 않아도 설치할 수 있습니다.\n')
    guide=(ROOT/'docs/Usage.ko.md').read_text()
    (stage/'사용 안내.html').write_text('<!doctype html><meta charset="utf-8"><title>연세 iPrint 사용 안내</title><style>body{font:16px/1.7 -apple-system,sans-serif;max-width:760px;margin:48px auto;padding:24px;white-space:pre-wrap}</style>'+html.escape(guide))
    image=ROOT/f'dist/연세-iPrint-Native-{version}-비공식-AppleSilicon.dmg'
    subprocess.run(['hdiutil','create','-ov','-volname','연세 iPrint (비공식)','-fs','HFS+','-format','UDZO','-srcfolder',str(stage),str(image)],check=True)
    subprocess.run(['hdiutil','verify',str(image)],check=True)
    digest=hashlib.sha256(image.read_bytes()).hexdigest()
    (image.parent/'SHA256.txt').write_text(f'{digest}  {image.name}\n')
    print(json.dumps({'image':str(image),'bytes':image.stat().st_size,'source_url':args.source_url,'sha256':digest},ensure_ascii=False))
if __name__=='__main__':main()
