use crate::protocol::DnsError;
use bytes::{Buf, BufMut, BytesMut};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Opcode {
    Query = 0,
    IQuery = 1,
    Status = 2,
    Reserved = 3,
}

impl Opcode {
    pub fn from_u8(val: u8) -> Self {
        match val {
            0 => Opcode::Query,
            1 => Opcode::IQuery,
            2 => Opcode::Status,
            _ => Opcode::Reserved,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResponseCode {
    NoError = 0,
    FormErr = 1,
    ServFail = 2,
    NXDomain = 3,
    NotImp = 4,
    Refused = 5,
}

impl ResponseCode {
    pub fn from_u8(val: u8) -> Self {
        match val {
            0 => ResponseCode::NoError,
            1 => ResponseCode::FormErr,
            2 => ResponseCode::ServFail,
            3 => ResponseCode::NXDomain,
            4 => ResponseCode::NotImp,
            5 => ResponseCode::Refused,
            _ => ResponseCode::ServFail,
        }
    }

    pub fn to_u8(self) -> u8 {
        self as u8
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DnsHeader {
    pub id: u16,
    pub is_response: bool,
    pub opcode: Opcode,
    pub authoritative_answer: bool,
    pub truncated: bool,
    pub recursion_desired: bool,
    pub recursion_available: bool,
    pub rcode: ResponseCode,
    pub qdcount: u16,
    pub ancount: u16,
    pub nscount: u16,
    pub arcount: u16,
}

impl DnsHeader {
    pub fn parse(buf: &mut impl Buf) -> Result<Self, DnsError> {
        if buf.remaining() < 12 {
            return Err(DnsError::BufferTooShort("DNS header requires 12 bytes"));
        }

        let id = buf.get_u16();
        let flags = buf.get_u16();

        let is_response = (flags & 0x8000) != 0;
        let opcode = Opcode::from_u8(((flags >> 11) & 0x0F) as u8);
        let authoritative_answer = (flags & 0x0400) != 0;
        let truncated = (flags & 0x0200) != 0;
        let recursion_desired = (flags & 0x0100) != 0;
        let recursion_available = (flags & 0x0080) != 0;
        let rcode = ResponseCode::from_u8((flags & 0x000F) as u8);

        let qdcount = buf.get_u16();
        let ancount = buf.get_u16();
        let nscount = buf.get_u16();
        let arcount = buf.get_u16();

        Ok(DnsHeader {
            id,
            is_response,
            opcode,
            authoritative_answer,
            truncated,
            recursion_desired,
            recursion_available,
            rcode,
            qdcount,
            ancount,
            nscount,
            arcount,
        })
    }

    pub fn write_to(&self, buf: &mut BytesMut) {
        buf.put_u16(self.id);

        let mut flags: u16 = 0;
        if self.is_response {
            flags |= 0x8000;
        }
        flags |= ((self.opcode as u16) & 0x0F) << 11;
        if self.authoritative_answer {
            flags |= 0x0400;
        }
        if self.truncated {
            flags |= 0x0200;
        }
        if self.recursion_desired {
            flags |= 0x0100;
        }
        if self.recursion_available {
            flags |= 0x0080;
        }
        flags |= (self.rcode.to_u8() as u16) & 0x000F;

        buf.put_u16(flags);
        buf.put_u16(self.qdcount);
        buf.put_u16(self.ancount);
        buf.put_u16(self.nscount);
        buf.put_u16(self.arcount);
    }
}
