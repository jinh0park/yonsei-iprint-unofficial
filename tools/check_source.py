#!/usr/bin/env python3
"""Verify the checked-in source manifest. Does not contact any server."""
from pathlib import Path
import hashlib, sys
root=Path(__file__).resolve().parents[1]
manifest=root/'SOURCE_MANIFEST.sha256'
if not manifest.is_file():raise SystemExit('Source manifest is missing.')
count=0;bad=[]
for line in manifest.read_text().splitlines():
    digest,name=line.split('  ',1);path=root/name
    if path.is_symlink():data=path.readlink().as_posix().encode()
    elif path.is_file():data=path.read_bytes()
    else:bad.append(name);continue
    if hashlib.sha256(data).hexdigest()!=digest:bad.append(name)
    count+=1
if bad:
    print('Missing or different source files:',*bad,sep='\n');sys.exit(1)
print(f'Verified {count} source files; no server contacted.')
