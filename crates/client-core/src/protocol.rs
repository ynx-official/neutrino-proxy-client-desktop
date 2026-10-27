use crate::config::{valid_framing, ClientConfig};
use bytes::{Buf, BufMut, BytesMut};
use std::io;
use tokio_util::codec::{Decoder, Encoder};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub kind: u8,
    pub serial: i64,
    pub info: String,
    pub data: Vec<u8>,
}
pub const MAX_FRAME: usize = 2_097_152;
impl Frame {
    pub fn new(kind: u8, info: impl Into<String>, data: Vec<u8>) -> Self {
        Self {
            kind,
            serial: chrono::Utc::now().timestamp_millis(),
            info: info.into(),
            data,
        }
    }
}
#[derive(Default)]
pub struct Codec;
/// The Java length-field decoder is configurable; its message encoder stays fixed.
pub struct ConfiguredCodec {
    max: usize,
    offset: usize,
    width: usize,
    adjustment: i32,
    strip: usize,
    valid: bool,
}
impl ConfiguredCodec {
    pub fn new(config: &ClientConfig) -> Self {
        Self {
            max: config.max_frame_length,
            offset: config.length_field_offset,
            width: config.length_field_length,
            adjustment: config.length_adjustment,
            strip: config.initial_bytes_to_strip,
            valid: valid_framing(config),
        }
    }
}
impl Default for ConfiguredCodec {
    fn default() -> Self {
        Self {
            max: MAX_FRAME,
            offset: 0,
            width: 4,
            adjustment: 0,
            strip: 0,
            valid: true,
        }
    }
}
impl Encoder<Frame> for Codec {
    type Error = io::Error;
    fn encode(&mut self, item: Frame, dst: &mut BytesMut) -> io::Result<()> {
        let len = 13usize
            .checked_add(item.info.len())
            .and_then(|n| n.checked_add(item.data.len()))
            .ok_or_else(invalid)?;
        // ProxyMessageEncoder has a signed 32-bit body length, independent of decoder limits.
        if len > i32::MAX as usize {
            return Err(invalid());
        }
        dst.reserve(len + 4);
        dst.put_u32(len as u32);
        dst.put_u8(item.kind);
        dst.put_i64(item.serial);
        dst.put_u32(item.info.len() as u32);
        dst.extend_from_slice(item.info.as_bytes());
        dst.extend_from_slice(&item.data);
        Ok(())
    }
}
impl Encoder<Frame> for ConfiguredCodec {
    type Error = io::Error;
    fn encode(&mut self, frame: Frame, dst: &mut BytesMut) -> io::Result<()> {
        Codec.encode(frame, dst)
    }
}
impl Decoder for Codec {
    type Item = Frame;
    type Error = io::Error;
    fn decode(&mut self, src: &mut BytesMut) -> io::Result<Option<Frame>> {
        ConfiguredCodec::default().decode(src)
    }
}
impl Decoder for ConfiguredCodec {
    type Item = Frame;
    type Error = io::Error;
    fn decode(&mut self, src: &mut BytesMut) -> io::Result<Option<Frame>> {
        if !self.valid {
            return Err(invalid());
        }
        let end = self.offset + self.width;
        if src.len() < end {
            return Ok(None);
        }
        let mut raw = 0u64;
        for byte in &src[self.offset..end] {
            raw = (raw << 8) | u64::from(*byte);
        }
        // Netty treats 8-byte lengths as signed and the shorter widths as unsigned.
        if raw > i64::MAX as u64 {
            return Err(invalid());
        }
        let total = i128::from(raw) + i128::from(self.adjustment) + end as i128;
        if total < end as i128 || total > self.max as i128 || self.strip as i128 > total {
            return Err(invalid());
        }
        let total = total as usize;
        if src.len() < total {
            return Ok(None);
        }
        let mut bytes = src.split_to(total);
        bytes.advance(self.strip);
        // ProxyMessageDecoder parses the normal 4-byte header AFTER Netty's stripping.
        // Malformed combinations close the channel rather than copying Java's buffer leaks.
        if bytes.len() < 17 {
            return Err(invalid());
        }
        let len = bytes.get_u32() as usize;
        if len < 13 || len > bytes.len() {
            return Err(invalid());
        }
        let kind = bytes.get_u8();
        let serial = bytes.get_i64();
        let info_len = bytes.get_u32() as usize;
        if info_len > len - 13 {
            return Err(invalid());
        }
        let info = String::from_utf8(bytes.split_to(info_len).to_vec()).map_err(|_| invalid())?;
        Ok(Some(Frame {
            kind,
            serial,
            info,
            data: bytes.split_to(len - 13 - info_len).to_vec(),
        }))
    }
}
fn invalid() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, "隧道消息格式或长度无效")
}
