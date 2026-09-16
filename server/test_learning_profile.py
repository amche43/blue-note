import time
import test_community
import community as app
class ProfileTest(test_community.CommunityTest):
    test_community_delivery_and_ownership=None
    def test_valid_public_work_age_dedup_help_and_private_totals(self):
        uid=self.call(self.a,'GET','/v1/me')['id'];path='/v1/profiles/'+uid
        q={key:'' for key in app.FIELDS}
        q.update(title='题目',subject='高数',prompt='只拍照',deleted=False,notebookId='book-'+'c'*32,notebookTitle='知识本',questionNumber='1',contentKind='knowledge')
        self.call(self.a,'POST','/v1/questions',dict(requestId='1'*32,question=q,consent=True))
        self.assertEqual(self.call(self.b,'GET',path)['counts']['first'],0)
        ids=[]
        for n in range(3):
            item={**q,'prompt':'题目'+str(n),'answer':'我的解释','questionNumber':str(n+2)}
            ids.append(self.call(self.a,'POST','/v1/questions',dict(requestId=str(n+2)*32,question=item,consent=True))['id'])
        duplicate={**q,'prompt':'题目0','answer':'我的解释','questionNumber':'5'}
        self.call(self.a,'POST','/v1/questions',dict(requestId='5'*32,question=duplicate,consent=True))
        counts=self.call(self.b,'GET',path)['counts'];self.assertEqual(counts['first'],3);self.assertEqual(counts['knowledge'],3);self.assertEqual(counts['open'],0)
        with app.connect(self.db) as db:db.execute('UPDATE questions SET created=?,qualified_at=? WHERE owner=?',(time.time_ns()-8*86400*10**9,time.time_ns()-8*86400*10**9,uid))
        self.assertEqual(self.call(self.b,'GET',path)['counts']['open'],1)
        for qid in ids:
            self.call(self.b,'PUT','/v1/questions/'+qid+'/helpful',dict(value=True))
            self.call(self.b,'PUT','/v1/questions/'+qid+'/helpful',dict(value=True))
        self.assertEqual(self.call(self.a,'GET',path)['counts']['helpful'],1)
        self.call(self.a,'PUT','/v1/questions/'+ids[0]+'/helpful',dict(value=True),400)
        for qid in ids:self.call(self.b,'PUT','/v1/questions/'+qid+'/helpful',dict(value=False))
        self.assertEqual(self.call(self.b,'GET',path)['counts']['helpful'],0)
        self.call(self.a,'PUT',path,dict(counts={'knowledge':99999}),404)
        self.assertNotIn('token',self.call(self.b,'GET',path))
