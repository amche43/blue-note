"""Start an isolated service; test auth, two clients, conflicts and restart persistence."""
import json,os,pathlib,secrets,subprocess,tempfile,time,urllib.request,urllib.error,socket
root=pathlib.Path(__file__).resolve().parent
java=os.environ.get('BLUE_NOTE_JAVA','java')
def run():
    with tempfile.TemporaryDirectory(prefix='blue-note-sync-test-') as scratch:
        token=secrets.token_hex(24)
        with socket.socket() as probe:
            probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
        env=os.environ.copy();env.update(BLUE_NOTE_TOKEN=token,BLUE_NOTE_PORT=str(port),BLUE_NOTE_BIND='127.0.0.1',BLUE_NOTE_DATA=str(pathlib.Path(scratch)/'journal.json'))
        def start():
            p=subprocess.Popen([java,'--add-modules','jdk.httpserver',str(root/'BlueNoteServer.java')],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            for _ in range(100):
                if p.poll() is not None:raise RuntimeError(p.stderr.read().decode(errors='replace'))
                try:
                    with socket.create_connection(('127.0.0.1',port),timeout=.2):return p
                except OSError:time.sleep(.1)
            p.terminate();raise RuntimeError('Server did not start')
        def post(events,key=token,schema=1):
            data=json.dumps({'schemaVersion':schema,'events':events},ensure_ascii=False).encode()
            req=urllib.request.Request(f'http://127.0.0.1:{port}/v1/sync',data=data,headers={'Authorization':'Bearer '+key,'Content-Type':'application/json'})
            with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(req,timeout=10) as response:return json.load(response)
        a={'id':'a'*32,'lessonId':'math-symmetry','type':'note','at':1000,'payload':{'text':'先互换，再相加。'}}
        b={'id':'b'*32,'lessonId':'math-symmetry','type':'attempt','at':2000,'payload':{'rating':'good','correct':True,'assisted':False,'variantId':'sym-near','reason':'没有卡住'}}
        process=start()
        try:
            try:post([],key='wrong');raise AssertionError('Unauthorized request accepted')
            except urllib.error.HTTPError as error:assert error.code==401
            assert len(post([a])['events'])==1
            assert len(post([b])['events'])==2
            assert len(post([a,b])['events'])==2
            c=dict(a,id='c'*32)
            conflicting=dict(a,payload={'text':'冲突修改'})
            try:post([c,conflicting]);raise AssertionError('Conflict accepted')
            except urllib.error.HTTPError as error:assert error.code==400
            assert len(post([])['events'])==2
            process.terminate();process.wait(timeout=10)
            process=start()
            restored=post([])['events']
            assert len(restored)==2
            assert next(e for e in restored if e['id']==a['id'])['payload']['text']=='先互换，再相加。'
            fields={key:'' for key in ['title','subject','chapter','prompt','formula','answer','trigger','action','conditions','pitfall','source','origin']}
            fields.update(title='自己的题目',subject='高等数学',prompt='题干',deleted=False)
            question={'id':'d'*32,'lessonId':'user-'+'e'*32,'type':'question','at':3000,'payload':fields}
            try:post([question]);raise AssertionError('V1 accepted question revision')
            except urllib.error.HTTPError as error:assert error.code==400
            merged=post([question],schema=2)
            assert merged['schemaVersion']==2 and len(merged['events'])==3
            assert len(post([question],schema=2)['events'])==3
            broken=dict(question,id='f'*32,payload=dict(fields,prompt=''))
            try:post([broken],schema=2);raise AssertionError('Empty question accepted')
            except urllib.error.HTTPError as error:assert error.code==400
            process.terminate();process.wait(timeout=10)
            process=start()
            restored=post([],schema=2)
            assert restored['schemaVersion']==2 and len(restored['events'])==3
            assert next(e for e in restored['events'] if e['type']=='question')['payload']['title']=='自己的题目'
            print('PASS: authentication, two-device merge, idempotency, atomic conflicts, restart persistence, v1/v2 migration and custom questions')
        finally:
            process.terminate();process.wait(timeout=10)
            errors=process.stderr.read().decode(errors='replace')
            if errors: print(errors)
if __name__=='__main__':run()
