//! Netty-compatible idle events and byte-counted write-buffer hysteresis.
use crate::{
    config::{ClientConfig, WaterMark},
    protocol::{ConfiguredCodec, Frame},
    transport::Stream,
};
use bytes::BytesMut;
use std::{collections::VecDeque, io};
use tokio::{
    io::{AsyncWrite, AsyncWriteExt, ReadHalf, WriteHalf},
    time::{sleep_until, Duration, Instant},
};
use tokio_util::codec::{Encoder, FramedRead};

pub(crate) struct Outbound<W> {
    writer: W,
    queue: VecDeque<(Vec<u8>, usize)>,
    bytes: usize,
    writable: bool,
    mark: WaterMark,
}
impl<W: AsyncWrite + Unpin> Outbound<W> {
    pub fn new(writer: W, mark: WaterMark) -> Self {
        Self {
            writer,
            queue: VecDeque::new(),
            bytes: 0,
            writable: true,
            mark,
        }
    }
    pub fn writable(&self) -> bool {
        self.writable
    }
    pub fn pending(&self) -> bool {
        !self.queue.is_empty()
    }
    pub fn push(&mut self, bytes: Vec<u8>) {
        self.bytes += bytes.len();
        self.queue.push_back((bytes, 0));
        if self.bytes > self.mark.high {
            self.writable = false;
        }
    }
    /// Cancellation safe: offsets stay in the queue across select! polling.
    /// Count a whole message until flush completes, just as Netty's outbound buffer does.
    pub async fn flush_one(&mut self) -> io::Result<()> {
        let Some((bytes, offset)) = self.queue.front_mut() else {
            return Ok(());
        };
        while *offset < bytes.len() {
            let n = self.writer.write(&bytes[*offset..]).await?;
            if n == 0 {
                return Err(io::ErrorKind::WriteZero.into());
            }
            *offset += n;
        }
        self.writer.flush().await?;
        self.bytes -= self.queue.pop_front().unwrap().0.len();
        if self.bytes == 0 || self.bytes < self.mark.low {
            self.writable = true;
        }
        Ok(())
    }
    pub async fn finish(&mut self) -> io::Result<()> {
        while self.pending() {
            self.flush_one().await?;
        }
        self.writer.shutdown().await
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum IdleEvent {
    Read,
    Write,
    All,
}
pub(crate) struct Idle {
    read: Option<Duration>,
    write: Option<Duration>,
    all: Option<Duration>,
    next_read: Option<Instant>,
    next_write: Option<Instant>,
    next_all: Option<Instant>,
}
impl Idle {
    pub fn new(config: &ClientConfig, control: bool) -> Self {
        let interval = |seconds| (seconds > 0).then(|| Duration::from_secs(seconds));
        let (read, write, all) = (
            interval(config.read_idle_seconds),
            interval(config.heartbeat_seconds),
            if control {
                interval(config.all_idle_seconds)
            } else {
                None
            },
        );
        let now = Instant::now();
        Self {
            read,
            write,
            all,
            next_read: read.map(|d| now + d),
            next_write: write.map(|d| now + d),
            next_all: all.map(|d| now + d),
        }
    }
    pub fn read(&mut self) {
        let now = Instant::now();
        self.next_read = self.read.map(|d| now + d);
        self.next_all = self.all.map(|d| now + d);
    }
    pub fn written(&mut self) {
        let now = Instant::now();
        self.next_write = self.write.map(|d| now + d);
        self.next_all = self.all.map(|d| now + d);
    }
    pub async fn next(&mut self) -> IdleEvent {
        let Some((deadline, event)) = [
            self.next_read.map(|t| (t, IdleEvent::Read)),
            self.next_write.map(|t| (t, IdleEvent::Write)),
            self.next_all.map(|t| (t, IdleEvent::All)),
        ]
        .into_iter()
        .flatten()
        .min_by_key(|(t, _)| *t) else {
            return std::future::pending().await;
        };
        sleep_until(deadline).await;
        // Non-writable data channels ignore this read event, then check again one interval later.
        let now = Instant::now();
        match event {
            IdleEvent::Read => self.next_read = self.read.map(|d| now + d),
            IdleEvent::Write => self.next_write = self.write.map(|d| now + d),
            IdleEvent::All => self.next_all = self.all.map(|d| now + d),
        }
        event
    }
}

pub(crate) struct Tunnel {
    pub reader: FramedRead<ReadHalf<Stream>, ConfiguredCodec>,
    pub writer: Outbound<WriteHalf<Stream>>,
    pub idle: Idle,
    codec: ConfiguredCodec,
}
impl Tunnel {
    pub fn new(stream: Stream, config: &ClientConfig, control: bool, tcp: bool) -> Self {
        let (read, write) = tokio::io::split(stream);
        Self {
            reader: FramedRead::new(read, ConfiguredCodec::new(config)),
            writer: Outbound::new(
                write,
                if tcp {
                    config.water_marks()
                } else {
                    WaterMark::default()
                },
            ),
            idle: Idle::new(config, control),
            codec: ConfiguredCodec::new(config),
        }
    }
    pub fn send(&mut self, frame: Frame) -> Result<(), String> {
        let mut bytes = BytesMut::new();
        self.codec
            .encode(frame, &mut bytes)
            .map_err(|_| "隧道消息编码失败".to_owned())?;
        self.writer.push(bytes.to_vec());
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::AsyncReadExt;

    #[tokio::test]
    async fn slow_writer_pauses_at_high_water_and_only_resumes_below_low_water() {
        let (writer, mut reader) = tokio::io::duplex(1);
        let mut out = Outbound::new(writer, WaterMark { low: 3, high: 5 });
        out.push(vec![1, 2]);
        out.push(vec![3, 4]);
        out.push(vec![5, 6]);
        assert!(!out.writable());
        // A cancelled partial flush must not duplicate bytes or reopen the producer.
        assert!(
            tokio::time::timeout(Duration::from_millis(10), out.flush_one())
                .await
                .is_err()
        );
        assert!(!out.writable());
        let drain = tokio::spawn(async move {
            let mut b = Vec::new();
            reader.read_to_end(&mut b).await.unwrap();
            b
        });
        out.flush_one().await.unwrap();
        assert!(!out.writable());
        out.flush_one().await.unwrap();
        assert!(out.writable());
        out.finish().await.unwrap();
        assert_eq!(drain.await.unwrap(), [1, 2, 3, 4, 5, 6]);
    }

    #[test]
    fn configured_byte_units_and_overflow_are_validated() {
        use crate::config::parse_water_mark;
        assert_eq!(
            parse_water_mark(" 0.5 kb / 1 M "),
            Some(WaterMark {
                low: 512,
                high: 1048576
            })
        );
        for invalid in ["1GB/2GB", "1KB/1KB", "2KB/1KB", "1..2KB/2MB", "-1B/2KB"] {
            assert!(parse_water_mark(invalid).is_none(), "{invalid}");
        }
    }

    #[tokio::test]
    async fn data_channels_ignore_all_idle_and_incoming_reads_do_not_postpone_heartbeats() {
        let config = ClientConfig {
            read_idle_seconds: 0,
            heartbeat_seconds: 1,
            all_idle_seconds: 1,
            ..Default::default()
        };
        let mut idle = Idle::new(&config, false);
        assert!(idle.next_all.is_none());
        let deadline = idle.next_write.unwrap();
        idle.read();
        assert_eq!(idle.next_write.unwrap(), deadline);
        // Speed up the timer without changing the event semantics under test.
        idle.next_write = Some(Instant::now());
        assert_eq!(idle.next().await, IdleEvent::Write);
        idle.written();
        assert!(idle.next_write.unwrap() > deadline);
    }
}
