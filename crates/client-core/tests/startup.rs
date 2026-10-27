use futures_util::{SinkExt, StreamExt};
use neutrino_client_core::{
    config::{ClientConfig, Secrets},
    protocol::{Codec, Frame},
    Engine,
};
use tokio::{
    net::TcpListener,
    time::{timeout, Duration},
};
use tokio_util::codec::Framed;

async fn fixture() -> (TcpListener, ClientConfig, Secrets) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let config = ClientConfig {
        server: "127.0.0.1".into(),
        port: listener.local_addr().unwrap().port(),
        ssl: false,
        reconnect_seconds: 1,
        unlimited: true,
        ..Default::default()
    };
    let secrets = Secrets {
        license: "startup-test-license".into(),
        ..Default::default()
    };
    (listener, config, secrets)
}

async fn await_state(engine: &Engine, expected: &str) {
    let mut states = engine.subscribe();
    timeout(Duration::from_secs(3), async {
        loop {
            if states.borrow_and_update().state == expected {
                break;
            }
            states.changed().await.unwrap();
        }
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn initial_startup_failure_does_not_retry_even_when_unlimited() {
    let (listener, config, secrets) = fixture().await;
    let engine = Engine::new();
    assert!(engine.connect_on_startup(config, secrets).await.unwrap());
    let (socket, _) = timeout(Duration::from_secs(3), listener.accept())
        .await
        .unwrap()
        .unwrap();
    drop(socket);
    assert!(
        timeout(Duration::from_millis(1300), listener.accept())
            .await
            .is_err(),
        "startup attempted a second connection"
    );
    assert_eq!(engine.snapshot().state, "error");
    assert!(engine.snapshot().retry_at.is_none());
    engine.disconnect().await;
}

#[tokio::test]
async fn successful_startup_retains_reconnection_after_a_later_drop() {
    let (listener, config, secrets) = fixture().await;
    let engine = Engine::new();
    engine.connect_on_startup(config, secrets).await.unwrap();
    let (socket, _) = timeout(Duration::from_secs(3), listener.accept())
        .await
        .unwrap()
        .unwrap();
    let mut wire = Framed::new(socket, Codec);
    assert_eq!(wire.next().await.unwrap().unwrap().kind, 2);
    wire.send(Frame::new(2, r#"{"code":0}"#, vec![]))
        .await
        .unwrap();
    await_state(&engine, "connected").await;
    drop(wire);
    let _second = timeout(Duration::from_secs(3), listener.accept())
        .await
        .unwrap()
        .unwrap();
    engine.disconnect().await;
}

#[tokio::test]
async fn startup_auth_rejection_stops_but_manual_connect_keeps_its_retry_policy() {
    let (listener, config, secrets) = fixture().await;
    let engine = Engine::new();
    engine
        .connect_on_startup(config.clone(), secrets.clone())
        .await
        .unwrap();
    let (socket, _) = timeout(Duration::from_secs(3), listener.accept())
        .await
        .unwrap()
        .unwrap();
    let mut wire = Framed::new(socket, Codec);
    wire.next().await.unwrap().unwrap();
    wire.send(Frame::new(2, r#"{"code":1}"#, vec![]))
        .await
        .unwrap();
    await_state(&engine, "error").await;
    assert!(timeout(Duration::from_millis(1300), listener.accept())
        .await
        .is_err());
    engine.connect(config, secrets).await.unwrap();
    let (socket, _) = timeout(Duration::from_secs(3), listener.accept())
        .await
        .unwrap()
        .unwrap();
    drop(socket);
    let _retry = timeout(Duration::from_secs(3), listener.accept())
        .await
        .unwrap()
        .unwrap();
    engine.disconnect().await;
}

#[tokio::test]
async fn startup_is_consumed_once_and_never_overrides_manual_disconnect() {
    let (listener, config, secrets) = fixture().await;
    let engine = Engine::new();
    assert!(engine
        .connect_on_startup(config.clone(), secrets.clone())
        .await
        .unwrap());
    assert!(!engine
        .connect_on_startup(config.clone(), secrets.clone())
        .await
        .unwrap());
    let _socket = timeout(Duration::from_secs(3), listener.accept())
        .await
        .unwrap()
        .unwrap();
    engine.disconnect().await;
    assert!(!engine
        .connect_on_startup(config.clone(), secrets.clone())
        .await
        .unwrap());
    let other = Engine::new();
    other.disconnect().await;
    assert!(!other.connect_on_startup(config, secrets).await.unwrap());
}

#[tokio::test]
async fn incomplete_startup_is_skipped_even_if_configuration_is_completed_later() {
    let (_listener, config, secrets) = fixture().await;
    for (invalid, missing) in [
        (ClientConfig::default(), secrets.clone()),
        (config.clone(), Secrets::default()),
        (
            config.clone(),
            Secrets {
                license: "  ".into(),
                ..Default::default()
            },
        ),
        (
            ClientConfig {
                port: 0,
                ..config.clone()
            },
            secrets.clone(),
        ),
    ] {
        let engine = Engine::new();
        assert!(!engine.connect_on_startup(invalid, missing).await.unwrap());
        assert!(!engine
            .connect_on_startup(config.clone(), secrets.clone())
            .await
            .unwrap());
        assert_eq!(engine.snapshot().state, "idle");
    }
}
