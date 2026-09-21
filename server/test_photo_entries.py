import base64
import io
from PIL import Image
import test_community
import community as app


class PhotoEntriesTest(test_community.CommunityTest):
    test_community_delivery_and_ownership = None

    def test_photo_only_publication_and_validation(self):
        self.assertTrue(self.call(self.a, 'GET', '/v1/photo-capabilities')['photoEntries'])
        buf = io.BytesIO()
        Image.new('RGB', (20, 20), 'white').save(buf, format='PNG')
        photo = base64.b64encode(buf.getvalue()).decode()
        q = {key: '' for key in app.FIELDS}
        q.update(title='PV 操作理发师问题', subject='操作系统', chapter='进程同步',
                 questionPhoto=photo, answerPhoto=photo, deleted=False,
                 notebookId='book-'+'c'*32, notebookTitle='操作系统错题本', questionNumber='1')
        body = dict(question=q, consent=False, requestId='c'*32)
        self.call(self.a, 'POST', '/v1/questions', body, 400)
        result = self.call(self.a, 'POST', '/v1/questions', dict(body, consent=True))
        detail = self.call(self.b, 'GET', '/v1/questions/'+result['id'])
        self.assertEqual(detail['package']['question']['questionPhoto'], photo)
        self.assertEqual(detail['package']['question']['answerPhoto'], photo)
        self.assertEqual(detail['package']['question']['chapter'], '进程同步')
        bad = dict(q, questionPhoto=base64.b64encode(b'not an image').decode())
        self.call(self.a, 'POST', '/v1/questions', dict(question=bad, consent=True, requestId='d'*32), 400)
        self.call(self.a, 'POST', '/v1/questions', dict(question=dict(q, questionPhoto=''), consent=True, requestId='e'*32), 400)
