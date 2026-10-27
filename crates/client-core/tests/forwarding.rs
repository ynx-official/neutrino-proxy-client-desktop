use futures_util::{SinkExt, StreamExt};
use neutrino_client_core::{
    config::{ClientConfig, Secrets},
    protocol::{Codec, Frame},
    Engine,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, UdpSocket},
    time::{timeout, Duration},
};
use tokio_util::codec::Framed;

#[tokio::test]
async fn tcp_forwards_binary_payload_in_both_directions() {
    let target = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = target.local_addr().unwrap();
    let echo = tokio::spawn(async move {
        let (mut socket, _) = target.accept().await.unwrap();
        let mut bytes = [0; 1024];
        loop {
            let n = socket.read(&mut bytes).await.unwrap();
            if n == 0 {
                break;
            }
            socket.write_all(&bytes[..n]).await.unwrap();
        }
    });
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let peer = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut control = Framed::new(socket, Codec);
        let _ = control.next().await;
        control
            .send(Frame::new(2, r#"{"code":0}"#, vec![]))
            .await
            .unwrap();
        control
            .send(Frame::new(
                3,
                "visitor-one",
                address.to_string().into_bytes(),
            ))
            .await
            .unwrap();
        let (socket, _) = listener.accept().await.unwrap();
        let mut data = Framed::new(socket, Codec);
        assert_eq!(
            data.next().await.unwrap().unwrap().info,
            "visitor-one@license"
        );
        let payload = vec![0, 255, 1, 128, 32];
        data.send(Frame::new(5, "visitor-one", payload.clone()))
            .await
            .unwrap();
        assert_eq!(data.next().await.unwrap().unwrap().data, payload);
    });
    let engine = Engine::new();
    engine
        .connect(
            ClientConfig {
                server: "127.0.0.1".into(),
                port,
                ssl: false,
                ..Default::default()
            },
            Secrets {
                license: "license".into(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    timeout(Duration::from_secs(5), peer)
        .await
        .unwrap()
        .unwrap();
    engine.disconnect().await;
    timeout(Duration::from_secs(2), echo)
        .await
        .unwrap()
        .unwrap();
}

#[tokio::test]
async fn udp_preserves_datagram_and_returns_response() {
    let target = UdpSocket::bind("127.0.0.1:0").await.unwrap();
    let target_port = target.local_addr().unwrap().port();
    let echo = tokio::spawn(async move {
        let mut bytes = [0u8; 1024];
        let (n, peer) = target.recv_from(&mut bytes).await.unwrap();
        target.send_to(&bytes[..n], peer).await.unwrap();
    });
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let peer = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut control = Framed::new(socket, Codec);
        let _ = control.next().await;
        control
            .send(Frame::new(2, r#"{"code":0}"#, vec![]))
            .await
            .unwrap();
        let info=serde_json::json!({"visitorId":"udp-visitor","visitorIp":"127.0.0.1","visitorPort":12345,"serverPort":19001,"targetIp":"127.0.0.1","targetPort":target_port,"proxyResponses":1,"proxyTimeoutMs":1000}).to_string();
        control.send(Frame::new(8, &info, vec![])).await.unwrap();
        let (socket, _) = listener.accept().await.unwrap();
        let mut data = Framed::new(socket, Codec);
        let bind = data.next().await.unwrap().unwrap();
        assert_eq!(bind.kind, 8);
        assert_eq!(bind.data, b"license");
        data.send(Frame::new(16, info, vec![0, 255, 11, 22]))
            .await
            .unwrap();
        let response = data.next().await.unwrap().unwrap();
        assert_eq!(response.kind, 16);
        assert_eq!(response.data, vec![0, 255, 11, 22]);
        let meta: serde_json::Value = serde_json::from_str(&response.info).unwrap();
        assert_eq!(meta["visitorId"], "udp-visitor");
    });
    let engine = Engine::new();
    engine
        .connect(
            ClientConfig {
                server: "127.0.0.1".into(),
                port,
                ssl: false,
                udp_port_range: "50200-50210".into(),
                ..Default::default()
            },
            Secrets {
                license: "license".into(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    let result = timeout(Duration::from_secs(4), peer).await;
    engine.disconnect().await;
    assert!(
        result.is_ok(),
        "UDP data tunnel must open and return a response"
    );
    result.unwrap().unwrap();
    timeout(Duration::from_secs(2), echo)
        .await
        .unwrap()
        .unwrap();
}
