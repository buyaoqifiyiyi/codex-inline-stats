"""Run with Python test_telemetry.py; no network or live Codex mutation."""
import datetime as dt
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from telemetry import Measurements


def event(m, seconds, kind, typ=None, **payload):
    if typ:
        payload['type'] = typ
    stamp = dt.datetime.fromtimestamp(1791600000 + seconds, dt.timezone.utc).isoformat()
    m.feed({'timestamp': stamp, 'type': kind, 'payload': payload})


usage = dict(input_tokens=1000, cached_input_tokens=800, output_tokens=242,
             reasoning_output_tokens=167)
m = Measurements()
event(m, 0, 'event_msg', 'task_started', turn_id='turn')
event(m, 29.757, 'event_msg', 'item_completed', item={'type': 'Reasoning'},
      started_at_ms=1791600029757)
event(m, 30, 'token_usage_record', response_id='one', usage=usage)
assert m.last['duration_ms'] == 30000 and abs(m.last['rate'] - 242 / 30) < 1e-9
assert m.last['output_tokens'] == 242 and m.last['basis'] == 'request_observed'
first = m.last
event(m, 30.01, 'event_msg', 'token_count', info={
    'last_token_usage': usage, 'total_token_usage': usage})
event(m, 30.02, 'token_usage_record', response_id='one', usage=usage)
assert m.last is first and m.sample_count == 1

# Parallel tools finish at different times. Count the model interval only after
# the last known output, and ignore a repeated output delivered later.
event(m, 31, 'response_item', 'custom_tool_call', call_id='a')
event(m, 31, 'response_item', 'function_call', call_id='b')
event(m, 90, 'response_item', 'custom_tool_call_output', call_id='a')
event(m, 100, 'response_item', 'function_call_output', call_id='b')
event(m, 109.9, 'response_item', 'custom_tool_call_output', call_id='a')
event(m, 110, 'token_usage_record', response_id='two', usage=usage)
assert m.last['duration_ms'] == 10000 and m.last['rate'] == 24.2
assert m.output_total == 484 and m.last['cache_percent'] == 80

partial = Measurements()
event(partial, 0, 'event_msg', 'item_completed', item={'type': 'AgentMessage'},
      started_at_ms=1791600000000)
event(partial, 1, 'token_usage_record', response_id='partial', usage=usage)
assert partial.last['rate'] is None and partial.last['output_tokens'] == 242
event(m, 111, 'event_msg', 'task_complete')
event(m, 200, 'token_usage_record', response_id='after-finish', usage=usage)
assert m.last['rate'] is None

legacy = Measurements()
event(legacy, 0, 'event_msg', 'task_started', turn_id='legacy')
event(legacy, 10, 'event_msg', 'token_count', info={
    'last_token_usage': usage, 'total_token_usage': usage})
assert legacy.last['rate'] == 24.2
event(legacy, 11, 'event_msg', 'token_count', info={
    'last_token_usage': usage, 'total_token_usage': usage})
assert legacy.sample_count == 1
print('PASS: whole-response timing, reasoning counted once, duplicate usage, '
      'parallel tools, late outputs, missing boundaries, legacy usage')
