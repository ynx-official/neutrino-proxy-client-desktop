use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", default)]
pub struct ClientConfig {
    pub server: String,
    pub port: u16,
    pub ssl: bool,
    pub client_id: String,
    pub reconnect_seconds: u64,
    pub unlimited: bool,
    pub udp_port_range: String,
    pub read_idle_seconds: u64,
    pub heartbeat_seconds: u64,
    pub all_idle_seconds: u64,
    pub water_mark: String,
    pub max_frame_length: usize,
    pub length_field_offset: usize,
    pub length_field_length: usize,
    pub length_adjustment: i32,
    pub initial_bytes_to_strip: usize,
    pub certificate_path: String,
}
impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            server: String::new(),
            port: 9002,
            ssl: true,
            client_id: uuid::Uuid::new_v4().simple().to_string(),
            reconnect_seconds: 10,
            unlimited: false,
            udp_port_range: "10000-10500".into(),
            read_idle_seconds: 120,
            heartbeat_seconds: 20,
            all_idle_seconds: 0,
            water_mark: String::new(),
            max_frame_length: 2_097_152,
            length_field_offset: 0,
            length_field_length: 4,
            length_adjustment: 0,
            initial_bytes_to_strip: 0,
            certificate_path: String::new(),
        }
    }
}
#[derive(Clone, Default)]
pub struct Secrets {
    pub license: String,
    pub store_password: String,
}
pub fn validate(config: &ClientConfig, has_license: bool) -> BTreeMap<String, String> {
    let mut errors = BTreeMap::new();
    if config.server.trim().is_empty()
        || config.server.contains("://")
        || config
            .server
            .chars()
            .any(|c| c.is_whitespace() || c == '/' || c == '\\')
    {
        errors.insert("server".into(), "请填写域名或 IP，不包含协议和路径".into());
    }
    if config.port == 0 {
        errors.insert("port".into(), "端口应为 1–65535".into());
    }
    if !has_license {
        errors.insert("license".into(), "请填写 License".into());
    }
    if config.reconnect_seconds == 0 {
        errors.insert("reconnectSeconds".into(), "重连间隔至少为 1 秒".into());
    }
    for (key, seconds) in [
        ("reconnectSeconds", config.reconnect_seconds),
        ("readIdleSeconds", config.read_idle_seconds),
        ("heartbeatSeconds", config.heartbeat_seconds),
        ("allIdleSeconds", config.all_idle_seconds),
    ] {
        if seconds > i32::MAX as u64 {
            errors.insert(key.into(), "时间不能超过 Java 客户端的整数范围".into());
        }
    }
    if !config.water_mark.trim().is_empty() && parse_water_mark(&config.water_mark).is_none() {
        errors.insert(
            "waterMark".into(),
            "水位线格式应为低/高，例如 32KB/1MB，且低水位小于高水位".into(),
        );
    }
    if !valid_framing(config) {
        errors.insert(
            "framing".into(),
            "协议长度参数组合无效，请检查最大帧长、偏移、长度字段及剥离字节数".into(),
        );
    }
    if udp_range(&config.udp_port_range).is_none() {
        errors.insert(
            "udpPortRange".into(),
            "UDP 范围应包含至少两个有效端口".into(),
        );
    }
    errors
}

pub fn valid_framing(config: &ClientConfig) -> bool {
    config.max_frame_length > 0
        && config.max_frame_length <= i32::MAX as usize
        && matches!(config.length_field_length, 1 | 2 | 3 | 4 | 8)
        && config
            .length_field_offset
            .checked_add(config.length_field_length)
            .is_some_and(|end| end <= config.max_frame_length)
        && config.initial_bytes_to_strip <= config.max_frame_length
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WaterMark {
    pub low: usize,
    pub high: usize,
}
impl Default for WaterMark {
    fn default() -> Self {
        Self {
            low: 32 * 1024,
            high: 64 * 1024,
        }
    }
}
impl ClientConfig {
    pub fn water_marks(&self) -> WaterMark {
        parse_water_mark(&self.water_mark).unwrap_or_default()
    }
}

/// Java's B/K/KB/M/MB/G/GB syntax, without its narrowing integer overflow.
pub fn parse_water_mark(value: &str) -> Option<WaterMark> {
    fn bytes(value: &str) -> Option<usize> {
        let text = value.trim().to_ascii_uppercase();
        let split = text.find(|c: char| c.is_ascii_alphabetic())?;
        let number = text[..split].trim();
        if !number.starts_with(|c: char| c.is_ascii_digit())
            || !number.chars().all(|c| c.is_ascii_digit() || c == '.')
        {
            return None;
        }
        let factor = match text[split..].trim() {
            "B" => 1.0,
            "K" | "KB" => 1024.0,
            "M" | "MB" => 1048576.0,
            "G" | "GB" => 1073741824.0,
            _ => return None,
        };
        let size = number.parse::<f64>().ok()? * factor;
        (size.is_finite() && size >= 0.0 && size <= i32::MAX as f64).then_some(size as usize)
    }
    let (low, high) = value.split_once('/')?;
    let mark = WaterMark {
        low: bytes(low)?,
        high: bytes(high)?,
    };
    (mark.low < mark.high).then_some(mark)
}
pub fn udp_range(value: &str) -> Option<(u16, u16)> {
    let (a, b) = value.split_once('-')?;
    let (a, b) = (a.parse().ok()?, b.parse().ok()?);
    if a > 0 && b > a {
        Some((a, b))
    } else {
        None
    }
}
pub fn license_hint(value: &str) -> String {
    if value.is_empty() {
        return "尚未设置".into();
    }
    if value.chars().count() <= 4 {
        return "••••".into();
    }
    let tail: String = value
        .chars()
        .rev()
        .take(4)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();
    format!("•••• •••• •••• {tail}")
}
