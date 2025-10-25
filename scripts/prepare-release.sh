#!/usr/bin/env bash
#
# prepare-release.sh - Prepare a new release of the Confidential Containers Helm chart
#
# This script:
# 1. Fetches the latest kata-containers release
# 2. Updates Chart.yaml with the new kata-deploy version
# 3. Bumps the chart version
# 4. Updates Helm dependencies
# 5. Creates a new branch
# 6. Commits the changes
# 7. Opens a pull request
#
# Requirements:
# System tools (must be pre-installed):
# - git
# - gh (GitHub CLI)
# - curl
#
# The script will automatically download the latest versions of:
# - yq (mikefarah/yq)
# - jq
# - helm
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Temporary directory for tools
TOOLS_DIR=""

# Track script state for rollback
BRANCH_CREATED=""
ORIGINAL_BRANCH=""
CHANGES_MADE=false

# Helper functions
info() {
    echo -e "${BLUE}ℹ${NC} $*" >&2
}

success() {
    echo -e "${GREEN}✅${NC} $*" >&2
}

warning() {
    echo -e "${YELLOW}⚠️${NC} $*" >&2
}

error() {
    echo -e "${RED}❌${NC} $*" >&2
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    # If script failed and we made changes, rollback
    if [ ${exit_code} -ne 0 ] && [ "${CHANGES_MADE}" = true ]; then
        warning "Script failed, rolling back changes..."
        
        # Always try to switch back to original branch if we have it
        if [ -n "${ORIGINAL_BRANCH}" ]; then
            local current_branch
            current_branch=$(git branch --show-current)
            
            if [ "${current_branch}" != "${ORIGINAL_BRANCH}" ]; then
                info "Switching back to ${ORIGINAL_BRANCH}..."
                if git checkout "${ORIGINAL_BRANCH}" 2>&1; then
                    success "Switched back to ${ORIGINAL_BRANCH}"
                else
                    error "Failed to switch back to ${ORIGINAL_BRANCH}"
                fi
            fi
        fi
        
        # If we created a branch, delete it
        if [ -n "${BRANCH_CREATED}" ]; then
            info "Deleting branch ${BRANCH_CREATED}..."
            if git branch -D "${BRANCH_CREATED}" 2>&1; then
                success "Deleted branch ${BRANCH_CREATED}"
            else
                warning "Could not delete branch ${BRANCH_CREATED} (may not exist or already deleted)"
            fi
        fi
        
        # Reset any uncommitted changes on the original branch
        if [ -f Chart.yaml ]; then
            info "Resetting Chart.yaml..."
            git checkout -- Chart.yaml 2>&1 || true
        fi
        
        if [ -f Chart.lock ]; then
            info "Resetting Chart.lock..."
            git checkout -- Chart.lock 2>&1 || true
        fi
        
        success "Rollback complete"
    fi
    
    # Clean up temporary tools directory
    if [ -n "${TOOLS_DIR}" ] && [ -d "${TOOLS_DIR}" ]; then
        info "Cleaning up temporary tools directory..."
        rm -rf "${TOOLS_DIR}"
    fi
}

# Register cleanup on exit
trap cleanup EXIT

# Check if working tree is clean
check_clean_tree() {
    info "Checking working tree status..."
    
    if ! git diff-index --quiet HEAD --; then
        error "Working tree is not clean"
        error "Please commit or stash your changes before running this script"
        error ""
        error "Uncommitted changes:"
        git status --short >&2
        exit 1
    fi
    
    success "Working tree is clean"
}

# Check required system commands
check_requirements() {
    local missing_tools=()
    
    # Only check for system tools (git, gh, curl are needed from system)
    for tool in git gh curl; do
        if ! command -v "${tool}" &> /dev/null; then
            missing_tools+=("${tool}")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        error "Missing required system tools: ${missing_tools[*]}"
        error "Please install them before running this script"
        exit 1
    fi
    
    success "All required system tools are available"
}

# Download and setup tools
setup_tools() {
    info "Setting up tools in temporary directory..."
    
    # Create temporary directory
    TOOLS_DIR="$(mktemp -d)"
    info "Tools directory: ${TOOLS_DIR}"
    
    # Detect OS and architecture
    local os=""
    local arch=""
    
    case "$(uname -s)" in
        Linux*)  os="linux" ;;
        Darwin*) os="darwin" ;;
        *)
            error "Unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac
    
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    
    info "Detected: ${os}/${arch}"
    
    # Download yq (mikefarah/yq - the Go version)
    info "Downloading yq..."
    local yq_version
    yq_version="$(curl -sS https://api.github.com/repos/mikefarah/yq/releases/latest | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/')"
    local yq_url="https://github.com/mikefarah/yq/releases/download/${yq_version}/yq_${os}_${arch}"
    
    if curl -sS -L -o "${TOOLS_DIR}/yq" "${yq_url}"; then
        chmod +x "${TOOLS_DIR}/yq"
        success "Downloaded yq ${yq_version}"
    else
        error "Failed to download yq"
        exit 1
    fi
    
    # Download jq
    info "Downloading jq..."
    local jq_version
    jq_version="$(curl -sS https://api.github.com/repos/jqlang/jq/releases/latest | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/')"
    local jq_url="https://github.com/jqlang/jq/releases/download/${jq_version}/jq-${os}-${arch}"
    
    if curl -sS -L -o "${TOOLS_DIR}/jq" "${jq_url}"; then
        chmod +x "${TOOLS_DIR}/jq"
        success "Downloaded jq ${jq_version}"
    else
        error "Failed to download jq"
        exit 1
    fi
    
    # Download helm
    info "Downloading helm..."
    local helm_version
    helm_version="$(curl -sS https://api.github.com/repos/helm/helm/releases/latest | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/')"
    local helm_tar="helm-${helm_version}-${os}-${arch}.tar.gz"
    local helm_url="https://get.helm.sh/${helm_tar}"
    
    if curl -sS -L -o "${TOOLS_DIR}/${helm_tar}" "${helm_url}"; then
        tar -xzf "${TOOLS_DIR}/${helm_tar}" -C "${TOOLS_DIR}" --strip-components=1 "${os}-${arch}/helm"
        rm "${TOOLS_DIR}/${helm_tar}"
        chmod +x "${TOOLS_DIR}/helm"
        success "Downloaded helm ${helm_version}"
    else
        error "Failed to download helm"
        exit 1
    fi
    
    # Add tools directory to PATH
    export PATH="${TOOLS_DIR}:${PATH}"
    
    # Verify tools work
    info "Verifying tools..."
    "${TOOLS_DIR}/yq" --version
    "${TOOLS_DIR}/jq" --version
    "${TOOLS_DIR}/helm" version --short
    
    success "All tools ready"
}

# Get the latest kata-containers release
get_latest_kata_release() {
    info "Fetching latest kata-containers release..."
    
    local latest_release
    latest_release=$(curl -sS https://api.github.com/repos/kata-containers/kata-containers/releases/latest | jq -r '.tag_name')
    
    if [ -z "${latest_release}" ] || [ "${latest_release}" = "null" ]; then
        error "Failed to fetch latest kata-containers release"
        exit 1
    fi
    
    # Remove 'v' prefix if present
    latest_release="${latest_release#v}"
    
    success "Latest kata-containers release: ${latest_release}"
    echo "${latest_release}"
}

# Get current versions from Chart.yaml
get_current_versions() {
    local chart_version
    local kata_version
    
    chart_version=$(yq '.version' Chart.yaml)
    kata_version=$(yq '.dependencies[] | select(.name == "kata-deploy") | .version' Chart.yaml | head -1)
    
    echo "${chart_version}" "${kata_version}"
}

# Bump semantic version
bump_version() {
    local version="$1"
    local part="${2:-patch}" # major, minor, or patch
    
    IFS='.' read -r major minor patch <<< "${version}"
    
    # Remove any suffix (e.g., -rc.1)
    patch="${patch%%-*}"
    
    case "${part}" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            error "Invalid version part: ${part}"
            exit 1
            ;;
    esac
    
    echo "${major}.${minor}.${patch}"
}

# Update Chart.yaml
update_chart() {
    local new_chart_version="$1"
    local new_kata_version="$2"
    
    info "Updating Chart.yaml..."
    
    # Mark that we're making changes (for potential rollback)
    CHANGES_MADE=true
    
    # Update chart version and appVersion
    yq -i ".version = \"${new_chart_version}\"" Chart.yaml
    yq -i ".appVersion = \"${new_chart_version}\"" Chart.yaml
    
    # Update kata-deploy dependency version
    yq -i "(.dependencies[] | select(.name == \"kata-deploy\") | .version) = \"${new_kata_version}\"" Chart.yaml
    
    success "Updated Chart.yaml"
    info "  Chart version: ${new_chart_version}"
    info "  kata-deploy version: ${new_kata_version}"
}

# Update Helm dependencies
update_dependencies() {
    info "Running update-dependencies.sh script..."
    
    if ! "${SCRIPT_DIR}/update-dependencies.sh"; then
        error "Failed to update dependencies"
        exit 1
    fi
}

# Create branch and commit
create_branch_and_commit() {
    local new_chart_version="$1"
    local new_kata_version="$2"
    local branch_name="topic/prepare-release-${new_chart_version}"
    
    info "Creating branch: ${branch_name}"
    
    # Save current branch for potential rollback
    ORIGINAL_BRANCH=$(git branch --show-current)
    
    # Check if branch already exists locally and delete it
    if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
        warning "Branch ${branch_name} already exists locally, deleting..."
        git branch -D "${branch_name}" >/dev/null 2>&1 || true
    fi
    
    # Check if branch exists on remote and delete it
    if git ls-remote --exit-code --heads origin "${branch_name}" >/dev/null 2>&1; then
        warning "Branch ${branch_name} exists on remote, deleting..."
        git push origin --delete "${branch_name}" >/dev/null 2>&1 || true
    fi
    
    # Create new branch (suppress output)
    git checkout -b "${branch_name}" >/dev/null 2>&1
    BRANCH_CREATED="${branch_name}"
    
    # Stage changes (suppress output)
    git add Chart.yaml Chart.lock >/dev/null 2>&1
    
    # Create commit
    local commit_message
    commit_message=$(cat <<EOF
Prepare release ${new_chart_version}

Update kata-deploy dependency to ${new_kata_version}

Changes:
- Chart version: ${new_chart_version}
- kata-deploy version: ${new_kata_version}
- Updated Chart.lock

This is an automated commit created by scripts/prepare-release.sh
EOF
)
    
    # Commit changes (suppress output to avoid contaminating return value)
    git commit -m "${commit_message}" >/dev/null 2>&1
    
    success "Created commit on branch ${branch_name}"
    echo "${branch_name}"
}

# Push and create PR
create_pull_request() {
    local branch_name="$1"
    local new_chart_version="$2"
    local new_kata_version="$3"
    
    info "Pushing branch to origin..."
    git push -u origin "${branch_name}"
    
    success "Branch pushed to origin"
    
    info "Creating pull request..."
    
    local pr_body
    pr_body=$(cat <<EOF
## Release ${new_chart_version}

This PR prepares the release ${new_chart_version} with updated kata-deploy dependency.

### Changes

- **Chart version**: ${new_chart_version}
- **kata-deploy version**: ${new_kata_version}
- Updated Chart.lock with new dependencies

### Checklist

- [ ] Review Chart.yaml changes
- [ ] Verify kata-deploy version is correct
- [ ] Test installation on x86_64
- [ ] Test installation on s390x
- [ ] Test installation on aarch64
- [ ] Test installation for peer-pods
- [ ] Update CHANGELOG.md (if applicable)
- [ ] Merge this PR
- [ ] Run the Release Helm Chart workflow

### After Merge

Once this PR is merged, trigger the release workflow:
1. Go to Actions → Release Helm Chart
2. Click "Run workflow"
3. Select the main branch
4. Click "Run workflow"

This will create:
- Git tag: \`v${new_chart_version}\`
- GitHub Release with chart package
- OCI Registry: \`ghcr.io/{org}/charts/confidential-containers:${new_chart_version}\`

---
*This PR was automatically created by \`scripts/prepare-release.sh\`*
EOF
)
    
    if gh pr create \
        --title "Release ${new_chart_version}" \
        --body "${pr_body}" \
        --base main \
        --head "${branch_name}"; then
        success "Pull request created successfully!"
        
        # Switch back to original branch
        if [ -n "${ORIGINAL_BRANCH}" ]; then
            info "Switching back to ${ORIGINAL_BRANCH}..."
            git checkout "${ORIGINAL_BRANCH}"
            success "Switched back to ${ORIGINAL_BRANCH}"
        fi
    else
        error "Failed to create pull request"
        error "You can create it manually at:"
        error "  https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/compare/${branch_name}"
        exit 1
    fi
}

# Main function
main() {
    local version_bump="${1:-patch}"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║     Confidential Containers Helm Chart - Release Preparation     ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Check working tree is clean before starting
    check_clean_tree
    
    # Check requirements
    check_requirements
    
    # Setup tools
    setup_tools
    
    # Get latest kata-containers release
    local latest_kata_version
    latest_kata_version=$(get_latest_kata_release)
    
    # Get current versions
    read -r current_chart_version current_kata_version <<< "$(get_current_versions)"
    
    info "Current versions:"
    info "  Chart: ${current_chart_version}"
    info "  kata-deploy: ${current_kata_version}"
    echo ""
    
    # Check if kata-deploy is already up to date
    if [ "${current_kata_version}" = "${latest_kata_version}" ]; then
        warning "kata-deploy is already at the latest version (${latest_kata_version})"
        read -rp "Do you want to continue and bump the chart version anyway? [y/N] " -n 1
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Aborted"
            exit 0
        fi
    fi
    
    # Calculate new chart version
    local new_chart_version
    new_chart_version=$(bump_version "${current_chart_version}" "${version_bump}")
    
    info "New versions:"
    info "  Chart: ${new_chart_version}"
    info "  kata-deploy: ${latest_kata_version}"
    echo ""
    
    # Confirm
    read -rp "Proceed with these changes? [y/N] " -n 1
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Aborted"
        exit 0
    fi
    
    # Update Chart.yaml
    update_chart "${new_chart_version}" "${latest_kata_version}"
    
    # Update dependencies
    update_dependencies
    
    # Create branch and commit
    local branch_name
    branch_name=$(create_branch_and_commit "${new_chart_version}" "${latest_kata_version}")
    
    # Create PR
    create_pull_request "${branch_name}" "${new_chart_version}" "${latest_kata_version}"
    
    # Mark as successful - no rollback needed
    CHANGES_MADE=false
    
    echo ""
    success "✨ Release preparation complete!"
    echo ""
    info "Next steps:"
    info "  1. Review the pull request"
    info "  2. Test the changes"
    info "  3. Merge the PR"
    info "  4. Run the 'Release Helm Chart' workflow from GitHub Actions"
    echo ""
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        cat <<EOF
Usage: $0 [VERSION_BUMP]

Prepare a new release of the Confidential Containers Helm chart.

VERSION_BUMP: major, minor, or patch (default: patch)
  - major: 1.0.0 → 2.0.0
  - minor: 1.0.0 → 1.1.0
  - patch: 1.0.0 → 1.0.1

Examples:
  $0              # Bump patch version (0.16.0 → 0.16.1)
  $0 minor        # Bump minor version (0.16.0 → 0.17.0)
  $0 major        # Bump major version (0.16.0 → 1.0.0)

Requirements:
  - yq, gh, helm, git, jq, curl

This script will:
  1. Fetch the latest kata-containers release
  2. Update Chart.yaml with new versions
  3. Update Helm dependencies
  4. Create a new branch
  5. Commit the changes
  6. Push and create a pull request

EOF
        exit 0
        ;;
    major|minor|patch|"")
        main "${1:-patch}"
        ;;
    *)
        error "Invalid argument: $1"
        error "Use -h or --help for usage information"
        exit 1
        ;;
esac

