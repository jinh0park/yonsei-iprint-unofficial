#!/usr/bin/env python3
from pathlib import Path
import subprocess,shutil,plistlib,hashlib,json,os
HERE=Path(__file__).resolve().parent;OUT=HERE.parent;ROOT=HERE.parents[2]
APP=OUT/'연세 iPrint Native (비공식).app';BUILD=ROOT/'work/native-build';BUILD.mkdir(exist_ok=True)
TEMP=BUILD/'app.new';shutil.rmtree(TEMP,ignore_errors=True)
CONTENTS=TEMP/'Contents';MAC=CONTENTS/'MacOS';RES=CONTENTS/'Resources';MAC.mkdir(parents=True);RES.mkdir()
subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-fno-modules','-framework','Cocoa','-framework','PDFKit','-framework','UniformTypeIdentifiers','-arch','arm64','-mmacosx-version-min=13.0','-O2',str(HERE/'NativeCore.m'),str(HERE/'main.m'),'-o',str(MAC/'iPrintNative')],check=True)
gs=ROOT/'work/distribution-build/ghostscript-10.0.0';G=RES/'ghostscript';G.mkdir();(G/'bin').mkdir();shutil.copy2(gs/'bin/gs',G/'bin/gs')
for name in ('Resource','lib','iccprofiles'):shutil.copytree(gs/name,G/name,ignore=shutil.ignore_patterns('*.o','*.a'))
shutil.copy2(ROOT/'work/distribution-build/AppIcon.icns',RES/'AppIcon.icns')
shutil.copytree(HERE,RES/'Source',ignore=shutil.ignore_patterns('__pycache__'))
# Complete upstream archive + two source modifications are provided beside the app.
license_dir=RES/'Licenses';license_dir.mkdir();shutil.copy2(gs/'LICENSE',license_dir/'Ghostscript-License-Notes.txt');shutil.copy2(gs/'doc/COPYING',license_dir/'Ghostscript-AGPL.txt');shutil.copy2(gs/'DroidSansFallback.NOTICE',license_dir/'DroidSansFallback-NOTICE.txt')
(license_dir/'Components.txt').write_text('iPrint Native 0.1.14 experimental ARM64 client\nOriginal Windows client, Wine and Samsung binaries are not included.\nGhostscript 10.0.0: Artifex Software, GNU AGPL v3.\nCorresponding source and macOS build changes are provided in Source Materials/ beside this app.\n')
info={'CFBundleExecutable':'iPrintNative','CFBundleIdentifier':'local.family.yonsei-iprint.native','CFBundleName':'연세 iPrint Native (비공식)','CFBundleDisplayName':'연세 iPrint Native (비공식)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1.14','CFBundleVersion':'15','LSMinimumSystemVersion':'15.0','CFBundleIconFile':'AppIcon.icns','NSHighResolutionCapable':True}
(CONTENTS/'Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--sign','-',str(TEMP)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(TEMP)],check=True)
if APP.exists():
 old=BUILD/'app.previous';shutil.rmtree(old,ignore_errors=True);APP.rename(old)
TEMP.rename(APP)
SOURCE=OUT/'Source Materials';SOURCE.mkdir(exist_ok=True);shutil.copy2(ROOT/'work/distribution-build/ghostscript-10.0.0.tar.gz',SOURCE/'ghostscript-10.0.0.tar.gz')
for name in ('zlib/zutil.h','libpng/pngpriv.h'):
 target=SOURCE/'macos-sdk-fixes'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(gs/name,target)
shutil.copy2(HERE/'BUILD.md',SOURCE/'BUILD.md')
size=sum(p.stat().st_size for p in APP.rglob('*') if p.is_file())
(OUT/'build.json').write_text(json.dumps({'version':'0.1.14','app_bytes':size,'requires_rosetta':False,'school_login_verified':False,'physical_print_verified':False,'minimum_macos':'15.0'},indent=2))
print(json.dumps({'app':str(APP),'bytes':size}))
