FROM rust:1-alpine AS planner
WORKDIR /app
COPY Cargo.toml ./
COPY src ./src
RUN cargo install cargo-chef --locked && cargo chef prepare --recipe-path recipe.json

FROM rust:1-alpine AS builder
WORKDIR /app
RUN apk add --no-cache \
    pkgconfig \
    libressl-dev \
    sqlite-dev \
    musl-dev
RUN cargo install cargo-chef --locked
COPY --from=planner /app/recipe.json ./
RUN cargo chef cook --release --recipe-path recipe.json

COPY . .
RUN cargo build --release

# Runtime image - Alpine for minimal size
FROM alpine:3.20

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    sqlite \
    openssl

# Create non-root user
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -s /bin/sh -D appuser

# Create data directory
RUN mkdir -p /data && chown appuser:appgroup /data

# Copy binary from builder
COPY --from=builder /app/target/release/mattermost-telemetry /usr/local/bin/

# Set environment variables
ENV SERVER_ADDRESS=0.0.0.0:8080
ENV DATABASE_URL=sqlite:///data/telemetry.db

# Switch to non-root user
USER 1000:1000

# Work directory
WORKDIR /data

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["mattermost-telemetry"]

# Run the application
CMD ["mattermost-telemetry"]
