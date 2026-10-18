#!/usr/bin/env python3
"""Build the native client and its bundled Ghostscript from this repository."""
from pathlib import Path
import argparse, hashlib, json, os, platform, plistlib, shutil, subprocess

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
DIST=ROOT/'dist'
NATIVE=ROOT/'native'
UPSTREAM=ROOT/'third_party/ghostscript-10.0.0'
PATCHES=ROOT/'patches/ghostscript'
VERSION=(ROOT/'VERSION').read_text().strip()

def run(command, *, cwd=None, log=None):
    if log:
        with log.open('w') as output:
            result=subprocess.run(command,cwd=cwd,stdout=output,stderr=subprocess.STDOUT)
        if result.returncode:
            raise SystemExit(f'Build failed. See {log}')
    else:
        subprocess.run(command,cwd=cwd,check=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs',type=int,default=min(4,os.cpu_count() or 1))
    parser.add_argument('--force-ghostscript',action='store_true')
    args=parser.parse_args()
    if platform.system()!='Darwin' or platform.machine()!='arm64':
        raise SystemExit('Build on an Apple Silicon Mac with Xcode Command Line Tools.')
    if not 1<=args.jobs<=32:raise SystemExit('--jobs must be between 1 and 32')
    BUILD.mkdir(exist_ok=True);DIST.mkdir(exist_ok=True)
    gs=BUILD/'ghostscript-10.0.0'
    stamp=gs/'.iprint-build-complete'
    inputs=hashlib.sha256((ROOT/'VERSION').read_bytes())
    for name in ('zlib/zutil.h','libpng/pngpriv.h'):inputs.update((PATCHES/name).read_bytes())
    fingerprint=inputs.hexdigest()
    cached=stamp.exists() and stamp.read_text()==fingerprint and (gs/'bin/gs').is_file()
    if args.force_ghostscript or not cached:
        if gs.exists():shutil.rmtree(gs)
        print('Copying pristine Ghostscript source and applying the two macOS fixes.',flush=True)
        shutil.copytree(UPSTREAM,gs,symlinks=True)
        for name in ('zlib/zutil.h','libpng/pngpriv.h'):shutil.copy2(PATCHES/name,gs/name)
        print('Configuring Ghostscript; output: build/ghostscript-configure.log',flush=True)
        run(['./configure','--prefix=/iprint-bundled','--without-x','--disable-cups','--disable-gtk','--disable-fontconfig','--without-tesseract','--without-libidn'],cwd=gs,log=BUILD/'ghostscript-configure.log')
        print('Compiling Ghostscript; output: build/ghostscript-make.log',flush=True)
        run(['make',f'-j{args.jobs}','CFLAGS_STANDARD=-O2 -DNDEBUG -mmacosx-version-min=13.0','XCFLAGS=-Wno-error=declaration-after-statement','XLDFLAGS=-mmacosx-version-min=15.0'],cwd=gs,log=BUILD/'ghostscript-make.log')
        stamp.write_text(fingerprint)
    else:print('Reusing this repository’s completed Ghostscript build.',flush=True)
    temp=BUILD/'app.new'
    if temp.exists():shutil.rmtree(temp)
    contents=temp/'Contents';mac=contents/'MacOS';resources=contents/'Resources'
    mac.mkdir(parents=True);resources.mkdir()
    print('Compiling native AppKit client.',flush=True)
    run(['xcrun','clang','-fobjc-arc','-fblocks','-fno-modules','-framework','Cocoa','-framework','PDFKit','-framework','UniformTypeIdentifiers','-arch','arm64','-mmacosx-version-min=13.0','-O2',str(NATIVE/'NativeCore.m'),str(NATIVE/'main.m'),'-o',str(mac/'iPrintNative')])
    bundled=resources/'ghostscript';(bundled/'bin').mkdir(parents=True)
    shutil.copy2(gs/'bin/gs',bundled/'bin/gs')
    for name in ('Resource','lib','iccprofiles'):
        shutil.copytree(gs/name,bundled/name,symlinks=True,ignore=shutil.ignore_patterns('*.o','*.a'))
    shutil.copy2(ROOT/'assets/AppIcon.icns',resources/'AppIcon.icns')
    shutil.copytree(NATIVE,resources/'Source',ignore=shutil.ignore_patterns('__pycache__','.DS_Store'))
    license_dir=resources/'Licenses';license_dir.mkdir()
    for source,target in [('LICENSE','Ghostscript-License-Notes.txt'),('doc/COPYING','Ghostscript-AGPL.txt'),('DroidSansFallback.NOTICE','DroidSansFallback-NOTICE.txt')]:shutil.copy2(gs/source,license_dir/target)
    shutil.copy2(ROOT/'LICENSE',license_dir/'Native-Client-AGPL.txt')
    (license_dir/'Components.txt').write_text(f'Yonsei iPrint Native {VERSION}\nNative client: GNU AGPL v3.\nGhostscript 10.0.0: Artifex Software, GNU AGPL v3 and retained third-party notices.\nCorresponding source, macOS fixes and build instructions are in the source repository distributed with this release.\nNo Windows client, Wine, Samsung filter or Rosetta is included.\n')
    info={'CFBundleExecutable':'iPrintNative','CFBundleIdentifier':'local.family.yonsei-iprint.native','CFBundleName':'연세 iPrint Native (비공식)','CFBundleDisplayName':'연세 iPrint Native (비공식)','CFBundlePackageType':'APPL','CFBundleShortVersionString':VERSION,'CFBundleVersion':VERSION.replace('.',''),'LSMinimumSystemVersion':'15.0','CFBundleIconFile':'AppIcon.icns','NSHighResolutionCapable':True}
    (contents/'Info.plist').write_bytes(plistlib.dumps(info))
    run(['codesign','--force','--sign','-',str(temp)])
    run(['codesign','--verify','--deep','--strict',str(temp)])
    app=DIST/'연세 iPrint Native (비공식).app'
    if app.exists():
        previous=BUILD/'app.previous'
        if previous.exists():shutil.rmtree(previous)
        app.rename(previous)
    temp.rename(app)
    (DIST/'build.json').write_text(json.dumps({'version':VERSION,'app':app.name,'architecture':'arm64','minimum_macos':'15.0','source_built_ghostscript':True,'school_network_contacted':False},indent=2)+'\n')
    print(f'Built and ad-hoc signed: {app}',flush=True)

if __name__=='__main__':main()
