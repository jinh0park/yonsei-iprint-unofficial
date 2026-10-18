"""Synthetic local read-only GETUSER peer; never connects to a school server."""
from pathlib import Path
import os,socket,threading,subprocess,json,struct,base64,hashlib,sys
sys.path.insert(0,str(Path(__file__).parent))
from test_protocol import exact,line,fragmented,short,decode
ROOT=Path(__file__).resolve().parents[2]
BIN=Path(os.environ.get('IPRINT_NATIVE_BINARY',str(ROOT/'연세 iPrint Native (비공식).app/Contents/MacOS/iPrintNative')))
def put(r,off,value,encoding='ascii'):
 b=value.encode(encoding);r[off]=len(b);r[off+1:off+1+len(b)]=b

def case(mode):
 server=socket.socket();server.bind(('127.0.0.1',0));server.listen(4);server.settimeout(5);port=server.getsockname()[1];errors=[];commands=[];profile={'name':'가나다','phone':'01012345678','email':'native@example.com'}
 def auth_request(c):
  r=exact(c,471);assert decode(short(r,8,50),short(r,465,5))==b'NativeTest'
  assert short(r,59,56)==base64.b64encode(hashlib.sha1(b'Native-Test-17').hexdigest().encode());return r
 def reply(r):
  r=bytearray(r);put(r,116,profile['name'],'cp949');put(r,351,profile['phone']);put(r,300,profile['email']);put(r,137,'ExistingPIN');struct.pack_into('<ii',r,402,300,700);return r
 def peer():
  try:
   c,_=server.accept()
   with c:
    c.settimeout(3);command=line(c);commands.append(command);assert command==b'USERAUTH:COMMAND\r\n';c.sendall(b'UserAuth:Ok\r\n');r=auth_request(c);fragmented(c,b'AuthUserProc:Ok\r\n'+reply(r))
   c,_=server.accept()
   with c:
    c.settimeout(3);command=line(c);commands.append(command);assert command==b'GETUSER:COMMAND\r\n'
    if mode=='get-rejected':c.sendall(b'GETUSER:NO\r\n');return
    c.sendall(b'GetUser:Ok\r\n');r=auth_request(c);fragmented(c,b'GetUserProc:Ok\r\n'+reply(r))
  except Exception as e:errors.append(repr(e))
  finally:server.close()
 t=threading.Thread(target=peer,daemon=True);t.start();op='profile-read'
 r=subprocess.run([str(BIN),'--test-network','127.0.0.1',str(port),op],capture_output=True,text=True,timeout=15);t.join(6)
 assert not t.is_alive() and not errors,(mode,errors,r.stdout,r.stderr)
 value=json.loads(r.stdout);assert value['success']==(mode=='read-only'),(mode,value)
 assert commands==[b'USERAUTH:COMMAND\r\n',b'GETUSER:COMMAND\r\n']
 if mode=='read-only':assert {k:value[k] for k in profile}==profile
 return {'case':mode,'passed':True,'update_requests':0}
if __name__=='__main__':
 results=[case(x) for x in ['read-only','get-rejected']]
 print(json.dumps({'passed':True,'synthetic_only':True,'cases':results},indent=2))
