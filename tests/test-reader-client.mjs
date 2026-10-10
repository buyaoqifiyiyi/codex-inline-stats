import assert from 'node:assert/strict';
import {createReader} from '../reader-client.mjs';

const fixture = `
const readline = require('node:readline');
readline.createInterface({input: process.stdin}).on('line', line => {
 const {id} = JSON.parse(line);
 if (id === 'exit') process.exit(1);
 else if (id === 'hang') return;
 else console.log(JSON.stringify({id, ok: true, pid: process.pid}));
});`;
const reader = createReader(process.execPath, ['-e', fixture], 700);
try {
  const first = await reader.read('first');
  assert.equal(first.ok, true);
  assert.equal((await reader.read('same')).pid, first.pid, 'Healthy subprocess reused');
  await assert.rejects(reader.read('exit'), /Reader (exited|pipe|write)/);
  const afterExit = await reader.read('after-exit');
  assert.notEqual(afterExit.pid, first.pid, 'Crash restarts subprocess');
  const hanging = reader.read('hang');
  const failure = assert.rejects(hanging, /Reader timeout/);
  await assert.rejects(reader.read('concurrent'), /Concurrent/);
  await failure;
  assert.notEqual((await reader.read('after-timeout')).pid, afterExit.pid, 'Timeout discards stuck process');
  reader.close();
  assert.equal((await reader.read('restart')).ok, true);
  console.log('PASS: subprocess reuse, crash recovery, timeout recovery, concurrent guard, explicit restart');
} finally { reader.close(); }
const missing = createReader('codex-stats-nonexistent-runtime', [], 700);
try { await assert.rejects(missing.read('missing'), /Reader unavailable/); }
finally { missing.close(); }
