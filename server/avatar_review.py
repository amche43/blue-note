"""Private pending uploads; only local moderation can publish an avatar."""
import base64
import hashlib
import io
import secrets
import time


def initialize(db):
    db.executescript('''
    CREATE TABLE IF NOT EXISTS avatar_requests(id TEXT PRIMARY KEY, owner TEXT REFERENCES users(id), request_id TEXT NOT NULL, image TEXT NOT NULL, digest TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', reason TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL, reviewed INTEGER, UNIQUE(owner,request_id));
    CREATE TABLE IF NOT EXISTS avatar_images(user TEXT PRIMARY KEY REFERENCES users(id), image TEXT NOT NULL);
    ''')


def normalize(value, Invalid):
    if not isinstance(value,str) or len(value)>350000:
        raise Invalid('头像图片过大，请重新裁剪')
    try:
        from PIL import Image
    except ImportError:
        raise Invalid('后台缺少头像图片处理组件，请安装Pillow',503)
    try:
        raw=base64.b64decode(value,validate=True)
        with Image.open(io.BytesIO(raw)) as im:
            if im.format not in ('PNG','JPEG') or max(im.size)>2048 or min(im.size)<32:
                raise ValueError()
            im.load()
            # Re-encode pixels only; discard metadata and original file bytes.
            side=min(im.size)
            x,y=(im.width-side)//2,(im.height-side)//2
            clean=im.crop((x,y,x+side,y+side)).convert('RGB').resize((128,128))
            out=io.BytesIO()
            clean.save(out,format='PNG',optimize=True)
        image=base64.b64encode(out.getvalue()).decode()
        return image,hashlib.sha256(out.getvalue()).hexdigest()
    except (ValueError,OSError,Image.DecompressionBombError):
        raise Invalid('无法读取头像，请选择有效的PNG或JPEG照片')


def active(db,uid):
    row=db.execute('SELECT image FROM avatar_images WHERE user=?',(uid,)).fetchone()
    return row['image'] if row else ''


def use_default(db,uid):
    db.execute('DELETE FROM avatar_images WHERE user=?',(uid,))
    db.execute("UPDATE avatar_requests SET status='cancelled',reviewed=? WHERE owner=? AND status='pending'",(time.time_ns(),uid))


def route(db,uid,method,path,body,Invalid,request_id):
    if path!='/v1/me/avatar': return None
    if method=='GET':
        row=db.execute('SELECT id,status,reason,image,created FROM avatar_requests WHERE owner=? ORDER BY created DESC LIMIT 1',(uid,)).fetchone()
        return dict(activeImage=active(db,uid),request=dict(row) if row else None)
    if method=='POST':
        if body.get('consent') is not True:
            raise Invalid('请确认提交头像审核，通过后对其他用户可见')
        rid=request_id(body)
        image,digest=normalize(body.get('image'),Invalid)
        old=db.execute('SELECT id,status,digest FROM avatar_requests WHERE owner=? AND request_id=?',(uid,rid)).fetchone()
        if old:
            if old['digest']!=digest: raise Invalid('同一提交编号对应的照片发生变化',409)
            return dict(id=old['id'],status=old['status'])
        db.execute("UPDATE avatar_requests SET status='cancelled',reviewed=? WHERE owner=? AND status='pending'",(time.time_ns(),uid))
        aid=secrets.token_hex(16)
        db.execute('INSERT INTO avatar_requests(id,owner,request_id,image,digest,created) VALUES(?,?,?,?,?,?)',(aid,uid,rid,image,digest,time.time_ns()))
        return dict(id=aid,status='pending')
    if method=='DELETE':
        db.execute("UPDATE avatar_requests SET status='cancelled',reviewed=? WHERE owner=? AND status='pending'",(time.time_ns(),uid))
        return dict(ok=True)
    raise Invalid('接口不存在',404)


def review(db,aid,approve,reason=''):
    # This function is only called by the local management program, never HTTP.
    db.execute('BEGIN IMMEDIATE')
    row=db.execute('SELECT * FROM avatar_requests WHERE id=?',(aid,)).fetchone()
    if not row or row['status']!='pending': raise ValueError('申请已撤回或已处理，请刷新')
    if not approve and not reason.strip(): raise ValueError('请填写未通过原因')
    if len(reason)>1000: raise ValueError('原因最多1000字')
    db.execute('UPDATE avatar_requests SET status=?,reason=?,reviewed=? WHERE id=?',('approved' if approve else 'rejected',reason.strip(),time.time_ns(),aid))
    if approve:
        db.execute('INSERT INTO avatar_images VALUES(?,?) ON CONFLICT(user) DO UPDATE SET image=excluded.image',(row['owner'],row['image']))
