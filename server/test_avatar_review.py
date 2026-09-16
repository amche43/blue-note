import base64
import io
from PIL import Image
import test_community
import community as app
import avatar_review


class AvatarTest(test_community.CommunityTest):
    test_community_delivery_and_ownership=None

    def test_moderation_privacy_and_stale_requests(self):
        def photo(color):
            buf=io.BytesIO();Image.new('RGB',(64,64),color).save(buf,format='PNG')
            return base64.b64encode(buf.getvalue()).decode()
        def submit(rid,color):
            return self.call(self.a,'POST','/v1/me/avatar',dict(requestId=rid*32,image=photo(color),consent=True,status='approved'))
        first=submit('1','blue')
        self.assertEqual(first['status'],'pending')
        self.assertEqual(submit('1','blue'),first)
        self.call(self.a,'POST','/v1/me/avatar',dict(requestId='1'*32,image=photo('red'),consent=True),409)
        self.assertEqual(self.call(self.a,'GET','/v1/me')['avatarImage'],'')
        self.assertIsNone(self.call(self.b,'GET','/v1/me/avatar')['request'])
        self.call(self.a,'POST','/v1/admin/avatars',dict(id=first['id'],approved=True),404)
        second=submit('2','red')
        with app.connect(self.db) as db:
            with self.assertRaises(ValueError):avatar_review.review(db,first['id'],True)
        with app.connect(self.db) as db:avatar_review.review(db,second['id'],True)
        approved=self.call(self.a,'GET','/v1/me')['avatarImage']
        self.assertTrue(approved)
        image=Image.open(io.BytesIO(base64.b64decode(approved)))
        self.assertEqual(image.size,(128,128))
        third=submit('3','green')
        self.assertEqual(self.call(self.a,'GET','/v1/me')['avatarImage'],approved)
        with app.connect(self.db) as db:avatar_review.review(db,third['id'],False,'图片不符合头像要求')
        status=self.call(self.a,'GET','/v1/me/avatar')
        self.assertEqual(status['request']['status'],'rejected')
        self.assertEqual(status['activeImage'],approved)
        fourth=submit('4','white')
        self.call(self.a,'PUT','/v1/me',dict(name='甲',avatar=2,useDefault=True))
        self.assertEqual(self.call(self.a,'GET','/v1/me')['avatarImage'],'')
        with app.connect(self.db) as db:
            with self.assertRaises(ValueError):avatar_review.review(db,fourth['id'],True)
        fifth=submit('5','black')
        self.call(self.b,'DELETE','/v1/me/avatar')
        self.assertEqual(self.call(self.a,'GET','/v1/me/avatar')['request']['status'],'pending')
        self.call(self.a,'DELETE','/v1/me/avatar')
        with app.connect(self.db) as db:
            with self.assertRaises(ValueError):avatar_review.review(db,fifth['id'],True)
        self.call(self.a,'POST','/v1/me/avatar',dict(requestId='6'*32,image='invalid',consent=True),400)
        self.call(self.a,'POST','/v1/me/avatar',dict(requestId='7'*32,image=photo('blue'),consent=False),400)


if __name__=='__main__':
    import unittest
    unittest.main()
