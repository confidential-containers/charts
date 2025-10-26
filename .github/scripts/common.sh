#!/usr/bin/env bash
#
# common.sh - Common utilities for all GitHub Actions scripts
#
# This file should be sourced by other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Retry wrapper for kubectl commands
# Retries any command up to 30 times with 10-second delays
# Usage: retry_kubectl kubectl get pods
retry_kubectl() {
    local max_retries=30
    local retry_delay=10
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        if "$@" 2>&1; then
            return 0
        fi
        
        if [ $attempt -eq $max_retries ]; then
            echo "❌ Command failed after $max_retries attempts: $*" >&2
            return 1
        fi
        
        echo "  Retry $attempt/$max_retries failed, waiting ${retry_delay}s..." >&2
        sleep $retry_delay
        attempt=$((attempt + 1))
    done
}

