use std::net::SocketAddr;
use std::time::Duration;
use tokio::net::UdpSocket;
use tokio::time::timeout;
use crate::protocol::{DnsPacket, DnsError};

#[derive(Debug, Clone)]
pub struct UpstreamForwarder {
    upstream_addr: SocketAddr,
    timeout_duration: Duration,
}

impl UpstreamForwarder {
    pub fn new(upstream_addr: SocketAddr, timeout_secs: u64) -> Self {
        Self {
            upstream_addr,
            timeout_duration: Duration::from_secs(timeout_secs),
        }
    }

    /// Forwards raw DNS query packet bytes to upstream (Unbound) and receives raw response
    pub async fn forward_raw(&self, query_bytes: &[u8]) -> Result<Vec<u8>, DnsError> {
        let socket = UdpSocket::bind("0.0.0.0:0")
            .await
            .map_err(|e| DnsError::ParseError(format!("UDP bind error: {}", e)))?;

        socket
            .connect(self.upstream_addr)
            .await
            .map_err(|e| DnsError::ParseError(format!("UDP connect error: {}", e)))?;

        socket
            .send(query_bytes)
            .await
            .map_err(|e| DnsError::ParseError(format!("UDP send error: {}", e)))?;

        let mut buf = vec![0u8; 4096];
        let len = timeout(self.timeout_duration, socket.recv(&mut buf))
            .await
            .map_err(|_| DnsError::ParseError("Upstream DNS query timed out".to_string()))?
            .map_err(|e| DnsError::ParseError(format!("UDP recv error: {}", e)))?;

        buf.truncate(len);
        Ok(buf)
    }

    /// Forwards a parsed DnsPacket and returns the parsed DnsPacket response
    pub async fn forward_packet(&self, packet: &DnsPacket) -> Result<DnsPacket, DnsError> {
        let raw_bytes = packet.to_bytes();
        let resp_bytes = self.forward_raw(&raw_bytes).await?;
        DnsPacket::parse(&resp_bytes)
    }
}
