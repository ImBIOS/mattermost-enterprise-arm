FROM debian:bookworm-slim

# Some ENV variables
ENV PATH="/mattermost/bin:${PATH}"
ENV MM_INSTALL_TYPE=docker

# Build arguments
ARG PUID=1000
ARG PGID=1000
ARG MM_LISTEN_PORT=8000
ARG MM_VERSION=v11.3.0
ARG GO_VERSION=1.24.11
ARG NODE_VERSION=20.20.0
ARG TARGETOS=linux
ARG TARGETARCH=arm64
ARG MM_EDITION=sourceavailable

# Install runtime and build dependencies
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
	ca-certificates \
	curl \
	jq \
	libcap2 \
	libffi-dev \
	libxml2-dev \
	libxslt1.1 \
	netcat-openbsd \
	tzdata \
	gosu \
	xz-utils \
	autoconf \
	automake \
	libtool \
	wget \
	git \
	make \
	gcc \
	g++ \
	libc6-dev \
	&& rm -rf /var/lib/apt/lists/*

# Install Go
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
		GO_ARCH="arm64"; \
	elif [ "${TARGETARCH}" = "amd64" ]; then \
		GO_ARCH="amd64"; \
	else \
		GO_ARCH="${TARGETARCH}"; \
	fi && \
	wget -q "https://golang.org/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" && \
	tar -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -C /tmp && \
	rm "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" && \
	mv /tmp/go /usr/local/go

ENV GOROOT=/usr/local/go
ENV PATH=$GOROOT/bin:$PATH

# Install Node.js directly
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
		NODE_ARCH="arm64"; \
		NODE_ARCH_DOWNLOAD="arm64"; \
	elif [ "${TARGETARCH}" = "amd64" ]; then \
		NODE_ARCH="x64"; \
		NODE_ARCH_DOWNLOAD="x64"; \
	else \
		NODE_ARCH="${TARGETARCH}"; \
		NODE_ARCH_DOWNLOAD="${TARGETARCH}"; \
	fi && \
	wget -q "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH_DOWNLOAD}.tar.xz" && \
	mkdir -p /usr/local && \
	tar -xJf "node-v${NODE_VERSION}-linux-${NODE_ARCH_DOWNLOAD}.tar.xz" -C /usr/local && \
	rm "node-v${NODE_VERSION}-linux-${NODE_ARCH_DOWNLOAD}.tar.xz" && \
	ln -s "/usr/local/node-v${NODE_VERSION}-linux-${NODE_ARCH_DOWNLOAD}/bin/node" /usr/local/bin/node && \
	ln -s "/usr/local/node-v${NODE_VERSION}-linux-${NODE_ARCH_DOWNLOAD}/bin/npm" /usr/local/bin/npm && \
	ln -s "/usr/local/node-v${NODE_VERSION}-linux-${NODE_ARCH_DOWNLOAD}/bin/npx" /usr/local/bin/npx

ENV PATH=/usr/local/node-v${NODE_VERSION}-linux-${NODE_ARCH_DOWNLOAD}/bin:$PATH

# Create directories
RUN mkdir -p /mattermost/data /mattermost/plugins /mattermost/client-plugins /build

# Clone and build Mattermost from source
WORKDIR /build
RUN git clone --depth 1 --branch ${MM_VERSION} https://github.com/mattermost/mattermost.git mattermost-src

# Clone enterprise repo if building enterprise
WORKDIR /build/mattermost-src
RUN if [ "${MM_EDITION}" = "enterprise" ]; then \
		cd .. && \
		git config --global advice.detachedHead false && \
		git clone --depth 1 https://github.com/mattermost/enterprise.git enterprise 2>/dev/null || \
		echo "Enterprise repo clone failed (rate limit or network issue), using sourceavailable mode"; \
	fi

# Build webapp
WORKDIR /build/mattermost-src/webapp
RUN npm ci --quiet 2>/dev/null || npm install --quiet && \
	npm run build

# Build server
WORKDIR /build/mattermost-src/server
RUN sed -i \
		-e 's#go generate#env --unset=GOOS --unset=GOARCH go generate#' \
		-e 's#$(GO) generate#env --unset=GOOS --unset=GOARCH go generate#' \
		Makefile build/release.mk && \
	if [ -d "../../enterprise" ]; then \
		BUILD_TAGS="enterprise"; \
	else \
		BUILD_TAGS="sourceavailable"; \
	fi && \
	echo "Building with tags: ${BUILD_TAGS}" && \
	make config-reset \
		BUILD_NUMBER="docker-${TARGETOS}-${TARGETARCH}-${MM_VERSION}" \
		GO="${TARGETOS} ${TARGETARCH} $(command -v go)" \
		PLUGIN_PACKAGES='' && \
	make setup-go-work \
		BUILD_NUMBER="docker-${TARGETOS}-${TARGETARCH}-${MM_VERSION}" \
		GO="${TARGETOS} ${TARGETARCH} $(command -v go)" \
		PLUGIN_PACKAGES='' && \
	export GOOS=${TARGETOS} && \
	export GOARCH=${TARGETARCH} && \
	make build-linux package-linux \
		BUILD_NUMBER="docker-${TARGETOS}-${TARGETARCH}-${MM_VERSION}" \
		GO="${TARGETOS} ${TARGETARCH} $(command -v go)" \
		PLUGIN_PACKAGES='' \
		BUILD_TAGS="${BUILD_TAGS}"

# Extract built package
WORKDIR /build
RUN PKG_FILE=$(ls mattermost-src/server/dist/mattermost-*-${TARGETOS}-${TARGETARCH}.tar.gz 2>/dev/null | head -1) && \
	if [ -n "$PKG_FILE" ]; then \
		echo "Found package: $PKG_FILE" && \
		tar -xzf "$PKG_FILE" -C /mattermost && \
		echo "Package contents:" && \
		tar -tzf "$PKG_FILE" | head -15; \
	else \
		echo "ERROR: Build package not found in mattermost-src/server/dist/" && \
		ls -la mattermost-src/server/dist/ 2>/dev/null || echo "dist directory not found"; \
		exit 1; \
	fi

# Setup user and permissions
RUN cp /mattermost/config/config.json /mattermost/config.json.save && \
	rm -rf /mattermost/config/config.json && \
	groupadd -g ${PGID} mattermost && \
	useradd -u ${PUID} -G mattermost -d /mattermost -m mattermost && \
	chown -R mattermost:mattermost /mattermost/config.json.save /mattermost/plugins /mattermost/client-plugins && \
	setcap cap_net_bind_service=+ep /mattermost/bin/mattermost

# Clean up build dependencies to reduce image size
RUN apt-get update -qq && apt-get remove -y \
	wget \
	git \
	make \
	gcc \
	g++ \
	libc6-dev \
	autoconf \
	automake \
	libtool \
	nodejs \
	npm \
	&& rm -rf /build /root/.npm /usr/local/node-v${NODE_VERSION}-linux-${TARGETARCH}

# Configure entrypoint and command
COPY priv-entrypoint.sh /
COPY entrypoint.sh /
ENTRYPOINT ["/priv-entrypoint.sh"]

WORKDIR /mattermost
CMD ["mattermost"]

# Expose port 8000 of the container
EXPOSE $MM_LISTEN_PORT

# Declare volumes for mount point directories
VOLUME ["/mattermost/data", "/mattermost/logs", "/mattermost/config", "/mattermost/plugins", "/mattermost/client-plugins"]
