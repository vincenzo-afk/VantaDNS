pub mod config;
pub mod protocol;
pub mod filter;
pub mod cache;
pub mod resolver;
pub mod health;

pub use config::ServerConfig;
pub use protocol::{DnsPacket, DnsHeader, DnsQuestion, QueryType, QueryClass, ResourceRecord, ResourceData, ResponseCode};
pub use filter::{FilterEngine, FilterResult, DomainTrie};
pub use cache::{DnsCache, CacheStats};
pub use resolver::UpstreamForwarder;
pub use health::{ServiceState, SystemHealth};
