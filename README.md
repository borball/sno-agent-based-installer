# SNO Agent-Based Installer

<p align="center">
<img src="https://img.shields.io/badge/OpenShift-4.14+-red?style=flat-square&logo=redhat">
<img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=flat-square">
<img src="https://img.shields.io/badge/Platform-Single%20Node%20OpenShift-orange?style=flat-square">
</p>

## Overview

The SNO Agent-Based Installer is a comprehensive toolkit for deploying and managing Single Node OpenShift (SNO) clusters using the OpenShift Agent-Based Installer. This repository provides automated scripts for ISO generation, cluster deployment, and configuration management, specifically optimized for Telco RAN workloads.

> **Note**: This repository requires OpenShift 4.12 or later. For multi-node deployments, see the sister repository: [Multiple Nodes OpenShift](https://github.com/borball/mno-with-abi)

## ✨ Features

- **📦 Automated ISO Generation**: Generate bootable ISO images with pre-configured operators and tunings
- **🚀 Automated Deployment**: Deploy SNO clusters via BMC/Redfish integration
- **⚙️ Day-1 Operations**: Pre-configure operators and system tunings during installation
- **🔧 Day-2 Operations**: Post-deployment configuration and operator management
- **✅ Validation Framework**: Comprehensive cluster validation and health checks
- **🏗️ Telco RAN Ready**: Optimized for vDU applications with performance tunings
- **🌐 Multi-Platform Support**: Works with HPE, ZT Systems, Dell, and KVM environments
- **🔄 Version Management**: Support for operator version locking and OpenShift version substitution
- **📋 Custom Manifests**: Support for extra manifests in both Day-1 and Day-2 operations
- **⚡ Performance Tuning**: Advanced CPU frequency scaling and hardware tuning options
- **🔗 Network Bonding**: Support for network interface bonding and VLAN configurations
- **💾 Storage Provisioning**: Automated local storage and LVM volume provisioning
- **🔐 Container Security**: Support for container storage partitioning and cgroup v2

## 🏗️ Architecture

The toolkit consists of main components:

| Script | Purpose | Phase |
|--------|---------|-------|
| `sno-iso.sh` | Generate bootable ISO with operators and tunings | Pre-deployment |
| `sno-install.sh` | Deploy SNO via BMC/Redfish integration | Deployment |
| `sno-day2.sh` | Apply post-deployment configurations | Post-deployment |
| `sno-ready.sh` | Validate cluster configuration and health | Validation |

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

Create a configuration file based on the sample:

```bash
cp config.yaml.sample config-mysno.yaml
```

Edit the configuration file with your environment details:

```yaml
cluster:
  domain: example.com
  name: mysno
  ntps:
    - pool.ntp.org

host:
  hostname: mysno.example.com
  interface: ens1f0
  mac: b4:96:91:b4:9d:f0
  ipv4:
    enabled: true
    dhcp: false
    ip: 192.168.1.100
    dns: 
      - 192.168.1.1
    gateway: 192.168.1.1
    prefix: 24
    machine_network_cidr: 192.168.1.0/24
  disk: /dev/nvme0n1

cpu:
  isolated: 2-31,34-63
  reserved: 0-1,32-33

bmc:
  address: 192.168.1.200
  username: admin
  password: password

iso:
  address: http://192.168.1.10/iso/mysno.iso

pull_secret: ./pull-secret.json
ssh_key: /root/.ssh/id_rsa.pub
```

### 2. Generate ISO

```bash
./sno-iso.sh config-mysno.yaml
```

### 3. Deploy SNO

```bash
./sno-install.sh mysno
```

### 4. Apply Day-2 Configuration

```bash
./sno-day2.sh mysno
```

### 5. Validate Deployment

```bash
./sno-ready.sh mysno
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

The configuration follows a structured approach with separate sections for different aspects:

```yaml
cluster:
  domain: example.com
  name: mysno
  platform: intel              # intel, amd, arm
  ntps:
    - 0.rhel.pool.ntp.org
    - 1.rhel.pool.ntp.org
  capabilities:
    baselineCapabilitySet: None  # None, vCurrent, v4.12, v4.14, etc.
    additionalEnabledCapabilities:
      - NodeTuning
      - OperatorLifecycleManager
      - Ingress

# Cluster-level tunings: none, 4.14, 4.16, 4.18
cluster_tunings: none

# Node-level tunings
node_tunings:
  workload_partitioning:
    enabled: true
  performance_profile:
    enabled: true
  tuned_profile:
    enabled: true

# Container storage partitioning
container_storage:
  enabled: false
  device: /dev/nvme0n1
  startMiB: 250000
  sizeMiB: 0

# Custom manifests for Day-1 and Day-2
extra_manifests:
  day1:
    - ${HOME}/day1-manifests
    - ${OCP_Y_VERSION}/version-specific
  day2:
    - ${HOME}/day2-manifests
    - ${OCP_Z_VERSION}/patch-specific

# Operators configuration
operators:
  ptp:
    enabled: true
    version: ptp-operator.v4.18.0-202507211933  # Optional version lock
    config:
      manifests:
        - ptpconfig-boundary-clock.yaml.j2
        - ptp-operator-config-for-event.yaml.j2
    data:
      ptpconfig: disabled       # disabled, ordinary, boundary
      clock_threshold_tuning:
        hold_over_timeout: 5
        max_offset: 500
        min_offset: -500
  
  sriov:
    enabled: true
    version: sriov-network-operator.v4.18.0-202507211933
    
  local-storage:
    enabled: true
    version: local-storage-operator.v4.18.0-202507211933
    provision:
      manifests:
        - 60-prepare-lso-partition-mc.yaml.j2  # Option 1: partition
        # - 60-create-lvs-mc.yaml.j2           # Option 2: logical volumes
    config:
      manifests:
        - local-volume-partition.yaml.j2
    data:
      local_volume:
        name: local-disks
        storageClassName: general
      disk_by_path: pci-0000:03:00.0-nvme-1
      partitions:
        10g: 30
        
  lvm:
    enabled: false
    version: lvm-operator.v4.18.3
    data:
      disks:
        - disk_by_path: pci-0000:03:00.0-nvme-1
          wipe_table: true
      device_classes:
        - name: vg1
          thin_pool_name: thin-pool-1
          selector:
            paths:
              - /dev/disk/by-path/pci-0000:03:00.0-nvme-1
              
  cluster-logging:
    enabled: true
    version: cluster-logging.v6.2.4
    
  lca:
    enabled: true            # Lifecycle Agent
    version: lifecycle-agent.v4.18.0
    
  adp:
    enabled: true            # OpenShift API for Data Protection (OADP)
    version: redhat-oadp-operator.v1.4.5
    
  fec:
    enabled: false           # Intel SRIOV-FEC Operator
    version: sriov-fec.v2.11.1
    
  # Hub cluster operators
  rhacm:
    enabled: false           # Red Hat Advanced Cluster Management
  gitops:
    enabled: false           # Red Hat OpenShift GitOps  
  talm:
    enabled: false           # Topology Aware Lifecycle Manager
```

### Additional Configuration Sections

```yaml
# CPU partitioning
cpu:
  isolated: 2-31,34-63
  reserved: 0-1,32-33

# Authentication
pull_secret: ${HOME}/pull-secret.json
ssh_key: ${HOME}/.ssh/id_rsa.pub
ssh_priv_key: ${HOME}/.ssh/id_rsa

# Catalog sources management
catalog_sources:
  create_marketplace_ns: true
  update_operator_hub: false
  create_default_catalog_sources: true
  defaults:
    - redhat-operators
    - certified-operators
  customs:
    - name: prega
      display: Red Hat Operators OCP_Y_RELEASE PreGA
      image: quay.io/prega/prega-operator-index:vOCP_Y_RELEASE
      publisher: Red Hat

# Container registry and mirroring
container_registry:
  image_source: ${HOME}/registry/local-mirror.yaml
  icsp:
    - templates/day1/icsp/prega-OCP_Y_RELEASE.yaml

# Proxy configuration
proxy:
  enabled: false
  http: http://proxy.example.com:8080
  https: https://proxy.example.com:8080
  noproxy: localhost,127.0.0.1,.example.com

# Additional trust bundle for disconnected environments
additional_trust_bundle: /root/registry/ca-bundle.crt

# BMC configuration
bmc:
  address: 192.168.1.200
  username: Administrator
  password: password
  kvm_uuid: 11111111-1111-1111-1234-000000000000

# ISO configuration
iso:
  address: http://192.168.1.10/iso/mysno.iso
  protocol: skip               # Optional: skip TransferProtocolType for compatibility
  deploy: ${HOME}/bin/deploy_boot_iso.sh  # Optional deploy script

# Readiness validation
readiness:
  default: true
  extra_checks:
    - ${HOME}/custom-checks
    - ${HOME}/validation-scripts
```

### Performance Tuning

Performance tuning is configured through the `node_tunings` section:

```yaml
node_tunings:
  workload_partitioning:
    enabled: true
  performance_profile:
    enabled: true
    name: sno-perfprofile
    real_time: false
    net:
      user_level_networking: true
    hardwareTuning:
      isolatedCpuFreq: 2500000
      reservedCpuFreq: 2800000
    hugepage:
      default: 2M
      pages:
        - size: 2M
          count: 32768
          node: 1
  tuned_profile:
    enabled: true
    cmdline_pstate: intel_pstate=active  # For passive mode BIOS settings
    kdump: false
    sysfs:
      cpufreq_max_freq: 2500000         # Cap CPU frequency
```

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

### Operator-Specific Manifests

Operators can include custom manifests and configuration data:

```yaml
operators:
  local-storage:
    enabled: true
    version: local-storage-operator.v4.18.0-202507211933
    provision:                    # Day-1 manifests
      before:
        - pre-setup.sh           # Optional pre-setup script
      manifests:
        - 60-prepare-lso-partition-mc.yaml.j2
    config:                      # Day-2 manifests
      manifests:
        - local-volume-partition.yaml.j2
    data:                        # Variables passed to manifest templates
      local_volume:
        name: local-disks
        storageClassName: general
      disk_by_path: pci-0000:03:00.0-nvme-1
      partitions:
        10g: 30
```

### Profile Templates

The repository includes several pre-configured profile templates:

| Template | Purpose | Key Features |
|----------|---------|--------------|
| `cluster-profile-full.yaml` | Complete configuration template | All sections with examples |
| `cluster-profile-ran-4.18.yaml` | RAN-optimized for 4.18+ | Performance tuning, RAN operators |
| `cluster-profile-hub.yaml` | Hub cluster configuration | RHACM, GitOps, TALM enabled |
| `cluster-profile-none.yaml` | Minimal configuration | Basic cluster setup only |

### Version-Specific Templates

RAN profiles are available for different OpenShift versions:
- `cluster-profile-ran-4.14.yaml` - OpenShift 4.14 optimizations
- `cluster-profile-ran-4.15.yaml` - OpenShift 4.15 optimizations  
- `cluster-profile-ran-4.16.yaml` - OpenShift 4.16 optimizations
- `cluster-profile-ran-4.17.yaml` - OpenShift 4.17 optimizations
- `cluster-profile-ran-4.18.yaml` - OpenShift 4.18 optimizations
- `cluster-profile-ran-4.19.yaml` - OpenShift 4.19 optimizations
- `cluster-profile-ran-4.20.yaml` - OpenShift 4.20 optimizations

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

The `sno-ready.sh` and `sno-ready2.sh` scripts validate:

- ✅ **Cluster Health**: Node status, operator health, pod status
- ✅ **Machine Configs**: CPU partitioning, kdump, performance settings
- ✅ **Performance Profile**: Isolated/reserved CPUs, real-time kernel
- ✅ **Operators**: PTP, SR-IOV, Local Storage, Cluster Logging, MetalLB, NMState
- ✅ **Network**: SR-IOV node state, network diagnostics
- ✅ **System**: Kernel parameters, cgroup configuration, container runtime
- ✅ **Monitoring**: AlertManager, Prometheus, Telemetry settings
- ✅ **Storage**: Local storage, LVM storage configurations
