import json, os, sys, time
from pathlib import Path
from telemetry import ThreadRepository, TailCache

home = Path(os.environ.get('CODEX_HOME', str(Path.home()/'.codex')))
repository = ThreadRepository(home)
tails = TailCache()

def reading(thread_id):
    repository.refresh()
    row = repository.rows.get(thread_id)
    if not row and repository.database:
        with repository._connect() as conn:
            conn.row_factory = __import__('sqlite3').Row
            result = conn.execute(repository._select()+' WHERE id = ?', (thread_id,)).fetchone()
            row = dict(result) if result else None
    if not row: return {'id':thread_id, 'ok':False}
    tail = tails.update(row)
    if not tail: return {'id':thread_id, 'ok':False}
    metrics = tail.measurements.snapshot()
    last = metrics.get('last') or {}
    total = None
    recent_input = None
    try:
        with Path(row['rollout_path']).open('rb') as f:
            f.seek(max(0, f.seek(0,2) - 2*1024*1024)); lines = f.read().splitlines()
        for line in reversed(lines):
            try: event = json.loads(line)
            except ValueError: continue
            payload = event.get('payload') or {}
            if event.get('type') == 'event_msg' and payload.get('type') == 'token_count':
                info = payload.get('info') or {}
                usage = info.get('total_token_usage') or {}
                total = usage.get('total_tokens')
                recent = info.get('last_token_usage') or {}
                recent_input = recent.get('input_tokens')
                break
    except OSError: pass
    stale = time.time()*1000-last.get('measured_at_ms',0)>900000
    # A previous turn's completed response is not labelled as the current turn's live speed.
    current = last.get('turn_id') == metrics.get('turn_id')
    return {'id':thread_id,'ok':True,'stage':metrics.get('stage'),
        'rate':None if stale or not current else last.get('rate'),
        'cache':None if stale else last.get('cache_percent'),
        'total':total,'recentInputTokens':recent_input}

for line in sys.stdin:
    try:
        query = json.loads(line)
        result = reading(query['id'])
    except Exception as error:
        result = {'id':locals().get('query',{}).get('id'), 'ok':False, 'error':type(error).__name__}
    print(json.dumps(result, ensure_ascii=False, allow_nan=False), flush=True)
