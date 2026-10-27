use crate::{
    channel::{IdleEvent, Tunnel},
    config::{udp_range, ClientConfig},
    protocol::Frame,
    transport, Engine,
};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeSet,
    sync::{Arc, Mutex},
};
use tokio::{
    net::UdpSocket,
    sync::OnceCell,
    time::{Duration, Instant},
};

#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Metadata {
    pub visitor_id: String,
    pub visitor_ip: String,
    pub visitor_port: u16,
    pub server_port: u16,
    pub target_ip: String,
    pub target_port: u16,
    pub proxy_responses: i32,
    pub proxy_timeout_ms: i64,
}
pub struct Pool {
    min: u16,
    max: u16,
    used: Mutex<BTreeSet<u16>>,
    default: OnceCell<Arc<UdpSocket>>,
}
struct Lease {
    socket: Arc<UdpSocket>,
    port: u16,
    pool: Arc<Pool>,
}
impl Drop for Lease {
    fn drop(&mut self) {
        self.pool.used.lock().unwrap().remove(&self.port);
    }
}
impl Pool {
    pub fn new(config: &ClientConfig) -> Arc<Self> {
        let (min, max) = udp_range(&config.udp_port_range).unwrap();
        Arc::new(Self {
            min,
            max,
            used: Mutex::new(BTreeSet::new()),
            default: OnceCell::new(),
        })
    }
    async fn default_socket(&self) -> Result<Arc<UdpSocket>, String> {
        self.default
            .get_or_try_init(|| async {
                UdpSocket::bind(("0.0.0.0", self.min))
                    .await
                    .map(Arc::new)
                    .map_err(|_| "无法绑定 UDP 默认端口".to_owned())
            })
            .await
            .cloned()
    }
    async fn lease(self: &Arc<Self>) -> Option<Lease> {
        for port in self.min + 1..=self.max {
            let available = { self.used.lock().unwrap().insert(port) };
            if !available {
                continue;
            }
            match UdpSocket::bind(("0.0.0.0", port)).await {
                Ok(socket) => {
                    return Some(Lease {
                        socket: Arc::new(socket),
                        port,
                        pool: self.clone(),
                    })
                }
                Err(_) => {
                    self.used.lock().unwrap().remove(&port);
                }
            }
        }
        None
    }
}
pub async fn transfer(
    config: ClientConfig,
    license: String,
    initial: Metadata,
    tls: Option<Arc<rustls::ClientConfig>>,
    pool: Arc<Pool>,
    engine: Engine,
) -> Result<(), String> {
    let stream = transport::open(&config, tls).await?;
    let mut wire = Tunnel::new(stream, &config, false, false);
    let bind = Metadata {
        visitor_id: initial.visitor_id.clone(),
        server_port: initial.server_port,
        target_ip: initial.target_ip,
        target_port: initial.target_port,
        ..Default::default()
    };
    wire.send(Frame::new(
        8,
        serde_json::to_string(&bind).unwrap(),
        license.into_bytes(),
    ))
    .map_err(|_| "绑定 UDP 隧道失败".to_owned())?;
    let mut lease: Option<Lease> = None;
    let mut bound = Metadata::default();
    let mut responses = 0;
    let mut warned = false;
    let mut buffer = vec![0u8; 65536];
    let mut deadline = Box::pin(tokio::time::sleep(Duration::from_secs(1)));
    loop {
        tokio::select! {
            _=&mut deadline,if lease.is_some()=>break,
            event=wire.idle.next()=>match event {
                IdleEvent::Read if wire.writer.writable()=>return Err("UDP 隧道读取空闲超时".into()),
                IdleEvent::Write if wire.writer.writable()=>{wire.send(Frame::new(1,"",vec![]))?;},
                _=>{},
            },
            result=wire.writer.flush_one(),if wire.writer.pending()=>{result.map_err(|_|"UDP 隧道写入失败".to_owned())?;wire.idle.written();},
            packet=async{match &lease{Some(lease)=>lease.socket.recv_from(&mut buffer).await,None=>std::future::pending().await}},if wire.writer.writable()=>{
                let(size,_)=packet.map_err(|_|"读取 UDP 响应失败".to_owned())?;
                let reply=Metadata{proxy_responses:0,proxy_timeout_ms:0,..bound.clone()};
                wire.send(Frame::new(16,serde_json::to_string(&reply).unwrap(),buffer[..size].to_vec())).map_err(|_|"发送 UDP 响应失败".to_owned())?;
                responses+=1;
                if bound.proxy_responses>0&&responses>=bound.proxy_responses{break}
                deadline.as_mut().reset(Instant::now()+Duration::from_millis(bound.proxy_timeout_ms as u64));
            },
            frame=wire.reader.next()=>{
                let frame=match frame{Some(Ok(frame))=>frame,Some(Err(_))=>return Err("UDP 隧道消息格式无效".into()),None=>break};
                wire.idle.read();
                if frame.kind==4||frame.kind==9{break}
                if frame.kind!=16{continue}
                let meta:Metadata=serde_json::from_str(&frame.info).map_err(|_|"UDP 元数据格式无效".to_owned())?;
                if frame.data.len()>65507{return Err("UDP 数据报超出最大长度".into())}
                if lease.is_none()&&meta.proxy_responses!=0&&meta.proxy_timeout_ms>0{
                    lease=pool.lease().await;
                    if lease.is_some(){bound=meta.clone();}else if !warned{engine.log("warn","UDP","UDP 回包端口不足，当前会话仅发送数据");warned=true;}
                }
                let socket=if let Some(lease)=&lease{lease.socket.clone()}else{pool.default_socket().await?};
                socket.send_to(&frame.data,(meta.target_ip.as_str(),meta.target_port)).await.map_err(|_|"发送到 UDP 目标失败".to_owned())?;
                if lease.is_some(){responses=0;deadline.as_mut().reset(Instant::now()+Duration::from_millis(bound.proxy_timeout_ms as u64));}
            }
        }
    }
    // A response-count deadline can end a session immediately after enqueueing its last reply.
    wire.writer
        .finish()
        .await
        .map_err(|_| "关闭 UDP 隧道失败".to_owned())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::Codec;
    use futures_util::StreamExt;
    use tokio::{net::TcpListener, time::timeout};
    use tokio_util::codec::Framed;

    #[tokio::test]
    async fn udp_tunnel_enforces_read_idle_without_a_response_lease() {
        let server = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let config = ClientConfig {
            server: "127.0.0.1".into(),
            port: server.local_addr().unwrap().port(),
            ssl: false,
            read_idle_seconds: 1,
            heartbeat_seconds: 0,
            ..Default::default()
        };
        let pool = Pool::new(&config);
        let worker = tokio::spawn(transfer(
            config,
            "test-license".into(),
            Metadata::default(),
            None,
            pool,
            Engine::new(),
        ));
        let mut wire = Framed::new(server.accept().await.unwrap().0, Codec);
        assert_eq!(wire.next().await.unwrap().unwrap().kind, 8);
        assert!(matches!(
            timeout(Duration::from_millis(2200), wire.next()).await,
            Ok(None)
        ));
        assert!(worker.await.unwrap().unwrap_err().contains("读取空闲超时"));
    }
}
