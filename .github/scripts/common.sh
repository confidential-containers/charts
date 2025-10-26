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

# Retry wrapper for pod creation with transient failure handling
# Retries pod creation and waiting up to 5 times on failure
# This handles flaky network issues during image pulls inside the guest
# Usage: retry_pod_creation POD_NAME RUNTIME_CLASS NAMESPACE TIMEOUT
retry_pod_creation() {
    [ $# -lt 3 ] && { echo "Usage: $0 POD_NAME RUNTIME_CLASS NAMESPACE [TIMEOUT]"; return 1; }
    local pod_name="$1"
    local runtime_class="$2"
    local namespace="$3"
    local timeout="${4:-300}"
    local max_attempts=5
    
    for attempt in $(seq 1 $max_attempts); do
        echo ""
        echo "🔄 Pod creation attempt $attempt/$max_attempts..."
        
        # Create the pod
        cat > /tmp/test-pod-${pod_name}.yaml <<EOF
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
        
        if ! retry_kubectl kubectl apply -f /tmp/test-pod-${pod_name}.yaml; then
            echo "❌ Failed to create pod on attempt $attempt"
            retry_kubectl kubectl delete pod "$pod_name" -n "$namespace" --ignore-not-found=true || true
            
            if [ $attempt -lt $max_attempts ]; then
                echo "⏳ Waiting 10s before retry..."
                sleep 10
            fi
            continue
        fi
        
        echo "✅ Pod created successfully"
        
        # Wait for the pod to reach Running or Succeeded state
        local max_wait_attempts=$((timeout / 10))
        local wait_attempt=0
        local pod_phase=""
        local success=false
        
        while [ $wait_attempt -lt $max_wait_attempts ]; do
            pod_phase=$(retry_kubectl kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
            echo "  [$((wait_attempt+1))/$max_wait_attempts] Phase: $pod_phase"
            
            if [[ "$pod_phase" == "Running" || "$pod_phase" == "Succeeded" ]]; then
                echo "✅ Pod reached $pod_phase state"
                success=true
                break
            elif [ "$pod_phase" = "Failed" ]; then
                echo "❌ Pod failed on attempt $attempt"
                retry_kubectl kubectl describe pod "$pod_name" -n "$namespace" 2>/dev/null || true
                break
            fi
            
            sleep 10
            wait_attempt=$((wait_attempt + 1))
        done
        
        if [ "$success" = true ]; then
            echo "✅ Pod creation succeeded on attempt $attempt/$max_attempts"
            return 0
        fi
        
        # Pod failed or timed out, clean up and retry
        if [ $attempt -lt $max_attempts ]; then
            echo "🗑️  Cleaning up failed pod..."
            retry_kubectl kubectl delete pod "$pod_name" -n "$namespace" --ignore-not-found=true || true
            echo "⏳ Waiting 10s before retry..."
            sleep 10
        else
            echo "❌ Pod creation failed after $max_attempts attempts"
            retry_kubectl kubectl describe pod "$pod_name" -n "$namespace" 2>/dev/null || true
            return 1
        fi
    done
}

