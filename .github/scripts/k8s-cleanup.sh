#!/usr/bin/env bash
# k8s-cleanup.sh - Kubernetes cluster cleanup operations
# This script is called by k8s-operations.sh but can also be used standalone
# Usage: k8s-cleanup.sh COMMAND [OPTIONS]

set -euo pipefail

# Source common utilities (retry_kubectl, etc.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

cleanup_kubectl_config() {
    echo "🧹 Cleaning up kubectl configuration..."
    rm -rf "$HOME/.kube" || true
    echo "✅ kubectl config cleaned"
}

cleanup_kubeadm() {
    echo "🧹 Cleaning up kubeadm cluster..."

    container_runtime="${1:-containerd}"

    # Reset the cluster
    if command -v kubeadm >/dev/null 2>&1; then
        echo "🔄 Resetting kubeadm cluster..."
        sudo kubeadm reset -f || true
        echo "✅ Cluster reset"
    fi

    # Stop and disable services
    echo "🛑 Stopping services..."
    sudo systemctl stop kubelet || true
    sudo systemctl disable kubelet || true
    if [ "$container_runtime" = "containerd" ]; then
        sudo systemctl stop containerd || true
        sudo systemctl disable containerd || true
    elif [ "$container_runtime" = "crio" ]; then
        sudo systemctl stop crio || true
        sudo systemctl disable crio || true
    fi
    echo "✅ Services stopped"

    # Remove Kubernetes components
    echo "📦 Removing Kubernetes packages..."
    sudo apt-mark unhold kubelet kubeadm kubectl || true
    sudo apt-get remove -y kubelet kubeadm kubectl cri-tools kubernetes-cni || true
    sudo apt-get purge -y kubelet kubeadm kubectl cri-tools kubernetes-cni || true
    echo "✅ Kubernetes packages removed"

    # Remove container runtimes
    echo "📦 Removing container runtimes..."
    if [ "$container_runtime" = "crio" ]; then
        sudo apt-get remove -y cri-o || true
        sudo apt-get purge -y cri-o || true
    fi
    echo "✅ Container runtimes removed"

    # Remove configuration files and directories
    echo "🗑️  Removing configuration files..."
    sudo rm -rf /etc/kubernetes || true
    if [ "$container_runtime" = "containerd" ]; then
        sudo rm -rf /etc/containerd || true
        sudo rm -rf /var/lib/containerd || true
        sudo rm -rf /etc/systemd/system/containerd.service || true
        sudo rm -rf /usr/local/bin/containerd* || true
        sudo rm -rf /usr/local/bin/ctr || true
        sudo rm -rf /opt/containerd || true
    elif [ "$container_runtime" = "crio" ]; then
        sudo rm -rf /etc/crio || true
        sudo rm -rf /var/lib/crio || true
        sudo rm -rf /etc/apt/sources.list.d/cri-o.list || true
        sudo rm -rf /etc/apt/keyrings/cri-o-apt-keyring.gpg || true
    fi
    sudo rm -rf /var/lib/kubelet || true
    sudo rm -rf /var/lib/etcd || true
    sudo rm -rf /etc/systemd/system/kubelet.service.d || true
    sudo rm -rf /etc/apt/sources.list.d/kubernetes.list || true
    sudo rm -rf /etc/apt/keyrings/kubernetes-apt-keyring.gpg || true
    echo "✅ Configuration files removed"

    # Clean up network
    echo "🌐 Cleaning up network..."
    sudo ip link delete cni0 || true
    sudo ip link delete flannel.1 || true
    sudo rm -rf /etc/cni/net.d || true
    sudo rm -rf /opt/cni || true
    echo "✅ Network cleaned"

    # Reload systemd
    sudo systemctl daemon-reload

    cleanup_kubectl_config

    echo "✅ kubeadm cleanup complete"
}

cleanup_k3s() {
    echo "🧹 Cleaning up K3s..."

    # Run the k3s uninstall script if it exists
    if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
        echo "🔄 Running k3s-uninstall.sh..."
        sudo /usr/local/bin/k3s-uninstall.sh || true
        echo "✅ K3s uninstalled"
    else
        echo "⚠️  k3s-uninstall.sh not found, manual cleanup required"
    fi

    cleanup_kubectl_config

    echo "✅ K3s cleanup complete"
}

cleanup_k0s() {
    echo "🧹 Cleaning up K0s..."

    # Stop k0s
    if command -v k0s >/dev/null 2>&1; then
        echo "🛑 Stopping K0s..."
        sudo k0s stop || true
        echo "✅ K0s stopped"

        # Reset k0s
        echo "🔄 Resetting K0s..."
        sudo k0s reset || true
        echo "✅ K0s reset"
    fi

    # Remove k0s binary and files
    echo "🗑️  Removing K0s files..."
    sudo rm -rf /usr/local/bin/k0s || true
    sudo rm -rf /usr/bin/k0s || true
    sudo rm -rf /etc/k0s || true
    sudo rm -rf /var/lib/k0s || true
    sudo rm -rf /etc/systemd/system/k0scontroller.service || true
    sudo rm -rf /etc/systemd/system/k0sworker.service || true
    sudo systemctl daemon-reload
    echo "✅ K0s files removed"

    cleanup_kubectl_config

    echo "✅ K0s cleanup complete"
}

cleanup_rke2() {
    echo "🧹 Cleaning up RKE2..."

    # Run the rke2 uninstall script if it exists
    if [ -f /usr/local/bin/rke2-uninstall.sh ]; then
        echo "🔄 Running rke2-uninstall.sh..."
        sudo /usr/local/bin/rke2-uninstall.sh || true
        echo "✅ RKE2 uninstalled"
    else
        echo "⚠️  rke2-uninstall.sh not found, manual cleanup required"
    fi

    cleanup_kubectl_config

    echo "✅ RKE2 cleanup complete"
}

cleanup_microk8s() {
    echo "🧹 Cleaning up MicroK8s..."

    # Stop microk8s
    if command -v microk8s >/dev/null 2>&1; then
        echo "🛑 Stopping MicroK8s..."
        sudo microk8s stop || true
        echo "✅ MicroK8s stopped"
    fi

    # Remove microk8s snap
    if command -v snap >/dev/null 2>&1; then
        echo "📦 Removing MicroK8s snap..."
        sudo snap remove microk8s || true
        echo "✅ MicroK8s snap removed"
    fi

    # Remove any remaining files
    echo "🗑️  Removing MicroK8s files..."
    sudo rm -rf /var/snap/microk8s || true
    sudo rm -rf ~/snap/microk8s || true
    echo "✅ MicroK8s files removed"

    cleanup_kubectl_config

    echo "✅ MicroK8s cleanup complete"
}

# Command router
if [ $# -lt 1 ]; then
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  kubeadm   - Cleanup kubeadm cluster and components"
    echo "  k3s       - Cleanup K3s distribution"
    echo "  k0s       - Cleanup K0s distribution"
    echo "  rke2      - Cleanup RKE2 distribution"
    echo "  microk8s  - Cleanup MicroK8s distribution"
    exit 1
fi

case "$1" in
    kubeadm)
        shift
        cleanup_kubeadm "$@"
        ;;
    k3s)
        shift
        cleanup_k3s "$@"
        ;;
    k0s)
        shift
        cleanup_k0s "$@"
        ;;
    rke2)
        shift
        cleanup_rke2 "$@"
        ;;
    microk8s)
        shift
        cleanup_microk8s "$@"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Available commands: kubeadm, k3s, k0s, rke2, microk8s"
        exit 1
        ;;
esac
