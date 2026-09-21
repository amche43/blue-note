import json
import pathlib
import ssl
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import community as app


class CommunityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='blue-note-community-')
        root = pathlib.Path(cls.temp.name)
        cls.db = root / 'community.db'
        cert, key = root / 'cert.pem', root / 'key.pem'
        subprocess.run(['E:/Git/usr/bin/openssl.exe', 'req', '-x509', '-newkey', 'rsa:2048', '-noenc',
                        '-keyout', str(key), '-out', str(cert), '-days', '1', '-subj', '/CN=localhost',
                        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        app.initialize(cls.db)
        cls.a, cls.b = app.provision(cls.db, '甲'), app.provision(cls.db, '乙')
        cls.server = app.serve(cls.db, cert, key, 0)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        context = ssl.create_default_context(cafile=str(cert))
        cls.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=context))

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.temp.cleanup()

    def call(self, token, method, path, body=None, status=200):
        request = urllib.request.Request(f'https://127.0.0.1:{self.server.server_port}{path}',
            data=None if body is None else json.dumps(body).encode(), method=method,
            headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
        try:
            response = self.opener.open(request, timeout=5)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            self.assertEqual(response.status, status)
            return json.load(response)

    def test_canvas_publication_preserves_ink_and_rejects_malformed_documents(self):
        self.assertTrue(self.call(self.a,'GET','/v1/photo-capabilities')['canvasEntries'])
        element = dict(id='stroke',kind='highlight',points=[[10,20],[100,20]],box=[0,0,0,0],
                       color=0xfff9ca45,width=20,text='',note='先检查公式条件',image='',rows=3,columns=3)
        document = dict(version=1,height=1600,ruled=True,elements=[element])
        q = {key: '' for key in app.FIELDS}
        q.update(title='手写画布',subject='高数',deleted=False,canvas=json.dumps(document))
        body = dict(requestId='9ac0'*8,question=q,consent=True)
        published = self.call(self.a,'POST','/v1/questions',body)
        try:
            package = self.call(self.b,'GET','/v1/questions/'+published['id'])['package']
            self.assertEqual(json.loads(package['question']['canvas']), document)
            bad = {**document,'elements':[{**element,'points':[[float('inf'),20]]}]}
            self.call(self.a,'POST','/v1/questions',{**body,'requestId':'9ac1'*8,'question':{**q,'canvas':json.dumps(bad)}},400)
            self.call(self.a,'POST','/v1/questions',{**body,'requestId':'9ac2'*8,'question':{**q,'canvas':json.dumps({**document,'elements':[]})}},400)
        finally:
            self.call(self.a,'DELETE','/v1/questions/'+published['id'])

    def test_community_delivery_and_ownership(self):
        self.call('bad', 'GET', '/v1/me', status=401)
        q = {key: '' for key in app.FIELDS}
        q.update(title='对称换元', subject='高数', prompt='计算积分', answer='π/4', deleted=False)
        q.update(notebookId='book-'+'e'*32,notebookTitle='我的高数错题本',questionNumber='12')
        body = dict(requestId='a'*32, question=q, consent=False, notes='private')
        self.call(self.a, 'POST', '/v1/questions', body, 400)
        self.assertEqual(self.call(self.a,'GET','/v1/notebooks')['items'],[])
        body['consent'] = True
        result = self.call(self.a, 'POST', '/v1/questions', body)
        qid = result['id']
        self.assertEqual(result, self.call(self.a, 'POST', '/v1/questions', body))
        path = '/v1/questions/' + qid
        listed = self.call(self.b, 'GET', path)
        self.assertNotIn('notes', listed['package'])
        self.assertEqual(listed['package']['author'], '甲')
        self.assertFalse(listed['mine'])
        books=self.call(self.a,'GET','/v1/notebooks')['items']
        self.assertEqual(books[0]['title'],'我的高数错题本')
        self.assertNotEqual(books[0]['id'],q['notebookId'])
        self.assertEqual(self.call(self.b,'GET','/v1/notebooks/'+books[0]['id'])['items'][0]['package']['question']['questionNumber'],'12')
        other=self.call(self.b,'POST','/v1/questions',{**body,'requestId':'d'*32})['id']
        self.assertEqual(len(self.call(self.a,'GET','/v1/notebooks')['items']),2)
        self.call(self.b,'DELETE','/v1/questions/'+other)
        from urllib.parse import urlencode
        knowledge={**q,'contentKind':'knowledge','notebookId':'book-'+'9'*32,'notebookTitle':'必备知识','subject':'线性代数','title':'秩的性质','prompt':'秩的性质与适用条件','questionNumber':'1'}
        kid=self.call(self.a,'POST','/v1/questions',dict(consent=True,requestId='9'*32,question=knowledge))['id']
        def hall(**args): return self.call(self.b,'GET','/v1/hall?'+urlencode(args))['items']
        found=hall(q='线代',kind='knowledge',sort='newest')
        self.assertEqual(len(found),1)
        bid=found[0]['id']
        reaction='/v1/notebooks/'+bid+'/reaction'
        for _ in range(2): self.call(self.b,'PUT',reaction,dict(field='liked',value=True))
        self.call(self.b,'PUT',reaction,dict(field='saved',value=True))
        ranked=hall(sort='likes')
        self.assertEqual(ranked[0]['id'],bid)
        self.assertEqual((ranked[0]['likes'],ranked[0]['saves'],ranked[0]['liked']),(1,1,1))
        self.assertEqual(hall(sort='saves')[0]['id'],bid)
        self.assertEqual(len(hall(saved='1')),1)
        self.assertEqual(self.call(self.a,'GET','/v1/hall?saved=1')['items'],[])
        mine=self.call(self.a,'GET','/v1/hall?sort=likes')['items'][0]
        self.assertEqual(mine['liked'],0)
        self.assertEqual(hall(q='不存在的科目'),[])
        self.assertEqual(hall(q='线代',kind='question'),[])
        self.call(self.b,'PUT',reaction,dict(field='liked',value=False))
        self.assertEqual(hall(kind='knowledge')[0]['likes'],0)
        self.call(self.b,'PUT',reaction,dict(field='other',value=True),400)
        self.call(self.a,'DELETE','/v1/questions/'+kid)
        self.assertEqual(hall(kind='knowledge'),[])
        self.call(self.b,'PUT',reaction,dict(field='saved',value=False),404)
        self.call(self.a,'POST','/v1/questions',{**body,'requestId':'f'*32},409)
        self.call(self.a,'POST','/v1/ocr',{'image':'invalid','consent':False},400)
        self.call(self.a,'POST','/v1/ocr',{'image':'invalid','consent':True},400)
        self.call(self.b, 'DELETE', path, status=403)
        self.call(self.b, 'PUT', path+'/like', {'liked': True})
        self.assertEqual(self.call(self.b, 'PUT', path+'/like', {'liked': True})['likes'], 1)
        self.assertEqual(self.call(self.b, 'PUT', path+'/like', {'liked': False})['likes'], 0)
        comment = dict(requestId='b'*32, body='可以补充适用条件')
        cid = self.call(self.b, 'POST', path+'/comments', comment)['id']
        self.call(self.b, 'POST', path+'/comments', comment)
        self.call(self.a, 'DELETE', '/v1/comments/'+cid)
        self.assertEqual(len(self.call(self.a, 'GET', path+'/comments')['items']), 1)
        self.call(self.b, 'DELETE', '/v1/comments/'+cid)
        self.assertEqual(self.call(self.a, 'GET', path+'/comments')['items'], [])
        feedback = dict(requestId='c'*32, lesson=qid, title=q['title'], body='答案可能缺少条件')
        receipt = self.call(self.b, 'POST', '/v1/feedback', feedback)
        self.assertEqual(receipt['status'], 'pending')
        self.assertEqual(receipt, self.call(self.b, 'POST', '/v1/feedback', feedback))
        self.assertEqual(self.call(self.a, 'GET', '/v1/feedback')['items'], [])
        self.call(self.b, 'POST', '/v1/feedback', {**feedback, 'body':'changed'}, 409)
        self.call(self.b, 'PUT', '/v1/feedback', {'status':'resolved'}, 404)
        with app.connect(self.db) as db:
            db.execute("UPDATE feedback SET status='reviewing',reply='正在核对' WHERE id=?", (receipt['id'],))
        self.assertEqual(self.call(self.b, 'GET', '/v1/feedback')['items'][0]['status'], 'reviewing')
        with app.connect(self.db) as db:
            db.execute("UPDATE feedback SET status='resolved',reply='已补充条件' WHERE id=?", (receipt['id'],))
        # Reinitializing an existing database preserves committed records.
        app.initialize(self.db)
        self.assertEqual(self.call(self.b, 'POST', '/v1/feedback', feedback)['status'], 'resolved')
        self.call(self.a, 'DELETE', path)
        self.call(self.b, 'GET', path, status=404)
        self.assertEqual(self.call(self.b, 'GET', '/v1/questions')['items'], [])


if __name__ == '__main__':
    unittest.main()
