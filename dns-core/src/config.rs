use std::net::SocketAddr;
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ConfigError {
    #[error("Failed to read config file: {0}")]
    IoError(#[from] std::io::Error),
    #[error("Failed to parse TOML config: {0}")]
    TomlError(#[from] toml::de::Error),
    #[error("Config validation error: {0}")]
    ValidationError(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerSection {
    pub bind_addr: SocketAddr,
    #[serde(default = "default_upstream_addr")]
    pub upstream_addr: SocketAddr,
    /// List of upstream resolvers. Parsed from entries like "udp:1.1.1.1:53" or
    /// "tcp:8.8.8.8:53". Used in preference to the legacy `upstream_addr` when set.
    #[serde(default)]
    pub upstreams: Vec<String>,
    /// Enable the plain-TCP DNS listener on the same bind port (RFC 1035 length framing).
    /// Required for DNS-over-TLS (DoT): the TLS layer terminates upstream and hands
    /// plaintext framed DNS to this listener. On Fly.io the TLS handler does exactly that.
    #[serde(default)]
    pub tcp_enabled: bool,
    /// Standalone TLS listener (real DoT endpoint, app-terminated TLS). Supply a cert and
    /// key file path (or via TLS_CERT / TLS_KEY env vars). Skip when the platform
    /// (e.g. Fly.io with `handlers = ["tls"]`) terminates TLS for you.
    #[serde(default)]
    pub tls_enabled: bool,
    #[serde(default)]
    pub tls_cert_path: Option<String>,
    #[serde(default)]
    pub tls_key_path: Option<String>,
    /// Port for the standalone TLS (DoT) listener. Defaults to 853 (standard DoT port).
    #[serde(default = "default_tls_port")]
    pub tls_port: u16,
    pub block_mode: String,
    #[serde(default)]
    pub logging_enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheSection {
    pub capacity: usize,
    pub min_ttl_secs: u64,
    pub max_ttl_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilterSection {
    #[serde(default)]
    pub blocklist_paths: Vec<String>,
    #[serde(default)]
    pub allowlist_paths: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TomlConfigFile {
    pub server: ServerSection,
    pub cache: CacheSection,
    #[serde(default)]
    pub filter: Option<FilterSection>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub bind_addr: SocketAddr,
    pub upstream_addr: SocketAddr,
    pub upstreams: Vec<String>,
    pub tcp_enabled: bool,
    pub tls_enabled: bool,
    pub tls_cert_path: Option<String>,
    pub tls_key_path: Option<String>,
    pub tls_port: u16,
    pub block_mode: String,
    pub cache_capacity: usize,
    pub min_ttl_secs: u64,
    pub max_ttl_secs: u64,
    pub blocklist_paths: Vec<String>,
    pub allowlist_paths: Vec<String>,
    pub logging_enabled: bool,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            bind_addr: "127.0.0.1:5353".parse().unwrap(),
            upstream_addr: "127.0.0.1:5335".parse().unwrap(),
            upstreams: vec![],
            tcp_enabled: false,
            tls_enabled: false,
            tls_cert_path: None,
            tls_key_path: None,
            tls_port: 853,
            block_mode: "nxdomain".to_string(),
            cache_capacity: 10000,
            min_ttl_secs: 60,
            max_ttl_secs: 86400,
            blocklist_paths: vec![],
            allowlist_paths: vec![],
            logging_enabled: false,
        }
    }
}

fn default_upstream_addr() -> SocketAddr {
    "127.0.0.1:5335".parse().unwrap()
}

fn default_tls_port() -> u16 {
    853
}

impl ServerConfig {
    pub fn load_from_file(path: &str) -> Result<Self, ConfigError> {
        let content = std::fs::read_to_string(path)?;
        
        // Try table format first
        if let Ok(toml_file) = toml::from_str::<TomlConfigFile>(&content) {
            let filter = toml_file.filter.unwrap_or_else(|| FilterSection {
                blocklist_paths: vec![],
                allowlist_paths: vec![],
            });
            let mut config = ServerConfig {
                bind_addr: toml_file.server.bind_addr,
                upstream_addr: toml_file.server.upstream_addr,
                upstreams: toml_file.server.upstreams,
                tcp_enabled: toml_file.server.tcp_enabled,
                tls_enabled: toml_file.server.tls_enabled,
                tls_cert_path: toml_file.server.tls_cert_path,
                tls_key_path: toml_file.server.tls_key_path,
                tls_port: toml_file.server.tls_port,
                block_mode: toml_file.server.block_mode,
                logging_enabled: toml_file.server.logging_enabled,
                cache_capacity: toml_file.cache.capacity,
                min_ttl_secs: toml_file.cache.min_ttl_secs,
                max_ttl_secs: toml_file.cache.max_ttl_secs,
                blocklist_paths: filter.blocklist_paths,
                allowlist_paths: filter.allowlist_paths,
            };
            config.apply_tls_env_overrides();
            config.validate()?;
            return Ok(config);
        }

        // Fallback to flat format
        let mut config: ServerConfig = toml::from_str(&content)?;
        config.apply_tls_env_overrides();
        config.validate()?;
        Ok(config)
    }

    pub fn validate(&self) -> Result<(), ConfigError> {
        if self.cache_capacity == 0 {
            return Err(ConfigError::ValidationError("cache_capacity must be greater than 0".to_string()));
        }
        if self.min_ttl_secs > self.max_ttl_secs {
            return Err(ConfigError::ValidationError("min_ttl_secs cannot be greater than max_ttl_secs".to_string()));
        }
        let mode = self.block_mode.to_lowercase();
        if mode != "nxdomain" && mode != "zero_ip" {
            return Err(ConfigError::ValidationError(format!("Invalid block_mode: '{}'. Allowed: 'nxdomain' or 'zero_ip'", self.block_mode)));
        }
        if self.tls_enabled {
            if self.tls_cert_path.is_none() && std::env::var("TLS_CERT_PATH").is_err() {
                return Err(ConfigError::ValidationError(
                    "tls_enabled=true but no TLS certificate provided. Set tls_cert_path or TLS_CERT env var".to_string(),
                ));
            }
            if self.tls_key_path.is_none() && std::env::var("TLS_KEY_PATH").is_err() {
                return Err(ConfigError::ValidationError(
                    "tls_enabled=true but no TLS private key provided. Set tls_key_path or TLS_KEY env var".to_string(),
                ));
            }
        }
        Ok(())
    }

    /// Allow cloud deployment overrides: TLS_CERT / TLS_KEY env vars fill cert & key paths,
    /// and VANTA_DNS_UPSTREAMS=udp:1.1.1.1:53,tcp:8.8.8.8:53 fills the upstream list.
    pub fn apply_tls_env_overrides(&mut self) {
        if let Ok(cert) = std::env::var("TLS_CERT") {
            self.tls_cert_path = Some(cert);
        }
        if let Ok(key) = std::env::var("TLS_KEY") {
            self.tls_key_path = Some(key);
        }
        if let Ok(cert) = std::env::var("TLS_CERT_PATH") {
            self.tls_cert_path = Some(cert);
        }
        if let Ok(key) = std::env::var("TLS_KEY_PATH") {
            self.tls_key_path = Some(key);
        }
        if let Ok(list) = std::env::var("VANTA_DNS_UPSTREAMS") {
            self.upstreams = list.split(',').map(|s| s.trim().to_string()).collect();
        }
        // Auto-detect DoT-ready environment: if TLS cert/key are present and TLS isn't
        // disabled explicitly, enable the standalone TLS listener.
        if !self.tls_enabled && self.tls_cert_path.is_some() && self.tls_key_path.is_some() {
            self.tls_enabled = true;
            self.tcp_enabled = true;
        }
    }

    /// Resolve the effective upstream list: `upstreams` entries first, falling back to the
    /// legacy `upstream_addr` single UDP entry.
    pub fn resolve_upstreams(&self) -> Vec<crate::resolver::UpstreamEntry> {
        let mut entries = Vec::new();
        for spec in &self.upstreams {
            let spec = spec.trim();
            if spec.is_empty() {
                continue;
            }
            if let Some(rest) = spec.strip_prefix("tcp:") {
                if let Ok(addr) = rest.parse::<SocketAddr>() {
                    entries.push(crate::resolver::UpstreamEntry {
                        addr,
                        transport: crate::resolver::UpstreamTransport::Tcp,
                    });
                }
            } else if let Some(rest) = spec.strip_prefix("udp:") {
                if let Ok(addr) = rest.parse::<SocketAddr>() {
                    entries.push(crate::resolver::UpstreamEntry {
                        addr,
                        transport: crate::resolver::UpstreamTransport::Udp,
                    });
                }
            } else if let Ok(addr) = spec.parse::<SocketAddr>() {
                // Bare address defaults to UDP (legacy compatibility).
                entries.push(crate::resolver::UpstreamEntry {
                    addr,
                    transport: crate::resolver::UpstreamTransport::Udp,
                });
            }
        }
        if entries.is_empty() && self.upstreams.is_empty() {
            entries.push(crate::resolver::UpstreamEntry {
                addr: self.upstream_addr,
                transport: crate::resolver::UpstreamTransport::Udp,
            });
        }
        entries
    }
}
