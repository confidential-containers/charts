# Quick Start Guide

Get started with Confidential Containers on your architecture in just a few commands!

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- Container runtime with RuntimeClass support (containerd or CRI-O)
- Hardware with TEE support (for production use)

## Installation

### Installing from OCI Registry (Recommended)

The chart is published to the OCI registry at `oci://ghcr.io/confidential-containers/charts/confidential-containers`.

#### For x86_64 (Intel/AMD)

```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --namespace kube-system
```

**What you get:**
- AMD SEV-SNP support (kata-qemu-snp)
- Intel TDX support (kata-qemu-tdx)
- NVIDIA GPU variants
- Development runtime (kata-qemu-coco-dev)

#### For s390x (IBM Z)

```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-s390x.yaml \
  --namespace kube-system
```

**What you get:**
- IBM Secure Execution (kata-qemu-se)
- Development runtime (kata-qemu-coco-dev)

#### For aarch64 (ARM64)

```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-aarch64.yaml \
  --namespace kube-system
```

**What you get:**
- Development runtime (kata-qemu-coco-dev)

#### For remote (peer-pods)

```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-remote.yaml \
  --namespace kube-system
```

**What you get:**
- remote runtime (peer-pods / Cloud API Adaptopr integration)

### Installing from Local Repository (Development)

If you're developing or customizing the chart:

```bash

# Clone the repository

git clone https://github.com/confidential-containers/charts.git
cd charts

# Update dependencies

helm dependencies update

# Install for your architecture

helm install coco . --namespace kube-system  # x86_64

# OR

helm install coco . -f values/kata-s390x.yaml --namespace kube-system  # s390x

# OR

helm install coco . -f values/kata-aarch64.yaml --namespace kube-system  # aarch64
```

## Verify Installation

```bash

# Check the daemonset is running

kubectl get daemonset -n kube-system

# List available RuntimeClasses

kubectl get runtimeclass
```

## Using Confidential Containers

### Create a Pod with Confidential Computing

#### x86_64 Example (AMD SEV-SNP)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: confidential-pod-snp
spec:
  runtimeClassName: kata-qemu-snp
  containers:
  - name: app
    image: nginx:latest
```

#### s390x Example (IBM SE)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: confidential-pod-se
spec:
  runtimeClassName: kata-qemu-se
  containers:
  - name: app
    image: nginx:latest
```

### Apply the Pod

```bash
kubectl apply -f pod.yaml
kubectl get pods -w
```

## Common Customizations

You can combine architecture values files (with `-f`) with `--set` flags for customizations.

### Enable Debug Logging

```bash

# For x86_64

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.env.debug=true \
  --namespace kube-system

# For s390x

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-s390x.yaml \
  --set kata-as-coco-runtime.env.debug=true \
  --namespace kube-system
```

### Deploy on Specific Nodes (Node Selector)

```bash

# x86_64 - deploy only on worker nodes

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.nodeSelector."node-role\.kubernetes\.io/worker"="" \
  --namespace kube-system

# s390x - deploy on nodes with custom label

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-s390x.yaml \
  --set kata-as-coco-runtime.nodeSelector."confidential-computing"="enabled" \
  --namespace kube-system
```

### Custom Image Pull Policy

```bash

# Use IfNotPresent instead of Always (default)

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-s390x.yaml \
  --set kata-as-coco-runtime.imagePullPolicy=IfNotPresent \
  --namespace kube-system
```

### Private Registry with Image Pull Secrets

```bash

# Create the secret first

kubectl create secret docker-registry my-registry-secret \
  --docker-server=my-registry.example.com \
  --docker-username=myuser \
  --docker-password=mypassword \
  --namespace kube-system

# Reference it in the installation

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-s390x.yaml \
  --set-json 'kata-as-coco-runtime.imagePullSecrets=[{"name":"my-registry-secret"}]' \
  --namespace kube-system
```

### Different Kubernetes Distribution

```bash

# For k3s

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.k8sDistribution=k3s \
  --namespace kube-system

# For RKE2 on s390x

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-s390x.yaml \
  --set kata-as-coco-runtime.k8sDistribution=rke2 \
  --namespace kube-system

# Supported: k8s (default), k3s, rke2, k0s, microk8s

```

### Multiple Customizations Combined

```bash

# s390x with: debug, specific nodes, and k3s distribution

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-s390x.yaml \
  --set kata-as-coco-runtime.env.debug=true \
  --set kata-as-coco-runtime.nodeSelector."node-role\.kubernetes\.io/worker"="" \
  --set kata-as-coco-runtime.k8sDistribution=k3s \
  --namespace kube-system
```

### Custom Shims (x86_64 example - SNP and TDX only)

```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.env.shims="qemu-snp qemu-tdx qemu-coco-dev" \
  --set kata-as-coco-runtime.env.snapshotterHandlerMapping="qemu-snp:nydus\,qemu-tdx:nydus\,qemu-coco-dev:nydus" \
  --namespace kube-system
```

### Custom Values File

For complex configurations, create a custom values file:

```yaml

# my-values.yaml

architecture: s390x

kata-as-coco-runtime:
  env:
    debug: "true"
    shims: "qemu-coco-dev qemu-se"
    snapshotterHandlerMapping: "qemu-coco-dev:nydus,qemu-se:nydus"
    agentHttpsProxy: "http://proxy.example.com:8080"
  nodeSelector:
    node-role.kubernetes.io/worker: ""
```

Then install:

```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f my-values.yaml \
  --namespace kube-system
```

## Advanced Configuration

### kata-deploy Specific Options

The following options are inherited from the upstream kata-deploy chart and can be customized:

#### Default Runtime Shim

Set which shim to use by default when none is specified in pod annotations (by default, kata-deploy auto-detects the appropriate shim):

```bash

# Force TDX as the default shim on x86_64

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.env.defaultShim=qemu-tdx \
  --namespace kube-system
```

#### Custom Installation Path

Override the installation prefix (by default, kata-deploy uses its built-in defaults):

```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.env.installationPrefix=/opt/custom-kata \
  --namespace kube-system
```

#### Multiple Installations

Enable multiple Kata installations on the same node with a suffix:

```bash

# Useful for testing different versions side-by-side

helm install coco-test oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.env.multiInstallSuffix=/opt/kata-PR12345 \
  --namespace kube-system
```

#### Custom Image Tag

Override the image tag (by default uses chart's appVersion):

```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.image.tag=3.21.0 \
  --namespace kube-system
```

#### RuntimeClass Management

Control creation of Kubernetes RuntimeClass resources:

```bash

# Disable RuntimeClass creation (manage them manually)

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.env.createRuntimeClasses=false \
  --namespace kube-system

# Create the default Kubernetes RuntimeClass

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.env.createDefaultRuntimeClass=true \
  --namespace kube-system
```

#### Hypervisor Annotations

Enable specific annotations to be passed when launching containers:

```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.env.allowedHypervisorAnnotations="io.katacontainers.*" \
  --namespace kube-system
```

#### Proxy Configuration for Kata Agent

Configure proxy settings for the Kata agent:

```bash

# Set HTTPS proxy

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.env.agentHttpsProxy="https://proxy.example.com:8080" \
  --namespace kube-system

# Set NO_PROXY

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.env.agentNoProxy="localhost,127.0.0.1,.svc" \
  --namespace kube-system

# Combine both

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --set kata-as-coco-runtime.env.agentHttpsProxy="https://proxy.example.com:8080" \
  --set kata-as-coco-runtime.env.agentNoProxy="localhost,127.0.0.1" \
  --namespace kube-system
```

## Upgrading

Upgrades are not yet supported

## Uninstalling

```bash
helm uninstall coco --namespace kube-system
```

## Troubleshooting

### Check Helm Release Status

```bash
helm status coco -n kube-system
```

### View Helm Release Details

```bash

# View all release information

helm get all coco -n kube-system

# View rendered manifests

helm get manifest coco -n kube-system

# View values used

helm get values coco -n kube-system
```

### Check DaemonSet Logs

```bash
kubectl logs -n kube-system -l name=kata-deploy
```

### Verify RuntimeClasses

```bash
kubectl get runtimeclass -o yaml
```

## Helm Chart Information

### Show Chart Values

```bash
helm show values oci://ghcr.io/confidential-containers/charts/confidential-containers
```

### Show Chart README

```bash
helm show readme oci://ghcr.io/confidential-containers/charts/confidential-containers
```

### List Installed Charts

```bash
helm list -n kube-system
```

## Important Notes

1. **Comma Escaping:** When using `--set` with values containing commas, escape them with `\,`
2. **Node Selectors:** When setting node selectors with dots in the key, escape them: `node-role\.kubernetes\.io/worker`
3. **Namespace:** All examples use `kube-system` namespace. Adjust as needed for your environment.
4. **Architecture:** The default architecture is x86_64. Other architectures must be explicitly specified.

## Next Steps

- **Advanced Configuration:** See `examples-custom-values.yaml`
- **Full Documentation:** See `README.md`

## Getting Help

- [Confidential Containers Documentation](https://github.com/confidential-containers)
- [Kata Containers Documentation](https://github.com/kata-containers/kata-containers)
- [Community Slack](https://slack.cncf.io/) - #confidential-containers channel

## Architecture-Specific Notes

### x86_64

- Requires AMD or Intel processors with SEV-SNP or TDX support
- GPU variants require NVIDIA GPU with appropriate drivers

### s390x

- Requires IBM Z15 or newer with Secure Execution support
- Ensure the host kernel has SE support enabled

### aarch64

- Currently only development runtime is available
- TEE support coming soon

### peer-pods

- To be used together with Cloud API Adaptor
