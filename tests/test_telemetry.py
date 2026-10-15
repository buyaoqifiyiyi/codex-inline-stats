"""Run with Python test_telemetry.py; no network or live Codex mutation."""
import datetime as dt
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from telemetry import Measurements, context_reading


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
assert m.last['cache_state'] == 'reported'

partial = Measurements()
event(partial, 0, 'event_msg', 'item_completed', item={'type': 'AgentMessage'},
      started_at_ms=1791600000000)
event(partial, 1, 'token_usage_record', response_id='partial', usage=usage)
assert partial.last['rate'] is None and partial.last['output_tokens'] == 242
assert partial.last['cache_state'] == 'reported'
uncached = Measurements()
event(uncached, 0, 'event_msg', 'task_started', turn_id='uncached')
event(uncached, 10, 'token_usage_record', response_id='zero-cache', usage={
    'input_tokens': 100, 'cached_input_tokens': 0, 'output_tokens': 10})
assert uncached.last['cache_percent'] == 0 and uncached.last['cache_state'] == 'reported'
event(uncached, 11, 'token_usage_record', response_id='missing-cache', usage={
    'input_tokens': 100, 'output_tokens': 10})
assert uncached.last['cache_percent'] is None and uncached.last['cache_state'] == 'field_missing'
event(m, 111, 'event_msg', 'task_complete')
event(m, 200, 'token_usage_record', response_id='after-finish', usage=usage)
assert m.last['rate'] is None

legacy = Measurements()
event(legacy, 0, 'event_msg', 'task_started', turn_id='legacy')
event(legacy, 10, 'event_msg', 'token_count', info={
    'last_token_usage': usage, 'total_token_usage': usage})
assert legacy.last['rate'] == 24.2
assert legacy.last['cache_state'] == 'reported'
event(legacy, 11, 'event_msg', 'token_count', info={
    'last_token_usage': usage, 'total_token_usage': usage})
assert legacy.sample_count == 1
empty_input = Measurements()
event(empty_input, 0, 'event_msg', 'task_started', turn_id='empty-input')
event(empty_input, 10, 'token_usage_record', response_id='empty', usage={
    'input_tokens': 0, 'cached_input_tokens': 0, 'output_tokens': 10})
assert empty_input.last['cache_state'] == 'empty_input'
print('PASS: whole-response timing, reasoning counted once, duplicate usage, '
      'parallel tools, late outputs, missing boundaries, legacy usage')

# Whole retained context uses the last reported total, never session spend or
# input-only counts. Context updates must also survive response-usage dedup.
context = Measurements('model-a')
event(context, 0, 'event_msg', 'task_started', turn_id='context-turn')
event(context, 10, 'token_usage_record', response_id='context-response', usage=usage)
response = context.last
event(context, 10.01, 'event_msg', 'token_count', info={
    'last_token_usage': {**usage, 'total_tokens': 198420},
    'total_token_usage': {**usage, 'total_tokens': 9000000},
    'model_context_window': 258400})
assert context.last is response and context.sample_count == 1
assert context.context['tokens'] == 198420 and context.context['window'] == 258400
event(context, 11, 'compacted')
assert context.context is None and context.context_state == 'waiting'
event(context, 11.01, 'event_msg', 'token_count', info={
    'last_token_usage': {'input_tokens': 0, 'output_tokens': 0, 'total_tokens': 20283},
    'total_token_usage': {'total_tokens': 9000000}, 'model_context_window': 258400})
assert context.context['tokens'] == 20283
assert abs(context.context['percent'] - 7.849458204334366) < 1e-9
event(context, 12, 'turn_context', model='model-b')
assert context.context is None and context.context_state == 'waiting'
event(context, 13, 'event_msg', 'token_count', info={
    'last_token_usage': {'total_tokens': 400000}, 'model_context_window': 1000000})
assert context.context['percent'] == 40
event(context, 14, 'event_msg', 'thread_rolled_back')
assert context.context is None and context.context_state == 'waiting'
for invalid in [None, True, {}, -1, '20283']:
    assert context_reading({'last_token_usage': {'total_tokens': invalid},
                            'model_context_window': 258400}, 0) is None
assert context_reading({'last_token_usage': {'total_tokens': 12}}, 0) is None
assert context_reading({'last_token_usage': {'total_tokens': 12},
                        'model_context_window': False}, 0) is None
assert context_reading({'last_token_usage': {'total_tokens': 0},
                        'model_context_window': 200}, 0)['percent'] == 0
assert context_reading({'last_token_usage': {'total_tokens': 201},
                        'model_context_window': 200}, 0)['percent'] == 100.5
other = Measurements('model-b')
assert other.context is None  # Per-thread instances do not share readings.
print('PASS: whole context, post-compaction totals, model/window changes, rollback, '
      'missing/invalid readings, no clamping, thread isolation')
