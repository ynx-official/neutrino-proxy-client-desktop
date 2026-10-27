use neutrino_client_core::config::{
    parse_water_mark, udp_range, valid_framing, validate, ClientConfig, Secrets,
};
use serde_json::Value;
use std::path::Path;

pub struct ParsedImport {
    pub config: ClientConfig,
    pub secrets: Secrets,
    pub notes: Vec<String>,
    pub can_apply: bool,
    pub imported_fields: Vec<&'static str>,
}

/// Import valid, supported fields over the saved values. Completeness is checked at connect time.
pub fn parse_import(
    bytes: &[u8],
    path: &Path,
    current: &ClientConfig,
    current_secrets: &Secrets,
) -> Result<ParsedImport, String> {
    let yaml = serde_yaml::from_slice(bytes).map_err(|_| "YAML 配置格式无效".to_owned())?;
    let mut reader = ImportFields {
        yaml,
        imported: vec![],
        skipped: vec![],
    };
    let mut config = current.clone();
    let mut secrets = current_secrets.clone();
    let mut migrated_identity = false;
    reader.set(
        "neutrino.proxy.tunnel.server-ip",
        &mut config.server,
        |value| {
            let candidate = ClientConfig {
                server: value.clone(),
                ..current.clone()
            };
            (!validate(&candidate, true).contains_key("server")).then_some(value)
        },
    );
    reader.set(
        "neutrino.proxy.tunnel.server-port",
        &mut config.port,
        |value| value.parse::<u16>().ok().filter(|port| *port > 0),
    );
    reader.set(
        "neutrino.proxy.tunnel.ssl-enable",
        &mut config.ssl,
        |value| value.parse().ok(),
    );
    reader.set(
        "neutrino.proxy.tunnel.license-key",
        &mut secrets.license,
        non_blank,
    );
    reader.set(
        "neutrino.proxy.tunnel.key-store-password",
        &mut secrets.store_password,
        non_blank,
    );
    reader.set(
        "neutrino.proxy.tunnel.client-id",
        &mut config.client_id,
        non_blank,
    );
    if !reader.imported.contains(&"neutrino.proxy.tunnel.client-id") {
        // Selection of the YAML authorizes only its sibling identity, never cwd/home discovery.
        let identity = path
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join(".NEUTRINO_PROXY_CLIENT_ID");
        if let Ok(metadata) = std::fs::symlink_metadata(&identity) {
            if metadata.is_file() && !metadata.file_type().is_symlink() && metadata.len() <= 4096 {
                if let Some(id) = std::fs::read_to_string(identity).ok().and_then(non_blank) {
                    config.client_id = id;
                    migrated_identity = true;
                    reader.imported.push("neutrino.proxy.tunnel.client-id");
                    reader
                        .skipped
                        .retain(|key| *key != "neutrino.proxy.tunnel.client-id");
                }
            }
        }
    }
    reader.set(
        "neutrino.proxy.tunnel.jks-path",
        &mut config.certificate_path,
        |value| {
            let value = non_blank(value)?;
            if value.starts_with("classpath:") {
                return Some(String::new());
            }
            let certificate = Path::new(&value);
            let certificate = if certificate.is_absolute() {
                certificate.to_path_buf()
            } else {
                path.parent()
                    .unwrap_or_else(|| Path::new("."))
                    .join(certificate)
            };
            certificate
                .is_file()
                .then(|| certificate.to_string_lossy().into_owned())
        },
    );
    reader.set(
        "neutrino.proxy.tunnel.reconnection.interval-seconds",
        &mut config.reconnect_seconds,
        |value| seconds(value).filter(|seconds| *seconds > 0),
    );
    reader.set(
        "neutrino.proxy.tunnel.reconnection.unlimited",
        &mut config.unlimited,
        |value| value.parse().ok(),
    );
    reader.set(
        "neutrino.proxy.client.udp.puppet-port-range",
        &mut config.udp_port_range,
        |value| udp_range(&value).map(|_| value),
    );
    reader.set(
        "neutrino.proxy.protocol.read-idle-time",
        &mut config.read_idle_seconds,
        seconds,
    );
    reader.set(
        "neutrino.proxy.protocol.write-idle-time",
        &mut config.heartbeat_seconds,
        seconds,
    );
    reader.set(
        "neutrino.proxy.protocol.all-idle-time-seconds",
        &mut config.all_idle_seconds,
        seconds,
    );
    reader.set(
        "neutrino.proxy.protocol.water-mark",
        &mut config.water_mark,
        |value| (value.trim().is_empty() || parse_water_mark(&value).is_some()).then_some(value),
    );
    reader.set(
        "neutrino.proxy.protocol.max-frame-length",
        &mut config.max_frame_length,
        |value| java_size(value).filter(|n| *n > 0),
    );
    reader.set(
        "neutrino.proxy.protocol.length-field-offset",
        &mut config.length_field_offset,
        java_size,
    );
    reader.set(
        "neutrino.proxy.protocol.length-field-length",
        &mut config.length_field_length,
        |value| java_size(value).filter(|n| matches!(n, 1 | 2 | 3 | 4 | 8)),
    );
    reader.set(
        "neutrino.proxy.protocol.length-adjustment",
        &mut config.length_adjustment,
        |value| value.parse().ok(),
    );
    reader.set(
        "neutrino.proxy.protocol.initial-bytes-to-strip",
        &mut config.initial_bytes_to_strip,
        java_size,
    );
    // Framing is a tuple: a partial update must not save a combination that cannot initialize.
    if !valid_framing(&config) {
        for key in [
            "max-frame-length",
            "length-field-offset",
            "length-field-length",
            "length-adjustment",
            "initial-bytes-to-strip",
        ] {
            if let Some(index) = reader
                .imported
                .iter()
                .position(|field| *field == format!("neutrino.proxy.protocol.{key}"))
            {
                let field = reader.imported.remove(index);
                reader.skipped.push(field);
            }
        }
        config.max_frame_length = current.max_frame_length;
        config.length_field_offset = current.length_field_offset;
        config.length_field_length = current.length_field_length;
        config.length_adjustment = current.length_adjustment;
        config.initial_bytes_to_strip = current.initial_bytes_to_strip;
    }
    let can_apply = !reader.imported.is_empty();
    let mut notes = vec![if can_apply {
        format!("可导入 {} 项配置，缺失项保留当前值", reader.imported.len())
    } else {
        "未发现可导入的配置".into()
    }];
    if migrated_identity {
        notes.push(
            "客户端 ID 来自所选 YAML 同目录的 .NEUTRINO_PROXY_CLIENT_ID，原文件保持不变".into(),
        );
    }
    if !reader.skipped.is_empty() {
        // Report only known field names, never imported values or environment contents.
        notes.push(format!(
            "已跳过不支持或无效的配置：{}",
            reader
                .skipped
                .iter()
                .map(|key| key.strip_prefix("neutrino.proxy.").unwrap_or(key))
                .collect::<Vec<_>>()
                .join("、")
        ));
    }
    Ok(ParsedImport {
        config,
        secrets,
        notes,
        can_apply,
        imported_fields: reader.imported,
    })
}

struct ImportFields {
    yaml: Value,
    imported: Vec<&'static str>,
    skipped: Vec<&'static str>,
}
impl ImportFields {
    fn set<T>(
        &mut self,
        key: &'static str,
        target: &mut T,
        parse: impl FnOnce(String) -> Option<T>,
    ) {
        // Older official clients store connection fields directly under proxy.client.
        // Prefer a declared tunnel field; fall back per field only when it is absent.
        let value = lookup(&self.yaml, key).or_else(|| {
            key.strip_prefix("neutrino.proxy.tunnel.")
                .and_then(|suffix| lookup(&self.yaml, &format!("neutrino.proxy.client.{suffix}")))
        });
        let Some(value) = value else {
            return;
        };
        if let Some(parsed) = resolve(value).and_then(parse) {
            *target = parsed;
            self.imported.push(key);
        } else {
            self.skipped.push(key);
        }
    }
}

// Solon configuration may mix nested YAML and dotted keys at any level.
fn lookup<'a>(value: &'a Value, key: &str) -> Option<&'a Value> {
    if let Some(value) = value.get(key) {
        return Some(value);
    }
    for (split, _) in key.match_indices('.') {
        if let Some(value) = value
            .get(&key[..split])
            .and_then(|value| lookup(value, &key[split + 1..]))
        {
            return Some(value);
        }
    }
    None
}
fn non_blank(value: String) -> Option<String> {
    (!value.trim().is_empty()).then_some(value)
}
fn seconds(value: String) -> Option<u64> {
    // Netty normalizes nonpositive idle durations to disabled timers.
    value.parse::<i32>().ok().map(|n| n.max(0) as u64)
}
fn java_size(value: String) -> Option<usize> {
    value
        .parse::<usize>()
        .ok()
        .filter(|n| *n <= i32::MAX as usize)
}
fn resolve(value: &Value) -> Option<String> {
    let raw = if let Some(s) = value.as_str() {
        s.to_owned()
    } else if value.is_boolean() || value.is_number() {
        value.to_string()
    } else {
        return None;
    };
    if raw.starts_with("${") && raw.ends_with('}') {
        let inside = &raw[2..raw.len() - 1];
        let (name, fallback) = inside.split_once(':').unwrap_or((inside, ""));
        std::env::var(name).ok().or_else(|| Some(fallback.into()))
    } else {
        Some(raw)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn java_nonpositive_idle_values_disable_the_corresponding_timers() {
        let parsed = parse("neutrino.proxy.protocol:\n  read-idle-time: -1\n  write-idle-time: 0\n  all-idle-time-seconds: -2147483648\n");
        assert_eq!(
            (
                parsed.config.read_idle_seconds,
                parsed.config.heartbeat_seconds,
                parsed.config.all_idle_seconds
            ),
            (0, 0, 0)
        );
        assert_eq!(parsed.imported_fields.len(), 3);
    }

    #[test]
    fn invalid_protocol_tuple_and_overflow_keep_saved_values() {
        let parsed = parse("neutrino.proxy.protocol:\n  max-frame-length: 4\n  length-field-offset: 8\n  water-mark: 1GB/2GB\n  write-idle-time: 2147483648\nneutrino.proxy.tunnel.server-ip: new.example.test\n");
        let (saved, _) = current();
        assert_eq!(parsed.config.max_frame_length, saved.max_frame_length);
        assert_eq!(parsed.config.length_field_offset, saved.length_field_offset);
        assert_eq!(parsed.config.water_mark, saved.water_mark);
        assert_eq!(parsed.config.heartbeat_seconds, saved.heartbeat_seconds);
        assert_eq!(parsed.config.server, "new.example.test");
        assert_eq!(parsed.imported_fields, ["neutrino.proxy.tunnel.server-ip"]);
        assert!(parsed.notes.join(" ").contains("已跳过"));
    }

    #[test]
    fn missing_blank_oversized_and_non_utf8_identity_keep_current_id() {
        let directory =
            std::env::temp_dir().join(format!("neutrino-identity-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir(&directory).unwrap();
        let identity = directory.join(".NEUTRINO_PROXY_CLIENT_ID");
        let (config, secrets) = current();
        let load = || {
            parse_import(
                b"neutrino.proxy.protocol.read-idle-time: 30",
                &directory.join("app.yml"),
                &config,
                &secrets,
            )
            .unwrap()
        };
        assert_eq!(load().config.client_id, config.client_id);
        for bytes in [b" \r\n".to_vec(), vec![b'a'; 4097], vec![255]] {
            std::fs::write(&identity, bytes).unwrap();
            let imported = load();
            assert_eq!(imported.config.client_id, config.client_id);
            assert!(!imported
                .imported_fields
                .contains(&"neutrino.proxy.tunnel.client-id"));
        }
        std::fs::remove_file(identity).unwrap();
        std::fs::remove_dir(directory).unwrap();
    }

    #[test]
    fn latest_java_protocol_fields_are_imported_instead_of_skipped() {
        let parsed = parse("neutrino.proxy.protocol:\n  water-mark: 32KB/1MB\n  all-idle-time-seconds: 60\n  max-frame-length: 4194304\n  length-field-offset: 2\n  length-field-length: 4\n  length-adjustment: -2\n  initial-bytes-to-strip: 2\n");
        assert!(parsed.can_apply);
        let config = serde_json::to_value(&parsed.config).unwrap();
        assert_eq!(config["waterMark"], "32KB/1MB");
        assert_eq!(config["allIdleSeconds"], 60);
        assert_eq!(config["maxFrameLength"], 4194304);
        assert_eq!(config["lengthFieldOffset"], 2);
        assert_eq!(config["lengthFieldLength"], 4);
        assert_eq!(config["lengthAdjustment"], -2);
        assert_eq!(config["initialBytesToStrip"], 2);
        assert_eq!(parsed.imported_fields.len(), 7);
        assert!(!parsed.notes.join(" ").contains("已跳过"));
    }

    #[test]
    fn selected_yaml_sibling_identity_is_migrated_with_explicit_id_taking_precedence() {
        let directory =
            std::env::temp_dir().join(format!("neutrino-identity-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir(&directory).unwrap();
        let identity_path = directory.join(".NEUTRINO_PROXY_CLIENT_ID");
        std::fs::write(&identity_path, "old-stable-client").unwrap();
        let (config, secrets) = current();
        let imported = parse_import(
            b"neutrino.proxy.tunnel.server-ip: imported.example.com",
            &directory.join("app.yml"),
            &config,
            &secrets,
        )
        .unwrap();
        let explicit = parse_import(
            b"neutrino.proxy.tunnel.client-id: explicit-client",
            &directory.join("app.yml"),
            &config,
            &secrets,
        )
        .unwrap();
        let original = std::fs::read_to_string(&identity_path).unwrap();
        std::fs::remove_file(identity_path).unwrap();
        std::fs::remove_dir(directory).unwrap();
        assert_eq!(imported.config.client_id, "old-stable-client");
        assert!(imported
            .imported_fields
            .contains(&"neutrino.proxy.tunnel.client-id"));
        assert_eq!(explicit.config.client_id, "explicit-client");
        assert_eq!(
            original, "old-stable-client",
            "migration must not rewrite the legacy identity"
        );
    }

    fn current() -> (ClientConfig, Secrets) {
        (
            ClientConfig {
                server: "saved.example.com".into(),
                port: 9443,
                ssl: false,
                client_id: "saved-client".into(),
                reconnect_seconds: 17,
                udp_port_range: "21000-21010".into(),
                ..ClientConfig::default()
            },
            Secrets {
                license: "test-license".into(),
                store_password: "test-password".into(),
            },
        )
    }
    fn parse(yaml: &str) -> ParsedImport {
        let (config, secrets) = current();
        parse_import(yaml.as_bytes(), Path::new("app.yml"), &config, &secrets)
            .expect("missing sections must not reject an otherwise useful import")
    }

    #[test]
    fn missing_tunnel_still_imports_protocol_and_udp_without_erasing_connection() {
        let parsed = parse("neutrino:\n  proxy:\n    protocol:\n      read-idle-time: 75\n    client:\n      udp:\n        puppet-port-range: 22000-22020\n");
        assert!(parsed.can_apply);
        assert_eq!(parsed.config.server, "saved.example.com");
        assert_eq!(parsed.config.port, 9443);
        assert!(!parsed.config.ssl);
        assert_eq!(parsed.config.client_id, "saved-client");
        assert_eq!(parsed.secrets.license, "test-license");
        assert_eq!(parsed.secrets.store_password, "test-password");
        assert_eq!(parsed.config.read_idle_seconds, 75);
        assert_eq!(parsed.config.udp_port_range, "22000-22020");
        assert_eq!(
            parsed.imported_fields,
            vec![
                "neutrino.proxy.client.udp.puppet-port-range",
                "neutrino.proxy.protocol.read-idle-time",
            ]
        );
    }

    #[test]
    fn official_legacy_client_section_imports_connection_fields() {
        let (mut config, secrets) = current();
        config.ssl = true;
        config.certificate_path = "saved.pem".into();
        let parsed = parse_import(b"neutrino:\n  proxy:\n    client:\n      key-store-password: official-password\n      jks-path: classpath:/test.jks\n      server-ip: official.example.com\n      server-port: 9000\n      ssl-enable: false\n      license-key: official-license\n", Path::new("app.yml"), &config, &secrets).unwrap();
        assert!(
            parsed.can_apply,
            "the official client section must be recognized"
        );
        assert_eq!(parsed.config.server, "official.example.com");
        assert_eq!(parsed.config.port, 9000);
        assert!(!parsed.config.ssl);
        assert!(parsed.config.certificate_path.is_empty());
        assert_eq!(parsed.secrets.license, "official-license");
        assert_eq!(parsed.secrets.store_password, "official-password");
        assert_eq!(parsed.config.client_id, "saved-client");
        assert_eq!(parsed.imported_fields.len(), 6);
        assert!(parsed
            .imported_fields
            .contains(&"neutrino.proxy.tunnel.server-ip"));
        assert!(parsed
            .imported_fields
            .contains(&"neutrino.proxy.tunnel.license-key"));
    }

    #[test]
    fn tunnel_fields_take_precedence_and_missing_fields_fall_back_to_legacy_client() {
        let parsed = parse("neutrino.proxy.client:\n  server-ip: legacy.example.com\n  server-port: 9000\n  license-key: official-license\n  ssl-enable: true\nneutrino.proxy.tunnel:\n  server-ip: current.example.com\n  ssl-enable: false\n");
        assert!(parsed.can_apply);
        assert_eq!(parsed.config.server, "current.example.com");
        assert_eq!(parsed.config.port, 9000);
        assert!(!parsed.config.ssl);
        assert_eq!(parsed.secrets.license, "official-license");
    }

    #[test]
    fn partial_tunnel_updates_only_valid_supported_values() {
        let parsed = parse("neutrino:\n  proxy:\n    tunnel:\n      server-ip: imported.example.com\n      server-port: nope\n      license-key: ''\n      reconnection:\n        interval-seconds: 0\n        unlimited: true\n    protocol:\n      write-idle-time: 33\n      max-frame-length: 1000000\n");
        assert!(parsed.can_apply);
        assert_eq!(parsed.config.server, "imported.example.com");
        assert_eq!(parsed.config.port, 9443);
        assert_eq!(parsed.config.reconnect_seconds, 17);
        assert!(parsed.config.unlimited);
        assert_eq!(parsed.config.heartbeat_seconds, 33);
        assert_eq!(parsed.secrets.license, "test-license");
        assert_eq!(parsed.config.max_frame_length, 1000000);
        assert!(parsed
            .imported_fields
            .contains(&"neutrino.proxy.protocol.max-frame-length"));
        let notes = parsed.notes.join(" ");
        assert!(!notes.contains("test-license") && !notes.contains("test-password"));
    }

    #[test]
    fn first_run_accepts_useful_partial_fields_before_connection_is_complete() {
        let config = ClientConfig::default();
        let parsed = parse_import(
            b"neutrino:\n  proxy:\n    tunnel:\n      server-ip: edge.example.com\n",
            Path::new("app.yml"),
            &config,
            &Secrets::default(),
        )
        .unwrap();
        assert!(parsed.can_apply);
        assert_eq!(parsed.config.server, "edge.example.com");
        assert!(parsed.secrets.license.is_empty());
        assert!(validate(&parsed.config, false).contains_key("license"));
    }

    #[test]
    fn unrelated_or_empty_files_are_a_non_applicable_preview_not_an_error() {
        for yaml in [
            "",
            "solon:\n  logging: false\n",
            "neutrino:\n  proxy:\n    tunnel: null\n",
        ] {
            let parsed = parse(yaml);
            assert!(!parsed.can_apply);
            assert!(parsed.imported_fields.is_empty());
            assert_eq!(parsed.config.server, "saved.example.com");
            assert_eq!(parsed.secrets.license, "test-license");
        }
    }

    #[test]
    fn mixed_dotted_and_nested_keys_import_the_same_fields() {
        let parsed = parse("neutrino.proxy.tunnel.server-ip: edge.example.com\nneutrino:\n  proxy.tunnel:\n    server-port: 9777\n    ssl-enable: true\n  proxy.protocol.read-idle-time: 80\n");
        assert!(parsed.can_apply);
        assert_eq!(parsed.config.server, "edge.example.com");
        assert_eq!(parsed.config.port, 9777);
        assert!(parsed.config.ssl);
        assert_eq!(parsed.config.read_idle_seconds, 80);
        assert_eq!(parsed.secrets.license, "test-license");
    }

    #[test]
    fn full_legacy_fields_and_environment_defaults_still_import() {
        let env_name = format!("NEUTRINO_IMPORT_TEST_{}", uuid::Uuid::new_v4().simple());
        let yaml = format!("neutrino:\n  proxy:\n    tunnel:\n      server-ip: edge.example.com\n      server-port: '${{{env_name}:9777}}'\n      ssl-enable: true\n      client-id: imported-client\n      license-key: ' imported-license '\n      key-store-password: imported-password\n      jks-path: classpath:/default.jks\n      reconnection:\n        interval-seconds: 15\n        unlimited: true\n    client:\n      udp:\n        puppet-port-range: 23000-23020\n    protocol:\n      read-idle-time: 90\n      write-idle-time: 30\n      max-frame-length: 2097152\n      length-field-length: 4\n");
        let parsed = parse(&yaml);
        assert!(parsed.can_apply);
        assert_eq!(parsed.config.server, "edge.example.com");
        assert_eq!(parsed.config.port, 9777);
        assert!(parsed.config.ssl);
        assert_eq!(parsed.config.client_id, "imported-client");
        assert_eq!(parsed.config.reconnect_seconds, 15);
        assert!(parsed.config.unlimited);
        assert_eq!(parsed.config.udp_port_range, "23000-23020");
        assert_eq!(parsed.config.read_idle_seconds, 90);
        assert_eq!(parsed.config.heartbeat_seconds, 30);
        assert!(parsed.config.certificate_path.is_empty());
        assert_eq!(parsed.secrets.license, " imported-license ");
        assert_eq!(parsed.secrets.store_password, "imported-password");
        assert!(!parsed.notes.join(" ").contains("已跳过"));
    }

    #[test]
    fn unresolved_variables_and_wrong_types_do_not_replace_saved_values() {
        let env_name = format!("NEUTRINO_IMPORT_TEST_{}", uuid::Uuid::new_v4().simple());
        let parsed = parse(&format!("neutrino.proxy.tunnel:\n  server-ip: '${{{env_name}}}'\n  license-key: '${{{env_name}}}'\n  ssl-enable: []\n  server-port: 70000\n  reconnection:\n    interval-seconds: 0\nneutrino.proxy.client.udp.puppet-port-range: bad\nneutrino.proxy.protocol.write-idle-time: 35\n"));
        assert!(parsed.can_apply);
        assert_eq!(parsed.config.server, "saved.example.com");
        assert_eq!(parsed.config.port, 9443);
        assert!(!parsed.config.ssl);
        assert_eq!(parsed.config.reconnect_seconds, 17);
        assert_eq!(parsed.config.udp_port_range, "21000-21010");
        assert_eq!(parsed.config.heartbeat_seconds, 35);
        assert_eq!(parsed.secrets.license, "test-license");
    }

    #[test]
    fn relative_certificates_resolve_and_missing_files_keep_the_saved_certificate() {
        struct TestDirectory(std::path::PathBuf);
        impl Drop for TestDirectory {
            fn drop(&mut self) {
                let _ = std::fs::remove_dir_all(&self.0);
            }
        }
        let directory = TestDirectory(
            std::env::temp_dir().join(format!("neutrino-import-{}", uuid::Uuid::new_v4())),
        );
        std::fs::create_dir(&directory.0).unwrap();
        let certificate = directory.0.join("test.pem");
        std::fs::write(&certificate, b"import path fixture").unwrap();
        let source = directory.0.join("app.yml");
        let (mut config, secrets) = current();
        config.certificate_path = "saved.pem".into();
        let parsed = parse_import(
            b"neutrino.proxy.tunnel.jks-path: test.pem",
            &source,
            &config,
            &secrets,
        )
        .unwrap();
        assert!(parsed.can_apply);
        assert_eq!(
            parsed.config.certificate_path,
            certificate.to_string_lossy()
        );
        let parsed = parse_import(
            b"neutrino.proxy.tunnel.jks-path: missing.pem",
            &source,
            &config,
            &secrets,
        )
        .unwrap();
        assert!(!parsed.can_apply);
        assert_eq!(parsed.config.certificate_path, "saved.pem");
        let parsed = parse_import(
            b"neutrino.proxy.tunnel.jks-path: classpath:/default.jks",
            &source,
            &config,
            &secrets,
        )
        .unwrap();
        assert!(parsed.can_apply);
        assert!(parsed.config.certificate_path.is_empty());
    }

    #[test]
    fn malformed_yaml_keeps_a_generic_error_without_exposing_values() {
        let (config, secrets) = current();
        let error = parse_import(
            b"neutrino: [test-license",
            Path::new("app.yml"),
            &config,
            &secrets,
        )
        .err()
        .unwrap();
        assert_eq!(error, "YAML 配置格式无效");
    }
}
