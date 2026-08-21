use crate::protocol::{
    question::{read_domain_name, write_domain_name, QueryClass, QueryType},
    DnsError,
};
use bytes::{Buf, BufMut, BytesMut};
use std::net::{Ipv4Addr, Ipv6Addr};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ResourceData {
    A(Ipv4Addr),
    AAAA(Ipv6Addr),
    CNAME(String),
    MX { preference: u16, exchange: String },
    TXT(Vec<String>),
    Raw(Vec<u8>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResourceRecord {
    pub name: String,
    pub rtype: QueryType,
    pub rclass: QueryClass,
    pub ttl: u32,
    pub rdata: ResourceData,
}

impl ResourceRecord {
    pub fn parse(buf: &mut std::io::Cursor<&[u8]>) -> Result<Self, DnsError> {
        let name = read_domain_name(buf)?;
        if buf.remaining() < 10 {
            return Err(DnsError::BufferTooShort(
                "ResourceRecord header requires 10 bytes",
            ));
        }

        let rtype = QueryType::from_u16(buf.get_u16());
        let rclass = QueryClass::from_u16(buf.get_u16());
        let ttl = buf.get_u32();
        let rdlength = buf.get_u16() as usize;

        if buf.remaining() < rdlength {
            return Err(DnsError::BufferTooShort(
                "RDATA length exceeds remaining buffer",
            ));
        }

        let rdata = match rtype {
            QueryType::A if rdlength == 4 => {
                let mut octets = [0u8; 4];
                buf.copy_to_slice(&mut octets);
                ResourceData::A(Ipv4Addr::from(octets))
            }
            QueryType::AAAA if rdlength == 16 => {
                let mut octets = [0u8; 16];
                buf.copy_to_slice(&mut octets);
                ResourceData::AAAA(Ipv6Addr::from(octets))
            }
            QueryType::CNAME => {
                let cname = read_domain_name(buf)?;
                ResourceData::CNAME(cname)
            }
            QueryType::MX if rdlength >= 3 => {
                let preference = buf.get_u16();
                let exchange = read_domain_name(buf)?;
                ResourceData::MX {
                    preference,
                    exchange,
                }
            }
            QueryType::TXT => {
                let mut txts = Vec::new();
                let mut read = 0;
                while read < rdlength {
                    let len = buf.get_u8() as usize;
                    read += 1 + len;
                    let mut txt_buf = vec![0u8; len];
                    buf.copy_to_slice(&mut txt_buf);
                    let txt_str = String::from_utf8_lossy(&txt_buf).to_string();
                    txts.push(txt_str);
                }
                ResourceData::TXT(txts)
            }
            _ => {
                let mut raw = vec![0u8; rdlength];
                buf.copy_to_slice(&mut raw);
                ResourceData::Raw(raw)
            }
        };

        Ok(ResourceRecord {
            name,
            rtype,
            rclass,
            ttl,
            rdata,
        })
    }

    pub fn write_to(&self, buf: &mut BytesMut) {
        write_domain_name(&self.name, buf);
        buf.put_u16(self.rtype.to_u16());
        buf.put_u16(self.rclass.to_u16());
        buf.put_u32(self.ttl);

        match &self.rdata {
            ResourceData::A(ip) => {
                buf.put_u16(4);
                buf.put_slice(&ip.octets());
            }
            ResourceData::AAAA(ip) => {
                buf.put_u16(16);
                buf.put_slice(&ip.octets());
            }
            ResourceData::CNAME(cname) => {
                let mut temp = BytesMut::new();
                write_domain_name(cname, &mut temp);
                buf.put_u16(temp.len() as u16);
                buf.put_slice(&temp);
            }
            ResourceData::MX {
                preference,
                exchange,
            } => {
                let mut temp = BytesMut::new();
                temp.put_u16(*preference);
                write_domain_name(exchange, &mut temp);
                buf.put_u16(temp.len() as u16);
                buf.put_slice(&temp);
            }
            ResourceData::TXT(txts) => {
                let mut temp = BytesMut::new();
                for txt in txts {
                    let bytes = txt.as_bytes();
                    temp.put_u8(bytes.len() as u8);
                    temp.put_slice(bytes);
                }
                buf.put_u16(temp.len() as u16);
                buf.put_slice(&temp);
            }
            ResourceData::Raw(raw) => {
                buf.put_u16(raw.len() as u16);
                buf.put_slice(raw);
            }
        }
    }
}
