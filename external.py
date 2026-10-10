"""Independent, local-only window; never connects to the Codex renderer."""
import json
import math
import os
from pathlib import Path
import queue
import sys
import threading
import tkinter as tk
from tkinter import ttk
from datetime import datetime

sys.path.insert(0, str(Path(__file__).resolve().parent))
import reader


def compact(value):
    if not isinstance(value, (int, float)) or not math.isfinite(value):
        return '--'
    if value >= 1e6:
        return f'{value / 1e6:.1f}M'
    if value >= 1e3:
        return f'{value / 1e3:.1f}k'
    return str(round(value))


def context_percent(context):
    if not isinstance(context, dict):
        return None
    tokens, window = context.get('tokens'), context.get('window')
    if (type(tokens) not in (int, float) or type(window) not in (int, float)
            or not math.isfinite(tokens) or not math.isfinite(window) or tokens < 0 or window <= 0):
        return None
    return 100 * tokens / window


def handoff_prompt(thread_id):
    return (f'请将本会话（ID：{thread_id}）的任务交接到新会话。\n'
            '先结合完整聊天与实际文件，保存可点击的 Markdown 交接说明：目标与最新要求、已完成事项与验证结果、'
            '关键文件路径和必要命令、未完成任务与阻塞条件、下一步具体动作。区分已验证和待验证结果，避免重复执行已完成工作。\n'
            '再新建同一项目下的会话，提供交接文件路径、工作目录和继续执行指令，让新会话接续剩余任务，返回打开入口。'
            '若无法创建，明确说明并提供可粘贴的新会话启动指令，不要声称已经创建。\n'
            '列出正在运行的任务与定时自动化的状态和归属，避免重复启动或重复创建。')


class MonitorState:
    def __init__(self, path):
        self.path = path
        self.selected = ''
        self.dismissed = set()
        try:
            value = json.loads(path.read_text(encoding='utf-8'))
            self.selected = value.get('selected', '') if isinstance(value.get('selected'), str) else ''
            self.dismissed = {x for x in value.get('dismissed', [])[-200:] if isinstance(x, str)}
        except (OSError, ValueError, TypeError, AttributeError):
            pass

    def save(self):
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temp = self.path.with_suffix('.tmp')
            temp.write_text(json.dumps({'selected': self.selected, 'dismissed': sorted(self.dismissed)[-200:]}), encoding='utf-8')
            os.replace(temp, self.path)
            return True
        except OSError:
            return False

    def remind(self, thread_id, context):
        percent = context_percent(context)
        if percent is not None and percent < 70 and thread_id in self.dismissed:
            self.dismissed.remove(thread_id)
            self.save()
        return percent is not None and percent >= 70 and thread_id not in self.dismissed


class Monitor:
    def __init__(self, root, state, start_worker=True):
        self.root, self.state = root, state
        self.rows, self.filtered = [], []
        self.incoming, self.requests = queue.Queue(), queue.Queue()
        self.stop = threading.Event()
        self.selected, self.data = state.selected, None
        self.feedback = ''
        root.title('Codex 外置统计')
        root.geometry('440x620')
        root.minsize(410, 620)
        root.configure(background='#1c232d')
        style = ttk.Style(root)
        style.theme_use('clam')
        style.configure('.', background='#1c232d', foreground='#edf1f6', font=('Microsoft YaHei UI', 10))
        style.configure('TFrame', background='#1c232d')
        style.configure('TLabel', background='#1c232d', foreground='#edf1f6')
        style.configure('Muted.TLabel', foreground='#929eaf', font=('Microsoft YaHei UI', 9))
        style.configure('Mono.TLabel', foreground='#929eaf', font=('Consolas', 9))
        style.configure('Hero.TLabel', font=('Consolas', 34, 'bold'))
        style.configure('Metric.TLabel', font=('Consolas', 22, 'bold'))
        style.configure('TButton', background='#27313e', foreground='#c5d0de', bordercolor='#3d4858',
                        lightcolor='#27313e', darkcolor='#27313e', padding=(10, 6), relief='flat')
        style.map('TButton', background=[('pressed', '#344659'), ('active', '#334050')],
                  bordercolor=[('focus', '#62bac4')])
        style.configure('Accent.TButton', foreground='#7ed0d6')
        style.configure('TCheckbutton', background='#1c232d', foreground='#929eaf', padding=4)
        style.map('TCheckbutton', background=[('active', '#27313e')], foreground=[('selected', '#7ed0d6')])
        style.configure('TEntry', fieldbackground='#131a23', foreground='#edf1f6', bordercolor='#394555', padding=8)
        style.configure('Treeview', background='#1c232d', fieldbackground='#1c232d', foreground='#edf1f6',
                        borderwidth=0, rowheight=38, font=('Microsoft YaHei UI', 9))
        style.map('Treeview', background=[('selected', '#2e4554')], foreground=[('selected', '#edf1f6')])
        style.configure('TSeparator', background='#37414f')
        style.configure('Horizontal.TProgressbar', background='#55adb9', troughcolor='#111821',
                        borderwidth=0, lightcolor='#55adb9', darkcolor='#55adb9')
        body = ttk.Frame(root, padding=22)
        self.body = body
        body.pack(fill='both', expand=True)
        self.status = ttk.Label(body, text='读取本机会话…', style='Muted.TLabel', wraplength=390)
        self.status.pack(side='bottom', anchor='w', pady=(12, 0))
        self.identity = ttk.Label(body, text='', style='Mono.TLabel', wraplength=390)
        self.identity.pack(side='bottom', anchor='w', pady=(8, 0))
        toolbar = ttk.Frame(body)
        toolbar.pack(fill='x')
        ttk.Label(toolbar, text='Σ · CODEX', font=('Consolas', 15, 'bold')).pack(side='left')
        self.topmost = tk.BooleanVar(value=False)
        ttk.Checkbutton(toolbar, text='置顶', variable=self.topmost,
                        command=lambda: root.attributes('-topmost', self.topmost.get())).pack(side='right')
        self.session_button = ttk.Button(toolbar, text='会话 ▾', command=self.toggle_sessions)
        self.session_button.pack(side='right', padx=(0, 6))
        self.sessions = ttk.Frame(body)
        self.search = tk.StringVar()
        ttk.Label(self.sessions, text='搜索标题或会话 ID', style='Muted.TLabel').pack(anchor='w', pady=(0, 6))
        ttk.Entry(self.sessions, textvariable=self.search).pack(fill='x', pady=(0, 8))
        self.search.trace_add('write', lambda *_: self.filter_rows())
        list_frame = ttk.Frame(self.sessions)
        list_frame.pack(fill='both', expand=True)
        self.choice = ttk.Treeview(list_frame, show='tree', columns=('id',), selectmode='browse', height=9)
        self.choice.column('#0', width=240, minwidth=120)
        self.choice.column('id', width=82, minwidth=70, stretch=False, anchor='e')
        scroll = ttk.Scrollbar(list_frame, orient='vertical', command=self.choice.yview)
        self.choice.configure(yscrollcommand=scroll.set)
        self.choice.pack(side='left', fill='both', expand=True)
        scroll.pack(side='right', fill='y')
        self.choice.bind('<<TreeviewSelect>>', self.select)
        self.list_note = ttk.Label(self.sessions, text='选择后固定监测该会话', style='Muted.TLabel')
        self.list_note.pack(anchor='w', pady=(8, 0))
        self.dashboard = ttk.Frame(body)
        self.dashboard.pack(fill='x', pady=(22, 0))
        self.title = ttk.Label(self.dashboard, text='等待会话列表', font=('Microsoft YaHei UI', 11, 'bold'), wraplength=380)
        self.title.pack(anchor='w')
        self.model = ttk.Label(self.dashboard, text='手动选择会话 · 本机日志', style='Muted.TLabel')
        self.model.pack(anchor='w', pady=(4, 18))
        self.values = {}
        ttk.Label(self.dashboard, text='累计 TOKEN', style='Muted.TLabel').pack(anchor='w')
        self.values['total'] = ttk.Label(self.dashboard, text='--', style='Hero.TLabel')
        self.values['total'].pack(anchor='w', pady=(2, 0))
        ttk.Label(self.dashboard, text='日志累计用量 · 非账单金额', style='Muted.TLabel').pack(anchor='w', pady=(0, 18))
        ttk.Separator(self.dashboard).pack(fill='x')
        metrics = ttk.Frame(self.dashboard)
        metrics.pack(fill='x', pady=16)
        for column, (key, title) in enumerate((('rate', '调用均速 · tok/s'), ('cache', '缓存命中'))):
            metrics.columnconfigure(column, weight=1, uniform='metrics')
            ttk.Label(metrics, text=title, style='Muted.TLabel').grid(row=0, column=column, sticky='w')
            label = ttk.Label(metrics, text='--', style='Metric.TLabel')
            label.grid(row=1, column=column, sticky='w', pady=(3, 0))
            self.values[key] = label
        ttk.Separator(self.dashboard).pack(fill='x', pady=(0, 14))
        self.context = ttk.Label(self.dashboard, text='对话上下文 · 等待统计', wraplength=380)
        self.context.pack(anchor='w')
        self.progress = ttk.Progressbar(self.dashboard, maximum=100)
        self.progress.pack(fill='x', pady=(10, 8), ipady=0)
        self.progress.configure(style='Horizontal.TProgressbar')
        self.report = ttk.Label(self.dashboard, text='最近上报：--', style='Mono.TLabel')
        self.report.pack(anchor='w')
        self.reminder = ttk.Frame(self.dashboard)
        self.reminder_message = ttk.Label(self.reminder, text='上下文达到 70%\n建议本轮结束后新开会话并交接。', foreground='#e0ba7c', wraplength=380)
        self.reminder_message.pack(anchor='w')
        actions = ttk.Frame(self.reminder)
        actions.pack(anchor='w', pady=(4, 0))
        self.copy = ttk.Button(actions, text='复制交接指令', style='Accent.TButton', command=self.copy_handoff)
        self.copy.pack(side='left')
        ttk.Button(actions, text='暂不提醒', command=self.dismiss).pack(side='left', padx=8)
        root.protocol('WM_DELETE_WINDOW', self.close)
        root.bind('<Configure>', self.resize)
        if start_worker:
            threading.Thread(target=self.worker, daemon=True).start()
        self.timer = root.after(200, self.poll)

    def toggle_sessions(self):
        if self.sessions.winfo_manager():
            self.sessions.pack_forget()
            self.dashboard.pack(fill='x', pady=(22, 0))
            self.session_button.configure(text='会话 ▾')
        else:
            self.dashboard.pack_forget()
            self.sessions.pack(fill='both', expand=True, pady=(22, 0))
            self.session_button.configure(text='返回统计')

    def resize(self, event):
        if event.widget is self.root:
            for label in (self.identity, self.status, self.title, self.context, self.reminder_message):
                label.configure(wraplength=max(200, event.width - 44))

    def filter_rows(self):
        query = self.search.get().casefold()
        self.filtered = [r for r in self.rows if query in (str(r.get('title') or '') + r['id']).casefold()]
        self.choice.delete(*self.choice.get_children())
        for row in self.filtered:
            self.choice.insert('', 'end', iid=row['id'], text=row.get('title') or '未命名会话', values=(row['id'][-8:],))
        if self.choice.exists(self.selected):
            self.choice.selection_set(self.selected)
        self.list_note.configure(text=f'{len(self.filtered)} 个会话 · 选择后固定监测')

    def select(self, _event=None):
        ids = self.choice.selection()
        if not ids or ids[0] == self.selected:
            return
        self.selected = ids[0]
        self.feedback = ''
        self.state.selected = self.selected
        self.state.save()
        self.data = None
        self.render({'id': self.selected, 'ok': False})
        self.requests.put(self.selected)
        if self.sessions.winfo_manager():
            self.toggle_sessions()

    def worker(self):
        selected = self.selected
        while not self.stop.is_set():
            try:
                while True:
                    selected = self.requests.get_nowait()
            except queue.Empty:
                pass
            try:
                reader.repository.refresh()
                rows = [{k: r.get(k) for k in ('id', 'title', 'model', 'updated_at')} for r in reader.repository.rows.values()]
                data = reader.reading(selected) if selected else None
                self.incoming.put((rows, data, reader.repository.state))
            except Exception as error:
                self.incoming.put(([], None, type(error).__name__))
            self.stop.wait(1)

    def poll(self):
        latest = None
        try:
            while True:
                latest = self.incoming.get_nowait()
        except queue.Empty:
            pass
        if latest:
            rows, data, repository_state = latest
            if rows != self.rows:
                self.rows = rows
                self.filter_rows()
            if not self.selected and rows:
                self.selected = rows[0]['id']
                self.state.selected = self.selected
                self.state.save()
                self.filter_rows()
                self.render({'id': self.selected, 'ok': False})
                self.requests.put(self.selected)
            if data and data.get('id') == self.selected:
                self.render(data)
            elif repository_state != 'ok':
                self.render({'id': self.selected, 'ok': False})
                self.status.configure(text=f'本机日志暂不可用：{repository_state}')
        self.timer = self.root.after(200, self.poll)

    def render(self, data):
        if data.get('id') != self.selected:
            return False
        self.data = data
        row = next((r for r in self.rows if r['id'] == self.selected), {})
        self.identity.configure(text=self.selected)
        title = row.get('title') or '所选会话'
        self.title.configure(text=title[:43] + '…' if len(title) > 44 else title)
        self.model.configure(text=row.get('model') or 'Codex · 本机日志')
        valid = data.get('ok')
        for key in ('rate', 'total', 'cache'):
            value = data.get(key) if valid else None
            numeric = type(value) in (int, float) and math.isfinite(value)
            text = (f'{value:,.0f}' if numeric else '--') if key == 'total' else (f'{value:.1f}' + ('%' if key == 'cache' else '') if numeric else '--')
            self.values[key].configure(text=text)
        context = data.get('context') if valid else None
        percent = context_percent(context)
        if percent is None:
            self.context.configure(text='对话上下文 · ' + ('等待新记录' if data.get('contextState') == 'waiting' else '等待统计'))
        else:
            self.context.configure(text=f"对话上下文约 {percent:.0f}% · {compact(context['tokens'])} / {compact(context['window'])} tok")
        self.progress['value'] = min(100, percent) if percent is not None else 0
        at = context.get('measured_at_ms') if context else None
        try:
            stamp = datetime.fromtimestamp(at / 1000).strftime('%m-%d %H:%M:%S') if at else '--'
        except (ValueError, TypeError, OverflowError, OSError):
            stamp = '--'
        self.report.configure(text='最近上报：' + stamp)
        if self.state.remind(self.selected, context):
            self.reminder.pack(fill='x', pady=(10, 0))
        else:
            self.reminder.pack_forget()
        self.copy.configure(text='复制交接指令')
        stage = {'generating': '生成中', 'tools': '工具运行中', 'idle': '最近响应'}.get(data.get('stage'), '等待统计')
        self.status.configure(text=self.feedback or (stage if valid else '所选会话日志暂不可用'))
        return True

    def dismiss(self):
        self.state.dismissed.add(self.selected)
        saved = self.state.save()
        self.reminder.pack_forget()
        if not saved:
            self.feedback = '暂不提醒已生效；无法保存选择，重启后会重新提醒'
            self.status.configure(text=self.feedback)

    def copy_handoff(self):
        if not self.selected:
            return
        try:
            self.root.clipboard_clear()
            self.root.clipboard_append(handoff_prompt(self.selected))
            self.root.update_idletasks()
            self.dismiss()
            self.feedback = '已复制交接指令，请粘贴到所选原会话发送'
            self.status.configure(text=self.feedback)
        except tk.TclError:
            self.status.configure(text='复制失败，请重试')

    def close(self):
        self.stop.set()
        self.root.after_cancel(self.timer)
        self.root.destroy()


def main():
    state_dir = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'CodexExternalStats'
    root = tk.Tk()
    Monitor(root, MonitorState(state_dir / 'preferences.json'))
    if sys.platform == 'win32':
        # Match the native title bar to the dark widget on supported Windows versions.
        import ctypes
        root.update_idletasks()
        hwnd = ctypes.windll.user32.GetParent(root.winfo_id())
        for attribute, value in ((20, 1), (35, 0x2d231c), (36, 0xf6f1ed)):
            color = ctypes.c_int(value)
            ctypes.windll.dwmapi.DwmSetWindowAttribute(hwnd, attribute, ctypes.byref(color), ctypes.sizeof(color))
    root.mainloop()


if __name__ == '__main__':
    main()
