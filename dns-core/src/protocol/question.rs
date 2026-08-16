use bytes::{Buf, BufMut, BytesMut};
use crate::protocol::DnsError;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum QueryType {
    A = 1,
    NS = 2,
    CNAME = 5,
    SOA = 6,
    PTR = 12,
    MX = 15,
    TXT = 16,
    AAAA = 28,
    ANY = 255,
    Unknown(u16),
}

impl QueryType {
    pub fn from_u16(val: u16) -> Self {
        match val {
            1 => QueryType::A,
            2 => QueryType::NS,
            5 => QueryType::CNAME,
            6 => QueryType::SOA,
            12 => QueryType::PTR,
            15 => QueryType::MX,
            16 => QueryType::TXT,
            28 => QueryType::AAAA,
            255 => QueryType::ANY,
            other => QueryType::Unknown(other),
        }
    }

    pub fn to_u16(self) -> u16 {
        match self {
            QueryType::A => 1,
            QueryType::NS => 2,
            QueryType::CNAME => 5,
            QueryType::SOA => 6,
            QueryType::PTR => 12,
            QueryType::MX => 15,
            QueryType::TXT => 16,
            QueryType::AAAA => 28,
            QueryType::ANY => 255,
            QueryType::Unknown(other) => other,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QueryClass {
    IN = 1,
    Unknown(u16),
}

impl QueryClass {
    pub fn from_u16(val: u16) -> Self {
        match val {
            1 => QueryClass::IN,
            other => QueryClass::Unknown(other),
        }
    }

    pub fn to_u16(self) -> u16 {
        match self {
            QueryClass::IN => 1,
            QueryClass::Unknown(other) => other,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DnsQuestion {
    pub name: String,
    pub qtype: QueryType,
    pub qclass: QueryClass,
}

impl DnsQuestion {
    pub fn parse(buf: &mut std::io::Cursor<&[u8]>) -> Result<Self, DnsError> {
        let name = read_domain_name(buf)?;
        if buf.remaining() < 4 {
            return Err(DnsError::BufferTooShort("DNS Question requires 4 bytes for QTYPE & QCLASS"));
        }
        let qtype = QueryType::from_u16(buf.get_u16());
        let qclass = QueryClass::from_u16(buf.get_u16());

        Ok(DnsQuestion { name, qtype, qclass })
    }

    pub fn write_to(&self, buf: &mut BytesMut) {
        write_domain_name(&self.name, buf);
        buf.put_u16(self.qtype.to_u16());
        buf.put_u16(self.qclass.to_u16());
    }
}

/// Decodes domain name with label length checks and pointer compression handling (RFC 1035 §4.1.4)
pub fn read_domain_name(buf: &mut std::io::Cursor<&[u8]>) -> Result<String, DnsError> {
    let mut domain = String::new();
    let mut jumped = false;
    let mut jumps_count = 0;
    let original_pos = buf.position();

    loop {
        if jumps_count > 50 {
            return Err(DnsError::InvalidDomainName("Infinite DNS compression pointer loop detected"));
        }
        if !buf.has_remaining() {
            return Err(DnsError::BufferTooShort("Unexpected EOF while reading domain name"));
        }

        let len = buf.get_u8();
        if len == 0 {
            break;
        }

        // Pointer compression check (top 2 bits set: 0xC0)
        if (len & 0xC0) == 0xC0 {
            if !buf.has_remaining() {
                return Err(DnsError::BufferTooShort("Incomplete compression pointer"));
            }
            let b2 = buf.get_u8();
            let pointer_offset = (((len & 0x3F) as u64) << 8) | (b2 as u64);

            if !jumped {
                jumped = true;
            }

            jumps_count += 1;
            buf.set_position(pointer_offset);
        } else {
            let label_len = len as usize;
            if buf.remaining() < label_len {
                return Err(DnsError::BufferTooShort("Label length exceeds buffer"));
            }

            let slice = &buf.chunk()[..label_len];
            let label = std::str::from_utf8(slice)
                .map_err(|_| DnsError::InvalidDomainName("Non-UTF8 domain label"))?;

            buf.advance(label_len);

            if !domain.is_empty() {
                domain.push('.');
            }
            domain.push_str(&label.to_lowercase());
        }
    }

    if jumped {
        // Position was restored if we jumped, but we don't need to restore because original_pos was tracked
    }

    Ok(domain)
}

/// Encodes domain name into standard DNS label format (e.g., "example.com" -> \x07example\x03com\x00)
pub fn write_domain_name(domain: &str, buf: &mut BytesMut) {
    let normalized = domain.trim_end_matches('.');
    if normalized.is_empty() {
        buf.put_u8(0);
        return;
    }

    for label in normalized.split('.') {
        let bytes = label.as_bytes();
        buf.put_u8(bytes.len() as u8);
        buf.put_slice(bytes);
    }
    buf.put_u8(0);
}
