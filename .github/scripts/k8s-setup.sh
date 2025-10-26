#!/usr/bin/env bash
# k8s-setup.sh - Kubernetes cluster setup operations
# This script is called by k8s-operations.sh but can also be used standalone
# Usage: k8s-setup.sh COMMAND [OPTIONS]

set -euo pipefail

free_disk_space() {
    echo "🧹 Removing unnecessary directories to free up disk space..."
    sudo rm -rf /usr/local/.ghcup /opt/hostedtoolcache/CodeQL /usr/local/lib/android /usr/share/dotnet
    sudo rm -rf /opt/ghc /usr/local/share/boost "${AGENT_TOOLSDIRECTORY:-/tmp/agent-tools}"
    sudo rm -rf /usr/lib/jvm /usr/share/swift /usr/local/share/powershell /usr/local/julia*
    sudo rm -rf /opt/az /usr/local/share/chromium /opt/microsoft /opt/google /usr/lib/firefox
    echo "✅ Disk space freed up"
    df -h / | grep -v Filesystem
}

prepare_system_kubeadm() {
    echo "🔧 Preparing system for Kubernetes..."
    sudo apt-get update && sudo apt-get -y install runc
    sudo modprobe overlay && sudo modprobe br_netfilter
    sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
    sudo sysctl -w net.ipv4.ip_forward=1
    sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1
    sudo swapoff -a
    echo "✅ System prepared"
}

install_containerd() {
    local version="${1:-latest}"
    echo "📦 Installing containerd ${version}..."
    local arch=$(uname -m); [[ "$arch" == "x86_64" ]] && arch="amd64" || arch="arm64"
    local api_url="https://api.github.com/repos/containerd/containerd/releases"
    local curl_auth=""; [ -n "${GH_TOKEN:-}" ] && curl_auth="-H Authorization: Bearer ${GH_TOKEN}"
    
    local full_version
    if [ "$version" = "latest" ]; then
        full_version=$(curl -sSf $curl_auth "$api_url" | jq -r '[.[]|select(.tag_name|contains("api/")|not)][0].tag_name//""' | sed 's/^v//')
    else
        full_version=$(curl -sSf $curl_auth "$api_url" | jq -r '[.[]|select(.tag_name|contains("api/")|not)][].tag_name' | grep "^v${version}\." | head -1 | sed 's/^v//')
    fi
    [ -z "$full_version" ] && { echo "❌ Failed to find containerd release"; exit 1; }
    
    echo "📥 Downloading containerd ${full_version}..."
    curl -fsSL -o /tmp/containerd.tar.gz "https://github.com/containerd/containerd/releases/download/v${full_version}/containerd-${full_version}-linux-${arch}.tar.gz"
    sudo tar -C /usr/local -xzf /tmp/containerd.tar.gz && rm /tmp/containerd.tar.gz
    sudo curl -fsSL -o /etc/systemd/system/containerd.service https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    sudo mkdir -p /etc/containerd
    containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml
    sudo systemctl daemon-reload && sudo systemctl enable --now containerd && sudo systemctl restart containerd
    echo "✅ containerd installed: $(containerd --version)"
}

install_crio() {
    echo "📦 Installing CRI-O..."
    local k8s_ver=$(curl -Ls https://dl.k8s.io/release/stable.txt | cut -d. -f-2)
    [ -z "$k8s_ver" ] && { echo "❌ Failed to determine K8s version"; exit 1; }
    
    local crio_ver="$k8s_ver"
    if ! curl -fsSL --head "https://download.opensuse.org/repositories/isv:/cri-o:/stable:/${crio_ver}/deb/Release.key" >/dev/null 2>&1; then
        local api_url="https://api.github.com/repos/cri-o/cri-o/releases"
        local curl_auth=""; [ -n "${GH_TOKEN:-}" ] && curl_auth="-H Authorization: Bearer ${GH_TOKEN}"
        crio_ver=$(curl -sSf $curl_auth "$api_url" | jq -r '[.[]|select(.prerelease==false)][0].tag_name')
    fi
    
    sudo apt-get update && sudo apt-get install -y software-properties-common curl
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/${k8s_ver}/deb/Release.key | sudo gpg --batch --yes --no-tty --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${k8s_ver}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/${crio_ver}/deb/Release.key | sudo gpg --batch --yes --no-tty --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/${crio_ver}/deb/ /" | sudo tee /etc/apt/sources.list.d/cri-o.list
    sudo apt-get update && sudo apt-get install -y cri-o cri-tools
    sudo mkdir -p /etc/crio/crio.conf.d/
    cat | sudo tee /etc/crio/crio.conf.d/00-default-capabilities.conf > /dev/null <<EOF
[crio]
storage_option = ["overlay.skip_mount_home=true"]
[crio.runtime]
default_capabilities = ["CHOWN","DAC_OVERRIDE","FSETID","FOWNER","SETGID","SETUID","SETPCAP","NET_BIND_SERVICE","KILL","SYS_CHROOT"]
EOF
    sudo systemctl daemon-reload && sudo systemctl enable --now crio && sudo systemctl restart crio
    echo "✅ CRI-O installed: $(crio --version)"
}

install_kubeadm_components() {
    echo "📦 Installing Kubernetes components..."
    local k8s_ver=$(curl -Ls https://dl.k8s.io/release/stable.txt | cut -d. -f-2)
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${k8s_ver}/deb/Release.key" | sudo gpg --batch --yes --no-tty --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${k8s_ver}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

    cat <<EOF | sudo tee /etc/apt/preferences.d/kubernetes
Package: kubelet kubeadm kubectl cri-tools kubernetes-cni
Pin: origin pkgs.k8s.io
Pin-Priority: 1000
EOF

    sudo apt-get update && sudo apt-get -y install kubeadm kubelet kubectl --allow-downgrades
    sudo apt-mark hold kubeadm kubelet kubectl
    echo "✅ Kubernetes installed: $(kubeadm version -o short)"
}

init_kubeadm_cluster() {
    local runtime="${1:-containerd}"
    echo "🚀 Initializing Kubernetes cluster..."
    local cri_socket="unix:///run/containerd/containerd.sock"
    [ "$runtime" = "crio" ] && cri_socket="unix:///var/run/crio/crio.sock"
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --cri-socket="$cri_socket"
    mkdir -p "$HOME/.kube" && sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    echo "✅ Cluster initialized"
}

install_flannel() {
    echo "📦 Installing Flannel CNI..."
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
    echo "✅ Flannel installed"
}

setup_kubectl() {
    local dist="$1"
    echo "🔧 Setting up kubectl for $dist..."
    local arch=$(uname -m); [[ "$arch" == "x86_64" ]] && arch="amd64" || arch="arm64"
    local ver=""
    
    case "$dist" in
        k3s)
            ver=$(/usr/local/bin/k3s kubectl version --client=true 2>/dev/null | grep "Client Version" | sed -e 's/Client Version: //' -e 's/+k3s[0-9]\+//')
            sudo curl -fL -o /usr/bin/kubectl https://dl.k8s.io/release/"$ver"/bin/linux/"$arch"/kubectl
            sudo chmod +x /usr/bin/kubectl && sudo rm -rf /usr/local/bin/kubectl
            mkdir -p ~/.kube && cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
            ;;
        k0s)
            ver=$(sudo k0s kubectl version 2>/dev/null | grep "Client Version" | sed 's/Client Version: //')
            sudo curl -fL -o /usr/bin/kubectl https://dl.k8s.io/release/"$ver"/bin/linux/"$arch"/kubectl
            sudo chmod +x /usr/bin/kubectl
            mkdir -p ~/.kube && sudo cp /var/lib/k0s/pki/admin.conf ~/.kube/config
            sudo chown "$USER:$USER" ~/.kube/config
            ;;
        rke2)
            sudo ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
            mkdir -p ~/.kube && sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
            sudo chown "$USER:$USER" ~/.kube/config
            ;;
        microk8s)
            ver=$(sudo microk8s version | grep -oe 'v[0-9]\+\(\.[0-9]\+\)*')
            sudo curl -fL -o /usr/bin/kubectl https://dl.k8s.io/release/"$ver"/bin/linux/"$arch"/kubectl
            sudo chmod +x /usr/bin/kubectl && sudo rm -rf /usr/local/bin/kubectl
            mkdir -p ~/.kube
            sudo microk8s kubectl config view --raw > ~/.kube/config
            sudo chown "$USER:$USER" ~/.kube/config
            ;;
    esac
    echo "✅ kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
}

verify_cluster() {
    local dist="${1:-Kubernetes}"
    echo "🔍 Verifying $dist cluster..."
    kubectl get nodes && kubectl get pods -A
    kubectl wait --for=condition=Ready pods --all --all-namespaces --timeout=10m --field-selector=status.phase!=Succeeded,status.phase!=Failed
    local not_ready=$(kubectl get pods -A -o json | jq -r '.items[]|select(.status.phase!="Running" and .status.phase!="Succeeded")|"\(.metadata.namespace)/\(.metadata.name)"')
    if [ -n "$not_ready" ]; then
        echo "❌ Some pods not ready: $not_ready" && kubectl get pods -A && exit 1
    fi
    echo "✅ $dist cluster ready!"
    command -v containerd >/dev/null 2>&1 && echo "containerd: $(containerd --version)" || true
    command -v crio >/dev/null 2>&1 && echo "crio: $(crio --version)" || true
}

# Main setup commands
setup_kubeadm() {
    local runtime="${1:-containerd}" version="${2:-latest}"
    free_disk_space && prepare_system_kubeadm
    [ "$runtime" = "containerd" ] && install_containerd "$version" || install_crio
    install_kubeadm_components && init_kubeadm_cluster "$runtime" && install_flannel
    verify_cluster "kubeadm"
}

setup_k3s() {
    free_disk_space
    echo "📦 Installing K3s..." && curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 ${1:-}
    echo "⏳ Waiting for K3s..." && sleep 120
    setup_kubectl "k3s" && verify_cluster "k3s"
}

setup_k0s() {
    free_disk_space
    echo "📦 Installing K0s..." && curl -sSLf https://get.k0s.sh | sudo sh
    sudo k0s install controller --single ${1:-}
    sudo mkdir -p /etc/k0s && k0s config create | sudo tee /etc/k0s/k0s.yaml
    sudo sed -i 's/metricsPort: 8080/metricsPort: 9999/' /etc/k0s/k0s.yaml && sudo k0s start
    echo "⏳ Waiting for K0s..." && sleep 120
    setup_kubectl "k0s" && verify_cluster "k0s"
}

setup_rke2() {
    free_disk_space
    echo "📦 Installing RKE2..." && curl -sfL https://get.rke2.io | sudo sh -
    sudo systemctl enable --now rke2-server.service
    echo "⏳ Waiting for RKE2..." && sleep 120
    setup_kubectl "rke2" && verify_cluster "rke2"
}

setup_microk8s() {
    free_disk_space
    echo "📦 Installing MicroK8s..." && sudo snap install microk8s --classic --channel=latest/stable
    sudo usermod -a -G microk8s "$USER"
    mkdir -p ~/.kube && sudo microk8s kubectl config view --raw > ~/.kube/config
    sudo chown "$USER:$USER" ~/.kube/config
    sudo microk8s status --wait-ready --timeout 300
    setup_kubectl "microk8s" && verify_cluster "microk8s"
}

# Command router
[ $# -lt 1 ] && { echo "Usage: $0 COMMAND [OPTIONS]"; echo "Commands: kubeadm, k3s, k0s, rke2, microk8s"; exit 1; }
case "$1" in
    kubeadm) shift; setup_kubeadm "$@" ;;
    k3s) shift; setup_k3s "$@" ;;
    k0s) shift; setup_k0s "$@" ;;
    rke2) shift; setup_rke2 "$@" ;;
    microk8s) shift; setup_microk8s "$@" ;;
    *) echo "Unknown command: $1"; exit 1 ;;
esac
