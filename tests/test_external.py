import importlib.util
from pathlib import Path
import tempfile
import tkinter as tk
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('external', Path(__file__).resolve().parents[1] / 'external.py')
external = importlib.util.module_from_spec(spec)
spec.loader.exec_module(external)

with tempfile.TemporaryDirectory(prefix='codex-external-test-') as temp:
    state_path = Path(temp) / 'preferences.json'
    state = external.MonitorState(state_path)
    first, second = '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222'
    assert not state.remind(first, {'tokens': 699, 'window': 1000})
    assert state.remind(first, {'tokens': 700, 'window': 1000})
    state.dismissed.add(first)
    state.selected = first
    assert state.save()
    state = external.MonitorState(state_path)
    assert state.selected == first and not state.remind(first, {'tokens': 800, 'window': 1000})
    assert state.remind(second, {'tokens': 800, 'window': 1000})
    assert not state.remind(first, None)
    assert not state.remind(first, {'tokens': 800})
    assert not state.remind(first, {'tokens': 200, 'window': 1000})
    assert state.remind(first, {'tokens': 700, 'window': 1000})
    assert external.context_percent({'tokens': 1100, 'window': 1000}) == 110
    root = tk.Tk()
    root.withdraw()
    try:
        app = external.Monitor(root, state, start_worker=False)
        app.rows = [{'id': first, 'title': 'Duplicate title', 'model': 'test'}, {'id': second, 'title': 'Duplicate title', 'model': 'test'}]
        app.filter_rows()
        assert app.choice.selection() == (first,)
        assert len(app.choice.get_children()) == 2 and app.choice.item(first, 'values') == (first[-8:],)
        data = {'id': first, 'ok': True, 'total': 10000, 'rate': 18.5, 'cache': 93,
                'stage': 'generating', 'context': {'tokens': 750, 'window': 1000, 'measured_at_ms': 1791590400000}}
        assert app.render(data)
        assert app.values['rate']['text'] == '18.5'
        assert '75%' in app.context['text'] and app.reminder.winfo_manager() == 'pack'
        assert not app.render({**data, 'id': second, 'rate': 999})
        assert app.values['rate']['text'] == '18.5'
        copied = []
        with patch.object(root, 'clipboard_clear'), patch.object(root, 'clipboard_append', side_effect=copied.append):
            app.copy_handoff()
        assert first in copied[0] and '新建同一项目' in copied[0]
        assert not app.reminder.winfo_manager()
        app.render(data)
        assert '已复制' in app.status['text']
        app.render({**data, 'context': None, 'contextState': 'waiting'})
        assert '等待新记录' in app.context['text']
        app.toggle_sessions()
        app.choice.selection_set(second)
        app.select()
        assert app.selected == second and app.values['rate']['text'] == '--'
        app.render({**data, 'id': second})
        assert app.reminder.winfo_manager() == 'pack'
        app.search.set(second)
        assert len(app.filtered) == 1 and app.selected == second
        app.search.set('not found')
        assert app.selected == second and not app.choice.get_children()
        root.deiconify()
        root.geometry('410x620')
        root.after(150, root.quit)
        root.mainloop()
        assert app.status.winfo_y() + app.status.winfo_height() <= app.status.master.winfo_height()
        assert app.reminder.winfo_rooty() + app.reminder.winfo_height() <= app.identity.winfo_rooty(), 'Reminder must not overlap footer'
        assert app.copy.winfo_ismapped(), 'Copy action visible at minimum size'
        assert app.progress.winfo_width() <= app.dashboard.winfo_width()
        assert app.root.cget('background') == '#1c232d', 'Dark widget theme'
        app.toggle_sessions()
        root.update()
        assert app.choice.winfo_ismapped() and not app.values['total'].winfo_ismapped(), 'Session list replaces statistics'
        assert app.choice.winfo_rooty() + app.choice.winfo_height() < app.identity.winfo_rooty(), 'Session list stays above footer'
        app.close()
    finally:
        try:
            root.destroy()
        except tk.TclError:
            pass
print('PASS: standalone selection, duplicate titles, stale response rejection, persisted 70% reminder, clipboard, context reset, minimum-size layout')
