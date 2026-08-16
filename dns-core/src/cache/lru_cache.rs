use std::num::NonZeroUsize;
use std::time::{Duration, Instant};
use lru::LruCache;
use crate::protocol::{DnsPacket, QueryType};

#[derive(Debug, Clone)]
pub struct CachedResponse {
    pub packet: DnsPacket,
    pub query_type: QueryType,
    pub created_at: Instant,
    pub ttl: Duration,
}

impl CachedResponse {
    pub fn is_expired(&self) -> bool {
        self.created_at.elapsed() >= self.ttl
    }

    pub fn remaining_ttl_secs(&self) -> u32 {
        let elapsed = self.created_at.elapsed();
        if elapsed >= self.ttl {
            0
        } else {
            (self.ttl - elapsed).as_secs() as u32
        }
    }
}

#[derive(Debug, Default, Clone, Copy)]
pub struct CacheStats {
    pub hits: u64,
    pub misses: u64,
    pub evictions: u64,
    pub expirations: u64,
}

pub struct DnsCache {
    cache: LruCache<(String, QueryType), CachedResponse>,
    min_ttl: Duration,
    max_ttl: Duration,
    stats: CacheStats,
}

impl DnsCache {
    pub fn new(capacity: usize, min_ttl_secs: u64, max_ttl_secs: u64) -> Self {
        let cap = NonZeroUsize::new(capacity).unwrap_or(NonZeroUsize::new(1024).unwrap());
        Self {
            cache: LruCache::new(cap),
            min_ttl: Duration::from_secs(min_ttl_secs),
            max_ttl: Duration::from_secs(max_ttl_secs),
            stats: CacheStats::default(),
        }
    }

    pub fn get(&mut self, domain: &str, qtype: QueryType) -> Option<DnsPacket> {
        let key = (domain.to_lowercase(), qtype);

        if let Some(entry) = self.cache.get(&key) {
            if entry.is_expired() {
                self.cache.pop(&key);
                self.stats.expirations += 1;
                self.stats.misses += 1;
                return None;
            }

            self.stats.hits += 1;
            let mut response = entry.packet.clone();
            let remaining_ttl = entry.remaining_ttl_secs();

            // Adjust TTL in response answer records to reflect remaining cached TTL
            for answer in &mut response.answers {
                answer.ttl = remaining_ttl;
            }

            return Some(response);
        }

        self.stats.misses += 1;
        None
    }

    pub fn insert(&mut self, domain: &str, qtype: QueryType, packet: DnsPacket) {
        let key = (domain.to_lowercase(), qtype);

        // Determine effective TTL from response answer records
        let raw_ttl = packet
            .answers
            .iter()
            .map(|ans| ans.ttl)
            .min()
            .unwrap_or(300) as u64;

        let effective_ttl = Duration::from_secs(raw_ttl)
            .clamp(self.min_ttl, self.max_ttl);

        let cached = CachedResponse {
            packet,
            query_type: qtype,
            created_at: Instant::now(),
            ttl: effective_ttl,
        };

        if self.cache.len() == self.cache.cap().get() {
            self.stats.evictions += 1;
        }

        self.cache.put(key, cached);
    }

    pub fn stats(&self) -> CacheStats {
        self.stats
    }

    pub fn len(&self) -> usize {
        self.cache.len()
    }

    pub fn is_empty(&self) -> bool {
        self.cache.is_empty()
    }

    pub fn clear(&mut self) {
        self.cache.clear();
    }
}
