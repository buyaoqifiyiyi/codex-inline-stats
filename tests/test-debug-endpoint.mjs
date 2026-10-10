import http from 'node:http';
import assert from 'node:assert/strict';
import {findCodexPages} from '../debug-endpoint.mjs';

const servers = [];
const modes = {'127.0.0.1': 'page', '[::1]': 'page'};
async function listen(address, port = 0) {
  const server = http.createServer((request, response) => {
    assert.equal(request.url, '/json/list');
    const mode = modes[address];
    response.setHeader('Content-Type', 'application/json');
    if (mode === 'invalid') { response.end('{broken'); return; }
    if (mode === 'error') { response.writeHead(503); response.end('[]'); return; }
    if (mode === 'empty') { response.end('[]'); return; }
    const target = {id: address, type: 'page', url: 'app://-/index.html', webSocketDebuggerUrl: `ws://${address}:${server.address().port}/devtools/page/test`};
    response.end(JSON.stringify(mode === 'unsafe'
      ? [{...target, webSocketDebuggerUrl: 'ws://example.com:9335/debug'}, {...target, url: 42}]
      : [null, {type: 'webview'}, target]));
  });
  servers.push(server);
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen({host: address === '[::1]' ? '::1' : address, port, ipv6Only: true}, resolve);
  });
  return server.address().port;
}
async function closeAll() {
  for (const server of servers.splice(0)) {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
}
try {
  const port = await listen('[::1]');
  let result = await findCodexPages(port);
  assert.equal(result.address, '[::1]', 'IPv6-only startup must work');
  assert.equal(result.pages.length, 1);
  await listen('127.0.0.1', port);
  modes['[::1]'] = 'empty';
  result = await findCodexPages(port);
  assert.equal(result.address, '127.0.0.1', 'Try other family when reachable endpoint has no Codex page');
  modes['127.0.0.1'] = 'invalid'; modes['[::1]'] = 'page';
  assert.equal((await findCodexPages(port)).address, '[::1]', 'Malformed response must fall back');
  modes['[::1]'] = 'error'; modes['127.0.0.1'] = 'page';
  assert.equal((await findCodexPages(port)).address, '127.0.0.1', 'HTTP error must fall back after family changes');
  modes['127.0.0.1'] = 'unsafe'; modes['[::1]'] = 'page';
  assert.equal((await findCodexPages(port)).address, '[::1]', 'Only connect to local Codex debugging URLs');
  modes['[::1]'] = 'empty';
  assert.deepEqual((await findCodexPages(port)).pages, [], 'No matching Codex page is a reachable waiting state');
  await closeAll();
  await assert.rejects(findCodexPages(port), /IPv4 and IPv6/);
  console.log('PASS: IPv6-only, IPv4 fallback, family changes, malformed/error responses, safe local targets, unavailable endpoint');
} finally { await closeAll(); }
