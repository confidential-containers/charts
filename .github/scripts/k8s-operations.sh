#!/usr/bin/env bash
#
# Kubernetes Operations Script - Main Router
# Routes commands to specialized sub-scripts
#
# Usage: k8s-operations.sh CATEGORY COMMAND [OPTIONS]
#
# Run: k8s-operations.sh --help for full documentation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
    cat << 'EOF'
Kubernetes Operations Script
All Kubernetes-related operations in one place

Usage: k8s-operations.sh CATEGORY COMMAND [OPTIONS]

Categories & Commands:

=== SETUP CATEGORY ===
  setup kubeadm [RUNTIME] [VERSION]
      Setup Kubernetes with kubeadm
      RUNTIME: containerd or crio (default: containerd)
      VERSION: containerd version for containerd runtime (default: latest)

  setup k3s [EXTRA_PARAMS]
      Setup K3s distribution

  setup k0s [EXTRA_PARAMS]
      Setup K0s distribution

  setup rke2
      Setup RKE2 distribution

  setup microk8s
      Setup MicroK8s distribution

=== POD CATEGORY ===
  pod verify-cluster-health
      Verify cluster health before running tests

  pod create POD_NAME RUNTIME_CLASS [NAMESPACE]
      Create a test pod with specified RuntimeClass

  pod wait POD_NAME [NAMESPACE] [TIMEOUT]
      Wait for pod to reach Running or Succeeded state

  pod check-status POD_NAME [NAMESPACE]
      Check and validate final pod status

  pod show-details POD_NAME [NAMESPACE]
      Show detailed information about a pod

  pod show-logs POD_NAME [NAMESPACE]
      Show logs from a pod

  pod verify-runtime POD_NAME RUNTIME_CLASS [NAMESPACE]
      Verify pod is using Kata runtime

  pod cleanup POD_NAME [NAMESPACE]
      Delete test pod

=== DEPLOYMENT CATEGORY ===
  deployment wait-daemonset [OPTIONS]
      Wait for kata-deploy daemonset to become ready
      Options:
        --namespace NAME          Namespace (default: kube-system)
        --label SELECTOR          Label selector (default: name=kata-as-coco-runtime)
        --timeout TIME            Timeout (default: 15m)

  deployment verify-daemonset [OPTIONS]
      Verify daemonset status
      Options:
        --namespace NAME          Namespace (default: kube-system)
        --label SELECTOR          Label selector (default: name=kata-as-coco-runtime)

  deployment show-logs [OPTIONS]
      Show daemonset logs
      Options:
        --namespace NAME          Namespace (default: kube-system)
        --label SELECTOR          Label selector (default: name=kata-as-coco-runtime)
        --tail LINES              Number of lines (default: 50)

  deployment verify-runtimeclasses RUNTIMECLASS [RUNTIMECLASS...]
      Verify RuntimeClasses exist
      Options:
        --timeout SECONDS         Timeout in seconds (default: 180)

  deployment show-runtimeclass-details RUNTIMECLASS [RUNTIMECLASS...]
      Show RuntimeClass details
EOF
}

if [ $# -lt 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

if [ $# -lt 2 ]; then
    echo "Usage: $0 CATEGORY COMMAND [OPTIONS]"
    echo ""
    echo "Categories:"
    echo "  setup       - Setup Kubernetes distributions"
    echo "  pod         - Pod operations"
    echo "  deployment  - Deployment verification"
    echo ""
    echo "Run '$0 --help' for detailed help"
    exit 1
fi

CATEGORY="$1"
COMMAND="$2"
shift 2

# Route to appropriate sub-script
case "${CATEGORY}" in
    setup)
        exec "${SCRIPT_DIR}/k8s-setup.sh" "${COMMAND}" "$@"
        ;;
    pod)
        exec "${SCRIPT_DIR}/k8s-pod-operations.sh" "${COMMAND}" "$@"
        ;;
    deployment)
        exec "${SCRIPT_DIR}/k8s-deployment-verification.sh" "${COMMAND}" "$@"
        ;;
    *)
        echo "Unknown category: ${CATEGORY}"
        echo "Available categories: setup, pod, deployment"
        echo "Run '$0 --help' for detailed help"
        exit 1
        ;;
esac
