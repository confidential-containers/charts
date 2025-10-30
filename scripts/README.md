# Helm Chart Scripts

This directory contains helper scripts for managing the Confidential Containers Helm chart.

## Updating Dependencies

Most users don't need to run this command, because when installing from an OCI registry, Helm fetches dependencies automatically.

If you are developing this chart and trying to install local changes (e.g., `helm install coco . --namespace coco-system`), you need to download the dependency charts first:

```bash
helm dependency update
```

This downloads dependency chart tarballs to the `charts/` directory. These files are required for local installation but are not committed to git.

**Note:** The `prepare-release.sh` script runs this automatically when preparing releases.

## prepare-release.sh

Automates the release preparation process for the Helm chart.

### What it does

1. **Fetches the latest kata-containers release** from GitHub
2. **Updates Chart.yaml** with:
   - New chart version (automatically bumped)
   - New kata-deploy dependency version
3. **Updates Helm dependencies** (runs `helm dependency update`)
4. **Creates a new branch** (e.g., `topic/prepare-release-0.17.0`)
5. **Commits the changes** with a descriptive message
6. **Pushes and creates a pull request** with a detailed description

### Requirements

The following **system tools** must be pre-installed:

- **git** - Version control
- **gh** - GitHub CLI (for creating PRs)
- **curl** - HTTP client

The script will **automatically download** the latest versions of:
- **yq** (mikefarah/yq) - YAML processor
- **jq** - JSON processor
- **helm** - Helm package manager

These tools are downloaded to a temporary directory and cleaned up after the script completes.

Install system tools on Ubuntu/Debian:
```bash
sudo apt install git gh curl
```

### Usage

```bash
# Default: bump patch version (0.16.0 → 0.16.1)
./scripts/prepare-release.sh

# Bump minor version (0.16.0 → 0.17.0)
./scripts/prepare-release.sh minor

# Bump major version (0.16.0 → 1.0.0)
./scripts/prepare-release.sh major

# Show help
./scripts/prepare-release.sh --help
```

### Version Bumping

The script supports semantic versioning with three bump types:

| Type | Example |
|------|---------|
| `patch` (default) | 0.16.0 → 0.16.1 |
| `minor` | 0.16.0 → 0.17.0 |
| `major` | 0.16.0 → 1.0.0 |

### Example Workflow

```bash
$ cd /path/to/confidential-containers/charts

$ ./scripts/prepare-release.sh minor

╔══════════════════════════════════════════════════════════════════╗
║     Confidential Containers Helm Chart - Release Preparation    ║
╚══════════════════════════════════════════════════════════════════╝

✅ All required system tools are available
ℹ Setting up tools in temporary directory...
ℹ Tools directory: /tmp/tmp.Xxxxxxxx
ℹ Detected: linux/amd64
ℹ Downloading yq...
✅ Downloaded yq v4.x.x
ℹ Downloading jq...
✅ Downloaded jq jq-1.x
ℹ Downloading helm...
✅ Downloaded helm v3.x.x
ℹ Verifying tools...
yq (https://github.com/mikefarah/yq/) version v4.x.x
jq-1.x
v3.x.x+gxxxxxxx
✅ All tools ready
ℹ Fetching latest kata-containers release...
✅ Latest kata-containers release: 3.22.0
ℹ Current versions:
ℹ   Chart: 0.16.0
ℹ   kata-deploy: 3.21.0

ℹ New versions:
ℹ   Chart: 0.17.0
ℹ   kata-deploy: 3.22.0

Proceed with these changes? [y/N] y
ℹ Updating Chart.yaml...
✅ Updated Chart.yaml
ℹ   Chart version: 0.17.0
ℹ   kata-deploy version: 3.22.0
ℹ Updating Helm dependencies...
✅ Helm dependencies updated
ℹ Creating branch: release-0.17.0
✅ Created commit on branch release-0.17.0
ℹ Pushing branch to origin...
✅ Branch pushed to origin
ℹ Creating pull request...
✅ Pull request created successfully!

✅ ✨ Release preparation complete!

ℹ Next steps:
ℹ   1. Review the pull request
ℹ   2. Test the changes
ℹ   3. Merge the PR
ℹ   4. Run the 'Release Helm Chart' workflow from GitHub Actions
ℹ Cleaning up temporary tools directory...
✅ Cleanup complete
```

### What the Pull Request Contains

The automatically created PR includes:

- **Title**: `Release X.Y.Z`
- **Description**: 
  - Summary of changes
  - kata-deploy version update
  - Testing checklist for all architectures
  - Instructions for triggering the release workflow
- **Commit**: Detailed commit message with all changes
- **Files**: 
  - `Chart.yaml` (updated versions)
  - `Chart.lock` (updated dependencies)

### After the PR is Merged

1. Go to **Actions** → **Release Helm Chart** in GitHub
2. Click **Run workflow**
3. Select the **main** branch
4. Click **Run workflow**

This will:
- Create a git tag (`v{version}`)
- Package the Helm chart
- Publish to GHCR (`ghcr.io/{org}/charts/confidential-containers:{version}`)
- Create a GitHub Release with the chart artifact

### Error Handling

The script includes comprehensive error handling:

- **Missing tools**: Lists all missing requirements
- **API failures**: Clear error messages if GitHub API is unavailable
- **Dirty working tree**: Prevents running if there are uncommitted changes
- **PR creation fails**: Provides manual URL for creating the PR
- **Confirmation prompts**: Asks for confirmation before making changes

### Troubleshooting

**Q: Script fails with "Working tree is not clean"**  
A: Commit or stash your changes before running the script:
```bash
git stash
./scripts/prepare-release.sh
git stash pop
```

**Q: kata-deploy is already up to date**  
A: The script will ask if you want to continue and bump the chart version anyway.

**Q: PR creation fails**  
A: Make sure you're authenticated with GitHub CLI:
```bash
gh auth login
```

**Q: How do I update to a specific kata-containers version?**  
A: Manually edit `Chart.yaml` before running the script, or edit it after the script creates the PR.

### Dry Run

To see what would happen without making changes:

```bash
# Review current versions
yq '.version' Chart.yaml
yq '.dependencies[] | select(.name == "kata-deploy") | .version' Chart.yaml

# Check latest kata-containers release
curl -sS https://api.github.com/repos/kata-containers/kata-containers/releases/latest | jq -r '.tag_name'
```

## Additional Scripts

Additional scripts may be added here for:
- Running validation tests (see `.github/scripts/` for current validation scripts)
- Generating changelogs
- Updating documentation
- Running security scans
