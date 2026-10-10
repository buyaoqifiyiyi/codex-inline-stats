(() => {
  if (window.codexInlineStats?.version === 5) return;
  window.codexInlineStats?.remove();
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  let bar, metrics, notice, identity = null, latest, copiedId = null;
  const storageKey = 'codex-inline-stats-handoff-dismissed-v1';
  const contextValid = context => Number.isFinite(context?.tokens) && context.tokens >= 0 && Number.isFinite(context.window) && context.window > 0;
  let dismissed = new Set();
  try {
    const saved = JSON.parse(localStorage.getItem(storageKey) || '[]');
    if (Array.isArray(saved)) dismissed = new Set(saved.filter(id => typeof id === 'string' && uuid.test(id)).slice(-200));
  } catch {}
  function saveDismissed() {
    dismissed = new Set([...dismissed].slice(-200));
    try { localStorage.setItem(storageKey, JSON.stringify([...dismissed])); } catch {}
  }
  function handoffPrompt(id) {
    return `请将本会话（ID：${id}）的任务交接到新会话。\n先结合完整聊天和实际文件，保存一份可点击的 Markdown 交接说明，包含：目标与最新要求、已完成事项及验证结果、关键文件路径与必要命令、未完成任务和阻塞条件、下一步具体动作。明确哪些结果已经验证，哪些仍待验证；已完成的工作不要重复执行。\n再新建同一项目下的会话，在初始消息中提供交接文件路径、工作目录和继续执行的指令，让新会话接续剩余任务，并返回打开新会话的入口。如果无法创建新会话，明确说明并给出可直接粘贴的新会话启动指令，不要声称已经创建。\n如有正在运行的任务或定时自动化，列出其状态与归属，避免重复启动或重复创建。`;
  }
  async function copyPrompt(text) {
    try { await navigator.clipboard.writeText(text); return; } catch {}
    const area = document.createElement('textarea');
    area.value = text; area.style.cssText = 'position:fixed;left:-10000px;top:0';
    const active = document.activeElement;
    const selection = window.getSelection();
    const ranges = Array.from({length: selection?.rangeCount || 0}, (_,i) => selection.getRangeAt(i).cloneRange());
    document.body.append(area);
    try {
      area.select();
      if (!document.execCommand('copy')) throw new Error('Clipboard unavailable');
    } finally {
      area.remove(); active?.focus({preventScroll:true});
      if (selection) { selection.removeAllRanges(); ranges.forEach(range => selection.addRange(range)); }
    }
  }
  function reminder(data) {
    const validContext = contextValid(data?.context);
    const high = validContext && data.context.tokens / data.context.window >= 0.7;
    if (validContext && !high) {
      if (dismissed.delete(identity)) saveDismissed();
      if (copiedId === identity) copiedId = null;
    }
    notice.hidden = !high || (dismissed.has(identity) && copiedId !== identity);
    if (notice.hidden) return;
    const copied = copiedId === identity;
    const signature = `${identity}:${copied}`;
    if (notice.dataset.signature === signature) return;
    notice.dataset.signature = signature;
    const message = document.createElement('span');
    message.textContent = copied ? '交接指令已复制，粘贴到本会话发送。' : '上下文已达到 70%，建议本轮结束后新开会话并交接。';
    const copy = document.createElement('button');
    copy.type = 'button'; copy.textContent = copied ? '已复制' : '复制交接指令'; copy.disabled = copied;
    copy.onclick = async () => {
      const id = identity;
      copy.disabled = true;
      try {
        await copyPrompt(handoffPrompt(id));
        dismissed.add(id); saveDismissed();
        if (identity === id) { copiedId = id; reminder(latest); }
      } catch {
        if (identity === id) { message.textContent = '复制失败，请重试。'; copy.disabled = false; }
      }
    };
    const close = document.createElement('button');
    close.type = 'button'; close.textContent = copied ? '关闭' : '暂不提醒';
    close.title = '本会话此次超过 70% 期间不再提醒；上下文降至 70% 以下后重新启用。';
    close.onclick = () => { dismissed.add(identity); saveDismissed(); copiedId = null; notice.hidden = true; };
    notice.replaceChildren(message, copy, close);
  }
  const style = document.createElement('style');
  style.id = 'codex-inline-stats-style';
  style.textContent = `#codex-inline-stats{position:static;display:flex;flex-direction:column;gap:4px;min-height:22px;padding:4px 8px 0;font:inherit;font-size:12px;line-height:18px;color:var(--text-tertiary,#83858b);background:transparent;pointer-events:none;user-select:none}#codex-inline-stats[hidden],#codex-inline-stats [hidden]{display:none}#codex-inline-stats .codex-inline-metrics{display:flex;justify-content:center;align-items:center;flex-wrap:wrap;gap:6px 20px}#codex-inline-stats .codex-inline-metrics span{white-space:nowrap}#codex-inline-stats .codex-inline-metrics span:last-child{white-space:normal;max-width:100%}#codex-inline-stats .codex-inline-handoff{display:flex;align-items:center;justify-content:center;flex-wrap:wrap;gap:4px 10px;max-width:100%;color:var(--text-secondary,#686b73)}#codex-inline-stats .codex-inline-handoff span{overflow-wrap:anywhere}#codex-inline-stats button{pointer-events:auto;font:inherit;line-height:inherit;color:inherit;background:transparent;border:1px solid var(--border-default,rgba(128,128,128,.3));border-radius:6px;padding:1px 7px;cursor:pointer}#codex-inline-stats button:hover{background:var(--bg-secondary,rgba(128,128,128,.12))}#codex-inline-stats button:focus-visible{outline:2px solid var(--text-primary,#808080);outline-offset:2px}#codex-inline-stats button:disabled{opacity:.65;cursor:default}`;
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
      metrics = document.createElement('div'); metrics.className = 'codex-inline-metrics';
      notice = document.createElement('div'); notice.className = 'codex-inline-handoff'; notice.hidden = true;
      notice.setAttribute('role','status'); notice.setAttribute('aria-live','polite');
      bar.append(metrics, notice);
    }
    // Normal document flow reserves its own space and follows the composer, including React remounts.
    if (form.nextElementSibling !== bar) form.after(bar);
    if (id !== identity) { identity = id; latest = null; copiedId = null; metrics.replaceChildren(); notice.hidden = true; delete notice.dataset.signature; bar.hidden = true; }
    return id;
  }
  const number = (v, digits = 1) => Number.isFinite(v) ? v.toFixed(digits) : '--';
  const compact = v => !Number.isFinite(v) ? '--' : v >= 1e6 ? (v/1e6).toFixed(1)+'M' : v >= 1e3 ? (v/1e3).toFixed(1)+'k' : Math.round(v).toString();
  const api = {
    version: 5,
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
      const validContext = contextValid(context);
      const contextText = validContext
        ? `对话上下文约 ${number(100*context.tokens/context.window,0)}% · ${compact(context.tokens)} / ${compact(context.window)} tok`
        : `对话上下文 · ${data.contextState === 'waiting' ? '等待新记录' : '等待统计'}`;
      values.push(['◯',contextText,'整段聊天当前有效上下文的最近上报估计，包含保留的历史、指令及工具信息；使用 last_token_usage.total_tokens 和会话上报窗口。压缩后等待新记录，不含尚未被计入的新内容，百分比可能与 Codex 原生显示不同。']);
      const signature = JSON.stringify(values);
      if (metrics.dataset.signature !== signature || !metrics.childNodes.length) metrics.replaceChildren(...values.map(([icon,text,title]) => {
        const span = document.createElement('span'); span.textContent = `${icon}  ${text}`; span.title = title; return span;
      }));
      metrics.dataset.signature = signature;
      latest = data;
      reminder(data);
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
