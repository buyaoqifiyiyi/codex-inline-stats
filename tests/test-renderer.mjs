import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const source = fs.readFileSync(path.join(root, 'renderer.js'), 'utf8');
const candidates = [process.env.EDGE_PATH,
  process.env['ProgramFiles(x86)'] && path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe'),
  process.env.ProgramFiles && path.join(process.env.ProgramFiles, 'Microsoft/Edge/Application/msedge.exe')].filter(Boolean);
const browser = candidates.find(p => fs.existsSync(p));
assert.ok(browser, 'Edge is required; set EDGE_PATH if installed elsewhere.');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-inline-test-'));
const fixture = path.join(temp, 'fixture.html');
const checks = `
const check=(ok,label)=>{if(!ok)throw Error(label)};
const first='11111111-1111-4111-8111-111111111111',second='22222222-2222-4222-8222-222222222222';
try {
 check(window.codexInlineStats.context().id===first,'ID binding');
 window.codexInlineStats.update({id:first,ok:true,rate:20,cache:80,total:1000});
 let form=document.querySelector('form'),bar=document.querySelector('#codex-inline-stats');
 check(bar.getBoundingClientRect().top>=form.getBoundingClientRect().bottom,'No overlap');
 check(getComputedStyle(bar).position==='static','Normal layout');
 document.querySelector('main').innerHTML='<form style="height:220px"><div contenteditable=true aria-label=Codex></div></form>';
 document.querySelector('[contenteditable]').__reactFiber$test={memoizedProps:{conversationId:second}};
 check(window.codexInlineStats.context().id===second,'Chat remount');
 check(bar.hidden,'Old data cleared');
 check(!window.codexInlineStats.update({id:first,ok:true,rate:999}),'Stale response rejected');
 document.querySelector('main').style.width='240px';
 window.codexInlineStats.update({id:second,ok:true,rate:18,total:500000,cache:93,recentInputTokens:184286});
 form=document.querySelector('form');bar=document.querySelector('#codex-inline-stats');
 check(bar.getBoundingClientRect().top>=form.getBoundingClientRect().bottom,'Narrow no overlap');
 check(bar.getBoundingClientRect().width===240,'Narrow width');
 check(bar.textContent.includes('调用均速 18.0 tok/s'),'Observed rate label');
 check(bar.textContent.includes('最近输入 184.3k tok'),'Last input label');
 check(!bar.textContent.includes('上下文'),'No misleading context label');
 window.codexInlineStats.remove();
 check(!document.querySelector('#codex-inline-stats'),'Clean removal');
 document.body.innerHTML='<pre>CODEX_INLINE_TEST_PASS</pre>';
}catch(error){document.body.innerHTML='<pre>CODEX_INLINE_TEST_FAIL: '+error.message+'</pre>';}
`;
try {
 fs.writeFileSync(fixture, `<!doctype html><html><meta charset="utf-8"><body><main style="width:600px"><form style="height:120px"><div contenteditable="true" aria-label="Codex"></div></form></main><script>document.querySelector('[contenteditable]').__reactFiber$test={memoizedProps:{conversationId:'11111111-1111-4111-8111-111111111111'}};</script><script>${source}</script><script>${checks}</script></body></html>`);
 const result = spawnSync(browser, ['--headless','--disable-gpu','--no-first-run',`--user-data-dir=${path.join(temp,'profile')}`,'--dump-dom',pathToFileURL(fixture).href], {encoding:'utf8',timeout:25000,windowsHide:true,maxBuffer:1024*1024});
 if(result.error)throw result.error;
 assert.equal(result.status, 0, 'Headless browser failed');
 assert.match(result.stdout, /<pre>CODEX_INLINE_TEST_PASS<\/pre>/, result.stdout.slice(-1200));
 console.log('PASS: renderer binding, remount, stale response, layout, labels, removal');
} finally {
 // Only remove this test's freshly created directory under the system temp root.
 assert.equal(path.dirname(path.resolve(temp)), path.resolve(os.tmpdir()));
 assert.ok(path.basename(temp).startsWith('codex-inline-test-'));
 fs.rmSync(temp, {recursive:true,force:true,maxRetries:3,retryDelay:200});
}
