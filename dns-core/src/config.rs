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
pub struct ServerConfig {
    pub bind_addr: SocketAddr,
    pub upstream_addr: SocketAddr,
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
            bind_addr: "127.0.0.1:53".parse().unwrap(),
            upstream_addr: "127.0.0.1:5335".parse().unwrap(),
            block_mode: "nxdomain".to_string(),
            cache_capacity: 10000,
            min_ttl_secs: 300,
            max_ttl_secs: 86400,
            blocklist_paths: vec!["config/blocklists/custom-blocklist.txt".to_string()],
            allowlist_paths: vec!["allowlists/custom-allowlist.txt".to_string()],
            logging_enabled: false,
        }
    }
}

impl ServerConfig {
    pub fn load_from_file(path: &str) -> Result<Self, ConfigError> {
        let content = std::fs::read_to_string(path)?;
        let config: ServerConfig = toml::from_str(&content)?;
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
        Ok(())
    }
}
