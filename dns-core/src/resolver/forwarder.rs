use std::net::SocketAddr;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpStream, UdpSocket};
use tokio::time::timeout;
use crate::protocol::{DnsPacket, DnsError};

/// Upstream DNS forwarding strategy.
/// - `Udp`: classic UDP/53 (default, works for Unbound-style local backends).
/// - `Tcp`: plain DNS-over-TCP (RFC 1035 length framing) to public resolvers.
#[derive(Debug, Clone)]
pub enum UpstreamTransport {
    Udp,
    Tcp,
}

#[derive(Debug, Clone)]
pub struct UpstreamEntry {
    pub addr: SocketAddr,
    pub transport: UpstreamTransport,
}

#[derive(Debug, Clone)]
pub struct UpstreamForwarder {
    /// Ordered list of upstream resolvers (first-success wins).
    upstreams: Vec<UpstreamEntry>,
    timeout_duration: Duration,
}

impl UpstreamForwarder {
    /// Legacy constructor: single UDP upstream (kept for backward compatibility with existing tests).
    pub fn new(upstream_addr: SocketAddr, timeout_secs: u64) -> Self {
        Self {
            upstreams: vec![UpstreamEntry {
                addr: upstream_addr,
                transport: UpstreamTransport::Udp,
            }],
            timeout_duration: Duration::from_secs(timeout_secs),
        }
    }

    /// Build a forwarder with an explicit list of upstreams.
    pub fn with_upstreams(upstreams: Vec<UpstreamEntry>, timeout_secs: u64) -> Self {
        Self {
            upstreams,
            timeout_duration: Duration::from_secs(timeout_secs),
        }
    }

    /// Returns true if there is at least one upstream configured.
    pub fn has_upstreams(&self) -> bool {
        !self.upstreams.is_empty()
    }

    /// Forwards raw DNS query bytes to the upstream chain and returns raw response bytes.
    /// Tries each upstream in order (UDP first by default); returns the first success.
    pub async fn forward_raw(&self, query_bytes: &[u8]) -> Result<Vec<u8>, DnsError> {
        if self.upstreams.is_empty() {
            return Err(DnsError::ParseError("No upstream resolver configured".to_string()));
        }

        let mut last_err = DnsError::ParseError("no upstream attempted".to_string());

        for entry in &self.upstreams {
            match entry.transport {
                UpstreamTransport::Udp => {
                    match self.forward_udp(query_bytes, entry.addr).await {
                        Ok(resp) => return Ok(resp),
                        Err(e) => last_err = e,
                    }
                }
                UpstreamTransport::Tcp => {
                    match self.forward_tcp(query_bytes, entry.addr).await {
                        Ok(resp) => return Ok(resp),
                        Err(e) => last_err = e,
                    }
                }
            }
        }

        Err(last_err)
    }

    /// Forward raw query over UDP.
    async fn forward_udp(&self, query_bytes: &[u8], addr: SocketAddr) -> Result<Vec<u8>, DnsError> {
        let socket = UdpSocket::bind("0.0.0.0:0")
            .await
            .map_err(|e| DnsError::ParseError(format!("UDP bind error: {}", e)))?;

        socket
            .connect(addr)
            .await
            .map_err(|e| DnsError::ParseError(format!("UDP connect error: {}", e)))?;

        socket
            .send(query_bytes)
            .await
            .map_err(|e| DnsError::ParseError(format!("UDP send error: {}", e)))?;

        let mut buf = vec![0u8; 65535];
        let len = timeout(self.timeout_duration, socket.recv(&mut buf))
            .await
            .map_err(|_| DnsError::ParseError("Upstream UDP query timed out".to_string()))?
            .map_err(|e| DnsError::ParseError(format!("UDP recv error: {}", e)))?;

        buf.truncate(len);
        Ok(buf)
    }

    /// Forward raw query over TCP with RFC 1035 2-byte length framing.
    async fn forward_tcp(&self, query_bytes: &[u8], addr: SocketAddr) -> Result<Vec<u8>, DnsError> {
        let conn = timeout(self.timeout_duration, TcpStream::connect(addr))
            .await
            .map_err(|_| DnsError::ParseError("Upstream TCP connect timed out".to_string()))?
            .map_err(|e| DnsError::ParseError(format!("TCP connect error: {}", e)))?;

        let _ = conn.set_nodelay(true);

        timeout(self.timeout_duration, async {
            let (mut reader, mut writer) = conn.into_split();

            // 2-byte big-endian length prefix + DNS message
            let len = query_bytes.len() as u16;
            writer.write_all(&len.to_be_bytes()).await
                .map_err(|e| DnsError::ParseError(format!("TCP send length error: {}", e)))?;
            writer.write_all(query_bytes).await
                .map_err(|e| DnsError::ParseError(format!("TCP send error: {}", e)))?;
            writer.flush().await
                .map_err(|e| DnsError::ParseError(format!("TCP flush error: {}", e)))?;

            // Read 2-byte response length
            let mut len_buf = [0u8; 2];
            reader.read_exact(&mut len_buf).await
                .map_err(|e| DnsError::ParseError(format!("TCP recv length error: {}", e)))?;
            let resp_len = u16::from_be_bytes(len_buf) as usize;
            if resp_len == 0 || resp_len > 65535 {
                return Err(DnsError::ParseError(format!("Invalid upstream TCP response length: {}", resp_len)));
            }

            // Read response DNS message
            let mut resp = vec![0u8; resp_len];
            reader.read_exact(&mut resp).await
                .map_err(|e| DnsError::ParseError(format!("TCP recv error: {}", e)))?;

            Ok(resp)
        })
        .await
        .map_err(|_| DnsError::ParseError("Upstream TCP query timed out".to_string()))?
    }

    /// Forwards a parsed DnsPacket and returns the parsed DnsPacket response.
    pub async fn forward_packet(&self, packet: &DnsPacket) -> Result<DnsPacket, DnsError> {
        let raw_bytes = packet.to_bytes();
        let resp_bytes = self.forward_raw(&raw_bytes).await?;
        DnsPacket::parse(&resp_bytes)
    }
}
