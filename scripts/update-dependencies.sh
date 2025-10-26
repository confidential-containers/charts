#!/usr/bin/env bash
#
# update-dependencies.sh - Update Helm chart dependencies and clean Chart.lock
#
# This script:
# 1. Runs 'helm dependency update' to fetch dependencies
# 2. Automatically removes 0.0.0-dev entries from Chart.lock (CI-only dependencies)
# 3. Recalculates the digest and updates timestamp
#
# Usage:
#   ./scripts/update-dependencies.sh
#
# The 0.0.0-dev version is used only for kata-as-coco-runtime-for-ci during
# CI testing and should never be committed to Chart.lock.
#
# Requirements:
# System tools (must be pre-installed):
# - curl
#
# The script will automatically download the latest versions of:
# - yq (mikefarah/yq)
# - helm

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Temporary directory for tools
TOOLS_DIR=""

# Helper functions
info() {
    echo -e "${BLUE}ℹ${NC} $*" >&2
}

success() {
    echo -e "${GREEN}✅${NC} $*" >&2
}

warning() {
    echo -e "${YELLOW}⚠️${NC} $*" >&2
}

error() {
    echo -e "${RED}❌${NC} $*" >&2
}

# Cleanup function
cleanup() {
    # Clean up temporary tools directory
    if [ -n "${TOOLS_DIR}" ] && [ -d "${TOOLS_DIR}" ]; then
        info "Cleaning up temporary tools directory..."
        rm -rf "${TOOLS_DIR}"
    fi
}

# Register cleanup on exit
trap cleanup EXIT

# Check if running from chart root
if [ ! -f Chart.yaml ]; then
    error "Chart.yaml not found. Please run this script from the chart root directory."
    exit 1
fi

# Check required system commands
check_requirements() {
    local missing_tools=()

    # Only check for curl (needed to download tools)
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        error "Missing required system tools: ${missing_tools[*]}"
        error "Please install them before running this script"
        exit 1
    fi

    success "All required system tools are available"
}

# Download and setup tools
setup_tools() {
    info "Setting up tools in temporary directory..."

    # Create temporary directory
    TOOLS_DIR="$(mktemp -d)"
    info "Tools directory: ${TOOLS_DIR}"

    # Detect OS and architecture
    local os=""
    local arch=""

    case "$(uname -s)" in
        Linux*)  os="linux" ;;
        Darwin*) os="darwin" ;;
        *)
            error "Unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        s390x) arch="s390x" ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac

    info "Detected: ${os}/${arch}"

    # Download yq (mikefarah/yq - the Go version)
    info "Downloading yq..."
    local yq_version
    yq_version="$(curl -sS https://api.github.com/repos/mikefarah/yq/releases/latest | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/')"
    local yq_url="https://github.com/mikefarah/yq/releases/download/${yq_version}/yq_${os}_${arch}"

    if curl -sS -L -o "${TOOLS_DIR}/yq" "${yq_url}"; then
        chmod +x "${TOOLS_DIR}/yq"
        success "Downloaded yq ${yq_version}"
    else
        error "Failed to download yq"
        exit 1
    fi

    # Download helm
    info "Downloading helm..."
    local helm_version
    helm_version="$(curl -sS https://api.github.com/repos/helm/helm/releases/latest | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/')"
    local helm_tar="helm-${helm_version}-${os}-${arch}.tar.gz"
    local helm_url="https://get.helm.sh/${helm_tar}"

    if curl -sS -L -o "${TOOLS_DIR}/${helm_tar}" "${helm_url}"; then
        tar -xzf "${TOOLS_DIR}/${helm_tar}" -C "${TOOLS_DIR}" --strip-components=1 "${os}-${arch}/helm"
        rm "${TOOLS_DIR}/${helm_tar}"
        chmod +x "${TOOLS_DIR}/helm"
        success "Downloaded helm ${helm_version}"
    else
        error "Failed to download helm"
        exit 1
    fi

    # Add tools directory to PATH
    export PATH="${TOOLS_DIR}:${PATH}"

    # Verify tools work
    info "Verifying tools..."
    "${TOOLS_DIR}/yq" --version
    "${TOOLS_DIR}/helm" version --short

    success "All tools ready"
}

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║           Update Helm Dependencies & Clean Chart.lock           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Check requirements
check_requirements

# Setup tools
setup_tools

# Update dependencies
info "Updating Helm dependencies..."
if ! helm dependency update; then
    error "Failed to update Helm dependencies"
    exit 1
fi
success "Helm dependencies updated"

# Check if Chart.lock exists
if [ ! -f Chart.lock ]; then
    error "Chart.lock not found after dependency update"
    exit 1
fi

info "Cleaning Chart.lock..."

# Check if 0.0.0-dev exists in Chart.lock
if grep -q "version: 0.0.0-dev" Chart.lock; then
    warning "Found 0.0.0-dev in Chart.lock, removing..."
    
    # Show what will be removed
    echo ""
    echo "Entries to be removed:"
    grep -B2 -A2 "version: 0.0.0-dev" Chart.lock || true
    echo ""
    
    # Create temporary file for cleaned Chart.lock
    TMP_FILE=$(mktemp)
    
    # Remove the entire dependency block containing 0.0.0-dev
    awk '
    BEGIN { skip = 0; buffer = "" }
    /^dependencies:/ {
        print $0
        next
    }
    /^[^ ]/ && !/^-/ {
        # Non-dependency line (like digest, generated)
        if (buffer != "" && skip == 0) {
            print buffer
        }
        buffer = ""
        skip = 0
        print $0
        next
    }
    /^- name:/ {
        if (buffer != "" && skip == 0) {
            print buffer
        }
        buffer = $0
        skip = 0
        next
    }
    /version: 0.0.0-dev/ {
        skip = 1
    }
    {
        if (buffer != "") {
            buffer = buffer "\n" $0
        }
    }
    END {
        if (buffer != "" && skip == 0) {
            print buffer
        }
    }
    ' Chart.lock > "$TMP_FILE"
    
    # Replace Chart.lock with cleaned version
    mv "$TMP_FILE" Chart.lock
    
    # Recalculate digest
    info "Recalculating Chart.lock digest..."
    DEPS_JSON=$(yq -o json '.dependencies' Chart.lock)
    NEW_DIGEST=$(echo "$DEPS_JSON" | sha256sum | awk '{print $1}')
    
    yq -i ".digest = \"sha256:${NEW_DIGEST}\"" Chart.lock
    yq -i ".generated = \"$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)\"" Chart.lock
    
    success "Removed 0.0.0-dev entries and regenerated Chart.lock digest"
else
    success "No 0.0.0-dev entries found in Chart.lock (already clean!)"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                           Summary                                ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Show current dependencies in Chart.lock
echo "Chart.lock dependencies:"
yq '.dependencies[] | "  - " + .name + " @ " + .version' Chart.lock

echo ""
success "✨ Dependencies updated and Chart.lock is clean!"
echo ""
echo "Next steps:"
echo "  - Review the changes: git diff Chart.lock charts/"
echo "  - Commit if needed: git add Chart.lock charts/ && git commit"
echo ""
