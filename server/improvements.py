"""Reviewed edits to public learning entries. All mutations use the caller transaction."""
import hashlib
import json
import re
import secrets
import time

FIELDS = {'answer':18000, 'trigger':4000, 'action':4000, 'conditions':4000, 'pitfall':4000}

def revision(package):
    return hashlib.sha256(package.encode()).hexdigest()

def initialize(db):
    db.execute('''CREATE TABLE IF NOT EXISTS improvements(
      id TEXT PRIMARY KEY, book TEXT NOT NULL REFERENCES notebooks(id), question TEXT NOT NULL REFERENCES questions(id),
      author TEXT NOT NULL REFERENCES users(id), request_id TEXT NOT NULL, base TEXT NOT NULL,
      field TEXT NOT NULL, before_text TEXT NOT NULL, after_text TEXT NOT NULL, reason TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending', reviewer TEXT, review_note TEXT NOT NULL DEFAULT '',
      created INTEGER NOT NULL, reviewed INTEGER, UNIQUE(author,request_id))''')

def route(db, uid, method, path, body, Invalid, text, request_id):
    match=re.fullmatch(r'/v1/notebooks/(book-[a-f0-9]{32})/improvements',path)
    if not match:return None
    bid=match[1]
    book=db.execute('SELECT * FROM notebooks WHERE id=?',(bid,)).fetchone()
    if not book:raise Invalid('学习本不存在',404)
    if method=='GET':
        rows=[dict(r) for r in db.execute('''SELECT i.*,u.name,q.owner=? AS canReview,
        json_extract(q.package,'$.question.title') AS title,
        json_extract(q.package,'$.question.questionNumber') AS questionNumber
        FROM improvements i JOIN users u ON u.id=i.author JOIN questions q ON q.id=i.question
        WHERE i.book=? AND (q.active=1 OR q.owner=? OR i.author=?) ORDER BY i.created DESC LIMIT 100''',(uid,bid,uid,uid))]
        return dict(items=rows)
    if method=='POST':
        rid=request_id(body);qid=text(body,'question',80);base=text(body,'base',64)
        field=body.get('field')
        if field not in FIELDS:raise Invalid('只支持解析与解题知识改进')
        after=text(body,'after',FIELDS[field]);reason=text(body,'reason',1000)
        old=db.execute('SELECT * FROM improvements WHERE author=? AND request_id=?',(uid,rid)).fetchone()
        if old:
            if (old['book'],old['question'],old['base'],old['field'],old['after_text'],old['reason'])!=(bid,qid,base,field,after,reason):raise Invalid('提案编号内容冲突',409)
            return dict(id=old['id'],status=old['status'])
        q=db.execute('SELECT * FROM questions WHERE id=? AND notebook_id=? AND active=1',(qid,bid)).fetchone()
        if not q:raise Invalid('条目已撤回或不属于此学习本',404)
        if revision(q['package'])!=base:raise Invalid('条目已更新，请刷新后重新提出改进',409)
        before=json.loads(q['package'])['question'].get(field,'')
        if before==after:raise Invalid('修改内容与原文相同')
        iid=secrets.token_hex(16)
        db.execute('INSERT INTO improvements(id,book,question,author,request_id,base,field,before_text,after_text,reason,created) VALUES(?,?,?,?,?,?,?,?,?,?,?)',(iid,bid,qid,uid,rid,base,field,before,after,reason,time.time_ns()))
        return dict(id=iid,status='pending')
    if method=='PUT':
        item=db.execute('SELECT i.*,q.owner,q.active,q.package FROM improvements i JOIN questions q ON q.id=i.question WHERE i.id=? AND i.book=?',(text(body,'id',32),bid)).fetchone()
        if not item:raise Invalid('提案不存在',404)
        if item['owner']!=uid:raise Invalid('只有条目作者可以处理改进',403)
        status=body.get('status');note=text({'note':body.get('note','')},'note',1000,False)
        if status not in ('accepted','rejected'):raise Invalid('处理状态不正确')
        if status=='rejected' and not note:raise Invalid('请说明拒绝原因')
        if item['status']!='pending':
            if item['status']==status:return dict(status=status)
            raise Invalid('提案已经处理',409)
        if status=='accepted':
            if not item['active'] or revision(item['package'])!=item['base']:raise Invalid('原文已更新或撤回，不能合并旧提案；请核对后重新提交',409)
            value=json.loads(item['package']);value['question'][item['field']]=item['after_text']
            db.execute('UPDATE questions SET package=? WHERE id=?',(json.dumps(value,ensure_ascii=False),item['question']))
            import learning_profile
            if learning_profile.valid(value['question']):db.execute('UPDATE questions SET qualified_at=COALESCE(qualified_at,?) WHERE id=?',(time.time_ns(),item['question']))
        db.execute('UPDATE improvements SET status=?,reviewer=?,review_note=?,reviewed=? WHERE id=?',(status,uid,note,time.time_ns(),item['id']))
        return dict(status=status)
    raise Invalid('接口不存在',404)
