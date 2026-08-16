//! Integration test: verifies DNS-over-TCP and DNS-over-TLS (DoT) framing
//! against a running vanta-dns-core instance with TCP + TLS listeners enabled.
//!
//! Run with a local server first (see tests/test.toml):
//!   sudo env TLS_CERT=... TLS_KEY=... target/release/vanta-dns-core run --config tests/test.toml
//!   cargo test --test dot_integration -- --nocapture

use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::rustls::client::danger::ServerCertVerifier;

fn build_query(domain: &str) -> Vec<u8> {
    let id = [0xABu8, 0xCD];
    let flags = [0x01, 0x00]; // RD=1
    let qdcount = [0x00, 0x01];
    let qtype = [0x00, 0x01]; // A
    let qclass = [0x00, 0x01]; // IN

    let mut qname = Vec::new();
    for part in domain.split('.') {
        qname.push(part.len() as u8);
        qname.extend_from_slice(part.as_bytes());
    }
    qname.push(0x00);

    let mut msg = Vec::new();
    msg.extend_from_slice(&id);
    msg.extend_from_slice(&flags);
    msg.extend_from_slice(&qdcount);
    msg.extend_from_slice(&[0; 6]); // AN/NS/AR count = 0
    msg.extend_from_slice(&qname);
    msg.extend_from_slice(&qtype);
    msg.extend_from_slice(&qclass);
    msg
}

async fn dot_query_tcp(domain: &str) -> Vec<u8> {
    let mut conn = TcpStream::connect("127.0.0.1:5353")
        .await
        .expect("TCP connect failed");
    let _ = conn.set_nodelay(true);

    let query = build_query(domain);
    let len = query.len() as u16;
    conn.write_all(&len.to_be_bytes()).await.unwrap();
    conn.write_all(&query).await.unwrap();
    conn.flush().await.unwrap();

    let mut len_buf = [0u8; 2];
    conn.read_exact(&mut len_buf).await.unwrap();
    let resp_len = u16::from_be_bytes(len_buf) as usize;
    assert!(resp_len > 0 && resp_len <= 65535);
    let mut resp = vec![0u8; resp_len];
    conn.read_exact(&mut resp).await.unwrap();
    resp
}

async fn dot_query_tls(domain: &str) -> Vec<u8> {
    let tcp = TcpStream::connect("127.0.0.1:853")
        .await
        .expect("TLS TCP connect failed");

    let tls_config = Arc::new(
        tokio_rustls::rustls::ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(SkipVerify))
            .with_no_client_auth(),
    );
    let connector = tokio_rustls::TlsConnector::from(tls_config);
    let server_name: tokio_rustls::rustls::pki_types::ServerName = "localhost".try_into().unwrap();
    let mut tls = connector.connect(server_name, tcp).await.unwrap();

    let query = build_query(domain);
    let len = query.len() as u16;
    tls.write_all(&len.to_be_bytes()).await.unwrap();
    tls.write_all(&query).await.unwrap();
    tls.flush().await.unwrap();

    let mut len_buf = [0u8; 2];
    tls.read_exact(&mut len_buf).await.unwrap();
    let resp_len = u16::from_be_bytes(len_buf) as usize;
    assert!(resp_len > 0 && resp_len <= 65535);
    let mut resp = vec![0u8; resp_len];
    tls.read_exact(&mut resp).await.unwrap();
    resp
}

/// Answers whether a DNS response contains an answer record.
fn response_has_answer(resp: &[u8]) -> bool {
    if resp.len() < 12 {
        return false;
    }
    u16::from_be_bytes([resp[6], resp[7]]) > 0
}

/// Answers whether a DNS response has rcode = NXDOMAIN (3).
fn response_is_nxdomain(resp: &[u8]) -> bool {
    if resp.len() < 12 {
        return false;
    }
    (resp[3] & 0x0F) == 3
}

fn block_on<F: std::future::Future>(f: F) -> F::Output {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(f)
}

#[derive(Debug)]
struct SkipVerify;
impl tokio_rustls::rustls::client::danger::ServerCertVerifier for SkipVerify {
    fn verify_server_cert(
        &self,
        _end_entity: &tokio_rustls::rustls::pki_types::CertificateDer<'_>,
        _intermediates: &[tokio_rustls::rustls::pki_types::CertificateDer<'_>],
        _server_name: &tokio_rustls::rustls::pki_types::ServerName<'_>,
        _ocsp_response: &[u8],
        _now: tokio_rustls::rustls::pki_types::UnixTime,
    ) -> Result<tokio_rustls::rustls::client::danger::ServerCertVerified, tokio_rustls::rustls::Error> {
        Ok(tokio_rustls::rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &tokio_rustls::rustls::pki_types::CertificateDer<'_>,
        _dss: &tokio_rustls::rustls::DigitallySignedStruct,
    ) -> Result<tokio_rustls::rustls::client::danger::HandshakeSignatureValid, tokio_rustls::rustls::Error> {
        Ok(tokio_rustls::rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &tokio_rustls::rustls::pki_types::CertificateDer<'_>,
        _dss: &tokio_rustls::rustls::DigitallySignedStruct,
    ) -> Result<tokio_rustls::rustls::client::danger::HandshakeSignatureValid, tokio_rustls::rustls::Error> {
        Ok(tokio_rustls::rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<tokio_rustls::rustls::SignatureScheme> {
        vec![
            tokio_rustls::rustls::SignatureScheme::RSA_PKCS1_SHA256,
            tokio_rustls::rustls::SignatureScheme::RSA_PKCS1_SHA384,
            tokio_rustls::rustls::SignatureScheme::RSA_PKCS1_SHA512,
            tokio_rustls::rustls::SignatureScheme::ECDSA_NISTP256_SHA256,
            tokio_rustls::rustls::SignatureScheme::ECDSA_NISTP384_SHA384,
            tokio_rustls::rustls::SignatureScheme::ECDSA_NISTP521_SHA512,
            tokio_rustls::rustls::SignatureScheme::RSA_PSS_SHA256,
            tokio_rustls::rustls::SignatureScheme::RSA_PSS_SHA384,
            tokio_rustls::rustls::SignatureScheme::RSA_PSS_SHA512,
            tokio_rustls::rustls::SignatureScheme::ED25519,
            tokio_rustls::rustls::SignatureScheme::ED448,
        ]
    }
}

#[test]
fn tcp_resolution_google() {
    let resp = block_on(dot_query_tcp("google.com"));
    assert!(response_has_answer(&resp), "expected answer for google.com over TCP");
    println!("TCP OK: google.com -> {} bytes", resp.len());
}

#[test]
fn tcp_blocked_domain() {
    let resp = block_on(dot_query_tcp("doubleclick.net"));
    assert!(
        response_is_nxdomain(&resp),
        "expected NXDOMAIN for doubleclick.net over TCP"
    );
    println!("TCP OK: doubleclick.net blocked -> NXDOMAIN");
}

#[test]
fn tls_resolution_google() {
    let resp = block_on(dot_query_tls("google.com"));
    assert!(response_has_answer(&resp), "expected answer for google.com over TLS");
    println!("TLS OK: google.com -> {} bytes", resp.len());
}

#[test]
fn tls_blocked_domain() {
    let resp = block_on(dot_query_tls("doubleclick.net"));
    assert!(
        response_is_nxdomain(&resp),
        "expected NXDOMAIN for doubleclick.net over TLS"
    );
    println!("TLS OK: doubleclick.net blocked -> NXDOMAIN");
}

