import test_community
import community as app
import json

class ForkTest(test_community.CommunityTest):
    test_community_delivery_and_ownership = None
    def test_private_copy_retry_and_modified_public_derivative(self):
        q = {k:'' for k in app.FIELDS}
        q.update(title='题目',subject='高数',prompt='求极限',answer='展开',deleted=False,
                 notebookId='book-'+'a'*32,notebookTitle='来源',questionNumber='1')
        self.call(self.a,'POST','/v1/questions',dict(requestId='a'*32,question=q,consent=True))
        book=self.call(self.b,'GET','/v1/notebooks')['items'][0]['id']
        local='book-'+'b'*32
        path='/v1/notebooks/'+book+'/fork'
        snapshot=self.call(self.b,'POST',path,dict(localId=local))
        self.assertTrue(snapshot['items'][0]['id'].startswith('user-'))
        self.assertIn('author',snapshot['items'][0])
        self.assertEqual(snapshot,self.call(self.b,'POST',path,dict(localId=local)))
        updates='/v1/notebooks/'+book+'/source-snapshot'
        self.call('bad','GET',updates,status=401)
        self.assertEqual(snapshot,self.call(self.b,'GET',updates))
        original_id=snapshot['items'][0]['id']
        with app.connect(self.db) as db:
            value=json.loads(db.execute('SELECT package FROM questions WHERE id=?',(original_id,)).fetchone()[0])
            value['question']['answer']='补充适用条件后展开'
            db.execute('UPDATE questions SET package=? WHERE id=?',(json.dumps(value),original_id))
        self.assertEqual(self.call(self.b,'GET',updates)['items'][0]['question']['answer'],'补充适用条件后展开')
        self.assertEqual(snapshot,self.call(self.b,'POST',path,dict(localId=local)))
        with app.connect(self.db) as db:db.execute('UPDATE questions SET active=0 WHERE id=?',(original_id,))
        self.assertEqual(self.call(self.b,'GET',updates)['items'],[])
        with app.connect(self.db) as db:db.execute('UPDATE questions SET active=1 WHERE id=?',(original_id,))
        self.call(self.a,'POST',path,dict(localId=local),400)
        uid=self.call(self.b,'GET','/v1/me')['id']
        profile='/v1/profiles/'+uid
        self.assertEqual(self.call(self.b,'GET',profile)['counts']['fork'],0)
        copy={**q,'notebookId':local,'notebookTitle':'我的版本'}
        self.call(self.b,'POST','/v1/questions',dict(requestId='b'*32,question=copy,consent=True))
        self.assertEqual(self.call(self.b,'GET',profile)['counts']['fork'],0)
        copy.update(summary='先比较展开阶数',questionNumber='2')
        self.call(self.b,'POST','/v1/questions',dict(requestId='c'*32,question=copy,consent=True))
        self.assertEqual(self.call(self.b,'GET',profile)['counts']['fork'],1)
