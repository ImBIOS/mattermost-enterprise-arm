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

# Detect host architecture for Go binary (what we're running on)
# This is different from TARGET_ARCH when cross-compiling
HOST_ARCH=$(uname -m)
case "${HOST_ARCH}" in
    x86_64)
        HOST_GO_ARCH="amd64"
        ;;
    aarch64|arm64)
        HOST_GO_ARCH="arm64"
        ;;
    armv7l|armhf)
        HOST_GO_ARCH="arm"
        ;;
    armv6l)
        HOST_GO_ARCH="arm"
        ;;
    *)
        HOST_GO_ARCH="${HOST_ARCH}"
        ;;
esac

echo "Host architecture: ${HOST_ARCH} (using Go ${HOST_GO_ARCH})"
echo "Target architecture: ${TARGET_ARCH}"

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

    # Clean up any previous failed Go installation
    if [ -d /usr/local/go ]; then
        echo "Removing previous Go installation..."
        rm -rf /usr/local/go
    fi

    # Install Go for the HOST architecture (not target)
    # We cross-compile using GOOS/GOARCH environment variables
    ARCHIVE_NAME="go${GO_VERSION}.linux-${HOST_GO_ARCH}"

    # Check if Go version exists, fall back if needed
    if ! wget -q --spider "https://go.dev/dl/${ARCHIVE_NAME}.tar.gz" 2>/dev/null; then
        echo "Go ${GO_VERSION} for ${HOST_GO_ARCH} not available, checking for alternatives..."
        # Try 1.23.x as fallback (1.24 may not be available yet, and go.mod requires 1.24)
        # Since go.mod requires 1.24.x, we need to ensure we install a compatible version
        for fallback_version in 1.24.11 1.24.10 1.24.9 1.24.8 1.24.7 1.24.6 1.24.5 1.24.4 1.24.3 1.24.2 1.24.1 1.24.0; do
            fallback_archive="go${fallback_version}.linux-${HOST_GO_ARCH}"
            if wget -q --spider "https://go.dev/dl/${fallback_archive}.tar.gz" 2>/dev/null; then
                echo "Using fallback Go version: ${fallback_version}"
                GO_VERSION="${fallback_version}"
                ARCHIVE_NAME="${fallback_archive}"
                break
            fi
        done
    fi

    if [ ! -f "${ARCHIVE_NAME}.tar.gz" ]; then
        echo "Downloading Go ${GO_VERSION} for host architecture (${HOST_GO_ARCH})..."
        # Use golang.org download URL directly (more reliable)
        # go.dev/dl redirects to the actual download URL
        curl -fsSL -o "${ARCHIVE_NAME}.tar.gz" \
            "https://golang.org/dl/${ARCHIVE_NAME}.tar.gz" || {
            echo "Failed to download Go ${GO_VERSION}, trying go.dev..."
            curl -fsSL -o "${ARCHIVE_NAME}.tar.gz" \
                "https://go.dev/dl/${ARCHIVE_NAME}.tar.gz" || true
        }

        # Verify the downloaded file is actually a tar.gz
        if [ -f "${ARCHIVE_NAME}.tar.gz" ]; then
            FILE_TYPE=$(file "${ARCHIVE_NAME}.tar.gz" 2>/dev/null || echo "unknown")
            if ! echo "$FILE_TYPE" | grep -qE "gzip|tar|Zip"; then
                echo "ERROR: Downloaded file is not a valid archive!"
                echo "File type: $FILE_TYPE"
                rm -f "${ARCHIVE_NAME}.tar.gz"
            else
                echo "Download verified: $FILE_TYPE"
            fi
        fi
    fi

    # If download failed, try downloading directly from the CDN
    if [ ! -f "${ARCHIVE_NAME}.tar.gz" ]; then
        rm -f "${ARCHIVE_NAME}.tar.gz" 2>/dev/null || true
        echo "Attempting direct download from Go CDN..."

        # Try direct download from go.dev/dl with redirect following
        curl -fsSL -L -o "${ARCHIVE_NAME}.tar.gz" \
            "https://go.dev/dl/${ARCHIVE_NAME}.tar.gz" || true

        if [ -f "${ARCHIVE_NAME}.tar.gz" ]; then
            FILE_SIZE=$(stat -c%s "${ARCHIVE_NAME}.tar.gz}" 2>/dev/null || echo "0")
            echo "Downloaded ${FILE_SIZE} bytes"
            if [ "$FILE_SIZE" -lt 1000000 ]; then
                echo "ERROR: File too small, download may have failed"
                rm -f "${ARCHIVE_NAME}.tar.gz"
            fi
        fi
    fi

    # If download failed or file is invalid, try installing from apt
    if [ ! -f "${ARCHIVE_NAME}.tar.gz" ]; then
        rm -f "${ARCHIVE_NAME}.tar.gz" 2>/dev/null || true

        echo "ERROR: Failed to download Go ${GO_VERSION}"
        echo "Cannot continue without Go ${GO_VERSION}.x - go.mod requires it."
        echo "Please check network connectivity and try again."
        exit 1
    fi

    # Extract Go if not already present
    if [ ! -d /usr/local/go ]; then
        echo "Extracting Go ${GO_VERSION}..."
        tar -xf "${ARCHIVE_NAME}.tar.gz" -C /usr/local
    fi

    # Verify Go works
    if [ -x "/usr/local/go/bin/go" ]; then
        echo "Verifying Go installation..."
        /usr/local/go/bin/go version || {
            echo "ERROR: Downloaded Go binary is not executable!"
            exit 1
        }
    else
        echo "ERROR: Go binary not found at /usr/local/go/bin/go"
        echo "Cannot continue without Go ${GO_VERSION}.x - go.mod requires it."
        exit 1
    fi

    # Ensure Go is in PATH for the rest of the script
    # Don't override if system Go is already in PATH with correct GOROOT
    if [ -x "/usr/local/go/bin/go" ]; then
        export PATH="/usr/local/go/bin:$PATH"
    elif [ -n "${GOROOT:-}" ] && [ -x "${GOROOT}/bin/go" ]; then
        export PATH="${GOROOT}/bin:$PATH"
    fi

    # Verify Go works on this host
    echo "Verifying Go installation..."
    GO_BIN="$(command -v go)"
    if [ -z "${GO_BIN}" ]; then
        echo "ERROR: Go binary not found in PATH"
        exit 1
    fi
    echo "Using Go: ${GO_BIN}"
    ${GO_BIN} version

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

# Find Go binary dynamically (works for both /usr/local/go and apt-installed Go)
if command -v go &>/dev/null; then
    export GOROOT=$(go env GOROOT)
    export PATH=$GOROOT/bin:$PATH
elif [ -x "/usr/local/go/bin/go" ]; then
    export GOROOT=/usr/local/go
    export PATH=$GOROOT/bin:$PATH
else
    echo "ERROR: Go not found! Please check Go installation."
    exit 1
fi

cd "${HOME}"

echo "=== Building as user: $(whoami) ==="
echo "Go version: $(go version)"
echo "GOOS: $(go env GOOS), GOARCH: $(go env GOARCH)"
echo "Will cross-compile for: ${TARGET_OS}/${TARGET_ARCH}"

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
        echo "Enterprise repository not found at expected paths:"
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

# Install Node.js directly (avoid nvm issues in containers)
NODE_MAJOR_VERSION=20
if [ ! -d "${HOME}/.node" ]; then
    echo "Installing Node.js ${NODE_MAJOR_VERSION}..."

    # Determine architecture for Node.js download
    ARCH="$(go env GOARCH)"
    if [ "${ARCH}" = "arm64" ]; then
        NODE_DOWNLOAD_ARCH="arm64"
    elif [ "${ARCH}" = "arm" ]; then
        NODE_DOWNLOAD_ARCH="armv7l"
    elif [ "${ARCH}" = "amd64" ]; then
        NODE_DOWNLOAD_ARCH="x64"
    else
        NODE_DOWNLOAD_ARCH="${ARCH}"
    fi

    wget -q "https://nodejs.org/dist/v${NODE_MAJOR_VERSION}/node-v${NODE_MAJOR_VERSION}-linux-${NODE_DOWNLOAD_ARCH}.tar.xz" && \
    mkdir -p "${HOME}/.node" && \
    tar -xJf "node-v${NODE_MAJOR_VERSION}-linux-${NODE_DOWNLOAD_ARCH}.tar.xz" -C "${HOME}/.node" && \
    rm "node-v${NODE_MAJOR_VERSION}-linux-${NODE_DOWNLOAD_ARCH}.tar.xz"
fi

export PATH="${HOME}/.node/node-v${NODE_MAJOR_VERSION}-linux-${NODE_DOWNLOAD_ARCH}/bin:$PATH"

# Build webapp dist
npm ci --quiet 2>/dev/null || npm install --quiet
npm run build 2>&1 | head -50 || true

cd "${HOME}/go/src/github.com/mattermost/mattermost"

# ============================================
# Prepare Build Environment
# ============================================

echo "Preparing build environment..."
mkdir -p "${HOME}/go/bin"

# Create cross-compilation setup
HOST_GO_ARCH="$(go env GOARCH)"
TARGET_GO_ARCH="${TARGET_ARCH}"

if [ "${HOST_GO_ARCH}" != "${TARGET_GO_ARCH}" ]; then
    echo "Cross-compiling from ${HOST_GO_ARCH} to ${TARGET_GO_ARCH}..."

    # Ensure the target platform directory exists
    install --directory "${HOME}/go/pkg/linux_${TARGET_GO_ARCH}" 2>/dev/null || true

    # Create symlink for cross-compilation
    if [ ! -L "${HOME}/go/bin/linux_${TARGET_GO_ARCH}" ]; then
        ln -sf "${HOME}/go/bin/linux_${HOST_GO_ARCH}" "${HOME}/go/bin/linux_${TARGET_GO_ARCH}"
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
    GO="$(command -v go)" \
    PLUGIN_PACKAGES='' 2>/dev/null || true

# Setup go work
make setup-go-work \
    BUILD_NUMBER="dev-${TARGET_OS}-${TARGET_ARCH}-${MATTERMOST_VERSION}" \
    GO="$(command -v go)" \
    PLUGIN_PACKAGES='' 2>/dev/null || true

# Build with correct Go flags for cross-compilation
# Set GOOS/GOARCH as environment variables for make
export GOOS="${TARGET_OS}"
export GOARCH="${TARGET_ARCH}"

# Build package using Makefile
MAKE_FLAGS=(
    "build-linux"
    "package-linux"
    "BUILD_NUMBER=dev-${TARGET_OS}-${TARGET_ARCH}-${MATTERMOST_VERSION}"
    "GO=$(command -v go)"
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
