import test_community
import community as app


class CollaborationTest(test_community.CommunityTest):
    # Do not inherit the unrelated legacy flow a second time.
    test_community_delivery_and_ownership = None

    def test_logout_revokes_token(self):
        self.call(self.a, 'GET', '/v1/me')
        self.assertTrue(self.call(self.a, 'POST', '/v1/auth/logout', {})['signedOut'])
        self.call(self.a, 'GET', '/v1/me', status=401)
        self.call(self.b, 'GET', '/v1/me')

    def test_accounts_and_collaboration(self):
        reg=dict(username='learner_test',password='test-password-123',name='新同学',avatar=11)
        user=self.call('', 'POST','/v1/auth/register',reg)
        self.call('', 'POST','/v1/auth/register',reg,409)
        self.call('', 'POST','/v1/auth/login',{**reg,'password':'wrong-password'},401)
        logged=self.call('', 'POST','/v1/auth/login',reg)
        self.call(user['token'],'GET','/v1/me',status=401)
        self.assertEqual(self.call(logged['token'],'GET','/v1/me')['id'],user['id'])
        self.assertEqual(logged['avatar'],11)
        self.assertEqual(self.call(logged['token'],'GET','/v1/me')['avatar'],11)
        self.call(self.b,'PUT','/v1/me',dict(name='乙',avatar=13))
        self.call(self.b,'PUT','/v1/me',dict(name='乙',avatar=16),400)
        with app.connect(self.db) as db:
            credential=db.execute('SELECT * FROM credentials WHERE username=?',(reg['username'],)).fetchone()
            self.assertNotIn(reg['password'],str(dict(credential)))
        q={key:'' for key in app.FIELDS}
        q.update(title='协作条目',subject='高数',prompt='学习内容',deleted=False,notebookId='book-'+'7'*32,notebookTitle='协作测试本',questionNumber='1')
        self.call(self.a,'POST','/v1/questions',dict(requestId='7'*32,question=q,consent=True))
        bid=self.call(self.a,'GET','/v1/notebooks')['items'][0]['id']
        path='/v1/notebooks/'+bid
        self.call(self.b,'GET',path+'/messages',status=403)
        self.call(self.b,'PUT',path+'/description',dict(description='偷改',version=0),403)
        self.call(self.b,'POST',path+'/apply',dict(reason='一起完善'))
        self.call(self.b,'POST',path+'/apply',dict(reason='一起完善'))
        inbox=self.call(self.a,'GET','/v1/inbox')
        self.assertEqual(len(inbox['applications']),1)
        aid=inbox['applications'][0]['id']
        self.call(self.b,'PUT',path+'/applications',dict(id=aid,status='accepted'),403)
        self.call(self.a,'PUT',path+'/applications',dict(id=aid,status='accepted'))
        self.call(self.a,'PUT',path+'/applications',dict(id=aid,status='accepted'))
        self.call(self.a,'PUT',path+'/applications',dict(id=aid,status='rejected'),409)
        self.assertEqual(len(self.call(self.b,'GET','/v1/inbox')['rooms']),1)
        self.assertTrue(self.call(self.b,'GET',path+'/workspace')['member'])
        self.call(self.a,'PUT',path+'/description',dict(description='第一版',version=0))
        self.call(self.b,'PUT',path+'/description',dict(description='第二版',version=0),409)
        self.call(self.b,'PUT',path+'/description',dict(description='第二版',version=1))
        self.assertEqual(len(self.call(self.a,'GET',path+'/workspace')['history']),2)
        payload=dict(requestId='8'*32,body='一起检查第1题\n[蓝笔表情:一起冲]')
        first=self.call(self.b,'POST',path+'/messages',payload)
        self.assertEqual(first,self.call(self.b,'POST',path+'/messages',payload))
        self.call(self.b,'POST',path+'/messages',{**payload,'body':'另一个内容'},409)
        messages=self.call(self.a,'GET',path+'/messages')['items']
        self.assertEqual(len(messages),1)
        self.assertEqual(messages[0]['avatar'],13)
        self.assertEqual(messages[0]['body'],payload['body'])
        self.assertEqual(inbox['applications'][0]['avatar'],13)
        self.call(logged['token'],'GET',path+'/messages',status=403)
        self.assertEqual(self.call(logged['token'],'GET','/v1/inbox')['applications'],[])


if __name__=='__main__':
    import unittest
    unittest.main()
