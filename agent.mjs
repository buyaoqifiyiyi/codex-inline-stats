import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {findCodexPages} from './debug-endpoint.mjs';
import {createReader} from './reader-client.mjs';
const folder=path.dirname(fileURLToPath(import.meta.url));
const config=JSON.parse((await fs.readFile(path.join(folder,'config.json'),'utf8')).replace(/^\uFEFF/,''));
const renderer=await fs.readFile(path.join(folder,'renderer.js'),'utf8');
const reader=createReader(config.python,['-I','-u',path.join(folder,'reader-entry.py')]);
async function status(state,error){
 await fs.writeFile(path.join(folder,'status.json'),JSON.stringify({state,updatedAt:new Date().toISOString(),...(error?{error}: {})}));
}
let serial=0;
function connect(url){return new Promise((resolve,reject)=>{
 const socket=new WebSocket(url);const pending=new Map();
 const connecting=setTimeout(()=>{socket.close();reject(new Error('Connection timeout'));},3000);
 socket.addEventListener('open',()=>{clearTimeout(connecting);resolve({socket,call(method,params={}){
  return new Promise((res,rej)=>{
   const id=++serial;
   const timer=setTimeout(()=>{pending.delete(id);rej(new Error('Page timeout'));},5000);
   pending.set(id,{res,rej,timer});socket.send(JSON.stringify({id,method,params}));
  });
 }});},{once:true});socket.addEventListener('error',()=>{clearTimeout(connecting);reject(new Error('Connection failed'));},{once:true});
 socket.addEventListener('message',event=>{const msg=JSON.parse(event.data);const entry=pending.get(msg.id);if(entry){clearTimeout(entry.timer);pending.delete(msg.id);msg.error?entry.rej(new Error(msg.error.message)):entry.res(msg.result);}});
 socket.addEventListener('close',()=>{clearTimeout(connecting);for(const entry of pending.values()){clearTimeout(entry.timer);entry.rej(new Error('Disconnected'));}pending.clear();});
});}
async function evaluate(client,expression){const result=await client.call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(result.exceptionDetails)throw new Error('Renderer evaluation failed');return result.result?.value;}
const clients=new Map();
try {
 while(true){
  try{
   const {pages}=await findCodexPages(config.port);
    if(!pages.length)await status('waiting');
   for(const target of pages){
    try {
     let client=clients.get(target.id);
     if(!client || client.socket.readyState!==WebSocket.OPEN){client=await connect(target.webSocketDebuggerUrl);clients.set(target.id,client);}
     await evaluate(client,renderer);
     const context=await evaluate(client,'window.codexInlineStats.context()');
     if(context?.id){
      const result=await reader.read(context.id);
      const accepted=await evaluate(client,`window.codexInlineStats.update(${JSON.stringify(result)})`);
      await status(accepted?'active':'waiting');
     }else await status('waiting');
    }catch{
     const client=clients.get(target.id);
     if(client?.socket.readyState===WebSocket.OPEN)try{await evaluate(client,'window.codexInlineStats?.waiting()');}catch{}
     await status('error','Page or reader unavailable');client?.socket.close();clients.delete(target.id);
    }
   }
   for(const [id,client] of clients)if(!pages.some(p=>p.id===id)){client.socket.close();clients.delete(id);}
  }catch{
   for(const client of clients.values()){
    if(client.socket.readyState===WebSocket.OPEN)try{await evaluate(client,'window.codexInlineStats?.waiting()');}catch{}
    client.socket.close();
   }
   clients.clear();
   await status('waiting','Debug endpoint unavailable');
  }
  await new Promise(resolve=>setTimeout(resolve,500));
 }
}finally{reader.close();for(const client of clients.values())client.socket.close();}
