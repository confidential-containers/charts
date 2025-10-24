# Confidential Containers Helm Chart

Umbrella Helm chart for Confidential Containers. This chart deploys kata-containers runtime with confidential computing support for TEE technologies.

## Overview

This chart includes:
- **Runtime**: kata-containers with TEE support for x86_64 (AMD SEV-SNP, Intel TDX, with optional NVIDIA GPU support) and s390x (IBM SE).

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- Container runtime with RuntimeClass support (containerd or CRI-O)
- Hardware with TEE support

## Installation

### Quick Start

The chart is published to `oci://ghcr.io/confidential-containers/charts/confidential-containers` and supports multiple architectures:
- **x86_64**: Intel and AMD processors (default)
- **s390x**: IBM Z mainframes
- **aarch64**: ARM64 processors
- **peer-pods**: architecture independent

**Basic installation for x86_64:**
```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  --namespace kube-system
```

**For s390x:**
```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-s390x.yaml \
  --namespace kube-system
```

**For aarch64:**
```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-aarch64.yaml \
  --namespace kube-system
```

**For peer-pods:**
```bash
helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-remote.yaml \
  --namespace kube-system
```

### Detailed Installation Instructions

For complete installation instructions, customization options, and troubleshooting, see **[QUICKSTART.md](QUICKSTART.md)**, which includes:
- Installation from OCI registry and local chart
- Common customizations (debug logging, node selectors, image pull policy, private registries, k8s distributions)
- Custom values file examples
- Upgrading and uninstalling
- Troubleshooting commands
- Architecture-specific notes

## Supported TEE Technologies

### x86_64 (Intel/AMD)

- **AMD SEV-SNP** (Secure Encrypted Virtualization - Secure Nested Paging)
- **Intel TDX** (Trust Domain Extensions)
- **NVIDIA GPU with SEV-SNP** (GPU workloads with AMD SEV-SNP)
- **NVIDIA GPU with TDX** (GPU workloads with Intel TDX)
- **Development runtime** (qemu-coco-dev for testing)

### s390x (IBM Z)

- **IBM SE** (IBM s390x Secure Execution)
- **Development runtime** (qemu-coco-dev for testing)

### aarch64 (ARM64)

- **Development runtime** (qemu-coco-dev for testing)

### peer-pods (architecture independent)

- **remote runtime**

The chart deploys architecture-appropriate TEE runtime shims. The kata-deploy daemonset will install the runtimes based on the specified architecture and underlying hardware capabilities.

## Usage

After installation, use confidential containers in your pods by specifying the appropriate RuntimeClass:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: confidential-pod
spec:
  runtimeClassName: kata-qemu-coco-dev  # Choose from available RuntimeClasses
  containers:
  - name: app
    image: your-image:tag
```

### Available RuntimeClasses

The available RuntimeClasses depend on the architecture:

#### x86_64

- `kata-qemu-coco-dev` - Development/testing runtime
- `kata-qemu-snp` - AMD SEV-SNP
- `kata-qemu-tdx` - Intel TDX
- `kata-qemu-nvidia-gpu-snp` - NVIDIA GPU with AMD SEV-SNP
- `kata-qemu-nvidia-gpu-tdx` - NVIDIA GPU with Intel TDX

#### s390x

- `kata-qemu-coco-dev` - Development/testing runtime
- `kata-qemu-se` - IBM Secure Execution

#### aarch64

- `kata-qemu-coco-dev` - Development/testing runtime

#### peer-pods

- `kata-remote`- Peer-pods

### Verification

```bash

# Check the daemonset

kubectl get daemonset -n kube-system

# List available RuntimeClasses

kubectl get runtimeclass
```

## Configuration

### Architecture-Specific Values Files

The chart provides architecture-specific kata runtime configuration files:

- **values.yaml**: x86_64 defaults (SNP, TDX, and NVIDIA GPU shims)
- **values/kata-s390x.yaml**: IBM SE shim
- **values/kata-aarch64.yaml**: Development shim only
- **values/kata-remote.yaml**: Peer-pods

### Key Configuration Parameters

Parameters that are commonly customized (use `--set` flags):

| Parameter | Description | Default (from kata-deploy) |
|-----------|-------------|---------------------------|
| `kata-as-coco-runtime.imagePullPolicy` | Image pull policy | `Always` |
| `kata-as-coco-runtime.imagePullSecrets` | Image pull secrets for private registry | `[]` |
| `kata-as-coco-runtime.k8sDistribution` | Kubernetes distribution (k8s, k3s, rke2, k0s, microk8s) | `k8s` |
| `kata-as-coco-runtime.nodeSelector` | Node selector for deployment | `{}` |
| `kata-as-coco-runtime.env.debug` | Enable debug logging | `false` |

Parameters set by architecture-specific kata runtime values files:

| Parameter | Description | Set by values/kata-*.yaml |
|-----------|-------------|---------------------------|
| `architecture` | Architecture label for NOTES | `x86_64`, `s390x`, `aarch64`, or `remote` |
| `kata-as-coco-runtime.env.shims` | Runtime shims to install | Architecture-specific list |
| `kata-as-coco-runtime.env.defaultShim` | Default shim if `kata` is specified in pood annotations | Architecture-specific mappings |
| `kata-as-coco-runtime.env.snapshotterHandlerMapping` | Snapshotter handler mapping | Architecture-specific mappings |
| `kata-as-coco-runtime.env.pullTypeMapping` | Image pull type mapping | Architecture-specific mappings |

### Additional Parameters (kata-deploy options)

These inherit from kata-deploy defaults but can be overridden:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `kata-as-coco-runtime.image.reference` | Kata deploy image | `quay.io/kata-containers/kata-deploy` |
| `kata-as-coco-runtime.image.tag` | Kata deploy image tag | Chart's appVersion |
| `kata-as-coco-runtime.env.defaultShim` | Default shim if `kata` is specified in pod annotations | `""` |
| `kata-as-coco-runtime.env.createRuntimeClasses` | Create RuntimeClass resources | `true` |
| `kata-as-coco-runtime.env.createDefaultRuntimeClass` | Create default k8s RuntimeClass | `false` |
| `kata-as-coco-runtime.env.installationPrefix` | Installation path prefix | `""` (uses kata-deploy defaults) |
| `kata-as-coco-runtime.env.multiInstallSuffix` | Suffix for multiple installations | `""` |
| `kata-as-coco-runtime.env.allowedHypervisorAnnotations` | Allowed hypervisor annotations | `""` |
| `kata-as-coco-runtime.env.agentHttpsProxy` | HTTPS proxy for guest agent | `""` |
| `kata-as-coco-runtime.env.agentNoProxy` | No proxy settings for guest agent | `""` |
| `kata-as-coco-runtime.env.pullTypeMapping` | Image pull type mapping | `guest-pull` |

**See [QUICKSTART.md](QUICKSTART.md) for complete customization examples and usage.**

## Repository Structure

```
charts/
├── Chart.yaml                  # Chart metadata with dependencies
├── values.yaml                 # Default values (x86_64)
├── values/                     # Architecture-specific values
│   ├── kata-s390x.yaml         # s390x kata runtime config
│   ├── kata-aarch64.yaml       # aarch64 kata runtime config
│   └── kata-remote.yaml        # peer-pods kata runtime config
├── examples-custom-values.yaml # Example custom configurations
├── templates/                  # Helm templates
│   ├── _helpers.tpl            # Template helpers for architecture support
│   └── NOTES.txt               # Post-installation notes (architecture-aware)
├── README.md                   # Main documentation (you are here)
├── QUICKSTART.md               # Quick start guide with all customization examples
├── .helmignore
└── LICENSE
```

## Multi-Architecture Support

### Overview

The Helm chart supports multiple architectures with appropriate TEE technology shims for each platform:
- **x86_64**: AMD SEV-SNP, Intel TDX, NVIDIA GPU variants
- **s390x**: IBM Secure Execution
- **aarch64**: Development runtime

### Architecture-Specific Values Files

Architecture-specific kata runtime configurations are organized in the `values/` directory:
- **x86_64** - Default configuration in `values.yaml` (Intel/AMD platforms)
- `values/kata-s390x.yaml` - For IBM Z mainframes
- `values/kata-aarch64.yaml` - For ARM64 platforms
- `values/kata-remote.yaml` - For peer-pods

Each file contains:
- Architecture label for NOTES template
- Appropriate kata runtime shims for that architecture
- Snapshotter mappings

These files can be referenced directly via URL when installing from the OCI registry:

```bash

# s390x example

helm install coco oci://ghcr.io/confidential-containers/charts/confidential-containers \
  -f https://raw.githubusercontent.com/confidential-containers/charts/main/values/kata-s390x.yaml \
  --namespace kube-system
```

### How It Works

1. **values.yaml**: Minimal configuration with x86_64 kata runtime defaults
2. **Architecture files in values/**: Set architecture-specific kata runtime shims and mappings
3. **NOTES template**: Dynamically displays actual configured shims
4. **User customizations**: Added via `--set` flags (imagePullPolicy, nodeSelector, k8sDistribution, etc.)

## Upgrading

Support for upgrading is coming soon

## Uninstallation

```bash
helm uninstall coco --namespace kube-system
```

The uninstall command is the same regardless of whether you installed from the OCI registry or locally.

## Contributing

See the [Confidential Containers contributing guide](https://github.com/confidential-containers/documentation/blob/main/CONTRIBUTING.md).

## License

Apache License 2.0
