use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;
use tokio::net::{TcpListener, UdpSocket};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::Mutex;
use clap::{Parser, Subcommand};
use tracing::{info, warn};

#[cfg(feature = "tls")]
use {
    tokio_rustls::TlsAcceptor,
    tokio_rustls::rustls::{
        ServerConfig as RustlsServerConfig,
        pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer},
    },
    std::io::BufReader,
};

use vanta_dns_core::{
    ServerConfig, DnsPacket, FilterEngine, FilterResult, DnsCache,
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
        Some(Commands::Run { config }) => {
            run_server(&config).await?;
        }
        None => {
            run_server("config/vanta-dns.toml").await?;
        }
    }

    Ok(())
}

async fn run_server(config_path: &str) -> Result<(), Box<dyn std::error::Error>> {
    println!("\n  VantaDNS Rust Core v0.1.0 starting...");
    let config = match ServerConfig::load_from_file(config_path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("ERROR: failed to load config '{}': {}", config_path, e);
            eprintln!("Falling back to built-in defaults.");
            ServerConfig::default()
        }
    };

    println!("  Bind address:     {}", config.bind_addr);
    println!("  Upstream:         {:?}", config.resolve_upstreams().iter().map(|u| format!("{:?} {}", u.transport, u.addr)).collect::<Vec<_>>());
    println!("  Block mode:       {}", config.block_mode);
    println!("  Cache capacity:   {} entries", config.cache_capacity);
    println!("  TCP listener:     {}", if config.tcp_enabled { "ENABLED" } else { "disabled" });
    println!("  TLS listener:     {}", if config.tls_enabled { "ENABLED" } else { "disabled" });

    let mut filter_engine = FilterEngine::new();
    for path in &config.blocklist_paths {
        if let Ok(content) = std::fs::read_to_string(path) {
            let n = filter_engine.load_blocklist_content(&content);
            
            println!("  Loaded {} rules from {}", n, path);
        } else {
            println!("  WARN: could not read blocklist {}", path);
        }
    }
    for path in &config.allowlist_paths {
        if let Ok(content) = std::fs::read_to_string(path) {
            let n = filter_engine.load_allowlist_content(&content);
            println!("  Loaded {} allowlist rules from {}", n, path);
        } else {
            println!("  WARN: could not read allowlist {}", path);
        }
    }
    println!("  Blocklist rules loaded: {} ({} allowlist)", filter_engine.blocklist_rule_count(), filter_engine.allowlist_rule_count());

    let cache = Arc::new(Mutex::new(DnsCache::new(
        config.cache_capacity,
        config.min_ttl_secs,
        config.max_ttl_secs,
    )));

    let forwarder = Arc::new(vanta_dns_core::UpstreamForwarder::with_upstreams(
        config.resolve_upstreams(),
        5,
    ));
    let filter = Arc::new(filter_engine);

    // UDP listener
    let socket = UdpSocket::bind(config.bind_addr).await?;
    println!("  UDP listener ready on {}", config.bind_addr);

    // TCP listener (plain DNS-over-TCP, RFC 1035 framing) — required for DoT
    let tcp_listener = if config.tcp_enabled {
        let l = TcpListener::bind(config.bind_addr).await?;
        println!("  TCP listener ready on {}", config.bind_addr);
        Some(l)
    } else {
        None
    };

    // TLS listener (app-terminated DoT, port 853)
    #[cfg(feature = "tls")]
    let tls_acceptor = if config.tls_enabled {
        build_tls_acceptor(&config).await?
    } else {
        None
    };
    #[cfg(not(feature = "tls"))]
    let tls_acceptor: Option<()> = None;

    println!("  VantaDNS Core is ONLINE and listening.\n");

    // ---------- UDP loop ----------
    let udp_socket = Arc::new(socket);
    let udp_state = Arc::new(DnsServiceState { cache: cache.clone(), forwarder: forwarder.clone(), filter: filter.clone(), block_mode: config.block_mode.clone() });
    let udp_sock = udp_socket.clone();
    let udp_state_clone = udp_state.clone();
    tokio::spawn(async move {
        let mut buf = [0u8; 4096];
        loop {
            let (len, src) = match udp_sock.recv_from(&mut buf).await {
                Ok(res) => res,
                Err(e) => {
                    warn!("UDP recv error: {}", e);
                    continue;
                }
            };
            let query_bytes = buf[..len].to_vec();
            let sock = udp_sock.clone();
            let st = udp_state_clone.clone();
            tokio::spawn(async move {
                if let Some(resp) = resolve_dns_query(&query_bytes, &st).await {
                    let _ = sock.send_to(&resp, src).await;
                }
            });
        }
    });

    // ---------- TCP loop (DNS-over-TCP & DoT) ----------
    if let Some(listener) = tcp_listener {
        let state = udp_state.clone();
        tokio::spawn(async move {
            loop {
                match listener.accept().await {
                    Ok((stream, peer)) => {
                        let state = state.clone();
                        let _ = stream.set_nodelay(true);
                        tokio::spawn(async move {
                            if let Err(e) = serve_tcp_dns(stream, &state).await {
                                warn!("TCP connection {} error: {}", peer, e);
                            }
                        });
                    }
                    Err(e) => warn!("TCP accept error: {}", e),
                }
            }
        });
    }

    // ---------- TLS loop (standalone DoT) ----------
    #[cfg(feature = "tls")]
    if let Some(acceptor) = tls_acceptor {
        // TLS (DoT) binds on its own port (default 853); TCP plaintext listener
        // shares the main bind_addr when the platform terminates TLS for us.
        let tls_host = config.bind_addr.ip();
        let tls_bind: SocketAddr = (tls_host, config.tls_port).into();
        let tls_listener = TcpListener::bind(tls_bind).await?;
        println!("  TLS listener ready on {} (DoT)", tls_bind);
        let state = udp_state.clone();
        let tls_acceptor_clone = acceptor.clone();
        tokio::spawn(async move {
            loop {
                match tls_listener.accept().await {
                    Ok((stream, peer)) => {
                        let acceptor_ref = tls_acceptor_clone.clone();
                        let state = state.clone();
                        tokio::spawn(async move {
                            match acceptor_ref.accept(stream).await {
                                Ok(tls_stream) => {
                                    if let Err(e) = serve_tcp_dns(tls_stream, &state).await {
                                        warn!("TLS connection {} error: {}", peer, e);
                                    }
                                }
                                Err(e) => warn!("TLS handshake failed for {}: {}", peer, e),
                            }
                        });
                    }
                    Err(e) => warn!("TLS accept error: {}", e),
                }
            }
        });
    }

    // Keep the main task alive
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
    }
}

/// Shared state used by UDP, TCP, and TLS handlers.
pub struct DnsServiceState {
    pub cache: Arc<Mutex<DnsCache>>,
    pub forwarder: Arc<vanta_dns_core::UpstreamForwarder>,
    pub filter: Arc<FilterEngine>,
    pub block_mode: String,
}

/// Reply target abstraction: UDP peer socket address.
pub enum DnsReplySink {
    Udp(std::net::SocketAddr),
}

/// Process one DNS query and return the response bytes (or None on upstream failure).
async fn resolve_dns_query(
    query_bytes: &[u8],
    state: &DnsServiceState,
) -> Option<Vec<u8>> {
    let packet = match DnsPacket::parse(query_bytes) {
        Ok(p) => p,
        Err(_) => return None,
    };

    let question = match packet.questions.first() {
        Some(q) => q.clone(),
        None => return None,
    };

    // 1. Check filter
    match state.filter.evaluate(&question.name) {
        FilterResult::Blocked(rule) => {
            info!("BLOCKED {} (matched rule: {})", question.name, rule);
            return Some(packet.build_blocked_response(state.block_mode == "nxdomain").to_bytes().to_vec());
        }
        FilterResult::AllowListMatched(rule) => {
            info!("ALLOWED {} (override rule: {})", question.name, rule);
        }
        FilterResult::Allowed => {}
    }

    // 2. Check cache
    {
        let mut cache_guard = state.cache.lock().await;
        if let Some(cached_resp) = cache_guard.get(&question.name, question.qtype) {
            info!("CACHE HIT {}", question.name);
            return Some(cached_resp.to_bytes().to_vec());
        }
    }

    // 3. Upstream forwarding
    match state.forwarder.forward_raw(query_bytes).await {
        Ok(resp_bytes) => {
            if let Ok(resp_packet) = DnsPacket::parse(&resp_bytes) {
                let mut cache_guard = state.cache.lock().await;
                cache_guard.insert(&question.name, question.qtype, resp_packet);
            }
            Some(resp_bytes)
        }
        Err(e) => {
            warn!("Upstream error for {}: {}", question.name, e);
            None
        }
    }
}

/// Write length-framed DNS response bytes to a writable stream (RFC 1035 §4.2.2).
pub async fn write_framed<W>(
    writer: &mut W,
    bytes: &[u8],
) -> Result<(), Box<dyn std::error::Error + Send + Sync>>
where
    W: AsyncWriteExt + Unpin + Send,
{
    writer.write_all(&(bytes.len() as u16).to_be_bytes()).await?;
    writer.write_all(bytes).await?;
    writer.flush().await?;
    Ok(())
}

/// Serve a TCP/TLS connection: read length-framed DNS messages (RFC 1035 §4.2.2)
/// and write length-framed responses until the client disconnects.
#[cfg(feature = "tls")]
async fn serve_tcp_dns<S>(
    mut stream: S,
    state: &DnsServiceState,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>>
where
    S: AsyncReadExt + AsyncWriteExt + Unpin + Send,
{
    use std::sync::Arc;
    let state = Arc::new(state);
    let mut len_buf = [0u8; 2];
    loop {
        match stream.read_exact(&mut len_buf).await {
            Ok(_) => {}
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(()),
            Err(e) => return Err(Box::new(e)),
        }
        let msg_len = u16::from_be_bytes(len_buf) as usize;
        if msg_len == 0 || msg_len > 65535 {
            return Ok(());
        }
        let mut query = vec![0u8; msg_len];
        stream.read_exact(&mut query).await?;

        // Build a response via the shared handler, then write it framed.
        let packet = match DnsPacket::parse(&query) {
            Ok(p) => p,
            Err(_) => continue,
        };
        let question = match packet.questions.first() {
            Some(q) => q.clone(),
            None => continue,
        };

        // Filter → cache → upstream (same logic as UDP, reply written directly).
        match state.filter.evaluate(&question.name) {
            FilterResult::Blocked(rule) => {
                info!("BLOCKED {} (tcp, matched rule: {})", question.name, rule);
                let blocked = packet.build_blocked_response(state.block_mode == "nxdomain");
                let resp = blocked.to_bytes();
                stream.write_all(&(resp.len() as u16).to_be_bytes()).await?;
                stream.write_all(&resp).await?;
                continue;
            }
            FilterResult::AllowListMatched(rule) => {
                info!("ALLOWED {} (tcp, override rule: {})", question.name, rule);
            }
            FilterResult::Allowed => {}
        }
        {
            let mut cache_guard = state.cache.lock().await;
            if let Some(cached_resp) = cache_guard.get(&question.name, question.qtype) {
                info!("CACHE HIT {} (tcp)", question.name);
                let resp = cached_resp.to_bytes();
                stream.write_all(&(resp.len() as u16).to_be_bytes()).await?;
                stream.write_all(&resp).await?;
                continue;
            }
        }
        match state.forwarder.forward_raw(&query).await {
            Ok(resp_bytes) => {
                stream.write_all(&(resp_bytes.len() as u16).to_be_bytes()).await?;
                stream.write_all(&resp_bytes).await?;
                if let Ok(resp_packet) = DnsPacket::parse(&resp_bytes) {
                    let mut cache_guard = state.cache.lock().await;
                    cache_guard.insert(&question.name, question.qtype, resp_packet);
                }
            }
            Err(e) => {
                warn!("Upstream error for {} (tcp): {}", question.name, e);
                // SERVFAIL keeps the connection alive.
                let mut fail = packet.clone();
                fail.header.is_response = true;
                fail.header.rcode = vanta_dns_core::ResponseCode::ServFail;
                let resp = fail.to_bytes();
                let _ = stream.write_all(&(resp.len() as u16).to_be_bytes()).await;
                let _ = stream.write_all(&resp).await;
            }
        }
        let _ = stream.flush().await;
    }
}

#[cfg(not(feature = "tls"))]
async fn serve_tcp_dns<S>(
    mut stream: S,
    state: &DnsServiceState,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>>
where
    S: AsyncReadExt + AsyncWriteExt + Unpin + Send,
{
    let _ = (stream, state);
    Ok(())
}

#[cfg(feature = "tls")]
async fn build_tls_acceptor(
    config: &ServerConfig,
) -> Result<Option<TlsAcceptor>, Box<dyn std::error::Error>> {
    use std::path::Path;

    let cert_path = config
        .tls_cert_path
        .as_deref()
        .ok_or("TLS cert path missing")?;
    let key_path = config
        .tls_key_path
        .as_deref()
        .ok_or("TLS key path missing")?;

    // Support both real PEM files and a directory containing a self-signed placeholder.
    let cert_file = std::fs::File::open(cert_path)?;
    let key_file = std::fs::File::open(key_path)?;

    let certs: Vec<CertificateDer<'static>> = rustls_pemfile::certs(&mut BufReader::new(cert_file))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("cert parse error: {}", e))?;

    let mut keys = BufReader::new(key_file);
    let mut key_items: Vec<PrivateKeyDer<'static>> = Vec::new();
    loop {
        match rustls_pemfile::read_one(&mut keys) {
            Ok(Some(rustls_pemfile::Item::Pkcs8Key(k))) => key_items.push(PrivateKeyDer::Pkcs8(k)),
            Ok(Some(rustls_pemfile::Item::Pkcs1Key(k))) => key_items.push(PrivateKeyDer::Pkcs1(k)),
            Ok(Some(_)) => continue,
            Ok(None) => break,
            Err(e) => return Err(format!("key parse error: {}", e).into()),
        }
    }

    let key = key_items.into_iter().next().ok_or("no private key found")?;

    let tls_config = RustlsServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)?;

    Ok(Some(TlsAcceptor::from(Arc::new(tls_config))))
}

