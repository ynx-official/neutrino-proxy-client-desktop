use bytes::BytesMut;
use neutrino_client_core::{
    config::{validate, ClientConfig},
    protocol::{Codec, ConfiguredCodec, Frame},
};
use tokio_util::codec::{Decoder, Encoder};

#[test]
fn auth_matches_java_wire_format() {
    let mut bytes = BytesMut::new();
    Codec
        .encode(
            Frame {
                kind: 2,
                serial: 0,
                info: "k,id".into(),
                data: vec![],
            },
            &mut bytes,
        )
        .unwrap();
    assert_eq!(
        &bytes[..],
        &[0, 0, 0, 17, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, b'k', b',', b'i', b'd']
    );
}
#[test]
fn handles_fragmented_unicode_and_binary_data() {
    let expected = Frame {
        kind: 5,
        serial: 42,
        info: "访客".into(),
        data: vec![0, 255, 3],
    };
    let mut bytes = BytesMut::new();
    Codec.encode(expected, &mut bytes).unwrap();
    let mut fragment = bytes.split_to(8);
    assert!(Codec.decode(&mut fragment).unwrap().is_none());
    fragment.extend_from_slice(&bytes);
    let decoded = Codec
        .decode(&mut fragment)
        .unwrap()
        .expect("complete frame");
    assert_eq!(decoded.info, "访客");
    assert_eq!(decoded.data, vec![0, 255, 3]);
}
#[test]
fn rejects_oversized_frames_before_allocating() {
    let mut bytes = BytesMut::from(&[127, 255, 255, 255][..]);
    assert!(Codec.decode(&mut bytes).is_err());
}
#[test]
fn rejects_invalid_info_length() {
    let mut bytes =
        BytesMut::from(&[0, 0, 0, 13, 2, 0, 0, 0, 0, 0, 0, 0, 0, 127, 255, 255, 255][..]);
    assert!(Codec.decode(&mut bytes).is_err());
}
#[test]
fn validation_reports_all_actionable_fields() {
    let config = ClientConfig {
        server: "https://bad/path".into(),
        port: 0,
        reconnect_seconds: 0,
        udp_port_range: "12000-10000".into(),
        ..Default::default()
    };
    let errors = validate(&config, false);
    for field in [
        "server",
        "port",
        "license",
        "reconnectSeconds",
        "udpPortRange",
    ] {
        assert!(errors.contains_key(field), "missing {field}");
    }
}

#[test]
fn built_in_jks_loads_without_java_runtime() {
    let roots = neutrino_client_core::transport::trust_roots(
        &ClientConfig::default(),
        &neutrino_client_core::config::Secrets::default(),
    )
    .unwrap();
    assert!(!roots.is_empty());
}

#[test]
fn a_short_license_is_never_fully_exposed_by_its_hint() {
    assert_eq!(neutrino_client_core::config::license_hint("abc"), "••••");
}

#[test]
fn configured_length_fields_preserve_fragmented_and_coalesced_messages() {
    let frame = Frame {
        kind: 5,
        serial: 72,
        info: "访客".into(),
        data: vec![0, 255, 31],
    };
    let mut plain = BytesMut::new();
    Codec.encode(frame.clone(), &mut plain).unwrap();
    // Netty also accepts the last 1/2/3 bytes of the ordinary 4-byte length field.
    for width in [1, 2, 3, 4, 8] {
        let (offset, strip, packet) = if width == 8 {
            let mut envelope = BytesMut::from(&(plain.len() as u64).to_be_bytes()[..]);
            envelope.extend_from_slice(&plain);
            (0, 8, envelope)
        } else {
            (4 - width, 0, plain.clone())
        };
        let config = ClientConfig {
            length_field_offset: offset,
            length_field_length: width,
            initial_bytes_to_strip: strip,
            max_frame_length: packet.len(),
            ..Default::default()
        };
        let mut codec = ConfiguredCodec::new(&config);
        let mut received = packet.clone();
        let mut first = received.split_to(packet.len() - 1);
        assert!(codec.decode(&mut first).unwrap().is_none());
        first.extend_from_slice(&received);
        first.extend_from_slice(&packet);
        assert_eq!(codec.decode(&mut first).unwrap(), Some(frame.clone()));
        assert_eq!(codec.decode(&mut first).unwrap(), Some(frame.clone()));
        assert!(first.is_empty());
        let mut too_small = ConfiguredCodec::new(&ClientConfig {
            max_frame_length: packet.len() - 1,
            ..config
        });
        assert!(too_small.decode(&mut packet.clone()).is_err());
    }
}

#[test]
fn length_adjustment_and_stripping_apply_before_the_fixed_java_message_header() {
    let expected = Frame {
        kind: 5,
        serial: -4,
        info: "id".into(),
        data: vec![2, 3, 4],
    };
    let mut plain = BytesMut::new();
    Codec.encode(expected.clone(), &mut plain).unwrap();
    for adjustment in [-3, 3] {
        let length = (plain.len() as i32 - adjustment) as u16;
        let mut envelope = BytesMut::from(&[0xaa, (length >> 8) as u8, length as u8][..]);
        envelope.extend_from_slice(&plain);
        let mut codec = ConfiguredCodec::new(&ClientConfig {
            length_field_offset: 1,
            length_field_length: 2,
            length_adjustment: adjustment,
            initial_bytes_to_strip: 3,
            ..Default::default()
        });
        assert_eq!(codec.decode(&mut envelope).unwrap(), Some(expected.clone()));
        // These are decoder settings: encoding must remain wire-compatible with Java.
        let mut encoded = BytesMut::new();
        codec.encode(expected.clone(), &mut encoded).unwrap();
        assert_eq!(encoded, plain);
    }
}

#[test]
fn malformed_custom_lengths_fail_without_allocating_unbounded_buffers() {
    for (config, raw) in [
        (
            ClientConfig {
                length_field_length: 8,
                ..Default::default()
            },
            vec![255; 8],
        ),
        (
            ClientConfig {
                length_adjustment: -10,
                ..Default::default()
            },
            vec![0, 0, 0, 1],
        ),
        (
            ClientConfig {
                initial_bytes_to_strip: 40,
                ..Default::default()
            },
            vec![0, 0, 0, 13],
        ),
        (
            ClientConfig {
                length_field_offset: usize::MAX,
                ..Default::default()
            },
            vec![],
        ),
    ] {
        assert!(ConfiguredCodec::new(&config)
            .decode(&mut BytesMut::from(raw.as_slice()))
            .is_err());
    }
}

#[test]
fn old_saved_configs_receive_java_defaults() {
    let cfg: ClientConfig =
        serde_json::from_str(r#"{"clientId":"existing-id","server":"example.test"}"#).unwrap();
    assert_eq!(cfg.client_id, "existing-id");
    assert_eq!(cfg.all_idle_seconds, 0);
    assert_eq!(cfg.water_marks().low, 32768);
    assert_eq!(cfg.water_marks().high, 65536);
    assert_eq!(
        (
            cfg.max_frame_length,
            cfg.length_field_offset,
            cfg.length_field_length,
            cfg.length_adjustment,
            cfg.initial_bytes_to_strip
        ),
        (2097152, 0, 4, 0, 0)
    );
}

#[test]
fn decodes_vectors_generated_and_verified_by_the_actual_java_codec() {
    let vectors: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/java-protocol-vectors.json")).unwrap();
    for row in vectors.as_array().unwrap() {
        let cfg = ClientConfig {
            max_frame_length: row["max"].as_u64().unwrap() as usize,
            length_field_offset: row["offset"].as_u64().unwrap() as usize,
            length_field_length: row["width"].as_u64().unwrap() as usize,
            length_adjustment: row["adjustment"].as_i64().unwrap() as i32,
            initial_bytes_to_strip: row["strip"].as_u64().unwrap() as usize,
            ..Default::default()
        };
        let hex = row["hex"].as_str().unwrap();
        let bytes: Vec<u8> = (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect();
        let frame = ConfiguredCodec::new(&cfg)
            .decode(&mut BytesMut::from(bytes.as_slice()))
            .unwrap()
            .unwrap();
        assert_eq!(
            frame,
            Frame {
                kind: 5,
                serial: 72,
                info: "访客".into(),
                data: vec![0, 255, 31]
            }
        );
    }
}
