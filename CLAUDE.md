# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SNO Agent-Based Installer is a Bash-based toolkit for deploying and managing Single Node OpenShift (SNO) clusters using the OpenShift Agent-Based Installer. It targets OpenShift 4.14-4.22 and is optimized for Telco RAN (vDU) workloads. Supports x86_64 and ARM64/AArch64.

## Key Scripts (Deployment Pipeline)

The four main scripts run sequentially as a pipeline:

1. **`sno-iso.sh <config.yaml> [version]`** - Generates bootable ISO with operators and tunings baked in
2. **`sno-install.sh [cluster-name]`** - Deploys via BMC/Redfish (boots from ISO). Uses latest cluster if no name given
3. **`sno-day2.sh [cluster-name]`** - Applies post-deployment configuration (operators, tuning)
4. **`sno-ready.sh [cluster-name]`** - Validates cluster health and configuration

All scripts require `yq`, `jinja2` (jinja2-cli), and `oc` in PATH. Each script auto-selects the latest cluster from `instances/` if no cluster name is provided.

## Architecture

### Configuration System

- User creates a `config.yaml` from `config.yaml.sample` or a profile template
- **Deployment profiles** (`ran`, `hub`, `none`) provide defaults via `templates/cluster-profile-<profile>-<version>.yaml`
- User config overrides profile defaults (hierarchical merge)
- After ISO generation, resolved config is saved to `instances/<cluster-name>/config-resolved.yaml`

### Directory Layout

- `operators/` - Operator subscription templates (NS, OperatorGroup YAML) + `operators.yaml` (operator registry with names, descriptions, default enabled status)
- `templates/day1/` - Installation-time manifests: cluster-tunings (version-specific), catalog sources, ICSP/IDMS, operator configs. Files can be `.yaml`, `.yaml.j2` (Jinja2), or `.sh` (executed before other files)
- `templates/day2/` - Post-install manifests: performance profiles, PTP, SR-IOV, tuned profiles, operator-specific configs
- `templates/cluster-profile-*.yaml` - Deployment profile templates (RAN has per-version variants: 4.14-4.22)
- `samples/` - Example configs for different network scenarios (IPv4, IPv6, dual-stack, VLAN, bond, proxy)
- `instances/` - Generated at runtime; contains per-cluster workspace (ISO, kubeconfig, resolved config). Gitignored
- `mirror/` - Scripts for disconnected/air-gapped environments
- `tests/` - Integration test scripts (`tests/sno130/`, `tests/acm0/`) that run the full pipeline

### Operator Profile System

Operators in config can specify day1/day2 profiles:
- Profile maps to `templates/day1/<operator>/<profile>/` or `templates/day2/<operator>/<profile>/`
- If no profile specified, uses `default/` directory
- Templates use Jinja2 (`.yaml.j2`) with operator `data:` passed as variables
- Shell scripts (`.sh`) in profile dirs execute before YAML files are applied

### Template Rendering

Jinja2 templates (`.yaml.j2`) are rendered with `jinja2` CLI using YAML data from the config. Version substitution variables (`${OCP_Y_VERSION}`, `${OCP_Z_VERSION}`) are available in extra manifest paths.

## Running Tests

Tests are integration tests that run the full ISO-generate/install/day2 pipeline against real hardware:
```bash
./tests/sno130/test-sno130-4.21.sh [version]
./tests/acm0/test-acm0.sh
```

There are no unit tests or linting tools configured.

## Code Conventions

- All main scripts are Bash with shared color output helpers (`info`, `warn`, `error`, `step`, `header`, `debug`)
- Debug mode: set `DEBUG=true` environment variable for verbose output
- Scripts use `yq` (mikefarah/yq) for YAML processing, not Python
- BMC interactions use `curl` with Redfish API
- Cluster state is managed via the `instances/<cluster-name>/` workspace directory
