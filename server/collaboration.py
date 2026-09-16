"""Notebook-scoped collaboration. Called within the community transaction."""
import re
import secrets
import time


def initialize(db):
    import notebook_forks
    notebook_forks.initialize(db)
    import learning_profile
    learning_profile.initialize(db)
    import improvements
    improvements.initialize(db)
    db.executescript('''
    CREATE TABLE IF NOT EXISTS book_profiles(book TEXT PRIMARY KEY REFERENCES notebooks(id), description TEXT NOT NULL DEFAULT '', version INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS book_members(book TEXT REFERENCES notebooks(id), user TEXT REFERENCES users(id), PRIMARY KEY(book,user));
    CREATE TABLE IF NOT EXISTS book_applications(id TEXT PRIMARY KEY, book TEXT REFERENCES notebooks(id), user TEXT REFERENCES users(id), reason TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', created INTEGER NOT NULL, UNIQUE(book,user));
    CREATE TABLE IF NOT EXISTS book_messages(id TEXT PRIMARY KEY, book TEXT REFERENCES notebooks(id), user TEXT REFERENCES users(id), request_id TEXT NOT NULL, body TEXT NOT NULL, created INTEGER NOT NULL, UNIQUE(user,request_id));
    CREATE TABLE IF NOT EXISTS book_history(book TEXT REFERENCES notebooks(id), version INTEGER NOT NULL, user TEXT REFERENCES users(id), description TEXT NOT NULL, created INTEGER NOT NULL, PRIMARY KEY(book,version));
    ''')


def route(db, uid, method, path, body, Invalid, text, request_id):
    if path == '/v1/inbox' and method == 'GET':
        applications = [dict(r) for r in db.execute('''SELECT a.*,u.name,COALESCE((SELECT avatar FROM user_profiles p WHERE p.user=u.id),0) AS avatar,(SELECT image FROM avatar_images ai WHERE ai.user=u.id) AS avatarImage,b.title,b.owner=? AS canReview FROM book_applications a JOIN users u ON a.user=u.id JOIN notebooks b ON b.id=a.book WHERE a.user=? OR b.owner=? ORDER BY a.created DESC LIMIT 200''',(uid,uid,uid))]
        rooms = [dict(r) for r in db.execute('''SELECT b.id,b.title,(SELECT max(created) FROM book_messages m WHERE m.book=b.id) AS updated FROM notebooks b WHERE b.owner=? OR EXISTS(SELECT 1 FROM book_members m WHERE m.book=b.id AND m.user=?) ORDER BY updated DESC,b.title LIMIT 200''',(uid,uid))]
        improvements = [dict(r) for r in db.execute('''SELECT i.id,i.book,i.status,i.created,i.reviewed,i.reason,i.review_note,u.name,b.title,
          json_extract(q.package,'$.question.title') AS entryTitle,q.owner=? AS canReview
          FROM improvements i JOIN questions q ON q.id=i.question JOIN notebooks b ON b.id=i.book JOIN users u ON u.id=i.author
          WHERE q.owner=? OR i.author=? ORDER BY COALESCE(i.reviewed,i.created) DESC LIMIT 100''',(uid,uid,uid))]
        return dict(applications=applications, rooms=rooms, improvements=improvements)
    match = re.fullmatch(r'/v1/notebooks/(book-[a-f0-9]{32})/(workspace|apply|applications|messages|description)',path)
    if not match:
        return None
    bid, action = match.groups()
    book = db.execute('SELECT b.*,u.name,COALESCE((SELECT avatar FROM user_profiles p WHERE p.user=u.id),0) AS avatar,(SELECT image FROM avatar_images ai WHERE ai.user=u.id) AS avatarImage FROM notebooks b JOIN users u ON u.id=b.owner WHERE b.id=?',(bid,)).fetchone()
    if not book:
        raise Invalid('学习本不存在',404)
    owner = book['owner'] == uid
    member = owner or db.execute('SELECT 1 FROM book_members WHERE book=? AND user=?',(bid,uid)).fetchone() is not None
    if action == 'workspace' and method == 'GET':
        profile = db.execute('SELECT description,version FROM book_profiles WHERE book=?',(bid,)).fetchone()
        members = [dict(r) for r in db.execute('SELECT u.id,u.name,COALESCE((SELECT avatar FROM user_profiles p WHERE p.user=u.id),0) AS avatar,(SELECT image FROM avatar_images ai WHERE ai.user=u.id) AS avatarImage FROM users u WHERE u.id=? OR u.id IN(SELECT user FROM book_members WHERE book=?)',(book['owner'],bid))]
        application = db.execute('SELECT status FROM book_applications WHERE book=? AND user=?',(bid,uid)).fetchone()
        history = [dict(r) for r in db.execute('SELECT h.version,h.description,h.created,u.name,COALESCE((SELECT avatar FROM user_profiles p WHERE p.user=u.id),0) AS avatar,(SELECT image FROM avatar_images ai WHERE ai.user=u.id) AS avatarImage FROM book_history h JOIN users u ON u.id=h.user WHERE h.book=? ORDER BY version DESC LIMIT 100',(bid,))]
        return dict(id=bid,title=book['title'],ownerId=book['owner'],name=book['name'],avatar=book['avatar'],avatarImage=book['avatarImage'],owner=owner,member=member,members=members,application=application['status'] if application else '',description=profile['description'] if profile else '',version=profile['version'] if profile else 0,history=history)
    if action == 'apply' and method == 'POST':
        if member:
            return dict(status='accepted')
        reason = text(body,'reason',1000)
        previous = db.execute('SELECT * FROM book_applications WHERE book=? AND user=?',(bid,uid)).fetchone()
        if previous:
            return dict(status=previous['status'])
        db.execute('INSERT INTO book_applications(id,book,user,reason,created) VALUES(?,?,?,?,?)',(secrets.token_hex(16),bid,uid,reason,time.time_ns()))
        return dict(status='pending')
    if action == 'applications' and method == 'PUT':
        if not owner:
            raise Invalid('只有学习本创建者可以处理申请',403)
        status = body.get('status')
        if status not in ('accepted','rejected'):
            raise Invalid('申请状态不正确')
        application = db.execute('SELECT * FROM book_applications WHERE id=? AND book=?',(text(body,'id',32),bid)).fetchone()
        if not application:
            raise Invalid('申请不存在',404)
        if application['status'] not in ('pending',status):
            raise Invalid('申请已经处理，请刷新',409)
        db.execute('UPDATE book_applications SET status=? WHERE id=?',(status,application['id']))
        if status == 'accepted':
            db.execute('INSERT OR IGNORE INTO book_members VALUES(?,?)',(bid,application['user']))
        return dict(status=status)
    if not member:
        raise Invalid('仅共同维护者可以进入协作工作区',403)
    if action == 'description' and method == 'PUT':
        description = text(body,'description',8000,False)
        version = body.get('version')
        if type(version) is not int or version < 0:
            raise Invalid('版本不正确')
        db.execute('INSERT OR IGNORE INTO book_profiles(book) VALUES(?)',(bid,))
        current = db.execute('SELECT * FROM book_profiles WHERE book=?',(bid,)).fetchone()
        if current['version'] != version:
            if current['description'] == description:
                return dict(version=current['version'])
            raise Invalid('其他维护者已更新简介，请刷新后再编辑',409)
        db.execute('UPDATE book_profiles SET description=?,version=version+1 WHERE book=?',(description,bid))
        db.execute('INSERT INTO book_history VALUES(?,?,?,?,?)',(bid,version+1,uid,description,time.time_ns()))
        return dict(version=version+1)
    if action == 'messages' and method == 'GET':
        rows = [dict(r) for r in db.execute('SELECT m.id,m.body,m.created,u.name,COALESCE((SELECT avatar FROM user_profiles p WHERE p.user=u.id),0) AS avatar,(SELECT image FROM avatar_images ai WHERE ai.user=u.id) AS avatarImage,m.user=? AS mine FROM book_messages m JOIN users u ON u.id=m.user WHERE book=? ORDER BY m.created DESC,m.id DESC LIMIT 200',(uid,bid))]
        return dict(items=list(reversed(rows)))
    if action == 'messages' and method == 'POST':
        rid, content = request_id(body), text(body,'body',2000)
        previous = db.execute('SELECT * FROM book_messages WHERE user=? AND request_id=?',(uid,rid)).fetchone()
        if previous:
            if previous['body'] != content or previous['book'] != bid:
                raise Invalid('消息编号对应的内容发生变化',409)
            return dict(id=previous['id'])
        mid = secrets.token_hex(16)
        db.execute('INSERT INTO book_messages VALUES(?,?,?,?,?,?)',(mid,bid,uid,rid,content,time.time_ns()))
        return dict(id=mid)
    raise Invalid('接口不存在',404)
