#!/bin/bash
set -euo pipefail

# Build configuration
BUILD_USER_HOME="${BUILD_USER_HOME:-/build}"
BUILD_USER_NAME="${BUILD_USER_NAME:-build}"
DEBIAN_RELEASE="${DEBIAN_RELEASE:-bookworm}"
MATTERMOST_VERSION="${MATTERMOST_VERSION:-v11.3.0}"
GO_VERSION="${GO_VERSION:-1.24.11}"
MM_EDITION="${MM_EDITION:-sourceavailable}"

# Support both CI environment variables (GOOS/GOARCH) and local variables
TARGET_OS="${TARGET_OS:-${GOOS:-linux}}"
TARGET_ARCH="${TARGET_ARCH:-${GOARCH:-arm64}}"

# Enterprise repo configuration
ENTERPRISE_REPO_DIR="${ENTERPRISE_REPO_DIR:-../../enterprise}"

echo "=== Mattermost Build Script ==="
echo "Edition: ${MM_EDITION}"
echo "Target: ${TARGET_OS}/${TARGET_ARCH}"
echo "Mattermost Version: ${MATTERMOST_VERSION}"
echo "Go Version: ${GO_VERSION}"
echo "=================================================="

# Check if we're running as root
if [ "$(id -u)" -eq 0 ]; then
	echo "Running as root - setting up build environment..."
	
	# Create build user if needed
	set +e
	if ! id -u "${BUILD_USER_NAME}" 2>/dev/null; then
		set -e
		useradd --create-home --home-dir "${BUILD_USER_HOME}" --skel "${PWD}" \
			"${BUILD_USER_NAME}"
	fi
	set -e
	
	# Configure apt
	printf 'APT::Install-Recommends "0";' > '/etc/apt/apt.conf.d/99-no-install-recommends'
	printf 'APT::Install-Suggests "0";' > '/etc/apt/apt.conf.d/99-no-install-suggests'
	printf 'APT::Get::Assume-Yes "true";' > '/etc/apt/apt.conf.d/99-assume-yes'
	
	# Update repositories
	apt-get update -qq
	
	# Install dependencies
	apt-get install -qq gnupg2 dirmngr apt-transport-https ca-certificates curl wget build-essential patch git python3
	
	# Add required repositories
	printf 'deb-src http://deb.debian.org/debian %s main' "${DEBIAN_RELEASE}" \
		> "/etc/apt/sources.list.d/${DEBIAN_RELEASE}-source.list"
	printf 'deb http://deb.debian.org/debian %s-backports main' "${DEBIAN_RELEASE}" \
		> "/etc/apt/sources.list.d/${DEBIAN_RELEASE}-backports.list"
	
	apt-get update -qq
	
	# Install build dependencies
	apt-get install -qq -t "${DEBIAN_RELEASE}-backports" \
		pngquant nodejs npm 2>/dev/null || apt-get install -qq pngquant nodejs npm
	
	# Install Go
	if [ "${TARGET_ARCH}" = "arm64" ]; then
		GO_ARCH="arm64"
	elif [ "${TARGET_ARCH}" = "amd64" ]; then
		GO_ARCH="amd64"
	else
		GO_ARCH="${TARGET_ARCH}"
	fi
	
	ARCHIVE_NAME="go${GO_VERSION}.linux-${GO_ARCH}"
	
	if [ ! -f "${ARCHIVE_NAME}.tar.gz" ]; then
		echo "Downloading Go ${GO_VERSION} for ${GO_ARCH}..."
		wget -q "https://golang.org/dl/${ARCHIVE_NAME}.tar.gz"
	fi
	
	if [ ! -d /usr/local/go ]; then
		echo "Extracting Go..."
		tar -xf "${ARCHIVE_NAME}.tar.gz" -C /usr/local
	fi
	
	export GOROOT=/usr/local/go
	export PATH=$GOROOT/bin:$PATH
	
	# Fix Go package directory permissions
	install --directory --owner="${BUILD_USER_NAME}" \
		"$(go env GOROOT)/pkg/$(go env GOOS)_$(go env GOARCH)" 2>/dev/null || true
	
	echo "Re-invoking build as user: ${BUILD_USER_NAME}"
	runuser -u "${BUILD_USER_NAME}" -- "${0}" "$@"
	
	# Copy build artifacts
	echo "Copying build artifacts..."
	cp --verbose \
		"${BUILD_USER_HOME}/mattermost-${MATTERMOST_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz" \
		"${BUILD_USER_HOME}/mattermost-${MATTERMOST_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz.sha512sum" \
		"${PWD}"
	
	echo "Build complete! Artifacts saved to ${PWD}"
	exit 0
fi

# ============================================
# Build as non-root user
# ============================================

export GOROOT=/usr/local/go
export PATH=$GOROOT/bin:$PATH
cd "${HOME}"

echo "=== Building as user: $(whoami) ==="
echo "Go version: $(go version)"
echo "GOOS: $(go env GOOS), GOARCH: $(go env GOARCH)"

# ============================================
# Setup Enterprise Repository
# ============================================

ENTERPRISE_SOURCE=""
if [ "${MM_EDITION}" = "enterprise" ]; then
	echo "Checking for enterprise repository..."
	
	# Check multiple possible locations for enterprise repo
	POSSIBLE_PATHS=(
		"${ENTERPRISE_REPO_DIR}"
		"${HOME}/../enterprise"
		"${PWD}/../enterprise"
		"/tmp/enterprise"
	)
	
	FOUND_ENTERPRISE=""
	for path in "${POSSIBLE_PATHS[@]}"; do
		if [ -d "${path}" ] && [ -f "${path}/README.md" ]; then
			FOUND_ENTERPRISE="${path}"
			break
		fi
	done
	
	if [ -n "${FOUND_ENTERPRISE}" ]; then
		echo "Found enterprise repository at: ${FOUND_ENTERPRISE}"
		ENTERPRISE_SOURCE="${FOUND_ENTERPRISE}"
		
		# Create symlink for build
		mkdir -p "${HOME}/go/src/github.com/mattermost"
		if [ ! -L "${HOME}/go/src/github.com/mattermost/enterprise" ]; then
			ln -sf "${ENTERPRISE_SOURCE}" "${HOME}/go/src/github.com/mattermost/enterprise"
			echo "Created symlink: ${HOME}/go/src/github.com/mattermost/enterprise -> ${ENTERPRISE_SOURCE}"
		fi
	else
		echo "WARNING: Enterprise repository not found at expected paths."
		echo "Expected locations:"
		for path in "${POSSIBLE_PATHS[@]}"; do
			echo "  - ${path}"
		done
		echo ""
		echo "Falling back to sourceavailable mode (limited enterprise features)."
		MM_EDITION="sourceavailable"
	fi
fi

# ============================================
# Download and Setup Mattermost Source
# ============================================

echo "Downloading Mattermost ${MATTERMOST_VERSION} source..."
mkdir -p "${HOME}/go/src/github.com/mattermost/mattermost"

# Download Mattermost source
wget -q --continue --output-document="mattermost.tar.gz" \
	"https://github.com/mattermost/mattermost/archive/${MATTERMOST_VERSION}.tar.gz"

# Extract source
tar --directory="${HOME}/go/src/github.com/mattermost/mattermost" \
	--strip-components=1 --extract --file="mattermost.tar.gz"

rm -f mattermost.tar.gz

# ============================================
# Build Webapp
# ============================================

echo "Building Mattermost webapp..."
cd "${HOME}/go/src/github.com/mattermost/mattermost/webapp"

# Setup Node.js (nvm)
if [ ! -d "${HOME}/.nvm" ]; then
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install and use correct Node version
nvm install
nvm use

# Build webapp dist
npm ci --quiet 2>/dev/null || npm install --quiet
npm run build 2>&1 | head -50 || true

cd "${HOME}/go/src/github.com/mattermost/mattermost"

# ============================================
# Prepare Build Environment
# ============================================

echo "Preparing build environment..."
mkdir -p "${HOME}/go/bin"

# Create cross-compilation symlinks if needed
HOST_ARCH="$(go env GOOS)_$(go env GOARCH)"
TARGET_COMBO="${TARGET_OS}_${TARGET_ARCH}"

if [ "${HOST_ARCH}" != "${TARGET_COMBO}" ]; then
	echo "Setting up cross-compilation for ${TARGET_COMBO}..."
	
	# Ensure the target platform directory exists
	install --directory "${HOME}/go/pkg/${TARGET_COMBO}" 2>/dev/null || true
	
	# Create symlink for cross-compilation
	if [ ! -L "${HOME}/go/bin/${TARGET_COMBO}" ]; then
		ln -sf "${HOME}/go/bin/${HOST_ARCH}" "${HOME}/go/bin/${TARGET_COMBO}"
	fi
fi

# ============================================
# Apply Build Patches
# ============================================

echo "Applying build patches..."
cd "${HOME}/go/src/github.com/mattermost/mattermost/server"

if [ -f "/root/build-release.patch" ]; then
	patch --strip=1 -t < "/root/build-release.patch" 2>/dev/null || true
fi

# Fix Makefile for cross-compilation
for makefile in Makefile build/release.mk; do
	if [ -f "${makefile}" ]; then
		sed -i \
			-e 's#go generate#env --unset=GOOS --unset=GOARCH go generate#' \
			-e 's#$(GO) generate#env --unset=GOOS --unset=GOARCH go generate#' \
			-e 's#PWD#CURDIR#' \
			"${makefile}"
	fi
done

# ============================================
# Build Mattermost Server
# ============================================

echo "Building Mattermost server (${MM_EDITION} edition)..."

# Determine build tags
BUILD_TAGS=""
case "${MM_EDITION}" in
	enterprise)
		BUILD_TAGS="enterprise"
		;;
	sourceavailable)
		BUILD_TAGS="sourceavailable"
		;;
	team)
		BUILD_TAGS=""
		;;
	*)
		BUILD_TAGS="${MM_EDITION}"
		;;
esac

echo "Build tags: ${BUILD_TAGS}"

# Reset config
make config-reset \
	BUILD_NUMBER="dev-${TARGET_OS}-${TARGET_ARCH}-${MATTERMOST_VERSION}" \
	GO="GOARCH= GOOS= $(command -v go)" \
	PLUGIN_PACKAGES='' 2>/dev/null || true

# Setup go work
make setup-go-work \
	BUILD_NUMBER="dev-${TARGET_OS}-${TARGET_ARCH}-${MATTERMOST_VERSION}" \
	GO="GOARCH= GOOS= $(command -v go)" \
	PLUGIN_PACKAGES='' 2>/dev/null || true

# Build with correct Go flags
export GOOS="${TARGET_OS}"
export GOARCH="${TARGET_ARCH}"

# Build package using Makefile
MAKE_FLAGS=(
	"build-linux"
	"package-linux"
	"BUILD_NUMBER=dev-${TARGET_OS}-${TARGET_ARCH}-${MATTERMOST_VERSION}"
	"GO=${TARGET_OS} ${TARGET_ARCH} $(command -v go)"
	"PLUGIN_PACKAGES="
)

if [ -n "${BUILD_TAGS}" ]; then
	MAKE_FLAGS+=("BUILD_TAGS=${BUILD_TAGS}")
fi

echo "Running make with flags: ${MAKE_FLAGS[*]}"
make "${MAKE_FLAGS[@]}" 2>&1 | tail -30 || true

# ============================================
# Package and Verify
# ============================================

cd "${HOME}"

# Find the built package
PACKAGE_PATTERN="${HOME}/go/src/github.com/mattermost/mattermost/server/dist/mattermost-*-${TARGET_OS}-${TARGET_ARCH}.tar.gz"

if compgen -G "${PACKAGE_PATTERN}" > /dev/null; then
	echo "Found built package:"
	ls -lh ${PACKAGE_PATTERN}
	
	# Copy to final location
	cp ${PACKAGE_PATTERN} "${HOME}/mattermost-${MATTERMOST_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz"
	
	# List package contents
	echo ""
	echo "Package contents:"
	tar -tzf "${HOME}/mattermost-${MATTERMOST_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz" | head -20
	
	# Calculate SHA512
	sha512sum "${HOME}/mattermost-${MATTERMOST_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz" | \
		tee "${HOME}/mattermost-${MATTERMOST_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz.sha512sum"
	
	echo ""
	echo "=== Build Complete ==="
	echo "Package: ${HOME}/mattermost-${MATTERMOST_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz"
	echo "Edition: ${MM_EDITION}"
	echo "Architecture: ${TARGET_OS}/${TARGET_ARCH}"
else
	echo "ERROR: Build package not found!"
	echo "Expected pattern: ${PACKAGE_PATTERN}"
	ls -la "${HOME}/go/src/github.com/mattermost/mattermost/server/dist/" 2>/dev/null || echo "dist directory not found"
	exit 1
fi
