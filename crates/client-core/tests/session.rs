use futures_util::{SinkExt, StreamExt};
use neutrino_client_core::{
    config::{ClientConfig, Secrets},
    protocol::{Codec, Frame},
    Engine,
};
use tokio::{
    net::TcpListener,
    time::{sleep, timeout, Duration},
};
use tokio_util::codec::Framed;

#[test]
fn saved_configuration_is_presented_as_ready_instead_of_first_run() {
    let engine = Engine::new();
    engine.configure(
        ClientConfig {
            server: "example.com".into(),
            ..Default::default()
        },
        &Secrets {
            license: "test-license".into(),
            ..Default::default()
        },
    );
    assert!(engine.snapshot().detail.contains("已就绪"));
    assert_eq!(engine.snapshot().state, "idle");
}

#[tokio::test]
async fn real_authentication_and_disconnect_cancel_retries() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let peer = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut wire = Framed::new(socket, Codec);
        let auth = wire.next().await.unwrap().unwrap();
        assert_eq!(auth.kind, 2);
        assert_eq!(auth.info, "test-license,test-id");
        wire.send(Frame::new(2, r#"{"code":0,"msg":"success"}"#, vec![]))
            .await
            .unwrap();
        sleep(Duration::from_millis(300)).await;
    });
    let engine = Engine::new();
    let config = ClientConfig {
        server: "127.0.0.1".into(),
        port,
        ssl: false,
        client_id: "test-id".into(),
        reconnect_seconds: 1,
        ..Default::default()
    };
    engine
        .connect(
            config,
            Secrets {
                license: "test-license".into(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    timeout(Duration::from_secs(3), async {
        while engine.snapshot().state != "connected" {
            sleep(Duration::from_millis(10)).await
        }
    })
    .await
    .unwrap();
    engine.disconnect().await;
    assert_eq!(engine.snapshot().state, "idle");
    peer.await.unwrap();
    sleep(Duration::from_millis(1100)).await;
    assert_eq!(engine.snapshot().state, "idle");
    assert!(!serde_json::to_string(&engine.snapshot())
        .unwrap()
        .contains("test-license"));
}

#[tokio::test]
async fn invalid_license_stops_engine_but_retains_error_state() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let peer = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut wire = Framed::new(socket, Codec);
        let _ = wire.next().await;
        wire.send(Frame::new(
            2,
            r#"{"code":1,"msg":"invalid secret"}"#,
            vec![],
        ))
        .await
        .unwrap();
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
                license: "private-token".into(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    timeout(Duration::from_secs(3), async {
        while engine.snapshot().state != "error" {
            sleep(Duration::from_millis(10)).await
        }
    })
    .await
    .unwrap();
    assert!(engine.snapshot().detail.contains("License"));
    assert!(engine.snapshot().retry_at.is_none());
    engine.disconnect().await;
    peer.await.unwrap();
}
