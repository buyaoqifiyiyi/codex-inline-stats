(() => {
  if (window.codexInlineStats?.version === 4) return;
  window.codexInlineStats?.remove();
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  let bar, identity = null;
  const style = document.createElement('style');
  style.id = 'codex-inline-stats-style';
  style.textContent = `#codex-inline-stats{position:static;display:flex;justify-content:center;align-items:center;flex-wrap:wrap;gap:6px 20px;min-height:22px;padding:4px 8px 0;font:inherit;font-size:12px;line-height:18px;color:var(--text-tertiary,#83858b);background:transparent;pointer-events:none;user-select:none}#codex-inline-stats[hidden]{display:none}#codex-inline-stats span{white-space:nowrap}#codex-inline-stats span:last-child{white-space:normal;max-width:100%}`;
  document.head.append(style);
  function editor() {
    const selectors = document.querySelector('[data-codex-composer-root]')
      ? '[data-codex-composer-root] [contenteditable="true"],[data-codex-composer-root] textarea'
      : '[contenteditable="true"][role="textbox"],[contenteditable="true"],textarea';
    return [...document.querySelectorAll(selectors)]
      .filter(e => e.getClientRects().length && !e.closest('[data-codex-inline-stats]'))
      .find(e => /Codex|协作/.test(e.getAttribute('aria-label') || e.getAttribute('data-placeholder') || '') || e.closest('[data-codex-composer-root],form'));
  }
  function threadId(e) {
    const route = (location.pathname + location.search + location.hash).match(/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}/i);
    if (route) return route[0];
    for (let el = e; el; el = el.parentElement) {
      const key = Object.keys(el).find(k => k.startsWith('__reactFiber$'));
      for (let fiber = el[key], depth = 0; fiber && depth < 40; fiber = fiber.return, depth++) {
        const props = fiber.memoizedProps;
        for (const name of ['conversationId','threadId','activeThreadId']) {
          if (uuid.test(props?.[name] || '')) return props[name];
        }
      }
    }
    return null;
  }
  function mount() {
    const e = editor();
    const form = e?.closest('[data-codex-composer-root]') || e?.closest('form');
    if (!e || !form || !form.parentElement) { if (bar) bar.hidden = true; identity = null; return null; }
    const id = threadId(e);
    if (!id) { if (bar) bar.hidden = true; identity = null; return null; }
    if (!bar) {
      bar = document.createElement('div'); bar.id = 'codex-inline-stats';
      bar.dataset.codexInlineStats = 'true'; bar.setAttribute('role','status');
      bar.setAttribute('aria-live','off');
    }
    // Normal document flow reserves its own space and follows the composer, including React remounts.
    if (form.nextElementSibling !== bar) form.after(bar);
    if (id !== identity) { identity = id; bar.replaceChildren(); bar.hidden = true; }
    return id;
  }
  const number = (v, digits = 1) => Number.isFinite(v) ? v.toFixed(digits) : '--';
  const compact = v => !Number.isFinite(v) ? '--' : v >= 1e6 ? (v/1e6).toFixed(1)+'M' : v >= 1e3 ? (v/1e3).toFixed(1)+'k' : Math.round(v).toString();
  const api = {
    version: 4,
    context: () => ({id: mount(), mounted: !!bar?.isConnected}),
    update: data => {
      const id = mount();
      if (!id || data.id !== id || !data.ok) { if (bar) bar.hidden = true; return false; }
      const stage = {generating:'生成中',tools:'工具运行中',idle:'最近响应'}[data.stage] || '等待统计';
      const values = [
        ['◷',`${stage} · 调用均速 ${number(data.rate)} tok/s`,'最近一次已完成调用：输出 token（含推理）÷ 客户端观察耗时。含排队、首 token 等待及日志交付；从已知工具返回后计时。不代表服务端实时生成速度。'],
        ['▤',`${compact(data.total)} tok · 缓存命中 ${number(data.cache,0)}%`,'累计 token 取日志累计计数；缓存命中率取最近一次模型调用。'],
      ];
      const context = data.context;
      const validContext = Number.isFinite(context?.tokens) && context.tokens >= 0 && Number.isFinite(context.window) && context.window > 0;
      const contextText = validContext
        ? `对话上下文约 ${number(100*context.tokens/context.window,0)}% · ${compact(context.tokens)} / ${compact(context.window)} tok`
        : `对话上下文 · ${data.contextState === 'waiting' ? '等待新记录' : '等待统计'}`;
      values.push(['◯',contextText,'整段聊天当前有效上下文的最近上报估计，包含保留的历史、指令及工具信息；使用 last_token_usage.total_tokens 和会话上报窗口。压缩后等待新记录，不含尚未被计入的新内容，百分比可能与 Codex 原生显示不同。']);
      const signature = JSON.stringify(values);
      if (bar.dataset.signature !== signature) bar.replaceChildren(...values.map(([icon,text,title]) => {
        const span = document.createElement('span'); span.textContent = `${icon}  ${text}`; span.title = title; return span;
      }));
      bar.dataset.signature = signature;
      bar.hidden = false;
      return true;
    },
    remove: () => { observer.disconnect(); bar?.remove(); style.remove(); delete window.codexInlineStats; },
  };
  const observer = new MutationObserver(() => { mount(); });
  observer.observe(document.body, {childList:true,subtree:true});
  window.codexInlineStats = api;
  mount();
})();
