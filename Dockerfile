# VantaDNS — cloud-ready DNS-over-TLS ad blocker
# Multi-stage build: rust compiler -> minimal static musl binary in scratch
FROM rust:1-bookworm AS builder

WORKDIR /build
COPY dns-core/Cargo.toml dns-core/Cargo.lock* ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs && \
    cargo build --release --bin vanta-dns-core 2>/dev/null || true && rm -rf src

COPY dns-core/ ./
RUN cargo build --release --bin vanta-dns-core

FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -S vanta && adduser -S vanta -G vanta

COPY --from=builder /build/target/release/vanta-dns-core /usr/local/bin/vanta-dns-core
COPY config/blocklists/ /data/blocklists/
COPY allowlists/ /data/allowlists/

# Optional: pull community blocklists (uncomment to enable)
# RUN curl -sSL "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt" -o /data/blocklists/adguard-base.txt

RUN mkdir -p /data/blocklists /data/allowlists && \
    chown -R vanta:vanta /data && \
    chmod 644 /data/blocklists/* /data/allowlists/* 2>/dev/null || true

USER vanta
WORKDIR /data

# DoT port (standard for DNS-over-TLS). On Fly.io the TLS handler terminates
# TLS for us and forwards plaintext to this same port.
EXPOSE 853/tcp

ENTRYPOINT ["/usr/local/bin/vanta-dns-core"]
CMD ["run", "--config", "/data/docker-vanta-dns.toml"]
