import test_community
import community as app

class ImprovementsTest(test_community.CommunityTest):
    test_community_delivery_and_ownership=None
    def test_review_permissions_retry_conflict_and_public_result(self):
        q={key:'' for key in app.FIELDS}
        q.update(title='改进测试',subject='高数',prompt='题干',answer='旧解析',deleted=False,notebookId='book-'+'9'*32,notebookTitle='共创本',questionNumber='1')
        qid=self.call(self.a,'POST','/v1/questions',dict(requestId='9'*32,question=q,consent=True))['id']
        bid=self.call(self.a,'GET','/v1/notebooks')['items'][0]['id'];path='/v1/notebooks/'+bid+'/improvements'
        current=self.call(self.b,'GET','/v1/questions/'+qid)
        payload=dict(requestId='a'*32,question=qid,base=current['revision'],field='answer',after='新解析',reason='补充条件')
        proposal=self.call(self.b,'POST',path,payload)
        owner_inbox=self.call(self.a,'GET','/v1/inbox')['improvements']
        self.assertEqual(owner_inbox[0]['id'],proposal['id'])
        self.assertEqual(owner_inbox[0]['canReview'],1)
        self.assertEqual(self.call(self.b,'GET','/v1/inbox')['improvements'][0]['canReview'],0)
        self.assertEqual(proposal,self.call(self.b,'POST',path,payload))
        self.call(self.b,'POST',path,{**payload,'after':'变了'},409)
        competing=self.call(self.b,'POST',path,{**payload,'requestId':'b'*32,'after':'另一个解析'})
        self.call(self.b,'PUT',path,dict(id=proposal['id'],status='accepted'),403)
        self.assertEqual(self.call(self.b,'GET','/v1/questions/'+qid)['package']['question']['answer'],'旧解析')
        self.call(self.a,'PUT',path,dict(id=proposal['id'],status='accepted'))
        self.call(self.a,'PUT',path,dict(id=proposal['id'],status='accepted'))
        self.assertEqual(self.call(self.b,'GET','/v1/questions/'+qid)['package']['question']['answer'],'新解析')
        self.call(self.a,'PUT',path,dict(id=competing['id'],status='accepted'),409)
        self.call(self.a,'PUT',path,dict(id=competing['id'],status='rejected'),400)
        self.call(self.a,'PUT',path,dict(id=competing['id'],status='rejected',note='基于旧版本'))
        rows=self.call(self.a,'GET',path)['items']
        self.assertEqual({r['status'] for r in rows},{'accepted','rejected'})
        self.assertEqual(next(r for r in rows if r['status']=='accepted')['before_text'],'旧解析')
        self.assertEqual({r['status'] for r in self.call(self.b,'GET','/v1/inbox')['improvements']},{'accepted','rejected'})
        other=self.call('', 'POST','/v1/auth/register',dict(username='outside_user',password='password-test-123',name='旁观者',avatar=0))
        self.assertEqual(self.call(other['token'],'GET','/v1/inbox')['improvements'],[])
        self.call(self.b,'POST',path,{**payload,'requestId':'c'*32,'field':'firstThought'},400)
        self.call(self.b,'POST',path,{**payload,'requestId':'c'*32},409)
