"""Queue queries/deletion against a synthetic loopback server only."""
from pathlib import Path
import base64,hashlib,json,os,socket,struct,subprocess,sys,threading
sys.path.insert(0,str(Path(__file__).parent))
from test_protocol import exact,line,fragmented,short,decode
ROOT=Path(__file__).resolve().parents[2]
BIN=Path(os.environ.get('IPRINT_NATIVE_BINARY',str(ROOT/'연세 iPrint Native (비공식).app/Contents/MacOS/iPrintNative')))
ROW='123&2026-10-18 12:34:56&한글 문서.pdf&A4&10&50&Samsung M4370 5370 Series&C&M'
ROW2='456&2026-10-18 12:35:56&Second.pdf&A4&1&50&Samsung M4370 5370 Series&C&M'

def case(mode):
    server=socket.socket();server.bind(('127.0.0.1',0));server.listen(8);server.settimeout(.2)
    port=server.getsockname()[1];stop=threading.Event();errors=[];commands=[];deletions=[];queries=0
    def peer():
        nonlocal queries
        try:
            while not stop.is_set():
                try:c,_=server.accept()
                except socket.timeout:continue
                with c:
                    c.settimeout(4);command=line(c);commands.append(command.decode().strip())
                    if command==b'USERAUTH:COMMAND\r\n':
                        fragmented(c,b'UserAuth:Ok\r\n');r=bytearray(exact(c,471))
                        assert decode(short(r,8,50),short(r,465,5))==b'NativeTest'
                        assert short(r,59,56)==base64.b64encode(hashlib.sha1(b'Native-Test-17').hexdigest().encode())
                        if mode=='auth-denied':c.sendall(b'AUTHUSERPROC:FAIL\r\n');continue
                        r[116:121]=b'\x04Test';struct.pack_into('<ii',r,402,300,700)
                        fragmented(c,b'AuthUserProc:Ok\r\n'+r)
                    elif command==b'GETWAITJOBLIST:COMMAND\r\n':
                        queries+=1
                        if mode=='query-denied':c.sendall(b'GETWAITJOBLIST:NO\r\n');continue
                        c.sendall(b'GetWaitJobList:Ok\r\n');r=exact(c,57)
                        assert decode(short(r,0,50),short(r,51,5))==b'NativeTest'
                        assert r[1+r[0]:51]==b'\0'*(50-r[0]);assert r[52+r[51]:]==b'\0'*(5-r[51])
                        body=ROW+';'+ROW2+';'
                        if mode=='empty':body=''
                        elif mode=='stale' and queries==2:body=ROW2+';'
                        elif mode=='changed' and queries==2:body=ROW.replace('한글 문서.pdf','Changed.pdf')+';'+ROW2+';'
                        elif deletions and mode not in ['still-listed']:body=ROW2+';'
                        if mode=='malformed':body='123&title'
                        elif mode=='duplicate':body=ROW+';'+ROW+';'
                        elif mode=='command-injection':body=ROW.replace('123&','123\rWAITJOBDEL&',1)
                        elif mode=='negative-id':body=ROW.replace('123&','-1&',1)
                        elif mode=='bad-pages':body=ROW.replace('&10&50&','&x&50&')
                        elif mode=='oversized':body='x'*(1024*1024+1)
                        elif mode=='large-list':body=';'.join(ROW.replace('123&',str(n)+'&',1) for n in range(1,101))+';'
                        elif mode=='quoted-separator':body=ROW.replace('한글 문서.pdf','"한글; 문서.pdf"')+';'
                        elif mode=='legacy-seven-fields':body='&'.join(ROW.split('&')[:7])+';'
                        elif mode=='post-query-dropped' and queries==3:continue
                        if mode=='truncated':c.sendall(body.encode('cp949'));continue
                        try:fragmented(c,body.encode('cp949')+b'\r\n')
                        except (ConnectionResetError,BrokenPipeError):
                            if mode!='oversized':raise
                    elif command==b'WAITJOBDEL:COMMAND\r\n':
                        if mode=='delete-denied':c.sendall(b'WAITJOBDEL:NO\r\n');assert c.recv(1)==b'';continue
                        fragmented(c,b'WaitJobDel:Ok\r\n');job=line(c);assert job==b'123\r\n';deletions.append(job.decode().strip())
                        # Original server protocol provides no final acknowledgement.
                    else:raise AssertionError(command)
        except Exception as e:errors.append(repr(e))
        finally:server.close()
    thread=threading.Thread(target=peer,daemon=True);thread.start()
    deleting=mode in ['delete','stale','changed','delete-denied','still-listed','post-query-dropped']
    result=subprocess.run([str(BIN),'--test-network','127.0.0.1',str(port),'queue-delete' if deleting else 'queue-list'],capture_output=True,text=True,timeout=25)
    stop.set();thread.join(5)
    assert not thread.is_alive() and not errors,(mode,errors,result.stdout,result.stderr)
    data=json.loads(result.stdout)
    success=mode in ['list','empty','delete','large-list','quoted-separator','legacy-seven-fields']
    assert data['success']==success,(mode,data)
    if mode=='list':assert data['jobs'][0]['title']=='한글 문서.pdf' and data['jobs'][0]['pages']==10 and len(data['jobs'])==2
    if mode=='empty':assert not data['jobs']
    if mode=='delete':assert len(data['jobs'])==1 and data['jobs'][0]['id']=='456'
    if mode=='large-list':assert len(data['jobs'])==100
    if mode=='quoted-separator':assert data['jobs'][0]['title']=='"한글; 문서.pdf"'
    if mode=='legacy-seven-fields':assert data['jobs'][0]['source']==''
    assert deletions==(['123'] if mode in ['delete','still-listed','post-query-dropped'] else []),(mode,deletions)
    if mode in ['stale','changed']:assert 'WAITJOBDEL:COMMAND' not in commands
    return {'case':mode,'passed':True,'queries':queries,'delete_commands':commands.count('WAITJOBDEL:COMMAND'),'job_ids_sent':len(deletions)}

if __name__=='__main__':
    modes=['list','empty','delete','auth-denied','query-denied','stale','changed','delete-denied','still-listed','post-query-dropped','truncated','malformed','duplicate','command-injection','negative-id','bad-pages','oversized','large-list','quoted-separator','legacy-seven-fields']
    results=[case(mode) for mode in modes]
    print(json.dumps({'passed':True,'school_network_contacted':False,'synthetic_only':True,'cases':results},indent=2))
