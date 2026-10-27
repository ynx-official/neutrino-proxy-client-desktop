//! Match the Java truststore policy: verify trust and signatures without endpoint identification.
use rsa::{pkcs8::DecodePublicKey, signature::Verifier, traits::PublicKeyParts, RsaPublicKey};
use rustls::{
    client::{
        danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
        verify_server_cert_signed_by_trust_anchor, WebPkiServerVerifier,
    },
    pki_types::{CertificateDer, ServerName, UnixTime},
    server::ParsedCertificate,
    DigitallySignedStruct, Error, RootCertStore, SignatureScheme,
};
use std::sync::Arc;

#[derive(Debug)]
struct JavaTrustVerifier {
    roots: RootCertStore,
    trusted: Vec<CertificateDer<'static>>,
    signatures: Arc<WebPkiServerVerifier>,
}

pub(crate) fn config(
    trusted: Vec<CertificateDer<'static>>,
) -> Result<rustls::ClientConfig, String> {
    let mut roots = RootCertStore::empty();
    for cert in &trusted {
        roots
            .add(cert.clone())
            .map_err(|_| "信任证书格式无效".to_owned())?;
    }
    let signatures = WebPkiServerVerifier::builder(Arc::new(roots.clone()))
        .build()
        .map_err(|_| "证书库没有可用的信任证书".to_owned())?;
    let mut config = rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(JavaTrustVerifier {
            roots,
            trusted,
            signatures,
        }))
        .with_no_client_auth();
    // Java creates SSLEngine without a peer host and therefore sends no SNI.
    config.enable_sni = false;
    Ok(config)
}

impl JavaTrustVerifier {
    fn pinned(&self, cert: &CertificateDer<'_>) -> bool {
        self.trusted
            .iter()
            .any(|trusted| trusted.as_ref() == cert.as_ref())
    }
    fn signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
        tls13: bool,
    ) -> Result<HandshakeSignatureValid, Error> {
        let result = if tls13 {
            self.signatures.verify_tls13_signature(message, cert, dss)
        } else {
            self.signatures.verify_tls12_signature(message, cert, dss)
        };
        // The shipped Java truststore pins a 1024-bit RSA certificate. Ring requires 2048 bits.
        // Restrict the compatibility verifier to that exact truststore certificate and still
        // verify the handshake signature; never accept an arbitrary small RSA certificate.
        if result.is_ok() || !self.pinned(cert) {
            return result;
        }
        if legacy_signature(cert, dss.scheme, message, dss.signature(), tls13) {
            Ok(HandshakeSignatureValid::assertion())
        } else {
            result
        }
    }
}

fn legacy_signature(
    cert: &CertificateDer<'_>,
    scheme: SignatureScheme,
    message: &[u8],
    signature: &[u8],
    tls13: bool,
) -> bool {
    let Ok(parsed) = ParsedCertificate::try_from(cert) else {
        return false;
    };
    let Ok(key) = RsaPublicKey::from_public_key_der(parsed.subject_public_key_info().as_ref())
    else {
        return false;
    };
    if !(1024..2048).contains(&key.n().bits()) {
        return false;
    }
    macro_rules! verify {
        ($module:ident, $digest:ty) => {{
            let Ok(sig) = rsa::$module::Signature::try_from(signature) else {
                return false;
            };
            rsa::$module::VerifyingKey::<$digest>::new(key)
                .verify(message, &sig)
                .is_ok()
        }};
    }
    match scheme {
        SignatureScheme::RSA_PKCS1_SHA256 if !tls13 => verify!(pkcs1v15, sha2::Sha256),
        SignatureScheme::RSA_PKCS1_SHA384 if !tls13 => verify!(pkcs1v15, sha2::Sha384),
        SignatureScheme::RSA_PKCS1_SHA512 if !tls13 => verify!(pkcs1v15, sha2::Sha512),
        SignatureScheme::RSA_PSS_SHA256 => verify!(pss, sha2::Sha256),
        SignatureScheme::RSA_PSS_SHA384 => verify!(pss, sha2::Sha384),
        SignatureScheme::RSA_PSS_SHA512 => verify!(pss, sha2::Sha512),
        _ => false,
    }
}

impl ServerCertVerifier for JavaTrustVerifier {
    fn verify_server_cert(
        &self,
        cert: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        _name: &ServerName<'_>,
        _ocsp: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        let parsed = ParsedCertificate::try_from(cert)?;
        // Java directly trusts an identical certificate in its truststore. Otherwise perform
        // normal chain, certificate-purpose and validity checks, omitting only hostname checks.
        if !self.pinned(cert) {
            verify_server_cert_signed_by_trust_anchor(
                &parsed,
                &self.roots,
                intermediates,
                now,
                rustls::crypto::ring::default_provider()
                    .signature_verification_algorithms
                    .all,
            )?;
        }
        Ok(ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.signature(message, cert, dss, false)
    }
    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.signature(message, cert, dss, true)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.signatures.supported_verify_schemes()
    }
}
