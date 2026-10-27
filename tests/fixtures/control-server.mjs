// Local-only protocol fixture for exercising the desktop UI without a production server.
import net from 'node:net';
const port=Number(process.argv[2]||19002);
const sockets=new Set();
function frame(kind,info=''){
  const text=Buffer.from(info);const bytes=Buffer.alloc(17+text.length);
  bytes.writeUInt32BE(13+text.length);bytes.writeUInt8(kind,4);bytes.writeBigInt64BE(BigInt(Date.now()),5);bytes.writeUInt32BE(text.length,13);text.copy(bytes,17);return bytes;
}
const server=net.createServer(socket=>{
  sockets.add(socket);let pending=Buffer.alloc(0),authenticated=false;
  const heartbeat=setInterval(()=>{if(authenticated&&!socket.destroyed)socket.write(frame(1));},5000);
  socket.on('data',bytes=>{
    pending=Buffer.concat([pending,bytes]);
    while(pending.length>=4){
      const length=pending.readUInt32BE();if(length<13||length>2097148){socket.destroy();return;}
      if(pending.length<length+4)return;
      const packet=pending.subarray(0,length+4);pending=pending.subarray(length+4);
      if(packet[4]===2){
        const n=packet.readUInt32BE(13);if(n>length-13){socket.destroy();return;}
        const info=packet.subarray(17,17+n).toString();authenticated=info.split(',')[0]==='local-test';
        socket.write(frame(2,JSON.stringify({code:authenticated?0:1,msg:authenticated?'success':'auth failed'})));
        console.log(authenticated?'Local test client authenticated':'Local test authentication rejected');
      }
    }
  });
  socket.on('error',()=>{});socket.on('close',()=>{clearInterval(heartbeat);sockets.delete(socket);});
});
function stop(){for(const socket of sockets)socket.destroy();server.close(()=>process.exit(0));}
process.on('SIGINT',stop);process.on('SIGTERM',stop);
server.listen(port,'127.0.0.1',()=>console.log(`Local test fixture ready: 127.0.0.1:${port} (License: local-test, SSL: off)`));
