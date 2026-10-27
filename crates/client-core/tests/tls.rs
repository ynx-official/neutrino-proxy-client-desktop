use futures_util::{SinkExt, StreamExt};
use neutrino_client_core::{
    config::{ClientConfig, Secrets},
    protocol::{Codec, Frame},
    Engine,
};
use rcgen::{BasicConstraints, CertificateParams, IsCa, KeyPair};
use rustls::pki_types::PrivatePkcs8KeyDer;
use std::{path::PathBuf, sync::Arc};
use tokio::{
    net::TcpListener,
    time::{sleep, timeout, Duration},
};
use tokio_rustls::TlsAcceptor;
use tokio_util::codec::Framed;

struct TrustFile(PathBuf);
impl Drop for TrustFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

async fn handshake(trusted: bool, expired: bool) -> (bool, String) {
    let ca_key = KeyPair::generate().unwrap();
    let mut ca_params = CertificateParams::new(vec![]).unwrap();
    ca_params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    let ca = ca_params.self_signed(&ca_key).unwrap();
    let server_key = KeyPair::generate().unwrap();
    let mut params = CertificateParams::new(vec!["different.example.test".into()]).unwrap();
    if expired {
        params.not_before = rcgen::date_time_ymd(2019, 1, 1);
        params.not_after = rcgen::date_time_ymd(2020, 1, 1);
    }
    let cert = params.signed_by(&server_key, &ca, &ca_key).unwrap();
    let mut roots = ca.pem();
    if !trusted {
        roots = CertificateParams::new(vec![])
            .unwrap()
            .self_signed(&KeyPair::generate().unwrap())
            .unwrap()
            .pem();
    }
    let file = TrustFile(
        std::env::temp_dir().join(format!("neutrino-trust-{}.pem", uuid::Uuid::new_v4())),
    );
    std::fs::write(&file.0, roots).unwrap();
    let server = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let cfg = ClientConfig {
        server: "127.0.0.1".into(),
        port: server.local_addr().unwrap().port(),
        ssl: true,
        certificate_path: file.0.to_string_lossy().into_owned(),
        ..Default::default()
    };
    let tls = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(
            vec![cert.der().clone()],
            PrivatePkcs8KeyDer::from(server_key.serialize_der()).into(),
        )
        .unwrap();
    let peer = tokio::spawn(async move {
        let socket = server.accept().await.unwrap().0;
        let Ok(socket) = TlsAcceptor::from(Arc::new(tls)).accept(socket).await else {
            return false;
        };
        let mut wire = Framed::new(socket, Codec);
        if !matches!(wire.next().await, Some(Ok(frame)) if frame.kind == 2) {
            return false;
        }
        wire.send(Frame::new(2, r#"{"code":0}"#, vec![]))
            .await
            .unwrap();
        while wire.next().await.is_some() {}
        true
    });
    let engine = Engine::new();
    engine
        .connect(
            cfg,
            Secrets {
                license: "tls-test-license".into(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    timeout(Duration::from_secs(4), async {
        while !matches!(
            engine.snapshot().state.as_str(),
            "connected" | "reconnecting" | "error"
        ) {
            sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
    let state = engine.snapshot().state;
    engine.disconnect().await;
    (
        timeout(Duration::from_secs(2), peer)
            .await
            .unwrap()
            .unwrap(),
        state,
    )
}

#[tokio::test]
async fn trusted_server_with_a_different_certificate_name_matches_java() {
    let (authenticated, state) = handshake(true, false).await;
    assert!(
        authenticated,
        "Java accepts this trusted chain without endpoint identification; state={state}"
    );
    assert_eq!(state, "connected");
}
#[tokio::test]
async fn unknown_issuer_is_still_rejected() {
    assert!(!handshake(false, false).await.0);
}
#[tokio::test]
async fn expired_unpinned_server_certificate_is_still_rejected() {
    assert!(!handshake(true, true).await.0);
}

// Use the existing public sample JKS as the server, too. Ring cannot sign with this
// 1024-bit key, so the test server uses RustCrypto and runs a real TLS handshake.
#[derive(Debug)]
struct SampleKey {
    key: rsa::RsaPrivateKey,
    corrupt: bool,
    scheme: rustls::SignatureScheme,
}
impl rustls::sign::SigningKey for SampleKey {
    fn choose_scheme(
        &self,
        offered: &[rustls::SignatureScheme],
    ) -> Option<Box<dyn rustls::sign::Signer>> {
        offered.contains(&self.scheme).then(|| {
            Box::new(Self {
                key: self.key.clone(),
                corrupt: self.corrupt,
                scheme: self.scheme,
            }) as Box<dyn rustls::sign::Signer>
        })
    }
    fn algorithm(&self) -> rustls::SignatureAlgorithm {
        rustls::SignatureAlgorithm::RSA
    }
}
impl rustls::sign::Signer for SampleKey {
    fn sign(&self, message: &[u8]) -> Result<Vec<u8>, rustls::Error> {
        use rsa::signature::{RandomizedSigner, SignatureEncoding, Signer};
        let mut bytes = if self.scheme == rustls::SignatureScheme::RSA_PSS_SHA256 {
            rsa::pss::SigningKey::<sha2::Sha256>::new(self.key.clone())
                .sign_with_rng(&mut rsa::rand_core::OsRng, message)
                .to_vec()
        } else {
            rsa::pkcs1v15::SigningKey::<sha2::Sha256>::new(self.key.clone())
                .sign(message)
                .to_vec()
        };
        if self.corrupt {
            bytes[0] ^= 1;
        }
        Ok(bytes)
    }
    fn scheme(&self) -> rustls::SignatureScheme {
        self.scheme
    }
}

async fn builtin_handshake(
    version: &'static rustls::SupportedProtocolVersion,
    scheme: rustls::SignatureScheme,
    corrupt: bool,
) -> bool {
    use rsa::pkcs8::DecodePrivateKey;
    use rustls::sign::{CertifiedKey, SingleCertAndKey};
    let mut jks = jks::KeyStore::new();
    jks.load(
        std::io::Cursor::new(include_bytes!("../resources/test.jks")),
        b"123456",
    )
    .unwrap();
    let entry = jks
        .aliases()
        .iter()
        .find_map(|alias| jks.get_private_key_entry(alias, b"123456").ok())
        .unwrap();
    let key = rsa::RsaPrivateKey::from_pkcs8_der(&entry.private_key).unwrap();
    let certs = entry
        .certificate_chain
        .into_iter()
        .map(|c| rustls::pki_types::CertificateDer::from(c.content))
        .collect();
    let cert = CertifiedKey::new(
        certs,
        Arc::new(SampleKey {
            key,
            corrupt,
            scheme,
        }),
    );
    let tls = rustls::ServerConfig::builder_with_protocol_versions(&[version])
        .with_no_client_auth()
        .with_cert_resolver(Arc::new(SingleCertAndKey::from(cert)));
    let server = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let config = ClientConfig {
        server: "127.0.0.1".into(),
        port: server.local_addr().unwrap().port(),
        ssl: true,
        ..Default::default()
    };
    let peer = tokio::spawn(async move {
        let socket = server.accept().await.unwrap().0;
        let Ok(socket) = TlsAcceptor::from(Arc::new(tls)).accept(socket).await else {
            return false;
        };
        let mut wire = Framed::new(socket, Codec);
        if !matches!(wire.next().await, Some(Ok(frame)) if frame.kind == 2) {
            return false;
        }
        wire.send(Frame::new(2, r#"{"code":0}"#, vec![]))
            .await
            .unwrap();
        while wire.next().await.is_some() {}
        true
    });
    let engine = Engine::new();
    engine
        .connect(
            config,
            Secrets {
                license: "sample-tls-test".into(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    timeout(Duration::from_secs(4), async {
        while !matches!(
            engine.snapshot().state.as_str(),
            "connected" | "reconnecting" | "error"
        ) {
            sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
    engine.disconnect().await;
    timeout(Duration::from_secs(2), peer)
        .await
        .unwrap()
        .unwrap()
}

#[tokio::test]
async fn builtin_java_jks_connects_with_tls12_and_tls13() {
    assert!(
        builtin_handshake(
            &rustls::version::TLS12,
            rustls::SignatureScheme::RSA_PKCS1_SHA256,
            false
        )
        .await
    );
    assert!(
        builtin_handshake(
            &rustls::version::TLS13,
            rustls::SignatureScheme::RSA_PSS_SHA256,
            false
        )
        .await
    );
}
#[tokio::test]
async fn pinned_certificate_does_not_allow_forged_handshake_signatures() {
    assert!(
        !builtin_handshake(
            &rustls::version::TLS12,
            rustls::SignatureScheme::RSA_PKCS1_SHA256,
            true
        )
        .await
    );
    assert!(
        !builtin_handshake(
            &rustls::version::TLS13,
            rustls::SignatureScheme::RSA_PSS_SHA256,
            true
        )
        .await
    );
}
