"""Local peer only. Never creates an actual school account."""
import os,socket,threading,subprocess,json,sys,hashlib,base64
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from test_protocol import exact,line,fragmented,short,decode
ROOT=Path(__file__).resolve().parents[2]
BIN=Path(os.environ.get('IPRINT_NATIVE_BINARY',str(ROOT/'연세 iPrint Native (비공식).app/Contents/MacOS/iPrintNative')))
def case(mode):
 server=socket.socket();server.bind(('127.0.0.1',0));server.listen(3);server.settimeout(4);errors=[];writes=[]
 def peer():
  try:
   c,_=server.accept()
   with c:
    c.settimeout(3);assert line(c)==b'USERDUP:COMMAND\r\n'
    if mode=='duplicate-handshake-rejected':c.sendall(b'USERDUP:NO\r\n');return
    c.sendall(b'UserDup:Ok\r\n');r=exact(c,471)
    assert decode(short(r,8,50),short(r,465,5))==b'NativeTest'
    assert short(r,116,20)=='가나다'.encode('cp949')
    assert short(r,137,50)==short(r,188,50)==short(r,8,50)
    assert short(r,239,60)==base64.b64encode(hashlib.sha1(b'NativeTest').hexdigest().encode())
    assert short(r,59,56)==base64.b64encode(hashlib.sha1(b'Native-Test-17').hexdigest().encode())
    assert short(r,300,50)==b'native@example.com' and short(r,351,50)==b'01012345678'
    if mode=='duplicate':c.sendall(b'IDUSE:NO\r\n');return
    c.sendall(b'IdUse:Ok\r\n');assert line(c)==b'USERINS:COMMAND\r\n'
    if mode=='insert-handshake-rejected':c.sendall(b'ADDUSER:NO\r\n');return
    c.sendall(b'AddUser:Ok\r\n');assert exact(c,471)==r;writes.append(True)
    if mode=='insert-response-lost':return
    if mode=='insert-rejected':c.sendall(b'ADDUSERINS:NO\r\n');return
    if mode=='insert-error':c.sendall(b'AddUserIns:Error\r\n');return
    if mode=='insert-empty':c.sendall(b'\r\n');return
    if mode=='insert-private-response':c.sendall(b'ADDUSERINS:private-person@example.com Native-Test-17\r\n');return
    if mode=='insert-private-detail':c.sendall(b'ADDUSERINS:ERROR:private-person@example.com Native-Test-17\r\n');return
    fragmented(c,b'AddUserIns:Ok\r\n')
   c,_=server.accept()
   with c:
    c.settimeout(3);assert line(c)==b'USERAUTH:COMMAND\r\n';c.sendall(b'USERAUTH:OK\r\n');a=bytearray(exact(c,471))
    name=('다른값' if mode=='name-mismatch' else '가나다').encode('cp949');a[116]=len(name);a[117:117+len(name)]=name
    fragmented(c,b'AUTHUSERPROC:OK\r\n'+a)
  except Exception as e:errors.append(repr(e))
  finally:server.close()
 t=threading.Thread(target=peer,daemon=True);t.start()
 r=subprocess.run([str(BIN),'--test-network','127.0.0.1',str(server.getsockname()[1]),'register'],capture_output=True,text=True,timeout=15);t.join(5)
 assert not t.is_alive() and not errors,(mode,errors,r.stdout,r.stderr)
 value=json.loads(r.stdout);assert value['success']==(mode=='success'),(mode,value)
 if mode in ['duplicate','duplicate-handshake-rejected','insert-handshake-rejected']:assert not writes and not value['registrationMayHaveBeenSent']
 if mode in ['insert-rejected','insert-response-lost','insert-error','insert-empty','insert-private-response','insert-private-detail']:
  assert len(writes)==1 and value['registrationMayHaveBeenSent'] and '가입 여부가 불확실' in value['error']
  assert 'R4' in value['error'] and '접속 서버: 127.0.0.1:' in value['error'] and '앱: ' in value['error']
  expected={'insert-rejected':'ADDUSERINS:NO','insert-response-lost':'응답 수신 실패','insert-error':'ADDUSERINS:ERROR','insert-empty':'빈 응답','insert-private-response':'비표준 응답','insert-private-detail':'ADDUSERINS:ERROR'}
  assert expected[mode] in value['error'],value
  assert all(secret not in value['error'] for secret in ['NativeTest','Native-Test-17','private-person@example.com','01012345678','가나다'])
 if mode=='duplicate':assert 'R2' in value['error'] and 'IDUSE:NO' in value['error']
 if mode=='name-mismatch':assert 'name read-back mismatch' in value['error']
 return {'case':mode,'passed':True,'create_requests':len(writes)}
if __name__=='__main__':print(json.dumps({'passed':True,'school_network_contacted':False,'cases':[case(x) for x in ['success','duplicate','duplicate-handshake-rejected','insert-handshake-rejected','insert-rejected','insert-response-lost','insert-error','insert-empty','insert-private-response','insert-private-detail','name-mismatch']]},indent=2))
