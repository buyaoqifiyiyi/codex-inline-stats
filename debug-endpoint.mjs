// Chromium can bind its debugging server to either IPv4 or IPv6 loopback.
let preferred = '127.0.0.1';
export async function findCodexPages(port) {
  let reachable;
  for (const address of new Set([preferred, '127.0.0.1', '[::1]'])) {
    try {
      const response = await fetch(`http://${address}:${port}/json/list`, {signal: AbortSignal.timeout(2000)});
      if (!response.ok) continue;
      const targets = await response.json();
      if (!Array.isArray(targets)) continue;
      const pages = targets.filter(target => {
        if (target?.type !== 'page' || typeof target.url !== 'string' || !target.url.startsWith('app://-/index.html')) return false;
        try {
          const socket = new URL(target.webSocketDebuggerUrl);
          return socket.protocol === 'ws:' && ['127.0.0.1', '[::1]', 'localhost'].includes(socket.hostname) && Number(socket.port) === Number(port);
        } catch { return false; }
      });
      if (pages.length) { preferred = address; return {address, pages}; }
      reachable ||= {address, pages};
    } catch {}
  }
  if (reachable) return reachable;
  throw new Error('Debug endpoint unavailable on IPv4 and IPv6 loopback');
}
