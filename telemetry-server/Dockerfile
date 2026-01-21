FROM rust:1-alpine AS planner
WORKDIR /app
RUN apk add --no-cache cargo-chef
COPY Cargo.toml ./
COPY src ./src
RUN mkdir -p src && touch src/lib.rs
RUN cargo-chef prepare --recipe recipe.json

FROM rust:1-alpine AS builder
WORKDIR /app
RUN apk add --no-cache \
    pkgconfig \
    libressl-dev \
    sqlite-dev \
    musl-dev
COPY --from=planner /app/recipe.json ./
RUN cargo-chef cook --release

COPY . .
RUN cargo build --release

# Runtime image - distroless for minimal size
FROM gcr.io/distroless/cc-debian12:nonroot

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    sqlite3 \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -g 1000 appgroup && \
    useradd -u 1000 -G appgroup -s /bin/sh appuser

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
