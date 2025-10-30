#!/usr/bin/env bash
#
# Helm Operations Script
# All Helm-related operations in one place
#
# Usage: helm-operations.sh COMMAND [OPTIONS]
#
# Commands:
#   update-dependencies [CHART_DIR]
#       Update Helm chart dependencies
#
#   validate [CHART_DIR]
#       Validate Helm chart using helm lint
#
#   install RELEASE_NAME [OPTIONS]
#       Install Helm chart
#       Options:
#         --namespace NAME       Kubernetes namespace (default: coco-system)
#         --values-file PATH     Path to values file (optional)
#         --extra-args ARGS      Extra Helm install arguments (optional)
#         --wait-timeout TIME    Timeout for helm install --wait (default: 15m)
#         --chart-dir DIR        Chart directory (default: current directory)

set -euo pipefail

# Parse command
if [ $# -lt 1 ]; then
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  update-dependencies [CHART_DIR]"
    echo "  validate [CHART_DIR]"
    echo "  install RELEASE_NAME [OPTIONS]"
    exit 1
fi

COMMAND="$1"
shift

# Command implementations
cmd_update_dependencies() {
    local chart_dir="${1:-.}"
    
    cd "${chart_dir}"
    
    echo "📦 Updating Helm dependencies..."
    helm dependency update
    echo "✅ Dependencies updated"
}

cmd_validate() {
    local chart_dir="${1:-.}"
    
    cd "${chart_dir}"
    
    echo "🔍 Validating chart..."
    helm lint .
    echo "✅ Chart is valid"
}

cmd_install() {
    # Default values
    local namespace="coco-system"
    local values_file=""
    local extra_args=""
    local wait_timeout="15m"
    local chart_dir="."
    
    # Parse arguments
    if [ $# -lt 1 ]; then
        echo "Usage: $0 install RELEASE_NAME [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --namespace NAME       Kubernetes namespace (default: coco-system)"
        echo "  --values-file PATH     Path to values file (optional)"
        echo "  --extra-args ARGS      Extra Helm install arguments (optional)"
        echo "  --wait-timeout TIME    Timeout for helm install --wait (default: 15m)"
        echo "  --chart-dir DIR        Chart directory (default: current directory)"
        exit 1
    fi
    
    local release_name="$1"
    shift
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --namespace)
                namespace="$2"
                shift 2
                ;;
            --values-file)
                values_file="$2"
                shift 2
                ;;
            --extra-args)
                extra_args="$2"
                shift 2
                ;;
            --wait-timeout)
                wait_timeout="$2"
                shift 2
                ;;
            --chart-dir)
                chart_dir="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    cd "${chart_dir}"
    
    echo "🚀 Installing chart: ${release_name}"
    echo "   Namespace: ${namespace}"
    echo "   Extra args: ${extra_args}"
    if [ -n "${values_file}" ]; then
      echo "   Values file: ${values_file}"
    fi
    
    local install_cmd="helm install ${release_name} . \
      --namespace ${namespace} \
      --create-namespace \
      --debug"
    
    if [ -n "${values_file}" ]; then
      install_cmd="${install_cmd} -f ${values_file}"
    fi
    
    if [ -n "${extra_args}" ]; then
      install_cmd="${install_cmd} ${extra_args}"
    fi
    
    echo "Running: ${install_cmd}"
    
    if eval "${install_cmd}"; then
      echo "✅ Chart installed successfully"
      if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "result=success" >> "${GITHUB_OUTPUT}"
      fi
    else
      echo "❌ Chart installation failed"
      if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "result=failed" >> "${GITHUB_OUTPUT}"
      fi
      exit 1
    fi
}

# Execute command
case "${COMMAND}" in
    update-dependencies)
        cmd_update_dependencies "$@"
        ;;
    validate)
        cmd_validate "$@"
        ;;
    install)
        cmd_install "$@"
        ;;
    *)
        echo "Unknown command: ${COMMAND}"
        echo "Available commands: update-dependencies, validate, install"
        exit 1
        ;;
esac
