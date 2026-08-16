use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ServiceState {
    Starting,
    Online,
    Degraded,
    Offline,
    Reconnecting,
    Error,
    Stopped,
}

impl std::fmt::Display for ServiceState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ServiceState::Starting => write!(f, "STARTING"),
            ServiceState::Online => write!(f, "ONLINE"),
            ServiceState::Degraded => write!(f, "DEGRADED"),
            ServiceState::Offline => write!(f, "OFFLINE"),
            ServiceState::Reconnecting => write!(f, "RECONNECTING"),
            ServiceState::Error => write!(f, "ERROR"),
            ServiceState::Stopped => write!(f, "STOPPED"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemHealth {
    pub state: ServiceState,
    pub agh_healthy: bool,
    pub unbound_healthy: bool,
    pub local_network_connected: bool,
    pub internet_connected: bool,
    pub blocklists_loaded: bool,
    pub total_queries: u64,
    pub total_blocked: u64,
    pub cache_hits: u64,
}

impl Default for SystemHealth {
    fn default() -> Self {
        Self {
            state: ServiceState::Starting,
            agh_healthy: true,
            unbound_healthy: true,
            local_network_connected: true,
            internet_connected: true,
            blocklists_loaded: true,
            total_queries: 0,
            total_blocked: 0,
            cache_hits: 0,
        }
    }
}
