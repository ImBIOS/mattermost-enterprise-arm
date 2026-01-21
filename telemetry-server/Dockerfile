FROM rust:1.92-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache \
    pkgconfig \
    libressl-dev \
    sqlite-dev \
    musl-dev \
    cargo

# Copy dependency files first for better caching
COPY Cargo.toml ./
COPY src ./src
RUN mkdir -p src && touch src/lib.rs

# Build dependencies
RUN cargo build --release

# Build the application
COPY src ./src
RUN cargo build --release

# Runtime image
FROM alpine:3.22

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl \
    sqlite-libs

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
    CMD curl -f http://localhost:8080/health || exit 1

# Run the application
CMD ["mattermost-telemetry"]
