"""Independent local protocol peer. Synthetic credentials and document only."""
from pathlib import Path
import socket,threading,subprocess,struct,hashlib,base64,json,time
import os
ROOT=Path(__file__).resolve().parents[2]
BIN=Path(os.environ.get('IPRINT_NATIVE_APP',str(ROOT/'연세 iPrint Native (비공식).app')))/'Contents/MacOS/iPrintNative'
def exact(c,n):
 b=b''
 while len(b)<n:
  v=c.recv(n-len(b))
  if not v:raise ValueError('unexpected EOF')
  b+=v
 return b
def line(c):
 b=b''
 while not b.endswith(b'\n') and len(b)<1024:b+=exact(c,1)
 return b
def fragmented(c,b):
 # Exercise short TCP reads and coalesced line + record responses.
 for n in [1,2,3,5,8,13,1000]:
  if not b:break
  c.sendall(b[:n]);b=b[n:]
 if b:c.sendall(b)
def short(b,o,cap):
 assert b[o]<=cap
 return b[o+1:o+1+b[o]]
def decode(b,salt):
 k=(int(salt)+0x2b67)&65535;out=b''
 for v in bytes.fromhex(b.decode()):
  out+=bytes([v^(k>>8)]);k=((k+v)*0x6009+0xd425)&65535
 return out
def length(b):
 fields=[(0,255),(0x108,255),(0x208,10),(0x215,50),(0x248,20),(0x25d,10),(0x276,50),(0x2a9,255),(0x3a9,50),(0x3dc,50)]
 return sum(4+len(short(b,o,c)) for o,c in fields)+8+4*4+5*3

def run_case(case,upload=False):
 server=socket.socket();server.bind(('127.0.0.1',0));server.listen(2);server.settimeout(6);errors=[];observed={}
 def peer():
  try:
   c,_=server.accept()
   with c:
    c.settimeout(5);assert line(c)==b'USERAUTH:COMMAND\r\n'
    if case=='bad-greeting':c.sendall(b'NO\r\n');return
    fragmented(c,b'UserAuth:Ok\r\n' if case=='mixed-case' else b'USERAUTH:OK\r\n');r=exact(c,471)
    assert r[:8]==b'\0'*8 and decode(short(r,8,50),short(r,465,5))==b'NativeTest'
    assert short(r,59,56)==base64.b64encode(hashlib.sha1(b'Native-Test-17').hexdigest().encode())
    if case=='bad-password':c.sendall(b'AUTHUSERPROC:FAIL\r\n');return
    r=bytearray(r);struct.pack_into('<ii',r,402,300,700)
    r[116:121]=b'\x04Test'
    if case=='wrong-user':r[9]^=1
    if case=='bad-field':r[8]=255
    if case=='short-response':c.sendall(b'AUTHUSERPROC:OK\r\n'+r[:100]);return
    fragmented(c,(b'AuthUserProc:Ok\r\n' if case=='mixed-case' else b'AUTHUSERPROC:OK\r\n')+r)
   if not upload:return
   c,_=server.accept()
   with c:
    c.settimeout(5);assert line(c)==b'TASA_V300\r\n';assert exact(c,3)==b'004'
    header=b''
    while not header.endswith(b'#$A') and len(header)<20:header+=exact(c,1)
    r=exact(c,1057);assert int(header[:-3])==length(r)
    observed.update(metadata_size=int(header[:-3]),record_bytes=len(r),document_bytes=struct.unpack_from('<Q',r,256)[0])
    assert short(r,533,50)==b'Samsung M4370 5370 Series'
    assert short(r,520,10)==b'A4';assert struct.unpack_from('<H',r,531)[0]==1
    assert struct.unpack_from('<HHHHHH',r,616)==(ord('M'),1,0,1,1,ord('S'))
    assert struct.unpack_from('<H',r,628)[0]==ord('R')
    assert decode(short(r,630,50),short(r,1051,5))==b'NativeTest'
    if case=='reject-record':c.sendall(b'1005');return
    fragmented(c,b'0000');assert line(c)==b'1.0.0.0\r\n';out=b''
    for i,n in enumerate([32768,32768,4464]):
     out+=exact(c,n)
     if case=='reject-chunk' and i==0:c.sendall(b'1006');return
     fragmented(c,b'0000')
    assert out==bytes(i%251 for i in range(70000))
    if case=='drop-final':return
    fragmented(c,b'1007' if case=='reject-final' else b'0000')
  except Exception as e:errors.append(repr(e))
  finally:server.close()
 thread=threading.Thread(target=peer,daemon=True);thread.start()
 result=subprocess.run([str(BIN),'--test-network','127.0.0.1',str(server.getsockname()[1]),'upload' if upload else 'auth'],capture_output=True,text=True,timeout=15)
 thread.join(7);assert not thread.is_alive(),case
 assert not errors,(case,errors,result.stdout,result.stderr)
 data=json.loads(result.stdout);expected=case in ['success','mixed-case'];assert data['success']==expected,(case,data)
 if expected:assert data['credit']==700
 if case in ['reject-chunk','reject-final','drop-final']:assert '불확실' in data['error']
 return {'case':case,'upload':upload,'passed':True,**observed}
if __name__=='__main__':
 cases=[run_case('success'),run_case('success',True),run_case('mixed-case')]
 cases.extend(run_case(c) for c in ['bad-greeting','bad-password','wrong-user','bad-field','short-response'])
 cases.extend(run_case(c,True) for c in ['reject-record','reject-chunk','reject-final','drop-final'])
 report={'all_passed':True,'cases':cases,'school_network_contacted':False,'credentials':'synthetic only'}
 print(json.dumps(report,indent=2))
