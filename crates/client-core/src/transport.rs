use crate::config::{ClientConfig, Secrets};
use rustls::{
    pki_types::{CertificateDer, ServerName},
    RootCertStore,
};
use std::{
    io::{self, Cursor},
    sync::Arc,
};
use tokio::{
    io::{AsyncRead, AsyncWrite},
    net::TcpStream,
    time::{timeout, Duration},
};

pub trait AsyncStream: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send> AsyncStream for T {}
pub type Stream = Box<dyn AsyncStream>;
pub fn trust_roots(config: &ClientConfig, secrets: &Secrets) -> Result<RootCertStore, String> {
    let mut roots = RootCertStore::empty();
    for cert in trust_certificates(config, secrets)? {
        roots
            .add(cert)
            .map_err(|_| "信任证书格式或算法无效".to_owned())?;
    }
    Ok(roots)
}
pub(crate) fn tls_config(
    config: &ClientConfig,
    secrets: &Secrets,
) -> Result<rustls::ClientConfig, String> {
    crate::tls::config(trust_certificates(config, secrets)?)
}
fn trust_certificates(
    config: &ClientConfig,
    secrets: &Secrets,
) -> Result<Vec<CertificateDer<'static>>, String> {
    let builtin = config.certificate_path.is_empty();
    let bytes = if builtin {
        include_bytes!("../resources/test.jks").to_vec()
    } else {
        let metadata = std::fs::metadata(&config.certificate_path)
            .map_err(|_| "无法读取信任证书文件".to_owned())?;
        if metadata.len() > 4 * 1024 * 1024 {
            return Err("证书文件不能超过 4 MiB".into());
        }
        std::fs::read(&config.certificate_path).map_err(|_| "无法读取信任证书文件".to_owned())?
    };
    let certs = if bytes.starts_with(&[0xfe, 0xed, 0xfe, 0xed]) {
        let mut store = jks::KeyStore::new();
        // This is the public example truststore password from the original Java client.
        let password = if builtin {
            "123456"
        } else {
            &secrets.store_password
        };
        store
            .load(Cursor::new(bytes), password.as_bytes())
            .map_err(|_| "JKS 证书库密码错误或文件无效".to_owned())?;
        let mut certs = vec![];
        for alias in store.aliases() {
            if let Ok(entry) = store.get_trusted_certificate_entry(&alias) {
                certs.push(CertificateDer::from(entry.certificate.content));
            } else if let Ok(chain) = store.get_private_key_entry_certificate_chain(&alias) {
                certs.extend(chain.into_iter().map(|c| CertificateDer::from(c.content)));
            }
        }
        certs
    } else if bytes.starts_with(b"-----") {
        rustls_pemfile::certs(&mut Cursor::new(bytes))
            .collect::<io::Result<Vec<_>>>()
            .map_err(|_| "PEM 证书格式无效".to_owned())?
    } else {
        vec![CertificateDer::from(bytes)]
    };
    if certs.is_empty() {
        return Err("证书库没有可用的信任证书".into());
    }
    Ok(certs)
}
pub async fn open(
    config: &ClientConfig,
    tls: Option<Arc<rustls::ClientConfig>>,
) -> Result<Stream, String> {
    let socket = timeout(
        Duration::from_secs(10),
        TcpStream::connect((config.server.as_str(), config.port)),
    )
    .await
    .map_err(|_| "连接服务器超时".to_owned())?
    .map_err(|_| "无法连接服务器，请检查地址、端口与网络".to_owned())?;
    socket.set_nodelay(true).ok();
    if let Some(tls) = tls {
        let name = ServerName::try_from(config.server.clone())
            .map_err(|_| "SSL 服务器名称无效".to_owned())?;
        let stream = timeout(
            Duration::from_secs(10),
            tokio_rustls::TlsConnector::from(tls).connect(name, socket),
        )
        .await
        .map_err(|_| "SSL 握手超时".to_owned())?
        .map_err(|_| "SSL 握手失败，请检查信任证书、有效期及签名算法".to_owned())?;
        Ok(Box::new(stream))
    } else {
        Ok(Box::new(socket))
    }
}
