"""Execute generated PostScript in the bundled interpreter with synthetic pages.
No sockets, school traffic or physical printer access. Compile print_options_tests.m
first, then pass its executable and a disposable output folder to this script.
"""
from pathlib import Path
import json, os, re, struct, subprocess, sys

app=Path(os.environ.get('IPRINT_NATIVE_APP',str(Path(__file__).resolve().parents[2]/'연세 iPrint Native (비공식).app')))
g=app/'Contents/Resources/ghostscript'
env=dict(os.environ,GS_LIB=f'{g}/Resource/Init:{g}/lib:{g}/Resource/Font',GS_FONTPATH=str(g/'Resource/Font'))
out=Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
subprocess.run([str(Path(sys.argv[1]).resolve()),str(out)],check=True)
cases=json.loads((out/'options.json').read_text())['cases']
source=out/'three-pages.ps'
source.write_text('%!PS-Adobe-3.0\n%%Pages: 3\n/Helvetica findfont 24 scalefont setfont\n'+''.join(f'72 750 moveto (Page {i}) show showpage\n' for i in range(1,4)))
spy='''/setpagedevice {
 dup /Duplex known {
  (OPTIONS ) print dup /NumCopies get == dup /Duplex get == dup /Tumble get == dup /Collate get ==
 } if systemdict /setpagedevice get exec
} bind def
/showpage {
 (PAGECOPIES ) print currentpagedevice /NumCopies get ==
 systemdict /showpage get exec
} bind def'''
results=[]
for row in cases:
    ps=out/(row['record']+'.ps')
    args=['-q','-dSAFER','-dBATCH','-dNOPAUSE','-sDEVICE=ps2write','-dNoOutputFonts','-dCompressPages=true','-sOutputFile='+str(ps),'-c','<< /PSDocOptions ('+row['setup']+') >> setdistillerparams','-f',str(source)]
    r=subprocess.run([str(g/'bin/gs'),*args],env=env,capture_output=True,text=True,timeout=30)
    assert r.returncode==0,(row,r.stdout,r.stderr)
    data=ps.read_bytes();assert re.findall(rb'^%%Pages: (\d+)$',data,re.M)==[b'3']
    assert data.count(row['setup'].encode())==1
    record=(out/(row['record']+'.bin')).read_bytes()
    assert struct.unpack_from('<H',record,0x213)[0]==3*row['copies']
    assert struct.unpack_from('<i',record,0x26a)[0]==3
    assert struct.unpack_from('<H',record,0x270)[0]==row['copies']
    r=subprocess.run([str(g/'bin/gs'),'-q','-dSAFER','-dBATCH','-dNOPAUSE','-sDEVICE=nullpage','-c',spy,'-f',str(ps)],env=env,capture_output=True,text=True,timeout=30)
    assert r.returncode==0 and 'Error' not in r.stdout,(row,r.stdout,r.stderr)
    expected=f"OPTIONS {row['copies']}\n{'true' if row['mode'] else 'false'}\n{'true' if row['mode']==2 else 'false'}\ntrue\n"
    assert r.stdout.count(expected)==1,(row,r.stdout)
    assert re.findall(r'PAGECOPIES (\d+)',r.stdout)==[str(row['copies'])]*3,(row,r.stdout)
    results.append({'mode':row['mode'],'copies':row['copies'],'pages':3,'total_page_images':3*row['copies'],'passed':True})
report={'passed':True,'cases':results,'actual_postscript_execution':True,'school_network_contacted':False,'physical_print_verified':False}
(out/'postscript-execution.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
