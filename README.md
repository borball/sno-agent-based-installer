# SNO Agent-Based Installer

<p align="center">
<img src="https://img.shields.io/badge/OpenShift-4.14+-red?style=flat-square&logo=redhat">
<img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=flat-square">
<img src="https://img.shields.io/badge/Platform-Single%20Node%20OpenShift-orange?style=flat-square">
</p>

## Overview

The SNO Agent-Based Installer is a comprehensive toolkit for deploying and managing Single Node OpenShift (SNO) clusters using the OpenShift Agent-Based Installer. This repository provides automated scripts for ISO generation, cluster deployment, and configuration management, specifically optimized for Telco RAN workloads.

**Version 2.x** introduces a redesigned configuration system with deployment profiles to simplify configuration management and improve maintainability.

> **Note**: This repository requires OpenShift 4.14 or later (tested up to 4.20+). For multi-node deployments, see the sister repository: [Multiple Nodes OpenShift](https://github.com/borball/mno-with-abi)

## 🆕 What's New in Version 2.x

### Major Configuration Redesign
- **🎯 Deployment Profiles**: Simplified configuration with predefined profiles (`ran`, `hub`, `none`)
- **📁 Operator Profiles**: Flexible day1/day2 configuration profiles for operators
- **🔧 Enhanced Operator Management**: Improved operator version locking and catalog source management
- **⚙️ Update Control**: New mechanisms to control operator updates and upgrades

### New Operators Support
- **🌐 MetalLB Operator**: Load balancer support for bare metal environments
- **🔗 NMState Operator**: Declarative network configuration management
- **💻 OpenShift Virtualization**: KubeVirt hyperconverged platform support
- **🔍 Node Feature Discovery**: Hardware feature detection and labeling
- **🎮 NVIDIA GPU Operator**: GPU workload support
- **📊 AMQ Streams & Console**: Apache Kafka messaging platform
- **🏢 Multicluster Global Hub**: Enhanced multi-cluster management

### Enhanced Features
- **📋 PreGA Catalog Sources**: Support for pre-GA operator testing
- **🎛️ Hardware Tuning**: Advanced CPU frequency and hardware optimization
- **🔄 Profile System**: Modular configuration system for operators
- **📦 Container Storage**: Enhanced container storage partitioning options

## ✨ Features

- **📦 Automated ISO Generation**: Generate bootable ISO images with pre-configured operators and tunings
- **🚀 Automated Deployment**: Deploy SNO clusters via BMC/Redfish integration
- **⚙️ Day-1 Operations**: Pre-configure operators and system tunings during installation
- **🔧 Day-2 Operations**: Post-deployment configuration and operator management
- **✅ Validation Framework**: Comprehensive cluster validation and health checks
- **🏗️ Telco RAN Ready**: Optimized for vDU applications with performance tunings
- **🌐 Multi-Platform Support**: Works with HPE, ZT Systems, Dell, and OpenShift Virtualization environments
- **🔄 Version Management**: Support for operator version locking and OpenShift version substitution
- **📋 Custom Manifests**: Support for extra manifests in both Day-1 and Day-2 operations

## 🏗️ Architecture

The toolkit consists of main components:

| Script | Purpose | Phase |
|--------|---------|-------|
| `sno-iso.sh` | Generate bootable ISO with operators and tunings | Pre-deployment |
| `sno-install.sh` | Deploy SNO via BMC/Redfish integration | Deployment |
| `sno-day2.sh` | Apply post-deployment configurations | Post-deployment |
| `sno-ready.sh` | Validate cluster configuration and health | Validation |
| `sno-ready2.sh` | Enhanced validation with additional checks | Validation |
| `fetch-infra-env.sh` | Fetch infrastructure environment information | Utility |

## 📋 Prerequisites

### System Requirements
- OpenShift 4.14 or later (tested up to 4.20+)
- Linux system with internet access
- BMC/Redfish access to target hardware
- HTTP server for ISO hosting
- Minimum 16GB RAM, 120GB disk space for SNO node

### Required Tools
Install the following tools before running the scripts:

```bash
# Install nmstatectl
sudo dnf install /usr/bin/nmstatectl -y

# Install yq (YAML processor)
# See: https://github.com/mikefarah/yq#install
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Install jinja2 CLI
pip3 install jinja2-cli jinja2-cli[yaml]
```

## 🚀 Quick Start

### 1. Configuration

Create a configuration file based on the sample or use a pre-configured profile:

```bash
# Option 1: Start with sample configuration
cp config.yaml.sample config-mysno.yaml

# Option 2: Use a pre-configured profile template
cp templates/cluster-profile-ran-4.20.yaml config-mysno.yaml
```

**Version 2.x Configuration** - Simplified with deployment profiles:

```yaml
cluster:
  domain: example.com
  name: mysno
  profile: ran                    # Deployment profile: ran, hub, none(not specify)

host:
  hostname: mysno.example.com
  interface: ens1f0
  mac: b4:96:91:b4:9d:f0
  ipv4:
    enabled: true
    ip: 192.168.1.100
    dns: 
      - 192.168.1.1
    gateway: 192.168.1.1
    prefix: 24
    machine_network_cidr: 192.168.1.0/24
  disk: /dev/disk/by-path/pci-0000:c2:00.0-nvme-1

cpu:
  isolated: 2-31,34-63
  reserved: 0-1,32-33

bmc:
  address: 192.168.1.200
  username: Administrator
  password: password

iso:
  address: http://192.168.1.10/iso/mysno.iso

pull_secret: ${HOME}/pull-secret.json
ssh_key: ${HOME}/.ssh/id_rsa.pub

operators:
  local-storage:
    data:
      disk_by_path: pci-0000:03:00.0-nvme-1
```

### 2. Generate ISO

```bash
./sno-iso.sh config-mysno.yaml
```

### 3. Deploy SNO

```bash
./sno-install.sh
```

### 4. Apply Day-2 Configuration

```bash
./sno-day2.sh
```

### 5. Validate Deployment

```bash
./sno-ready.sh
```

## 📖 Detailed Usage

### ISO Generation

Generate a bootable ISO image with pre-configured operators and tunings:

```bash
# Basic usage
./sno-iso.sh config-mysno.yaml

# Specify OpenShift version
./sno-iso.sh config-mysno.yaml 4.14.33

# Use specific release channel
./sno-iso.sh config-mysno.yaml stable-4.14
```

**Available Options:**
- `config file`: Path to configuration file (optional, defaults to `config.yaml`)
- `ocp version`: OpenShift version or channel (optional, defaults to `stable-4.14`)

### Automated Deployment

Deploy SNO using BMC/Redfish integration:

```bash
# Deploy latest generated cluster
./sno-install.sh

# Deploy specific cluster
./sno-install.sh mysno
```

**Supported Platforms:**
- HPE iLO
- ZT Systems
- Dell iDRAC
- KVM with Sushy tools

### Day-2 Operations

Apply post-deployment configurations:

```bash
# Apply to latest cluster
./sno-day2.sh

# Apply to specific cluster
./sno-day2.sh mysno
```

### Cluster Validation

Validate cluster configuration and health:

```bash
# Validate latest cluster
./sno-ready.sh

# Validate specific cluster
./sno-ready.sh mysno
```

## ⚙️ Configuration Reference

### Basic Configuration

```yaml
cluster:
  domain: example.com          # Cluster domain
  name: mysno                  # Cluster name
  ntps:                        # NTP servers (optional)
    - pool.ntp.org
  profile: ran                 # Profile template

host:
  hostname: mysno.example.com  # Node hostname
  interface: ens1f0            # Primary network interface
  mac: b4:96:91:b4:9d:f0      # MAC address
  disk: /dev/nvme0n1          # Installation disk

cpu:
  isolated: 2-31,34-63        # Isolated CPUs for workloads
  reserved: 0-1,32-33         # Reserved CPUs for system
```

### Network Configuration

#### IPv4 Configuration
```yaml
host:
  ipv4:
    enabled: true
    dhcp: false
    ip: 192.168.1.100
    dns: 
      - 192.168.1.1
    gateway: 192.168.1.1
    prefix: 24
    machine_network_cidr: 192.168.1.0/24
```

#### IPv6 Configuration
```yaml
host:
  ipv6:
    enabled: true
    dhcp: false
    ip: 2001:db8::100
    dns: 
      - 2001:db8::1
    gateway: 2001:db8::1
    prefix: 64
    machine_network_cidr: 2001:db8::/64
```

#### VLAN Configuration
```yaml
host:
  vlan:
    enabled: true
    name: ens1f0.100
    id: 100
```

### Configuration Structure

The SNO Agent-Based Installer uses a **hierarchical configuration system** with deployment profiles that provide pre-configured templates for different use cases. This system allows you to start with sensible defaults and override only what you need to customize.

#### Configuration Hierarchy

```
config.yaml (your configuration)
    ↓ inherits from
cluster-profile-<profile-name>-<ocp-version>.yaml (template)
    ↓ provides defaults for
All configuration sections
```

#### How Profile Inheritance Works

1. **Profile Selection**: The `cluster.profile` field in your `config.yaml` determines which template to use
2. **Template Loading**: The system loads `templates/cluster-profile-<profile>-<ocp-version>.yaml`
3. **Override Mechanism**: Any values you define in `config.yaml` override the template defaults
4. **Version Fallback**: If version-specific template doesn't exist, falls back to base profile

#### Available Deployment Profiles

| Profile | Template File | Use Case | Key Features |
|---------|---------------|----------|--------------|
| `ran` | `cluster-profile-ran-4.20.yaml` | Telco RAN workloads | Performance tuning, RAN operators, workload partitioning |
| `hub` | `cluster-profile-hub.yaml` | Hub cluster management | RHACM, GitOps, TALM, cluster logging |
| `none` | `cluster-profile-none.yaml` | Minimal setup | Basic cluster capabilities only |
| Not specified | No template loaded | Custom configuration | Manual configuration of all settings |

#### Configuration Examples

**Example 1: Using RAN Profile with Minimal Overrides**

```yaml
# config-mysno.yaml
cluster:
  domain: example.com
  name: mysno
  profile: ran                    # Inherits from cluster-profile-ran-<OCP-Y>.yaml

host:
  hostname: mysno.example.com
  interface: ens1f0
  mac: b4:96:91:b4:9d:f0
  ipv4:
    enabled: true
    ip: 192.168.1.100
    gateway: 192.168.1.1
    prefix: 24
    machine_network_cidr: 192.168.1.0/24
  disk: /dev/disk/by-path/pci-0000:c2:00.0-nvme-1

operators:
  local-storage:
    data:
      disk_by_path: pci-0000:03:00.0-nvme-1

# The RAN profile automatically provides:
# - Performance tuning (workload partitioning, performance profile)
# - RAN operators (PTP, SR-IOV, FEC, LCA, OADP)
# - Cluster tunings for 4.20
# - Update control settings
```

**Example 2: Overriding Operator Settings**

```yaml
# config-mysno.yaml  
cluster:
  profile: ran                    # Base RAN configuration

# Override specific operators from the RAN profile
operators:
  ptp:
    enabled: true                 # Keep PTP enabled (from profile)
    data:
      boundary_clock:
        ha_enabled: true          # Override: enable HA boundary clock
        profiles:
          - name: custom-bc-profile
            slave: ens2f0         # Override: use different interface
            masters: [ens2f1, ens2f2]
  
  local-storage:
    enabled: false                # Override: enable local storage
  
  lvm:
    enabled: true                 # Override: enable LVM
    data:                         # Override: Env specific settings
      disks:
        - path: /dev/disk/by-path/pci-0000:c4:00.0-nvme-1
          wipe_table: true
      device_classes:
        - name: vg1
          thin_pool_name: thin-pool-1
          selector:
            paths:
              - /dev/disk/by-path/pci-0000:c4:00.0-nvme-1
```

**Example 3: Hub Profile with Custom GitOps Configuration**

```yaml
# config-hub.yaml
cluster:
  profile: hub                    # Inherits hub cluster settings

# Override GitOps configuration
operators:
  gitops:
    enabled: true                 # Keep GitOps enabled (from profile)
    data:
      repo:
        clusters:
          url: ssh://git@github.com/myorg/clusters.git
          targetRevision: main
          path: clusters
        policies:
          url: ssh://git@github.com/myorg/policies.git
          targetRevision: main
          path: policies
```

**Example 4: Custom Hardware Tuning Override**

```yaml
# config-mysno.yaml
cluster:
  profile: ran

# Override performance tuning from RAN profile
node_tunings:
  performance_profile:
    enabled: true
    spec:
      cpu:
        isolated: 4-47,52-95      # Override: different CPU layout
        reserved: 0-3,48-51
      hardwareTuning:
        isolatedCpuFreq: 3000000  # Override: higher frequency
        reservedCpuFreq: 3200000
  tuned_profile:
    profiles:
      - profile: performance-patch
      - profile: hpe-settings     # Override: HPE-specific tuning instead of Dell
```

#### Profile Template Structure

Each profile template contains the following sections:

```yaml
# cluster-profile-ran-4.20.yaml (example)
cluster:
  capabilities:                   # Cluster capability settings
    baselineCapabilitySet: None
    additionalEnabledCapabilities: [...]

cluster_tunings: 4.20            # Version-specific cluster tunings

node_tunings:                    # Performance and tuning settings
  workload_partitioning: {...}
  performance_profile: {...}
  tuned_profile: {...}

update_control:                  # Operator update control
  pause_before_update: true
  disable_operator_auto_upgrade: true

operators:                       # Pre-configured operators
  ptp: {...}
  sriov: {...}
  lvm: {...}
  # ... other operators

# Additional sections like proxy, readiness, etc.
```

#### Best Practices

1. **Start with a Profile**: Choose the profile that best matches your use case
2. **Override Selectively**: Only override the specific settings you need to change
3. **Use Version-Specific Profiles**: Use the profile that matches your OpenShift version
4. **Test Overrides**: Validate that your overrides work as expected
5. **Document Changes**: Comment your overrides to explain why they differ from the profile 

## 🔧 Advanced Features

### Custom Manifests

Include custom resources during installation and post-deployment:

```yaml
extra_manifests:
  day1:
    - ${HOME}/day1-manifests
    - ./install-time-configs
    - ${OCP_Y_VERSION}/version-specific    # Auto-substituted with Y version (e.g., 4.16)
  day2:
    - ${HOME}/day2-manifests
    - ./post-install-configs
    - ${OCP_Z_VERSION}/patch-specific     # Auto-substituted with Z version (e.g., 4.16.3)
```

**Version Substitution Variables:**
- `${OCP_Y_VERSION}`: Substituted with major.minor version (e.g., `4.16`)
- `${OCP_Z_VERSION}`: Substituted with full version (e.g., `4.16.3`)
- `${OCP_Y_RELEASE}`: Substituted with Y release info
- `${OCP_Z_RELEASE}`: Substituted with Z release info

### Operator-Specific Manifests and Profiles

**Version 2.x** introduces operator profiles for flexible configuration:

```yaml
operators:
  example:
    enabled: false
    version: example.v4.20.0-202507211933
    source: prega              # Catalog source
    data:                      # Variables passed to templates
      key1: value1
      key2: value2
    
    # Day-1 configurations with profiles
    day1:
      - profile: a             # Uses templates/day1/example/a/
      - profile: b             # Uses templates/day1/example/b/
    
    # Day-2 configurations with profiles  
    day2:
      - profile: a             # Uses templates/day2/example/a/
      - profile: b             # Uses templates/day2/example/b/

  local-storage:
    enabled: false
    source: prega
    data:
      local_volume:
        name: local-disks
        storageClassName: general
      disk_by_path: pci-0000:03:00.0-nvme-1
      partitions:
        10g: 30

  lvm:
    enabled: true
    source: prega
    data:
      disks:
        - path: /dev/disk/by-path/pci-0000:03:00.0-nvme-1
          wipe_table: true
      device_classes:
        - name: vg1
          thin_pool_name: thin-pool-1
    day1:
      - profile: wipe-disks    # Disk preparation profile
```

**Profile System:**
- If no profiles specified: uses `default/` directory
- Profiles allow multiple configurations per operator
- Supports `.sh`, `.yaml`, and `.yaml.j2` files
- Shell scripts execute before other files

### Profile Templates

The repository includes several pre-configured profile templates:

| Template | Purpose | Key Features |
|----------|---------|--------------|
| `cluster-profile-full.yaml` | Complete configuration template | All sections with examples |
| `cluster-profile-ran-4.18.yaml` | RAN-optimized for 4.18+ | Performance tuning, RAN operators |
| `cluster-profile-hub.yaml` | Hub cluster configuration | RHACM, GitOps, TALM enabled |
| `cluster-profile-none.yaml` | Minimal configuration | Basic cluster setup only |

### Version-Specific Templates

RAN profiles are available for different OpenShift versions with version 2.x enhancements:
- `cluster-profile-ran-4.14.yaml` - OpenShift 4.14 optimizations
- `cluster-profile-ran-4.15.yaml` - OpenShift 4.15 optimizations  
- `cluster-profile-ran-4.16.yaml` - OpenShift 4.16 optimizations
- `cluster-profile-ran-4.17.yaml` - OpenShift 4.17 optimizations
- `cluster-profile-ran-4.18.yaml` - OpenShift 4.18 optimizations
- `cluster-profile-ran-4.19.yaml` - OpenShift 4.19 optimizations
- `cluster-profile-ran-4.20.yaml` - **Latest** OpenShift 4.20 optimizations with new features

**New in 4.20 Profile:**
- Enhanced operator profile system
- Update control mechanisms
- PreGA catalog source support
- Improved hardware tuning options

## 🧪 Testing

The repository includes comprehensive test configurations:

```bash
# Run basic test
./test/test.sh

# Test specific configuration
./test/test-sno130.sh

# Test KVM environment
./test/test-kvm.sh

# Test hub cluster
./test/test-hub.sh
```

## 📁 Sample Configurations

The repository includes various sample configurations for different scenarios:

| Configuration | Description | Use Case |
|---------------|-------------|----------|
| `config-full.yaml` | Complete configuration with all options | Production deployments |
| `config-ipv4.yaml` | Basic IPv4 networking | Standard deployments |
| `config-ipv6.yaml` | IPv6 networking | IPv6-only environments |
| `config-dual-stack.yaml` | IPv4 + IPv6 dual-stack | Dual-stack networking |
| `config-ipv6-proxy.yaml` | IPv6 with proxy support | Proxy environments |
| `config-ipv6-vlan.yaml` | IPv6 with VLAN tagging | VLAN networks |
| `config-bond.yaml` | Network bonding configuration | High availability networking |
| `config-ran.yaml` | RAN-optimized configuration | Telco RAN deployments |

### Usage
```bash
# Use a sample configuration
cp samples/config-ipv4.yaml config-mysno.yaml
./sno-iso.sh config-mysno.yaml
```

## 📊 Validation Checklist

The `sno-ready.sh` and `sno-ready2.sh` scripts provide comprehensive validation:

### Core Validation (`sno-ready.sh`)
- ✅ **Cluster Health**: Node status, operator health, pod status
- ✅ **Machine Configs**: CPU partitioning, kdump, performance settings
- ✅ **Performance Profile**: Isolated/reserved CPUs, real-time kernel
- ✅ **Operators**: PTP, SR-IOV, Local Storage, Cluster Logging
- ✅ **Network**: SR-IOV node state, network diagnostics
- ✅ **System**: Kernel parameters, cgroup configuration, container runtime

### Enhanced Validation (`sno-ready2.sh`)
- ✅ **Extended Operator Support**: MetalLB, NMState, LVM, LCA, OADP, FEC
- ✅ **Hub Cluster Features**: RHACM, GitOps, TALM, MCE, MCGH
- ✅ **Advanced Monitoring**: AlertManager, Prometheus, Telemetry settings
- ✅ **Storage Validation**: Local storage, LVM storage configurations
- ✅ **Container Features**: Virtualization, GPU operators
- ✅ **Update Control**: Operator upgrade policies and pause mechanisms

### Version 2.x Enhancements
- 🔄 **Profile Validation**: Deployment profile-specific checks
- 📋 **Operator Profiles**: Validation of day1/day2 profile configurations
- 🎯 **Catalog Sources**: PreGA and custom catalog source validation
- ⚙️ **Update Control**: Validation of operator update control settings
