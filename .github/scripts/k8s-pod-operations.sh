#!/usr/bin/env bash
# k8s-pod-operations.sh - Kubernetes pod testing operations
# This script is called by k8s-operations.sh but can also be used standalone
# Usage: k8s-pod-operations.sh COMMAND [OPTIONS]

set -euo pipefail

# Source common utilities (retry_kubectl, etc.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

verify_cluster_health() {
    echo "🏥 Checking cluster health..."
    local max_retries=15 retry_delay=3
    for attempt in $(seq 1 $max_retries); do
        if retry_kubectl kubectl cluster-info 2>&1 | grep -q "is running"; then
            echo "✅ API server responding"
            break
        elif [ $attempt -eq $max_retries ]; then
            echo "❌ API server not responding after $max_retries attempts"
            retry_kubectl kubectl cluster-info dump --output-directory=/tmp/cluster-info --namespaces=kube-system 2>&1 || true
            retry_kubectl kubectl get pods -n kube-system 2>&1 || true
            retry_kubectl kubectl get nodes 2>&1 || true
            exit 1
        else
            echo "  Waiting ${retry_delay}s..." && sleep $retry_delay
        fi
    done
    
    retry_kubectl kubectl get nodes
    local not_ready=$(retry_kubectl kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " | wc -l | tr -d ' \n')
    [ "$not_ready" -gt 0 ] 2>/dev/null && echo "⚠️ Some nodes not ready"
    retry_kubectl kubectl get pods -n kube-system
    echo "✅ Cluster healthy"
}

create_pod() {
    [ $# -lt 2 ] && { echo "Usage: $0 create POD_NAME RUNTIME_CLASS [NAMESPACE]"; exit 1; }
    local pod_name="$1" runtime_class="$2" namespace="${3:-default}"
    echo "🚀 Creating test pod with RuntimeClass: $runtime_class"
    
    cat > /tmp/test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $namespace
  labels:
    app: kata-test
spec:
  runtimeClassName: $runtime_class
  containers:
  - name: test
    image: quay.io/quay/busybox:latest
    command: ['sh', '-c', 'echo "Hello from Kata Containers!" && sleep 30']
  restartPolicy: Never
EOF
    
    if retry_kubectl kubectl apply -f /tmp/test-pod.yaml; then
        echo "✅ Pod created"
    else
        echo "❌ Failed to create pod"
        retry_kubectl kubectl cluster-info || true
        exit 1
    fi
}

wait_pod() {
    [ $# -lt 1 ] && { echo "Usage: $0 wait POD_NAME [NAMESPACE] [TIMEOUT]"; exit 1; }
    local pod_name="$1" namespace="${2:-default}" timeout="${3:-300}"
    echo "⏳ Waiting for pod (timeout: ${timeout}s)..."
    
    local max_attempts=$((timeout / 10))
    for i in $(seq 1 $max_attempts); do
        local phase=$(retry_kubectl kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        echo "  [$i/$max_attempts] Phase: $phase"
        
        if [[ "$phase" == "Running" || "$phase" == "Succeeded" ]]; then
            echo "✅ Pod $phase"
            return 0
        elif [ "$phase" = "Failed" ]; then
            echo "❌ Pod failed" && retry_kubectl kubectl describe pod "$pod_name" -n "$namespace"
            exit 1
        fi
        sleep 10
    done
    echo "❌ Timeout" && retry_kubectl kubectl describe pod "$pod_name" -n "$namespace" && exit 1
}

check_status() {
    [ $# -lt 1 ] && { echo "Usage: $0 check-status POD_NAME [NAMESPACE]"; exit 1; }
    local pod_name="$1" namespace="${2:-default}"
    retry_kubectl kubectl get pod "$pod_name" -n "$namespace"
    local phase=$(retry_kubectl kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}')
    echo "Phase: $phase"
    
    if [[ "$phase" == "Running" || "$phase" == "Succeeded" ]]; then
        echo "✅ Pod $phase"
        [ -n "${GITHUB_OUTPUT:-}" ] && echo "status=success" >> "$GITHUB_OUTPUT"
    else
        echo "❌ Pod not ready (current: $phase)"
        [ -n "${GITHUB_OUTPUT:-}" ] && echo "status=failed" >> "$GITHUB_OUTPUT"
        retry_kubectl kubectl describe pod "$pod_name" -n "$namespace" && exit 1
    fi
}

show_details() {
    [ $# -lt 1 ] && { echo "Usage: $0 show-details POD_NAME [NAMESPACE]"; exit 1; }
    echo "📋 Pod details:"
    retry_kubectl kubectl describe pod "$1" -n "${2:-default}"
}

show_logs() {
    [ $# -lt 1 ] && { echo "Usage: $0 show-logs POD_NAME [NAMESPACE]"; exit 1; }
    echo "📋 Pod logs:"
    retry_kubectl kubectl logs "$1" -n "${2:-default}" || echo "No logs available"
}

verify_runtime() {
    [ $# -lt 2 ] && { echo "Usage: $0 verify-runtime POD_NAME RUNTIME_CLASS [NAMESPACE]"; exit 1; }
    local pod_name="$1" runtime_class="$2" namespace="${3:-default}"
    echo "🔍 Verifying Kata runtime..."
    
    local node=$(retry_kubectl kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.nodeName}')
    [ -z "$node" ] && { echo "❌ No node found"; exit 1; }
    echo "Node: $node"
    
    local actual=$(retry_kubectl kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.runtimeClassName}')
    echo "RuntimeClass: $actual (expected: $runtime_class)"
    
    if [ "$actual" = "$runtime_class" ]; then
        echo "✅ Correct RuntimeClass"
    else
        echo "❌ Mismatch! Expected: $runtime_class, Got: $actual"
        retry_kubectl kubectl describe pod "$pod_name" -n "$namespace" && exit 1
    fi
}

cleanup_pod() {
    [ $# -lt 1 ] && { echo "Usage: $0 cleanup POD_NAME [NAMESPACE]"; exit 1; }
    echo "🗑️ Cleaning up..."
    retry_kubectl kubectl delete pod "$1" -n "${2:-default}" --ignore-not-found=true
    echo "✅ Cleaned up"
}

# Command router
[ $# -lt 1 ] && {
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo "Commands: verify-cluster-health, create, wait, check-status, show-details, show-logs, verify-runtime, cleanup"
    exit 1
}

case "$1" in
    verify-cluster-health) shift; verify_cluster_health "$@" ;;
    create) shift; create_pod "$@" ;;
    wait) shift; wait_pod "$@" ;;
    check-status) shift; check_status "$@" ;;
    show-details) shift; show_details "$@" ;;
    show-logs) shift; show_logs "$@" ;;
    verify-runtime) shift; verify_runtime "$@" ;;
    cleanup) shift; cleanup_pod "$@" ;;
    *) echo "Unknown command: $1"; exit 1 ;;
esac
