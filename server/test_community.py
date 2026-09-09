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

    def test_community_delivery_and_ownership(self):
        self.call('bad', 'GET', '/v1/me', status=401)
        q = {key: '' for key in app.FIELDS}
        q.update(title='对称换元', subject='高数', prompt='计算积分', answer='π/4', deleted=False)
        body = dict(requestId='a'*32, question=q, consent=False, notes='private')
        self.call(self.a, 'POST', '/v1/questions', body, 400)
        body['consent'] = True
        result = self.call(self.a, 'POST', '/v1/questions', body)
        qid = result['id']
        self.assertEqual(result, self.call(self.a, 'POST', '/v1/questions', body))
        path = '/v1/questions/' + qid
        listed = self.call(self.b, 'GET', path)
        self.assertNotIn('notes', listed['package'])
        self.assertEqual(listed['package']['author'], '甲')
        self.assertFalse(listed['mine'])
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
