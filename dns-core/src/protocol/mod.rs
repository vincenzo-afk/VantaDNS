use bytes::BytesMut;
use std::net::Ipv4Addr;
use thiserror::Error;

pub mod header;
pub mod question;
pub mod rr;

pub use header::{DnsHeader, Opcode, ResponseCode};
pub use question::{DnsQuestion, QueryClass, QueryType};
pub use rr::{ResourceData, ResourceRecord};

#[derive(Error, Debug, PartialEq, Eq)]
pub enum DnsError {
    #[error("Buffer too short: {0}")]
    BufferTooShort(&'static str),
    #[error("Invalid domain name: {0}")]
    InvalidDomainName(&'static str),
    #[error("Parse error: {0}")]
    ParseError(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DnsPacket {
    pub header: DnsHeader,
    pub questions: Vec<DnsQuestion>,
    pub answers: Vec<ResourceRecord>,
    pub authorities: Vec<ResourceRecord>,
    pub additionals: Vec<ResourceRecord>,
}

impl DnsPacket {
    pub fn parse(raw_bytes: &[u8]) -> Result<Self, DnsError> {
        let mut cursor = std::io::Cursor::new(raw_bytes);
        let header = DnsHeader::parse(&mut cursor)?;

        let mut questions = Vec::with_capacity(header.qdcount as usize);
        for _ in 0..header.qdcount {
            questions.push(DnsQuestion::parse(&mut cursor)?);
        }

        let mut answers = Vec::with_capacity(header.ancount as usize);
        for _ in 0..header.ancount {
            answers.push(ResourceRecord::parse(&mut cursor)?);
        }

        let mut authorities = Vec::with_capacity(header.nscount as usize);
        for _ in 0..header.nscount {
            authorities.push(ResourceRecord::parse(&mut cursor)?);
        }

        let mut additionals = Vec::with_capacity(header.arcount as usize);
        for _ in 0..header.arcount {
            additionals.push(ResourceRecord::parse(&mut cursor)?);
        }

        Ok(DnsPacket {
            header,
            questions,
            answers,
            authorities,
            additionals,
        })
    }

    pub fn to_bytes(&self) -> BytesMut {
        let mut buf = BytesMut::with_capacity(512);

        let mut header = self.header.clone();
        header.qdcount = self.questions.len() as u16;
        header.ancount = self.answers.len() as u16;
        header.nscount = self.authorities.len() as u16;
        header.arcount = self.additionals.len() as u16;

        header.write_to(&mut buf);

        for q in &self.questions {
            q.write_to(&mut buf);
        }
        for a in &self.answers {
            a.write_to(&mut buf);
        }
        for ns in &self.authorities {
            ns.write_to(&mut buf);
        }
        for ar in &self.additionals {
            ar.write_to(&mut buf);
        }

        buf
    }

    /// Creates a deterministic blocked response packet for an incoming query (either 0.0.0.0 A answer or NXDOMAIN)
    pub fn build_blocked_response(&self, use_nxdomain: bool) -> DnsPacket {
        let mut response = self.clone();
        response.header.is_response = true;

        if use_nxdomain {
            response.header.rcode = ResponseCode::NXDomain;
        } else {
            response.header.rcode = ResponseCode::NoError;
            if let Some(question) = self.questions.first() {
                if question.qtype == QueryType::A {
                    let record = ResourceRecord {
                        name: question.name.clone(),
                        rtype: QueryType::A,
                        rclass: QueryClass::IN,
                        ttl: 10,
                        rdata: ResourceData::A(Ipv4Addr::new(0, 0, 0, 0)),
                    };
                    response.answers.push(record);
                }
            }
        }

        response
    }
}
