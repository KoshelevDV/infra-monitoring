FROM rust:1-slim-bookworm AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo 'fn main(){}' > src/main.rs && \
    cargo build --release && rm -rf src
COPY src ./src
RUN touch src/main.rs && cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates wget && \
    rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/kafka-connect-exporter /usr/local/bin/
EXPOSE 9407
ENV BIND_ADDR=0.0.0.0:9407
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://localhost:9407/health || exit 1
CMD ["kafka-connect-exporter"]
