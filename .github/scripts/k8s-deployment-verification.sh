#!/usr/bin/env bash
# k8s-deployment-verification.sh - Kubernetes deployment verification
# This script is called by k8s-operations.sh but can also be used standalone
# Usage: k8s-deployment-verification.sh COMMAND [OPTIONS]

set -euo pipefail

# Source common utilities (retry_kubectl, etc.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Node label kata-deploy applies once an install completes (both daemonset and
# job deployment modes). In "job" mode there is no always-on DaemonSet to wait
# on, so this label is the "install complete" signal.
KATA_RUNTIME_NODE_LABEL="katacontainers.io/kata-runtime=true"

# In daemonset mode the deployment is selected via "name=<chart>". In job mode
# the dispatcher Job, per-node install Jobs and the templates ConfigMap are
# selected via "app.kubernetes.io/name=<chart>". Derive the latter from the
# former so callers keep passing a single --label value.
job_label_from_daemonset_label() {
    local label="$1"
    if [[ "$label" == name=* ]]; then
        echo "app.kubernetes.io/name=${label#name=}"
    else
        echo "$label"
    fi
}

# Dump everything useful about the job-mode install pipeline (dispatcher Job,
# per-node Jobs and their pods/logs) for post-mortem debugging.
dump_job_mode_diagnostics() {
    local namespace="$1" job_label="$2"
    retry_kubectl kubectl -n "$namespace" get jobs -l "$job_label" -o wide || true
    retry_kubectl kubectl -n "$namespace" get pods -l "$job_label" -o wide || true
    kubectl -n "$namespace" describe jobs -l "$job_label" || true
    kubectl -n "$namespace" logs -l "$job_label" --all-containers --tail=-1 --timestamps 2>/dev/null || true
}

# Wait until at least one node carries the kata-runtime label, which kata-deploy
# only applies after the per-node install Job finishes (artifacts extracted, CRI
# reconfigured, node labeled).
wait_job_install() {
    local namespace="$1" job_label="$2" timeout="$3"
    local timeout_secs deadline
    timeout_secs="$(duration_to_seconds "$timeout")"
    deadline=$(( $(date +%s) + timeout_secs ))

    echo "⏳ deploymentMode=job: waiting for per-node install Jobs to label node(s) (timeout: $timeout)..."
    while true; do
        if [ -n "$(kubectl get nodes -l "$KATA_RUNTIME_NODE_LABEL" -o name 2>/dev/null)" ]; then
            echo "✅ At least one node carries the kata-runtime label (install complete)"
            return 0
        fi
        if [ "$(date +%s)" -ge "$deadline" ]; then
            echo "❌ Timed out waiting for kata-deploy install Jobs to label any node"
            dump_job_mode_diagnostics "$namespace" "$job_label"
            exit 1
        fi
        sleep 5
    done
}

wait_daemonset() {
    local namespace="coco-system" label="name=kata-as-coco-runtime" timeout="15m"
    local deployment_mode="daemonset"
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --namespace) namespace="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            --timeout) timeout="$2"; shift 2 ;;
            --deployment-mode) deployment_mode="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [ "$deployment_mode" = "job" ]; then
        wait_job_install "$namespace" "$(job_label_from_daemonset_label "$label")" "$timeout"
        return
    fi

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

verify_job_install() {
    local namespace="$1" job_label="$2"

    echo "🔍 deploymentMode=job: verifying install Jobs and node labels..."
    retry_kubectl kubectl -n "$namespace" get jobs -l "$job_label" -o wide || true

    local labeled_nodes
    labeled_nodes="$(kubectl get nodes -l "$KATA_RUNTIME_NODE_LABEL" -o name 2>/dev/null || echo "")"
    if [ -n "$labeled_nodes" ]; then
        echo "✅ Node(s) labeled with kata-runtime:"
        echo "$labeled_nodes"
        [ -n "${GITHUB_OUTPUT:-}" ] && echo "status=success" >> "$GITHUB_OUTPUT"
    else
        echo "❌ No nodes labeled with kata-runtime"
        dump_job_mode_diagnostics "$namespace" "$job_label"
        [ -n "${GITHUB_OUTPUT:-}" ] && echo "status=failed" >> "$GITHUB_OUTPUT"
        exit 1
    fi
}

verify_daemonset() {
    local namespace="coco-system" label="name=kata-as-coco-runtime"
    local deployment_mode="daemonset"
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --namespace) namespace="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            --deployment-mode) deployment_mode="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [ "$deployment_mode" = "job" ]; then
        verify_job_install "$namespace" "$(job_label_from_daemonset_label "$label")"
        return
    fi
    
    echo "🔍 Verifying daemonset..."
    
    local pod_name=$(retry_kubectl kubectl get pods -n "$namespace" -l "$label" -o jsonpath='{.items[0].metadata.name}')
    [ -z "$pod_name" ] && { echo "❌ No pods with label $label"; exit 1; }
    
    local ds_name=$(retry_kubectl kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].name}')
    [ -z "$ds_name" ] && { echo "❌ Cannot find DaemonSet name"; exit 1; }
    
    echo "DaemonSet: $ds_name"
    retry_kubectl kubectl get daemonset "$ds_name" -n "$namespace"
    
    if retry_kubectl kubectl rollout status daemonset/"$ds_name" -n "$namespace" --timeout=180s; then
        echo "✅ DaemonSet rolled out successfully"
    else
        echo "❌ DaemonSet not rolled out in 180 seconds"
    fi

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
    local deployment_mode="daemonset"
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --namespace) namespace="$2"; shift 2 ;;
            --label) label="$2"; shift 2 ;;
            --tail) tail="$2"; shift 2 ;;
            --deployment-mode) deployment_mode="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [ "$deployment_mode" = "job" ]; then
        local job_label
        job_label="$(job_label_from_daemonset_label "$label")"
        echo "📋 kata-deploy job logs (last $tail lines):"
        retry_kubectl kubectl logs -n "$namespace" -l "$job_label" --tail="$tail" --prefix=true || true
        return
    fi
    
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
