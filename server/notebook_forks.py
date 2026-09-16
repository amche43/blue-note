import json
import re
import time
import learning_profile

def initialize(db):
    db.execute('CREATE TABLE IF NOT EXISTS notebook_forks(user TEXT REFERENCES users(id),local_id TEXT,source TEXT REFERENCES notebooks(id),snapshot TEXT NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(user,local_id))')

def route(db,uid,method,path,body,Invalid):
    current=re.fullmatch(r'/v1/notebooks/(book-[a-f0-9]{32})/source-snapshot',path)
    if current:
        if method!='GET':raise Invalid('接口不存在',404)
        book=db.execute('SELECT * FROM notebooks WHERE id=?',(current[1],)).fetchone()
        if not book:raise Invalid('原学习本不存在',404)
        rows=db.execute('SELECT id,package FROM questions WHERE notebook_id=? AND active=1 ORDER BY CAST(question_number AS INTEGER)',(current[1],)).fetchall()
        if len(rows)>200:raise Invalid('原学习本超过 200 条，暂不支持整本对照')
        result=dict(source=current[1],title=book['title'],items=[{**json.loads(r['package']),'id':r['id']} for r in rows])
        if len(json.dumps(result,ensure_ascii=False).encode())>16*1024*1024:raise Invalid('原学习本过大，暂不支持整本对照')
        return result
    match=re.fullmatch(r'/v1/notebooks/(book-[a-f0-9]{32})/fork',path)
    if not match:return None
    if method!='POST':raise Invalid('接口不存在',404)
    local=body.get('localId')
    if not isinstance(local,str) or not re.fullmatch(r'book-[a-f0-9]{32}',local):raise Invalid('副本编号无效')
    old=db.execute('SELECT * FROM notebook_forks WHERE user=? AND local_id=?',(uid,local)).fetchone()
    if old:
        if old['source']!=match[1]:raise Invalid('副本编号冲突',409)
        return json.loads(old['snapshot'])
    book=db.execute('SELECT * FROM notebooks WHERE id=?',(match[1],)).fetchone()
    if not book:raise Invalid('学习本不存在',404)
    if book['owner']==uid:raise Invalid('自己的学习本可直接继续整理')
    rows=db.execute('SELECT id,package FROM questions WHERE notebook_id=? AND active=1 ORDER BY CAST(question_number AS INTEGER)',(match[1],)).fetchall()
    if not rows:raise Invalid('原学习本已撤回',404)
    if len(rows)>200:raise Invalid('当前整本派生最多支持 200 条，请等待分批导入功能')
    snapshot=dict(source=match[1],title=book['title'],items=[{**json.loads(r['package']),'id':r['id']} for r in rows])
    raw=json.dumps(snapshot,ensure_ascii=False)
    if len(raw.encode())>16*1024*1024:raise Invalid('学习本过大，暂不能整本派生')
    db.execute('INSERT INTO notebook_forks VALUES(?,?,?,?,?)',(uid,local,match[1],raw,time.time_ns()))
    return snapshot

def qualified(db,uid):
    result=[]
    for fork in db.execute('SELECT f.*,b.id AS book FROM notebook_forks f JOIN notebooks b ON b.owner=f.user AND b.local_id=f.local_id WHERE f.user=?',(uid,)):
        baseline={learning_profile.fingerprint(p['question']) for p in json.loads(fork['snapshot'])['items']}
        current=[json.loads(r[0])['question'] for r in db.execute('SELECT package FROM questions WHERE notebook_id=? AND active=1',(fork['book'],))]
        if any(learning_profile.valid(q) and learning_profile.fingerprint(q) not in baseline for q in current):result.append(fork['source'])
    return len(set(result))
