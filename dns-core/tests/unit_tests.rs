use std::net::Ipv4Addr;
use vanta_dns_core::{
    DnsPacket, DnsHeader, DnsQuestion, QueryType, QueryClass, ResourceRecord, ResourceData, ResponseCode,
    FilterEngine, FilterResult, DomainTrie, DnsCache, ServerConfig
};

#[test]
fn test_dns_header_pack_unpack() {
    let header = DnsHeader {
        id: 0x1234,
        is_response: true,
        opcode: vanta_dns_core::protocol::Opcode::Query,
        authoritative_answer: false,
        truncated: false,
        recursion_desired: true,
        recursion_available: true,
        rcode: ResponseCode::NoError,
        qdcount: 1,
        ancount: 1,
        nscount: 0,
        arcount: 0,
    };

    let mut buf = bytes::BytesMut::new();
    header.write_to(&mut buf);

    let mut cursor = std::io::Cursor::new(buf.as_ref());
    let parsed = DnsHeader::parse(&mut cursor).expect("Header parse failed");

    assert_eq!(header.id, parsed.id);
    assert_eq!(header.is_response, parsed.is_response);
    assert_eq!(header.recursion_desired, parsed.recursion_desired);
    assert_eq!(header.recursion_available, parsed.recursion_available);
    assert_eq!(header.rcode, parsed.rcode);
}

#[test]
fn test_dns_packet_encode_decode() {
    let packet = DnsPacket {
        header: DnsHeader {
            id: 0xABCD,
            is_response: false,
            opcode: vanta_dns_core::protocol::Opcode::Query,
            authoritative_answer: false,
            truncated: false,
            recursion_desired: true,
            recursion_available: false,
            rcode: ResponseCode::NoError,
            qdcount: 1,
            ancount: 0,
            nscount: 0,
            arcount: 0,
        },
        questions: vec![DnsQuestion {
            name: "google.com".to_string(),
            qtype: QueryType::A,
            qclass: QueryClass::IN,
        }],
        answers: vec![],
        authorities: vec![],
        additionals: vec![],
    };

    let bytes = packet.to_bytes();
    let parsed = DnsPacket::parse(&bytes).expect("DnsPacket parse failed");

    assert_eq!(parsed.header.id, 0xABCD);
    assert_eq!(parsed.questions.len(), 1);
    assert_eq!(parsed.questions[0].name, "google.com");
    assert_eq!(parsed.questions[0].qtype, QueryType::A);
}

#[test]
fn test_filter_engine_allowlist_override() {
    let mut engine = FilterEngine::new();
    engine.load_blocklist_rule("||doubleclick.net^");
    engine.load_allowlist_rule("@@allowed.doubleclick.net");

    // Exact block match
    assert_eq!(engine.evaluate("doubleclick.net"), FilterResult::Blocked("doubleclick.net".to_string()));
    // Subdomain block match
    assert_eq!(engine.evaluate("ad.doubleclick.net"), FilterResult::Blocked("ad.doubleclick.net".to_string()));
    // Allowlist override match
    assert_eq!(engine.evaluate("allowed.doubleclick.net"), FilterResult::AllowListMatched("allowed.doubleclick.net".to_string()));
    // Non-blocked domain
    assert_eq!(engine.evaluate("google.com"), FilterResult::Allowed);
}

#[test]
fn test_domain_trie_normalization() {
    assert_eq!(DomainTrie::normalize("EXAMPLE.COM."), "example.com");
    assert_eq!(DomainTrie::normalize("  Sub.Domain.Org  "), "sub.domain.org");
}

#[test]
fn test_lru_cache_ttl_and_eviction() {
    let mut cache = DnsCache::new(2, 1, 3600);

    let dummy_packet = DnsPacket {
        header: DnsHeader {
            id: 1,
            is_response: true,
            opcode: vanta_dns_core::protocol::Opcode::Query,
            authoritative_answer: false,
            truncated: false,
            recursion_desired: true,
            recursion_available: true,
            rcode: ResponseCode::NoError,
            qdcount: 1,
            ancount: 1,
            nscount: 0,
            arcount: 0,
        },
        questions: vec![DnsQuestion { name: "example.com".to_string(), qtype: QueryType::A, qclass: QueryClass::IN }],
        answers: vec![ResourceRecord {
            name: "example.com".to_string(),
            rtype: QueryType::A,
            rclass: QueryClass::IN,
            ttl: 300,
            rdata: ResourceData::A(Ipv4Addr::new(93, 184, 216, 34)),
        }],
        authorities: vec![],
        additionals: vec![],
    };

    // Test Cache Miss
    assert!(cache.get("example.com", QueryType::A).is_none());

    // Test Cache Insert & Hit
    cache.insert("example.com", QueryType::A, dummy_packet.clone());
    assert!(cache.get("example.com", QueryType::A).is_some());

    // Insert 2 more items to test LRU Eviction (capacity = 2)
    cache.insert("domain2.com", QueryType::A, dummy_packet.clone());
    cache.insert("domain3.com", QueryType::A, dummy_packet.clone());

    // "example.com" should be evicted
    assert!(cache.get("example.com", QueryType::A).is_none());
    assert_eq!(cache.stats().evictions, 1);
}

#[test]
fn test_config_validation() {
    let mut cfg = ServerConfig::default();
    assert!(cfg.validate().is_ok());

    cfg.min_ttl_secs = 1000;
    cfg.max_ttl_secs = 100;
    assert!(cfg.validate().is_err());
}
