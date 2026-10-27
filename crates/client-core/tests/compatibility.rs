use futures_util::{SinkExt, StreamExt};
use neutrino_client_core::{
    config::{ClientConfig, Secrets},
    protocol::{Codec, Frame},
    Engine,
};
use tokio::{
    io::AsyncWriteExt,
    net::TcpListener,
    time::{sleep, timeout, Duration, Instant},
};
use tokio_util::{codec::Framed, sync::CancellationToken};

fn secrets() -> Secrets {
    Secrets {
        license: "compatibility-test-license".into(),
        ..Default::default()
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn stalled_receiver_applies_backpressure_without_firing_data_read_timeout() {
    let target = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = target.local_addr().unwrap();
    let server = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let config = ClientConfig {
        server: "127.0.0.1".into(),
        port: server.local_addr().unwrap().port(),
        ssl: false,
        read_idle_seconds: 1,
        heartbeat_seconds: 0,
        water_mark: "1KB/4KB".into(),
        ..Default::default()
    };
    const TOTAL: usize = 64 * 1024 * 1024;
    let peer = tokio::spawn(async move {
        let mut control = Framed::new(server.accept().await.unwrap().0, Codec);
        control.next().await.unwrap().unwrap();
        control
            .send(Frame::new(2, r#"{"code":0}"#, vec![]))
            .await
            .unwrap();
        control
            .send(Frame::new(
                3,
                "slow-receiver",
                address.to_string().into_bytes(),
            ))
            .await
            .unwrap();
        let mut data = Framed::new(server.accept().await.unwrap().0, Codec);
        assert_eq!(data.next().await.unwrap().unwrap().kind, 3);
        let mut target = target.accept().await.unwrap().0;
        let producer = tokio::spawn(async move {
            let chunk = vec![0xab; 64 * 1024];
            for _ in 0..(TOTAL / chunk.len()) {
                target.write_all(&chunk).await.unwrap();
            }
            // Retain the socket in the task result while the peer drains its payload.
            // This scenario tests backpressure, not a peer sending heartbeats after EOF.
            target
        });
        let keepalive = tokio::spawn(async move {
            loop {
                if control.send(Frame::new(1, "", vec![])).await.is_err() {
                    break;
                }
                sleep(Duration::from_millis(100)).await;
            }
        });
        // No reads or data-channel keepalives for more than two read-idle intervals.
        sleep(Duration::from_millis(2200)).await;
        let backpressured = !producer.is_finished();
        let transfer = timeout(Duration::from_secs(15), async {
            let mut received = 0;
            while received < TOTAL {
                data.send(Frame::new(1, "", vec![])).await.unwrap();
                let Some(Ok(frame)) = data.next().await else {
                    break;
                };
                assert_eq!(frame.kind, 5);
                assert!(frame.data.iter().all(|byte| *byte == 0xab));
                received += frame.data.len();
            }
            received
        })
        .await;
        keepalive.abort();
        producer.abort();
        (backpressured, transfer)
    });
    let engine = Engine::new();
    engine.connect(config, secrets()).await.unwrap();
    let result = timeout(Duration::from_secs(22), peer).await;
    engine.disconnect().await;
    let (backpressured, transferred) = result.unwrap().unwrap();
    assert!(
        backpressured,
        "the blocked receiver must eventually pause its producer"
    );
    assert_eq!(
        transferred.unwrap(),
        TOTAL,
        "a non-writable data tunnel must survive its read-idle events without losing payload"
    );
}

#[test]
fn protocol_settings_survive_configuration_round_trip() {
    let input = serde_json::json!({
        "waterMark": "32KB/1MB", "allIdleSeconds": 17,
        "maxFrameLength": 4194304, "lengthFieldOffset": 2,
        "lengthFieldLength": 3, "lengthAdjustment": -1, "initialBytesToStrip": 2,
    });
    let config: ClientConfig = serde_json::from_value(input.clone()).unwrap();
    let actual = serde_json::to_value(config).unwrap();
    for (key, expected) in input.as_object().unwrap() {
        assert_eq!(
            &actual[key], expected,
            "lost Java configuration field: {key}"
        );
    }
}

#[tokio::test]
async fn data_tunnel_read_timeout_is_independent_of_healthy_control_channel() {
    let target = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let target_address = target.local_addr().unwrap();
    let server = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let config = ClientConfig {
        server: "127.0.0.1".into(),
        port: server.local_addr().unwrap().port(),
        ssl: false,
        read_idle_seconds: 1,
        heartbeat_seconds: 0,
        ..Default::default()
    };
    let peer = tokio::spawn(async move {
        let mut control = Framed::new(server.accept().await.unwrap().0, Codec);
        control.next().await.unwrap().unwrap();
        control
            .send(Frame::new(2, r#"{"code":0}"#, vec![]))
            .await
            .unwrap();
        control
            .send(Frame::new(
                3,
                "read-timeout",
                target_address.to_string().into_bytes(),
            ))
            .await
            .unwrap();
        let mut data = Framed::new(server.accept().await.unwrap().0, Codec);
        data.next().await.unwrap().unwrap();
        let _target = target.accept().await.unwrap().0;
        let keepalive = tokio::spawn(async move {
            loop {
                if control.send(Frame::new(1, "", vec![])).await.is_err() {
                    break;
                }
                sleep(Duration::from_millis(100)).await;
            }
        });
        let closed = matches!(
            timeout(Duration::from_millis(2200), data.next()).await,
            Ok(None)
        );
        keepalive.abort();
        closed
    });
    let engine = Engine::new();
    engine.connect(config, secrets()).await.unwrap();
    let closed = timeout(Duration::from_secs(5), peer)
        .await
        .unwrap()
        .unwrap();
    engine.disconnect().await;
    assert!(closed, "the data channel must enforce read-idle-time too");
}

#[tokio::test]
async fn all_idle_closes_control_even_when_read_timeout_and_heartbeat_are_disabled() {
    let server = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let config: ClientConfig = serde_json::from_value(serde_json::json!({
        "server":"127.0.0.1", "port":server.local_addr().unwrap().port(),
        "ssl":false, "readIdleSeconds":0, "heartbeatSeconds":0, "allIdleSeconds":1
    }))
    .unwrap();
    let peer = tokio::spawn(async move {
        let mut control = Framed::new(server.accept().await.unwrap().0, Codec);
        control.next().await.unwrap().unwrap();
        control
            .send(Frame::new(2, r#"{"code":0}"#, vec![]))
            .await
            .unwrap();
        matches!(
            timeout(Duration::from_millis(2200), control.next()).await,
            Ok(None)
        )
    });
    let engine = Engine::new();
    engine.connect(config, secrets()).await.unwrap();
    let closed = timeout(Duration::from_secs(5), peer)
        .await
        .unwrap()
        .unwrap();
    engine.disconnect().await;
    assert!(
        closed,
        "all-idle-time-seconds must close the idle control channel"
    );
}

#[tokio::test]
async fn tcp_heartbeat_waits_for_write_idle_and_resumes_after_traffic_stops() {
    let target = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let target_address = target.local_addr().unwrap();
    let server = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let config = ClientConfig {
        server: "127.0.0.1".into(),
        port: server.local_addr().unwrap().port(),
        ssl: false,
        read_idle_seconds: 0,
        heartbeat_seconds: 1,
        ..Default::default()
    };
    let peer = tokio::spawn(async move {
        let mut control = Framed::new(server.accept().await.unwrap().0, Codec);
        control.next().await.unwrap().unwrap();
        control
            .send(Frame::new(2, r#"{"code":0}"#, vec![]))
            .await
            .unwrap();
        control
            .send(Frame::new(
                3,
                "write-idle",
                target_address.to_string().into_bytes(),
            ))
            .await
            .unwrap();
        let mut data = Framed::new(server.accept().await.unwrap().0, Codec);
        data.next().await.unwrap().unwrap();
        let mut target = target.accept().await.unwrap().0;
        let stop = CancellationToken::new();
        let token = stop.clone();
        let producer = tokio::spawn(async move {
            loop {
                target.write_all(b"traffic").await.unwrap();
                tokio::select! { _ = token.cancelled() => break, _ = sleep(Duration::from_millis(100)) => {} }
            }
            // Keep the target open while idle so the next message is a heartbeat, not EOF.
            target
        });
        let until = Instant::now() + Duration::from_millis(2200);
        let mut heartbeats = 0;
        while let Ok(Some(Ok(frame))) = tokio::time::timeout_at(until, data.next()).await {
            if frame.kind == 1 {
                heartbeats += 1;
            }
        }
        stop.cancel();
        let _target = producer.await.unwrap();
        let idle_heartbeat = timeout(Duration::from_secs(3), async {
            loop {
                if data.next().await.unwrap().unwrap().kind == 1 {
                    break;
                }
            }
        })
        .await
        .is_ok();
        (heartbeats, idle_heartbeat)
    });
    let engine = Engine::new();
    engine.connect(config, secrets()).await.unwrap();
    let (heartbeats, idle_heartbeat) = timeout(Duration::from_secs(7), peer)
        .await
        .unwrap()
        .unwrap();
    engine.disconnect().await;
    assert_eq!(
        heartbeats, 0,
        "normal traffic must postpone write-idle heartbeats"
    );
    assert!(
        idle_heartbeat,
        "heartbeats must resume after the last completed write"
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn active_connections_are_not_limited_by_the_old_1024_binding_cap() {
    let target = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let target_address = target.local_addr().unwrap();
    let targets = tokio::spawn(async move {
        let mut sockets = Vec::new();
        loop {
            sockets.push(target.accept().await.unwrap().0);
        }
    });
    let server = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let config = ClientConfig {
        server: "127.0.0.1".into(),
        port: server.local_addr().unwrap().port(),
        ssl: false,
        read_idle_seconds: 0,
        heartbeat_seconds: 0,
        ..Default::default()
    };
    let peer = tokio::spawn(async move {
        let mut control = Framed::new(server.accept().await.unwrap().0, Codec);
        control.next().await.unwrap().unwrap();
        control
            .send(Frame::new(2, r#"{"code":0}"#, vec![]))
            .await
            .unwrap();
        let mut sockets = Vec::new();
        for i in 0..1025 {
            control
                .send(Frame::new(
                    3,
                    format!("parallel-{i}"),
                    target_address.to_string().into_bytes(),
                ))
                .await
                .unwrap();
            let Ok(Ok((socket, _))) = timeout(Duration::from_secs(3), server.accept()).await else {
                break;
            };
            let mut data = Framed::new(socket, Codec);
            assert_eq!(
                timeout(Duration::from_secs(3), data.next())
                    .await
                    .unwrap()
                    .unwrap()
                    .unwrap()
                    .kind,
                3
            );
            sockets.push(data);
        }
        sockets.len()
    });
    let engine = Engine::new();
    engine.connect(config, secrets()).await.unwrap();
    let connected = timeout(Duration::from_secs(45), peer).await;
    engine.disconnect().await;
    targets.abort();
    assert_eq!(
        connected.unwrap().unwrap(),
        1025,
        "idle pool size must not become a business concurrency limit"
    );
}
