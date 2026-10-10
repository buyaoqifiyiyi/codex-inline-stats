import {spawn} from 'node:child_process';
import readline from 'node:readline';

// One outstanding request, as used by the agent's sequential page loop.
export function createReader(command, args, timeoutMs = 5000) {
  let child, pending;
  function discard(process, error) {
    if (child !== process) return;
    child = undefined;
    pending?.reject(error);
    process.kill();
  }
  function start() {
    const process = spawn(command, args, {windowsHide: true, stdio: ['pipe', 'pipe', 'ignore']});
    child = process;
    readline.createInterface({input: process.stdout}).on('line', line => {
      if (child !== process) return;
      try {
        const data = JSON.parse(line);
        if (data.id === pending?.id) pending.resolve(data);
      } catch {}
    });
    process.on('error', () => discard(process, new Error('Reader unavailable')));
    process.on('exit', () => discard(process, new Error('Reader exited')));
    process.stdin.on('error', () => discard(process, new Error('Reader pipe unavailable')));
    return process;
  }
  return {
    async read(id) {
      if (pending) throw new Error('Concurrent reader request');
      const process = child || start();
      let timer;
      try {
        return await new Promise((resolve, reject) => {
          pending = {id, resolve, reject};
          timer = setTimeout(() => discard(process, new Error('Reader timeout')), timeoutMs);
          process.stdin.write(JSON.stringify({id}) + '\n', error => {
            if (error) discard(process, new Error('Reader write failed'));
          });
        });
      } finally { clearTimeout(timer); pending = undefined; }
    },
    close() {
      if (child) discard(child, new Error('Reader stopped'));
    },
  };
}
