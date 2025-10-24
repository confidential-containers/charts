#!/usr/bin/env python3
"""
Validate that all kata-deploy chart configuration options are documented
in the Confidential Containers helm chart documentation.

This script:
1. Extracts configuration options from the upstream kata-deploy chart
2. Checks if they are documented in our values.yaml comments and docs
3. Reports missing or incomplete documentation
"""

import argparse
import sys
import yaml
import re
from pathlib import Path
from typing import Any, Dict, List, Set, Tuple, Optional
from dataclasses import dataclass, field

try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False


@dataclass
class ConfigOption:
    """Represents a configuration option from kata-deploy chart."""
    name: str
    path: str  # Full path like "env.debug"
    type: str
    default: Any
    description: str = ""
    documented_in: Set[str] = field(default_factory=set)


def fetch_github_readme(version: str) -> Optional[str]:
    """
    Fetch kata-deploy README from GitHub for the given version.

    Args:
        version: kata-deploy version (e.g., "3.21.0")

    Returns:
        README content as string, or None if unavailable
    """
    if not HAS_REQUESTS:
        return None

    url = f"https://raw.githubusercontent.com/kata-containers/kata-containers/{version}/tools/packaging/kata-deploy/helm-chart/README.md"

    try:
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            return response.text
    except Exception as e:
        print(f"   Warning: Could not fetch GitHub README: {e}")

    return None


def parse_kata_deploy_values(chart_path: Path, kata_version: Optional[str] = None, exclude_options: Optional[List[str]] = None) -> List[ConfigOption]:
    """
    Parse kata-deploy chart values.yaml and extract configuration options.

    Args:
        chart_path: Path to extracted kata-deploy chart directory
        kata_version: Version string to fetch GitHub README (optional)
        exclude_options: List of option paths to exclude (e.g., ["env.hostOS"])

    Returns:
        List of ConfigOption objects
    """
    values_file = chart_path / "values.yaml"
    readme_file = chart_path / "README.md"
    
    if not values_file.exists():
        print(f"Error: kata-deploy values.yaml not found at {values_file}")
        sys.exit(1)
    
    with open(values_file, 'r') as f:
        values = yaml.safe_load(f)
    
    if exclude_options is None:
        exclude_options = []

    # Extract options from values with their paths
    options = []

    def extract_options(data, parent_path=""):
        """Recursively extract configuration options."""
        if isinstance(data, dict):
            for key, value in data.items():
                current_path = f"{parent_path}.{key}" if parent_path else key

                # Skip YAML anchors and internal keys
                if key.startswith('_'):
                    continue

                # Skip excluded options
                if current_path in exclude_options:
                    continue

                option_type = type(value).__name__

                # For nested dicts, recurse
                if isinstance(value, dict):
                    extract_options(value, current_path)
                else:
                    options.append(ConfigOption(
                        name=key,
                        path=current_path,
                        type=option_type,
                        default=value
                    ))

    extract_options(values)

    # Try to extract descriptions from README
    readme_content = None

    # First, try local README
    if readme_file.exists():
        with open(readme_file, 'r') as f:
            readme_content = f.read()
    # If not found locally, try GitHub
    elif kata_version:
        print(f"   Fetching configuration reference from GitHub for version {kata_version}...")
        readme_content = fetch_github_readme(kata_version)
    
    # Extract descriptions if README is available
    if readme_content:
        # Look for configuration reference table
        # Format: | parameter | description | default |
        for option in options:
            # Try to find the option in README
            pattern = rf'\|\s*`?{re.escape(option.path)}`?\s*\|([^|]+)\|'
            match = re.search(pattern, readme_content, re.IGNORECASE)
            if match:
                option.description = match.group(1).strip()

    return options


def check_documentation(options: List[ConfigOption], our_values: Path, doc_files: List[Path], subchart_alias: str = "kata-as-coco-runtime") -> Tuple[List[ConfigOption], List[ConfigOption]]:
    """
    Check if options are documented in our files.

    Args:
        options: List of ConfigOption from kata-deploy
        our_values: Path to our values.yaml
        doc_files: List of paths to our documentation files
        subchart_alias: The alias used for the subchart (default: "kata-as-coco-runtime")

    Returns:
        Tuple of (documented_options, undocumented_options)
    """
    # Read all our documentation content
    all_content = ""

    # Read our values.yaml with comments
    if our_values.exists():
        with open(our_values, 'r') as f:
            all_content += f.read() + "\n"

    # Read all documentation files
    for doc_file in doc_files:
        if doc_file.exists():
            with open(doc_file, 'r') as f:
                all_content += f.read() + "\n"

    documented = []
    undocumented = []

    for option in options:
        # In our chart, kata-deploy options are under the subchart alias
        # So "imagePullPolicy" becomes "kata-as-coco-runtime.imagePullPolicy"
        prefixed_path = f"{subchart_alias}.{option.path}"

        # Check if the option path or name is mentioned in our docs
        # We prioritize the prefixed version since that's what users use
        patterns = [
            prefixed_path,  # e.g., "kata-as-coco-runtime.env.debug"
            option.path,  # e.g., "env.debug" (might be in comments)
            option.name,  # Just the name like "debug"
        ]

        found = False
        for pattern in patterns:
            # Look for mentions in various formats:
            # - In comments: # description with option.path
            # - In code blocks: option.path: value
            # - In tables: | option.path | description |
            # - In --set examples: --set kata-as-coco-runtime.option.path=value
            search_patterns = [
                rf'#.*{re.escape(pattern)}',  # In comments
                rf'{re.escape(pattern)}\s*:',  # As YAML key
                rf'`{re.escape(pattern)}`',  # In backticks
                rf'--set.*{re.escape(pattern)}',  # In --set examples
                rf'\|\s*{re.escape(pattern)}\s*\|',  # In tables
            ]

            for search_pattern in search_patterns:
                if re.search(search_pattern, all_content, re.IGNORECASE):
                    option.documented_in.add(pattern)
                    found = True
                    break

            if found:
                break

        if found:
            documented.append(option)
        else:
            undocumented.append(option)

    return documented, undocumented


def generate_report(kata_version: str, documented: List[ConfigOption], undocumented: List[ConfigOption], output_format: str = "text", subchart_alias: str = "kata-as-coco-runtime") -> str:
    """
    Generate a validation report.

    Args:
        kata_version: Version of kata-deploy chart being validated
        documented: List of documented options
        undocumented: List of undocumented options
        output_format: "text" or "github" (markdown for GitHub)
        subchart_alias: The alias used for the subchart (default: "kata-as-coco-runtime")

    Returns:
        Report as string
    """
    if output_format == "github":
        report = f"""# 📚 Kata-Deploy Documentation Validation Report

**Kata-Deploy Version:** `{kata_version}`  
**Validation Date:** {Path('/tmp').stat().st_mtime}

## Summary

- ✅ **Documented Options:** {len(documented)}
- ❌ **Undocumented Options:** {len(undocumented)}
- 📊 **Coverage:** {len(documented) / (len(documented) + len(undocumented)) * 100:.1f}%

"""

        if undocumented:
            report += """---

## ⚠️ Missing Documentation

The following configuration options from kata-deploy are **not documented** in our chart:

| Option Path (in our chart) | Type | Default Value | Description |
|----------------------------|------|---------------|-------------|
"""
            for option in sorted(undocumented, key=lambda x: x.path):
                # Show the prefixed path since that's what users need to use
                prefixed_path = f"{subchart_alias}.{option.path}"
                default_str = str(option.default)[:50] if option.default is not None else "N/A"
                desc_str = option.description if option.description else "*(No description available)*"
                report += f"| `{prefixed_path}` | `{option.type}` | `{default_str}` | {desc_str} |\n"

            report += f"""
### 📝 Action Required

Please add documentation for these options in one or more of the following places:

1. **values.yaml** - Add comments above the relevant configuration sections
2. **QUICKSTART.md** - Add to the "Common Customizations" or "Advanced Configuration" sections
3. **README.md** - Add to the configuration reference table

**Important:** In our chart, kata-deploy options are under the `{subchart_alias}` subchart alias.
Users need to use the prefixed path shown in the table above.

#### Example Documentation Format

For `values.yaml`:
```yaml
# Description of the option and its purpose
# Valid values: value1 | value2 | value3
# Default: value1
{subchart_alias}:
  optionName: value
```

For markdown docs:
```markdown
| Parameter | Description | Default |
|-----------|-------------|---------|
| `{subchart_alias}.optionName` | Description of what it does | `value` |
```

For `--set` examples:
```bash
helm install coco oci://... \\
  --set {subchart_alias}.optionName=value
```

"""
        else:
            report += """---

## ✅ All Options Documented

Great! All configuration options from kata-deploy are documented in our chart.

"""

        if documented:
            report += f"""---

## ✅ Documented Options ({len(documented)})

<details>
<summary>Click to expand list of documented options</summary>

"""
            for option in sorted(documented, key=lambda x: x.path):
                # Show the prefixed path for consistency
                prefixed_path = f"{subchart_alias}.{option.path}"
                report += f"- ✓ `{prefixed_path}` ({option.type})\n"

            report += "\n</details>\n"

    else:  # text format
        report = f"Kata-Deploy Documentation Validation Report\n"
        report += f"{'=' * 60}\n\n"
        report += f"Kata-Deploy Version: {kata_version}\n"
        report += f"Documented Options: {len(documented)}\n"
        report += f"Undocumented Options: {len(undocumented)}\n"
        report += f"Coverage: {len(documented) / (len(documented) + len(undocumented)) * 100:.1f}%\n\n"

        if undocumented:
            report += f"Missing Documentation:\n"
            report += f"{'-' * 60}\n"
            for option in sorted(undocumented, key=lambda x: x.path):
                report += f"  - {option.path} ({option.type})\n"
                if option.default is not None:
                    report += f"    Default: {option.default}\n"
                if option.description:
                    report += f"    Description: {option.description}\n"

    return report


def main():
    parser = argparse.ArgumentParser(
        description="Validate kata-deploy configuration documentation"
    )
    parser.add_argument(
        "--kata-deploy-chart",
        type=Path,
        required=True,
        help="Path to extracted kata-deploy chart directory"
    )
    parser.add_argument(
        "--our-values",
        type=Path,
        required=True,
        help="Path to our values.yaml file"
    )
    parser.add_argument(
        "--our-docs",
        type=Path,
        nargs="+",
        required=True,
        help="Paths to our documentation files"
    )
    parser.add_argument(
        "--output-format",
        choices=["text", "github"],
        default="text",
        help="Output format for the report"
    )
    parser.add_argument(
        "--fail-on-missing",
        action="store_true",
        help="Exit with error code if any options are undocumented"
    )

    args = parser.parse_args()

    # Extract kata-deploy version from Chart.yaml
    chart_yaml = Path("Chart.yaml")
    kata_version = "unknown"
    if chart_yaml.exists():
        with open(chart_yaml, 'r') as f:
            chart_data = yaml.safe_load(f)
            for dep in chart_data.get('dependencies', []):
                if dep.get('name') == 'kata-deploy':
                    kata_version = dep.get('version', 'unknown')
                    break

    print(f"🔍 Validating documentation against kata-deploy {kata_version}...")

    # Parse kata-deploy options
    # Note: env.hostOS is excluded as it's only relevant for CI/internal use
    exclude_options = ["env.hostOS"]
    print(f"📖 Parsing kata-deploy chart from {args.kata_deploy_chart}...")
    print(f"   Excluding options only relevant for CI: {', '.join(exclude_options)}")
    options = parse_kata_deploy_values(args.kata_deploy_chart, kata_version, exclude_options)
    print(f"   Found {len(options)} configuration options")

    # Check our documentation
    # Note: In our chart, kata-deploy options are under the "kata-as-coco-runtime" subchart alias
    subchart_alias = "kata-as-coco-runtime"
    print(f"📝 Checking our documentation (with subchart alias: {subchart_alias})...")
    documented, undocumented = check_documentation(
        options,
        args.our_values,
        args.our_docs,
        subchart_alias
    )

    # Generate report (with subchart alias for proper path prefixing)
    report = generate_report(kata_version, documented, undocumented, args.output_format, subchart_alias)

    # Print to stdout
    print("\n" + report)

    # Save report to file for GitHub Actions artifact
    report_file = Path("/tmp/validation-report.md")
    with open(report_file, 'w') as f:
        f.write(report)
    print(f"\n💾 Report saved to {report_file}")

    # Exit with appropriate code
    if undocumented:
        print(f"\n❌ Validation FAILED: {len(undocumented)} options are not documented")
        if args.fail_on_missing or args.output_format == "github":
            sys.exit(1)
    else:
        print(f"\n✅ Validation PASSED: All options are documented")
        sys.exit(0)


if __name__ == "__main__":
    main()

