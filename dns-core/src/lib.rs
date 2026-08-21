pub mod cache;
pub mod config;
pub mod filter;
pub mod health;
pub mod protocol;
pub mod resolver;

pub use cache::{CacheStats, DnsCache};
pub use config::ServerConfig;
pub use filter::{DomainTrie, FilterEngine, FilterResult};
pub use health::{ServiceState, SystemHealth};
pub use protocol::{
    DnsHeader, DnsPacket, DnsQuestion, QueryClass, QueryType, ResourceData, ResourceRecord,
    ResponseCode,
};
pub use resolver::UpstreamForwarder;
