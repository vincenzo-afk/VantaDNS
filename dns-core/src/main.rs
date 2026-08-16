use std::sync::Arc;
use std::time::Instant;
use tokio::net::UdpSocket;
use tokio::sync::Mutex;
use clap::{Parser, Subcommand};
use tracing::{info, warn, error};

use vanta_dns_core::{
    ServerConfig, DnsPacket, FilterEngine, FilterResult, DnsCache, UpstreamForwarder, ServiceState, SystemHealth
};

#[derive(Parser)]
#[command(name = "vanta-dns-core")]
#[command(author = "vincenzo-afk <itsmebk2007@gmail.com>")]
#[command(version = "0.1.0")]
#[command(about = "VantaDNS — High-performance, privacy-focused custom Rust DNS filtering engine & caching resolver", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the custom VantaDNS server
    Run {
        #[arg(short, long, default_value = "config/vanta-dns.toml")]
        config: String,
    },
    /// Evaluate a domain against the filtering engine
    TestDomain {
        #[arg(short, long)]
        domain: String,
    },
    /// Validate configuration file syntax
    ValidateConfig {
        #[arg(short, long, default_value = "config/vanta-dns.toml")]
        config: String,
    },
    /// Run internal benchmark suite
    Benchmark,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    let cli = Cli::parse();

    match cli.command {
        Some(Commands::TestDomain { domain }) => {
            let mut engine = FilterEngine::new();
            engine.load_blocklist_rule("||doubleclick.net^");
            engine.load_blocklist_rule("||googlesyndication.com^");
            engine.load_allowlist_rule("@@allowed.doubleclick.net");

            println!("\n  VantaDNS Rule Evaluation for: '{}'", domain);
            match engine.evaluate(&domain) {
                FilterResult::Allowed => println!("  Status: ALLOWED (Passthrough)"),
                FilterResult::AllowListMatched(rule) => println!("  Status: ALLOWED (AllowList matched: {})", rule),
                FilterResult::Blocked(rule) => println!("  Status: BLOCKED (BlockList matched: {})", rule),
            }
            println!();
        }
        Some(Commands::ValidateConfig { config }) => {
            match ServerConfig::load_from_file(&config) {
                Ok(cfg) => println!("\n  ✅ Config file '{}' is valid!\n  Bind: {}\n  Upstream: {}\n  Block mode: {}\n", config, cfg.bind_addr, cfg.upstream_addr, cfg.block_mode),
                Err(e) => {
                    println!("\n  ❌ Config validation failed: {}\n", e);
                    std::process::exit(1);
                }
            }
        }
        Some(Commands::Benchmark) => {
            println!("\n  ========================================================");
            println!("  VantaDNS Rust Core — Filtering Engine Benchmark");
            println!("  ========================================================\n");

            let mut engine = FilterEngine::new();
            for i in 0..100_000 {
                engine.load_blocklist_rule(&format!("||bad-domain-{}.com^", i));
            }
            println!("  Loaded 100,000 blocklist rules into DomainTrie.");

            let start = Instant::now();
            let iterations = 1_000_000;
            for i in 0..iterations {
                let test = if i % 2 == 0 { "sub.bad-domain-5000.com" } else { "clean-domain.org" };
                let _ = engine.evaluate(test);
            }
            let duration = start.elapsed();
            let ops_per_sec = (iterations as f64) / duration.as_secs_f64();

            println!("  Evaluated 1,000,000 domain lookups in {:.3?} ({:.0} ops/sec)", duration, ops_per_sec);
            println!("  Average lookup latency: {:.2} ns per domain\n", (duration.as_nanos() as f64) / (iterations as f64));
        }
        Some(Commands::Run { config }) | None => {
            println!("\n  VantaDNS Rust Core v0.1.0 starting...");
            let config = ServerConfig::load_from_file(&config).unwrap_or_default();
            
            println!("  Bind address:     {}", config.bind_addr);
            println!("  Upstream:         {}", config.upstream_addr);
            println!("  Block mode:       {}", config.block_mode);
            println!("  Cache capacity:   {} entries", config.cache_capacity);
            
            let mut filter_engine = FilterEngine::new();
            for path in &config.blocklist_paths {
                if let Ok(content) = std::fs::read_to_string(path) {
                    let n = filter_engine.load_blocklist_content(&content);
                    println!("  Loaded {} rules from {}", n, path);
                }
            }

            let cache = Arc::new(Mutex::new(DnsCache::new(
                config.cache_capacity,
                config.min_ttl_secs,
                config.max_ttl_secs,
            )));

            let forwarder = UpstreamForwarder::new(config.upstream_addr, 5);
            let filter = Arc::new(filter_engine);

            println!("  VantaDNS Core is ONLINE and listening.\n");
            
            let socket = UdpSocket::bind(config.bind_addr).await?;
            let mut buf = [0u8; 4096];

            loop {
                let (len, src) = match socket.recv_from(&mut buf).await {
                    Ok(res) => res,
                    Err(e) => {
                        warn!("UDP recv error: {}", e);
                        continue;
                    }
                };

                let query_bytes = &buf[..len];
                let packet = match DnsPacket::parse(query_bytes) {
                    Ok(p) => p,
                    Err(_) => continue,
                };

                let question = match packet.questions.first() {
                    Some(q) => q.clone(),
                    None => continue,
                };

                // 1. Check Filter
                match filter.evaluate(&question.name) {
                    FilterResult::Blocked(rule) => {
                        info!("BLOCKED {} (matched rule: {})", question.name, rule);
                        let blocked_pkt = packet.build_blocked_response(config.block_mode == "nxdomain");
                        let _ = socket.send_to(&blocked_pkt.to_bytes(), src).await;
                        continue;
                    }
                    FilterResult::AllowListMatched(rule) => {
                        info!("ALLOWED {} (override rule: {})", question.name, rule);
                    }
                    FilterResult::Allowed => {}
                }

                // 2. Check Cache
                {
                    let mut cache_guard = cache.lock().await;
                    if let Some(cached_resp) = cache_guard.get(&question.name, question.qtype) {
                        info!("CACHE HIT {}", question.name);
                        let _ = socket.send_to(&cached_resp.to_bytes(), src).await;
                        continue;
                    }
                }

                // 3. Upstream Forwarding
                match forwarder.forward_raw(query_bytes).await {
                    Ok(resp_bytes) => {
                        let _ = socket.send_to(&resp_bytes, src).await;
                        if let Ok(resp_packet) = DnsPacket::parse(&resp_bytes) {
                            let mut cache_guard = cache.lock().await;
                            cache_guard.insert(&question.name, question.qtype, resp_packet);
                        }
                    }
                    Err(e) => {
                        warn!("Upstream error for {}: {}", question.name, e);
                    }
                }
            }
        }
    }

    Ok(())
}
