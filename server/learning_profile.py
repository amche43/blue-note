"""Public learning achievements derived from server evidence, never client totals."""
import datetime as dt
import json
import re
import time

DETAILS=('trigger','action','answer','firstThought','errorReason','summary','conditions','pitfall')
def valid(q):
    try:
        canvas=json.loads(q.get('canvas') or '{}')
        annotated=any(e.get('note','').strip() for e in canvas.get('elements',[]))
    except (ValueError,TypeError,AttributeError):
        annotated=False
    return annotated or (bool(q.get('prompt','').strip()) and any(q.get(k,'').strip() for k in DETAILS))
def fingerprint(q):
    return tuple(''.join(q.get(k,'').split()) for k in ('prompt',)+DETAILS)+(q.get('canvas',''),)
def week(ns):
    d=dt.datetime.fromtimestamp(ns/1e9,dt.timezone.utc).date()
    return (d-dt.timedelta(days=d.weekday())).isoformat()
def initialize(db):
    db.execute('CREATE TABLE IF NOT EXISTS helpful(question TEXT REFERENCES questions(id),user TEXT REFERENCES users(id),created INTEGER NOT NULL,PRIMARY KEY(question,user))')
    if 'qualified_at' not in {r['name'] for r in db.execute('PRAGMA table_info(questions)')}:
        db.execute('ALTER TABLE questions ADD COLUMN qualified_at INTEGER')
        for row in db.execute('SELECT id,package FROM questions WHERE active=1').fetchall():
            if valid(json.loads(row['package'])['question']):db.execute('UPDATE questions SET qualified_at=? WHERE id=?',(time.time_ns(),row['id']))

def profile(db,uid,Invalid):
    user=db.execute('SELECT id,name FROM users WHERE id=?',(uid,)).fetchone()
    if not user:raise Invalid('学习者不存在',404)
    now=time.time_ns();cutoff=now-7*86400*10**9; year=now-364*86400*10**9
    rows=db.execute('SELECT * FROM questions WHERE owner=? AND active=1',(uid,)).fetchall()
    seen=set();knowledge=0;books={};activities=[];perbook={}
    for row in rows:
        q=json.loads(row['package'])['question']
        if not valid(q):continue
        fp=fingerprint(q)
        if fp not in seen:
            seen.add(fp);knowledge+=q.get('contentKind')=='knowledge'
            activities.append(row['created'])
            if row['notebook_id']:perbook.setdefault(row['notebook_id'],set()).add(week(row['created']))
        if row['notebook_id'] and row['qualified_at'] is not None and row['qualified_at']<=cutoff:books.setdefault(row['notebook_id'],set()).add(fp)
    submissions=db.execute('SELECT i.*,q.owner FROM improvements i JOIN questions q ON q.id=i.question WHERE i.author=? AND q.owner!=?',(uid,uid)).fetchall()
    unique={(i['question'],i['field'],''.join(i['after_text'].split())) for i in submissions if i['status']!='rejected'}
    accepted=[i for i in submissions if i['status']=='accepted']
    accepted_unique={(i['question'],i['field'],''.join(i['after_text'].split())) for i in accepted}
    for i in accepted:activities.append(i['reviewed']);perbook.setdefault(i['book'],set()).add(week(i['reviewed']))
    for h in db.execute('SELECT * FROM book_history WHERE user=?',(uid,)):
        if h['description'].strip():activities.append(h['created']);perbook.setdefault(h['book'],set()).add(week(h['created']))
    for i in db.execute("SELECT * FROM improvements WHERE reviewer=? AND status='accepted'",(uid,)):
        activities.append(i['reviewed']);perbook.setdefault(i['book'],set()).add(week(i['reviewed']))
    memberbooks={r[0] for r in db.execute('SELECT m.book FROM book_members m JOIN notebooks b ON b.id=m.book WHERE m.user=? AND b.owner!=?',(uid,uid))}
    activeweeks={week(n) for n in activities if year<=n<=now}
    eligibleweeks={week(now-n*7*86400*10**9) for n in range(56)}
    maintained=max((len(v & eligibleweeks) for v in perbook.values()),default=0)
    popular=db.execute('SELECT COALESCE(MAX(n),0) FROM (SELECT count(*) AS n FROM notebook_reactions r JOIN notebooks b ON b.id=r.book WHERE b.owner=? AND r.owner!=? AND r.saved=1 AND EXISTS(SELECT 1 FROM questions q WHERE q.notebook_id=b.id AND q.active=1) GROUP BY b.id)',(uid,uid)).fetchone()[0]
    helpful=db.execute('SELECT count(DISTINCT h.user) FROM helpful h JOIN questions q ON q.id=h.question WHERE q.owner=? AND q.active=1 AND h.user!=?',(uid,uid)).fetchone()[0]
    counts=dict(first=len(seen),open=sum(len(v)>=3 for v in books.values()),knowledge=knowledge,contribution=len(unique),maintainer=min(maintained,52),collaborator=len(memberbooks & perbook.keys()),accepted=len(accepted_unique),popular=popular,helpful=helpful,momentum=min(len(activeweeks),52))
    import notebook_forks
    counts['fork']=notebook_forks.qualified(db,uid)
    year_project=any(len(v & eligibleweeks)>=52 and min(v)<week(now-365*86400*10**9) for v in perbook.values())
    return dict(id=user['id'],name=user['name'],avatar=db.execute('SELECT COALESCE((SELECT avatar FROM user_profiles WHERE user=?),0)',(uid,)).fetchone()[0],avatarImage=db.execute("SELECT COALESCE((SELECT image FROM avatar_images WHERE user=?),'')",(uid,)).fetchone()[0],counts=counts,activeWeeks=sorted(activeweeks),scope='public',specials=['one_year'] if year_project else [])

def route(db,uid,method,path,body,Invalid):
    match=re.fullmatch(r'/v1/profiles/([a-f0-9]{32})',path)
    if match and method=='GET':return profile(db,match[1],Invalid)
    match=re.fullmatch(r'/v1/questions/(user-[a-f0-9]{32})/helpful',path)
    if not match:return None
    q=db.execute('SELECT owner FROM questions WHERE id=? AND active=1',(match[1],)).fetchone()
    if not q:raise Invalid('条目不存在或已撤回',404)
    if method=='PUT':
        if q['owner']==uid:raise Invalid('不能给自己的内容计入帮助人数')
        if type(body.get('value')) is not bool:raise Invalid('状态无效')
        if body['value']:db.execute('INSERT OR IGNORE INTO helpful VALUES(?,?,?)',(match[1],uid,time.time_ns()))
        else:db.execute('DELETE FROM helpful WHERE question=? AND user=?',(match[1],uid))
    elif method!='GET':raise Invalid('接口不存在',404)
    return dict(value=db.execute('SELECT 1 FROM helpful WHERE question=? AND user=?',(match[1],uid)).fetchone() is not None,count=db.execute('SELECT count(*) FROM helpful WHERE question=?',(match[1],)).fetchone()[0])
