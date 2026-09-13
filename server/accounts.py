"""Local test accounts; passwords are salted and derived, never stored verbatim."""
import hashlib
import hmac
import re
import secrets
import threading
import time

_lock = threading.Lock()
_attempts = {}


def initialize(db):
    db.execute('CREATE TABLE IF NOT EXISTS credentials(username TEXT PRIMARY KEY, user TEXT UNIQUE REFERENCES users(id), salt TEXT NOT NULL, digest TEXT NOT NULL)')


def authenticate(db, path, body, Invalid, text):
    username = text(body,'username',40).lower()
    if not re.fullmatch(r'[a-z0-9_]{3,40}',username):
        raise Invalid('账号请使用3—40位字母、数字或下划线')
    password = body.get('password')
    if not isinstance(password,str) or not 8 <= len(password) <= 128:
        raise Invalid('密码需要8—128个字符')
    now = time.monotonic()
    # Local service: bound total attempts as well as attempts per account.
    with _lock:
        for key in list(_attempts):
            _attempts[key]=[t for t in _attempts[key] if now-t<300]
            if not _attempts[key]: del _attempts[key]
        if len(_attempts.get(username,[]))>=10 or len(_attempts.get('*',[]))>=100:
            raise Invalid('尝试过于频繁，请5分钟后再试',429)
        _attempts.setdefault(username,[]).append(now)
        _attempts.setdefault('*',[]).append(now)
    credential = db.execute('SELECT * FROM credentials WHERE username=?',(username,)).fetchone()
    if path == '/v1/auth/register':
        name = text(body,'name',80)
        if credential:
            raise Invalid('这个账号已被注册',409)
        salt = secrets.token_hex(16)
        digest = hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(salt),600000).hex()
        uid, token = secrets.token_hex(16), secrets.token_hex(32)
        db.execute('INSERT INTO users VALUES(?,?,?)',(uid,name,hashlib.sha256(token.encode()).hexdigest()))
        db.execute('INSERT INTO credentials VALUES(?,?,?,?)',(username,uid,salt,digest))
    else:
        salt = credential['salt'] if credential else '0'*32
        digest = hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(salt),600000).hex()
        if not credential or not hmac.compare_digest(digest,credential['digest']):
            raise Invalid('账号或密码不正确',401)
        uid, token = credential['user'], secrets.token_hex(32)
        # A new login replaces the previous session on this local test account.
        db.execute('UPDATE users SET token=? WHERE id=?',(hashlib.sha256(token.encode()).hexdigest(),uid))
        name = db.execute('SELECT name FROM users WHERE id=?',(uid,)).fetchone()['name']
    return dict(id=uid,name=name,token=token)
