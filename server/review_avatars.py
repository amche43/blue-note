"""Local desktop moderation; not exposed through an app account or HTTP."""
import argparse
import pathlib
import sqlite3
import tkinter as tk
from tkinter import ttk, messagebox
import community
import avatar_review


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--data',default=str(pathlib.Path(__file__).parent/'data/community.db'))
    args=parser.parse_args()
    community.initialize(args.data)
    window=tk.Tk();window.title('蓝笔 · 头像审核');window.geometry('760x560');window.configure(bg='#f8fbff')
    style=ttk.Style();style.configure('TLabel',font=('Microsoft YaHei',11));style.configure('TButton',font=('Microsoft YaHei',11))
    frame=ttk.Frame(window,padding=20);frame.pack(fill='both',expand=True)
    ttk.Label(frame,text='头像审核 · 仅限这台电脑的管理者').pack(anchor='w')
    listing=tk.Listbox(frame,height=7,font=('Microsoft YaHei',11),exportselection=False);listing.pack(fill='x',pady=12)
    preview=ttk.Label(frame);preview.pack()
    ttk.Label(frame,text='未通过原因（拒绝时必填）').pack(anchor='w')
    reason=tk.Text(frame,height=3,font=('Microsoft YaHei',11));reason.pack(fill='x',pady=8)
    records=[]
    def refresh():
        nonlocal records
        with community.connect(args.data) as db:
            records=[dict(r) for r in db.execute("SELECT a.id,a.image,a.created,u.name FROM avatar_requests a JOIN users u ON a.owner=u.id WHERE a.status='pending' ORDER BY a.created")]
        listing.delete(0,'end');preview.configure(image='');preview.image=None
        for r in records:listing.insert('end',r['name']+' · 待审核 · '+r['id'][:8])
        window.title('蓝笔 · 头像审核（'+str(len(records))+'条待处理）')
    def select(_):
        if listing.curselection():
            picture=tk.PhotoImage(data=records[listing.curselection()[0]]['image'])
            preview.configure(image=picture);preview.image=picture
    def decide(approve):
        if not listing.curselection():return
        record=records[listing.curselection()[0]]
        try:
            with community.connect(args.data) as db:avatar_review.review(db,record['id'],approve,reason.get('1.0','end').strip())
            reason.delete('1.0','end');refresh()
        except (ValueError,OSError,sqlite3.Error) as e:messagebox.showerror('尚未处理',str(e))
    listing.bind('<<ListboxSelect>>',select)
    actions=ttk.Frame(frame);actions.pack(fill='x',pady=10)
    ttk.Button(actions,text='刷新',command=refresh).pack(side='left')
    ttk.Button(actions,text='审核通过',command=lambda:decide(True)).pack(side='right',padx=8)
    ttk.Button(actions,text='不通过',command=lambda:decide(False)).pack(side='right')
    refresh();window.mainloop()


if __name__=='__main__':main()
