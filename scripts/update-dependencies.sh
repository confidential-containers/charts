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

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if running from chart root
if [ ! -f Chart.yaml ]; then
    error "Chart.yaml not found. Please run this script from the chart root directory."
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    error "helm command not found. Please install Helm."
    exit 1
fi

# Check if yq is available
if ! command -v yq &> /dev/null; then
    error "yq command not found. Please install yq (mikefarah/yq)."
    error "Install: https://github.com/mikefarah/yq#install"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║           Update Helm Dependencies & Clean Chart.lock           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

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
