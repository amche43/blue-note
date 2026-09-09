"""Local-only community prototype. Python standard library + SQLite; HTTPS required.
Each provisioned tester has a separate bearer credential. Not a public deployment.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import pathlib
import re
import secrets
import sqlite3
import ssl
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LIMIT = 512 * 1024
FIELDS = dict(title=120, subject=60, chapter=120, prompt=18000, formula=4000,
              answer=18000, trigger=4000, action=4000, conditions=4000,
              pitfall=4000, source=1000, origin=80)


@contextmanager
def connect(path):
    db = sqlite3.connect(path, timeout=15)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA foreign_keys=ON')
    try:
        with db:
            yield db
    finally:
        db.close()


def initialize(path):
    pathlib.Path(path).parent.mkdir(parents=True, exist_ok=True)
    with connect(path) as db:
        db.executescript('''
        CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, name TEXT NOT NULL, token TEXT UNIQUE NOT NULL);
        CREATE TABLE IF NOT EXISTS questions(id TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES users(id),
          request_id TEXT NOT NULL, package TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1,
          created INTEGER NOT NULL, UNIQUE(owner,request_id));
        CREATE TABLE IF NOT EXISTS comments(id TEXT PRIMARY KEY, question TEXT NOT NULL REFERENCES questions(id),
          owner TEXT NOT NULL REFERENCES users(id), request_id TEXT NOT NULL, body TEXT NOT NULL,
          created INTEGER NOT NULL, UNIQUE(owner,request_id));
        CREATE TABLE IF NOT EXISTS likes(question TEXT NOT NULL REFERENCES questions(id),
          owner TEXT NOT NULL REFERENCES users(id), PRIMARY KEY(question,owner));
        CREATE TABLE IF NOT EXISTS feedback(id TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES users(id),
          request_id TEXT NOT NULL, lesson TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending', reply TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL,
          UNIQUE(owner,request_id));
        ''')


def provision(path, name):
    token = secrets.token_hex(32)
    with connect(path) as db:
        db.execute('INSERT INTO users VALUES(?,?,?)',
                   (secrets.token_hex(16), name, hashlib.sha256(token.encode()).hexdigest()))
    return token


class Invalid(Exception):
    def __init__(self, message, status=400):
        self.message, self.status = message, status


def text(body, key, maximum, required=True):
    value = body.get(key)
    if not isinstance(value, str) or len(value) > maximum or (required and not value.strip()):
        raise Invalid('请检查填写内容：' + key)
    return value.strip()


def request_id(body):
    value = text(body, 'requestId', 32)
    if not re.fullmatch('[a-f0-9]{32}', value):
        raise Invalid('请求编号不正确')
    return value


def package(body, author):
    if body.get('consent') is not True:
        raise Invalid('需要明确同意公开此题')
    value = body.get('question')
    if not isinstance(value, dict) or value.get('deleted') is not False:
        raise Invalid('题目格式不正确')
    q = {key: text(value, key, size, key in ('title', 'subject', 'prompt'))
         for key, size in FIELDS.items()}
    q.update(origin='', deleted=False)
    return dict(format='blue-note-question', version=1, author=author, question=q)


class Handler(BaseHTTPRequestHandler):
    server_version = 'BlueNoteLocal/0.3'

    def log_message(self, *_):
        pass  # No credentials or user content in request logs.

    def setup(self):
        super().setup()
        self.connection.settimeout(15)

    def send_json(self, status, value):
        raw = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(raw)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(raw)

    def dispatch(self):
        try:
            with connect(self.server.db_path) as db:
                auth = self.headers.get('Authorization', '')
                digest = hashlib.sha256(auth.removeprefix('Bearer ').encode()).hexdigest()
                user = db.execute('SELECT * FROM users WHERE token=?', (digest,)).fetchone() if auth.startswith('Bearer ') else None
                if user is None:
                    raise Invalid('连接口令无效，请重新导入连接配置', 401)
                body = {}
                if self.command in ('POST', 'PUT'):
                    if self.headers.get('Transfer-Encoding'):
                        raise Invalid('不支持此传输格式')
                    try:
                        size = int(self.headers.get('Content-Length', '0'))
                    except ValueError:
                        raise Invalid('请求长度不正确')
                    if not 0 < size <= LIMIT:
                        raise Invalid('内容过大或为空', 413)
                    try:
                        body = json.loads(self.rfile.read(size))
                    except (ValueError, UnicodeError):
                        raise Invalid('内容格式不正确')
                    if not isinstance(body, dict):
                        raise Invalid('内容格式不正确')
                # One transaction serializes read-before-write and idempotency checks.
                if self.command != 'GET':
                    db.execute('BEGIN IMMEDIATE')
                result = self.route(db, user, body)
            # Commit completed before acknowledging delivery.
            self.send_json(200, result)
        except Invalid as error:
            self.send_json(error.status, {'error': error.message})
        except (sqlite3.Error, OSError):
            self.send_json(503, {'error': '后台暂时无法保存，请稍后重试'})

    do_GET = do_POST = do_PUT = do_DELETE = dispatch

    def route(self, db, user, body):
        path, method = self.path, self.command
        uid = user['id']
        if path == '/v1/me' and method == 'GET':
            return {'id': uid, 'name': user['name']}
        if path == '/v1/questions' and method == 'GET':
            rows = db.execute('SELECT q.*,u.name FROM questions q JOIN users u ON u.id=q.owner WHERE active=1 ORDER BY created DESC,id DESC LIMIT 200')
            return {'items': [self.question(db, row, uid, summary=True) for row in rows]}
        if path == '/v1/questions' and method == 'POST':
            rid, value = request_id(body), package(body, user['name'])
            old = db.execute('SELECT * FROM questions WHERE owner=? AND request_id=?', (uid, rid)).fetchone()
            if old:
                value['id'] = old['id']
                if json.loads(old['package']) != value:
                    raise Invalid('相同请求编号的内容发生变化', 409)
                return {'id': old['id'], 'active': bool(old['active'])}
            qid = 'user-' + secrets.token_hex(16)
            value['id'] = qid
            db.execute('INSERT INTO questions(id,owner,request_id,package,created) VALUES(?,?,?,?,?)',
                       (qid, uid, rid, json.dumps(value, ensure_ascii=False), time.time_ns()))
            return {'id': qid, 'active': True}
        if path == '/v1/feedback' and method == 'GET':
            return {'items': [dict(r) for r in db.execute('SELECT id,request_id,lesson,title,body,status,reply FROM feedback WHERE owner=? ORDER BY created DESC LIMIT 500', (uid,))]}
        if path == '/v1/feedback' and method == 'POST':
            rid = request_id(body)
            values = (text(body, 'lesson', 80), text(body, 'title', 120), text(body, 'body', 8000))
            old = db.execute('SELECT * FROM feedback WHERE owner=? AND request_id=?', (uid, rid)).fetchone()
            if old:
                if tuple(old[k] for k in ('lesson', 'title', 'body')) != values:
                    raise Invalid('相同反馈编号的内容发生变化', 409)
                return {'id': old['id'], 'status': old['status'], 'reply': old['reply']}
            fid = secrets.token_hex(16)
            db.execute('INSERT INTO feedback(id,owner,request_id,lesson,title,body,created) VALUES(?,?,?,?,?,?,?)',
                       (fid, uid, rid, *values, time.time_ns()))
            return {'id': fid, 'status': 'pending', 'reply': ''}
        match = re.fullmatch(r'/v1/questions/(user-[a-f0-9]{32})(/comments|/like)?', path)
        if match:
            qid, action = match.groups()
            row = db.execute('SELECT q.*,u.name FROM questions q JOIN users u ON u.id=q.owner WHERE q.id=? AND active=1', (qid,)).fetchone()
            if row is None:
                raise Invalid('题目已撤回或不存在', 404)
            if action is None and method == 'GET':
                return self.question(db, row, uid)
            if action is None and method == 'DELETE':
                if row['owner'] != uid:
                    raise Invalid('只能撤回自己发布的题目', 403)
                db.execute('UPDATE questions SET active=0 WHERE id=?', (qid,))
                return {'withdrawn': True}
            if action == '/like' and method == 'PUT':
                if type(body.get('liked')) is not bool:
                    raise Invalid('点赞状态不正确')
                if body['liked']:
                    db.execute('INSERT OR IGNORE INTO likes VALUES(?,?)', (qid, uid))
                else:
                    db.execute('DELETE FROM likes WHERE question=? AND owner=?', (qid, uid))
                return self.question(db, row, uid)
            if action == '/comments' and method == 'GET':
                return {'items': [dict(r) for r in db.execute('SELECT c.id,c.body,u.name,c.owner=? AS mine FROM comments c JOIN users u ON c.owner=u.id WHERE question=? ORDER BY created DESC LIMIT 200', (uid, qid))]}
            if action == '/comments' and method == 'POST':
                rid, content = request_id(body), text(body, 'body', 2000)
                old = db.execute('SELECT * FROM comments WHERE owner=? AND request_id=?', (uid, rid)).fetchone()
                if old:
                    if old['question'] != qid or old['body'] != content:
                        raise Invalid('相同评论编号的内容发生变化', 409)
                    return {'id': old['id']}
                cid = secrets.token_hex(16)
                db.execute('INSERT INTO comments VALUES(?,?,?,?,?,?)', (cid, qid, uid, rid, content, time.time_ns()))
                return {'id': cid}
        match = re.fullmatch(r'/v1/comments/([a-f0-9]{32})', path)
        if match and method == 'DELETE':
            db.execute('DELETE FROM comments WHERE id=? AND owner=?', (match[1], uid))
            return {'deleted': True}
        raise Invalid('接口不存在', 404)

    @staticmethod
    def question(db, row, uid, summary=False):
        count = db.execute('SELECT count(*) FROM likes WHERE question=?', (row['id'],)).fetchone()[0]
        liked = db.execute('SELECT 1 FROM likes WHERE question=? AND owner=?', (row['id'], uid)).fetchone() is not None
        value = json.loads(row['package'])
        if summary:
            value = {'author': value['author'], 'question': {'title': value['question']['title']}}
        return {'id': row['id'], 'package': value, 'mine': row['owner'] == uid, 'likes': count, 'liked': liked}


def serve(path, cert, key, port):
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.db_path = path
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', default=str(pathlib.Path(__file__).parent / 'data/community.db'))
    sub = parser.add_subparsers(dest='command', required=True)
    add = sub.add_parser('add-user')
    add.add_argument('--name', required=True)
    add.add_argument('--cert', required=True)
    add.add_argument('--output', required=True)
    run = sub.add_parser('serve')
    run.add_argument('--cert', required=True)
    run.add_argument('--key', required=True)
    run.add_argument('--port', type=int, default=8788)
    sub.add_parser('feedback')
    review = sub.add_parser('review')
    review.add_argument('--id', required=True)
    review.add_argument('--status', choices=['pending', 'reviewing', 'resolved'], required=True)
    review.add_argument('--reply', required=True)
    args = parser.parse_args()
    initialize(args.data)
    if args.command == 'add-user':
        if not args.name.strip() or len(args.name) > 80:
            parser.error('name must contain 1-80 characters')
        # Exclusive creation avoids silently replacing a working tester identity.
        with open(args.output, 'x', encoding='utf-8') as out:
            json.dump({'url': 'https://10.0.2.2:8788', 'token': provision(args.data, args.name.strip()),
                       'certificate': pathlib.Path(args.cert).read_text()}, out, ensure_ascii=False)
        print('Connection file created. Keep it private.')
    elif args.command == 'serve':
        server = serve(args.data, args.cert, args.key, args.port)
        print('Blue Note local HTTPS server ready on port ' + str(server.server_port), flush=True)
        server.serve_forever()
    elif args.command == 'feedback':
        with connect(args.data) as db:
            for row in db.execute('SELECT id,title,body,status,reply FROM feedback ORDER BY created DESC'):
                print(json.dumps(dict(row), ensure_ascii=False))
    elif args.command == 'review':
        if not args.reply.strip() or len(args.reply) > 8000:
            parser.error('reply must contain 1-8000 characters')
        with connect(args.data) as db:
            result = db.execute('UPDATE feedback SET status=?,reply=? WHERE id=?', (args.status, args.reply.strip(), args.id))
            if result.rowcount != 1:
                parser.error('feedback not found')
        print('Feedback updated.')


if __name__ == '__main__':
    main()
