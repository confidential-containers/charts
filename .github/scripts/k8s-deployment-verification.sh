#!/usr/bin/env bash
# k8s-deployment-verification.sh - Kubernetes deployment verification
# This script is called by k8s-operations.sh but can also be used standalone
# Usage: k8s-deployment-verification.sh COMMAND [OPTIONS]

set -euo pipefail

# Source common utilities (retry_kubectl, etc.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

wait_daemonset() {
    local namespace="coco-system" label="name=kata-as-coco-runtime" timeout="15m"
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --namespace) namespace="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            --timeout) timeout="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    echo "⏳ Waiting for daemonset (label: $label, timeout: $timeout)..."
    
    if retry_kubectl kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout="$timeout"; then
        echo "✅ DaemonSet pods ready"
    else
        echo "❌ DaemonSet pods not ready"
        retry_kubectl kubectl get daemonset -n "$namespace" -l "$label"
        retry_kubectl kubectl get pods -n "$namespace" -l "$label"
        retry_kubectl kubectl describe pods -n "$namespace" -l "$label"
        exit 1
    fi
}

verify_daemonset() {
    local namespace="coco-system" label="name=kata-as-coco-runtime"
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --namespace) namespace="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    echo "🔍 Verifying daemonset..."
    
    local pod_name=$(retry_kubectl kubectl get pods -n "$namespace" -l "$label" -o jsonpath='{.items[0].metadata.name}')
    [ -z "$pod_name" ] && { echo "❌ No pods with label $label"; exit 1; }
    
    local ds_name=$(retry_kubectl kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].name}')
    [ -z "$ds_name" ] && { echo "❌ Cannot find DaemonSet name"; exit 1; }
    
    echo "DaemonSet: $ds_name"
    retry_kubectl kubectl get daemonset "$ds_name" -n "$namespace"
    
    local desired=$(retry_kubectl kubectl get daemonset "$ds_name" -n "$namespace" -o jsonpath='{.status.desiredNumberScheduled}')
    local ready=$(retry_kubectl kubectl get daemonset "$ds_name" -n "$namespace" -o jsonpath='{.status.numberReady}')
    
    echo "Status: $ready/$desired ready"
    
    if [ "$desired" = "$ready" ] && [ "$ready" != "0" ]; then
        echo "✅ DaemonSet healthy ($ready/$desired)"
        [ -n "${GITHUB_OUTPUT:-}" ] && echo "status=success" >> "$GITHUB_OUTPUT"
    else
        echo "❌ DaemonSet unhealthy ($ready/$desired)"
        [ -n "${GITHUB_OUTPUT:-}" ] && echo "status=failed" >> "$GITHUB_OUTPUT"
        exit 1
    fi
}

show_logs() {
    local namespace="coco-system" label="name=kata-as-coco-runtime" tail="50"
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --namespace) namespace="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            --tail) tail="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    echo "📋 DaemonSet logs (last $tail lines):"
    retry_kubectl kubectl logs -n "$namespace" -l "$label" --tail="$tail" --prefix=true
}

verify_runtimeclasses() {
    local timeout=180 runtimeclasses=()
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --timeout) timeout="$2"; shift 2 ;;
            *) runtimeclasses+=("$1"); shift ;;
        esac
    done
    
    [ ${#runtimeclasses[@]} -eq 0 ] && {
        echo "Usage: $0 verify-runtimeclasses RUNTIMECLASS [RUNTIMECLASS...] [--timeout SECONDS]"
        exit 1
    }
    
    echo "🔍 Verifying RuntimeClasses: ${runtimeclasses[*]} (timeout: ${timeout}s)"
    
    local interval=5 elapsed=0
    while [ $elapsed -lt $timeout ]; do
        echo "⏱️ [$elapsed/$timeout] Checking..."
        retry_kubectl kubectl get runtimeclass 2>/dev/null || echo "No RuntimeClasses yet"
        
        local all_found=true
        for rc in "${runtimeclasses[@]}"; do
            if retry_kubectl kubectl get runtimeclass "$rc" >/dev/null 2>&1; then
                echo "  ✅ $rc"
            else
                echo "  ⏳ $rc"
                all_found=false
            fi
        done
        
        if [ "$all_found" = "true" ]; then
            echo "✅ All RuntimeClasses exist"
            [ -n "${GITHUB_OUTPUT:-}" ] && echo "status=success" >> "$GITHUB_OUTPUT"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo "❌ Timeout: Missing RuntimeClasses after ${timeout}s"
    retry_kubectl kubectl get runtimeclass 2>/dev/null || echo "No RuntimeClasses found"
    [ -n "${GITHUB_OUTPUT:-}" ] && echo "status=failed" >> "$GITHUB_OUTPUT"
    exit 1
}

show_runtimeclass_details() {
    [ $# -lt 1 ] && {
        echo "Usage: $0 show-runtimeclass-details RUNTIMECLASS [RUNTIMECLASS...]"
        exit 1
    }
    
    echo "📋 RuntimeClass details:"
    for rc in "$@"; do
        if retry_kubectl kubectl get runtimeclass "$rc" >/dev/null 2>&1; then
            echo -e "\n=== $rc ==="
            retry_kubectl kubectl get runtimeclass "$rc" -o yaml
        fi
    done
}

# Command router
[ $# -lt 1 ] && {
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo "Commands: wait-daemonset, verify-daemonset, show-logs, verify-runtimeclasses, show-runtimeclass-details"
    exit 1
}

case "$1" in
    wait-daemonset) shift; wait_daemonset "$@" ;;
    verify-daemonset) shift; verify_daemonset "$@" ;;
    show-logs) shift; show_logs "$@" ;;
    verify-runtimeclasses) shift; verify_runtimeclasses "$@" ;;
    show-runtimeclass-details) shift; show_runtimeclass_details "$@" ;;
    *) echo "Unknown command: $1"; exit 1 ;;
esac
