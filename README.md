# SNO Agent-Based Installer

<p align="center">
<img src="https://img.shields.io/badge/OpenShift-4.12+-red?style=flat-square&logo=redhat">
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

## 🏗️ Architecture

The toolkit consists of four main components:

| Script | Purpose | Phase |
|--------|---------|-------|
| `sno-iso.sh` | Generate bootable ISO with operators and tunings | Pre-deployment |
| `sno-install.sh` | Deploy SNO via BMC/Redfish integration | Deployment |
| `sno-day2.sh` | Apply post-deployment configurations | Post-deployment |
| `sno-ready.sh` | Validate cluster configuration and health | Validation |

## 📋 Prerequisites

### System Requirements
- OpenShift 4.12 or later
- Linux system with internet access
- BMC/Redfish access to target hardware
- HTTP server for ISO hosting

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

### Day-1 Operations

Configure operators and system tunings during installation:

```yaml
day1:
  workload_partition: true     # Enable workload partitioning
  kdump:
    enabled: true
    blacklist_ice: false       # Set true for HPE servers
  boot_accelerate: true        # Enable boot acceleration
  ztp_hub: false              # Enable ZTP hub components
  crun: true                  # Use crun container runtime
  rcu_normal: true            # Enable RCU normal mode
  sriov_kernel: true          # Enable SR-IOV kernel optimizations
  sync_time_once: true        # Enable time synchronization
  cgv1: true                  # Use cgroup v1 (false for v2)
  
  container_storage:
    enabled: false
    device: /dev/nvme0n1
    startMiB: 250000
    sizeMiB: 0
  
  operators:
    ptp:
      enabled: true
      version: ptp-operator.4.14.0-202405070741  # Optional version lock
    sriov:
      enabled: true
      version: sriov-network-operator.v4.14.0-202405070741
    local-storage:
      enabled: true
      provision: true          # Create logical volumes
    lca:
      enabled: true            # Lifecycle Agent
    oadp:
      enabled: true            # Backup and restore
    cluster-logging:
      enabled: true
    metallb:
      enabled: true
    nmstate:
      enabled: true
    nfd:
      enabled: true            # Node Feature Discovery
    gpu:
      enabled: false
    kubevirt:
      enabled: false
    fec:
      enabled: false           # SR-IOV FEC
    adp:
      enabled: false           # Accelerated Data Processing
    mce:
      enabled: false           # Multi-cluster Engine
    rhacm:
      enabled: false           # Red Hat Advanced Cluster Management
    gitops:
      enabled: false           # OpenShift GitOps
    talm:
      enabled: false           # Topology Aware Lifecycle Manager
```

### Day-2 Operations

Configure post-deployment settings:

```yaml
day2:
  operators:
    ptp:
      enabled: true
      ptpconfig:
        enabled: true
        mode: boundary           # ordinary, boundary, or mixed
        logLevel: 2
        summary_interval: -4
        logReduce: true
        enableEventPublisher: true
        
    sriov:
      enabled: true
      sriovOperatorConfig:
        enabled: true
        enableInjector: true
        enableOperatorWebhook: true
        logLevel: 2
        
    cluster-logging:
      enabled: true
      clusterlogforwarder:
        enabled: true
        outputs:
          - name: remote-syslog
            type: syslog
            url: tcp://192.168.1.10:514
            
    metallb:
      enabled: true
      metallbConfig:
        enabled: true
        addressPools:
          - name: main-pool
            protocol: layer2
            addresses:
              - 192.168.1.200-192.168.1.220
```

### Performance Tuning

```yaml
performance:
  profile:
    enabled: true
    name: sno-perfprofile
    realTimeKernel: true
    userLevelNetworking: true
    hugepages:
      enabled: true
      size: 1G
      count: 32
    hardwareTuning:
      isolatedCpuFreq: 2700000
      reservedCpuFreq: 2700000
      
  tuned:
    enabled: true
    scaling_max_freq: 2700000
```

## 🔧 Advanced Features

### Custom Manifests

Include custom resources during installation:

```yaml
day1:
  extra_manifests:
    - ${HOME}/custom-manifests
    - ./additional-configs
    - ${OCP_Y_VERSION}/version-specific
```

### Proxy Configuration

Configure proxy settings:

```yaml
proxy:
  enabled: true
  http: http://proxy.example.com:8080
  https: https://proxy.example.com:8080
  noproxy: localhost,127.0.0.1,.example.com
```

### Mirror Registry

Configure disconnected/mirrored registry:

```yaml
mirror:
  enabled: true
  registry: registry.example.com:5000
  namespace: ocp4/openshift4
```

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

## 📊 Validation Checklist

The `sno-ready.sh` script validates:

- ✅ **Cluster Health**: Node status, operator health, pod status
- ✅ **Machine Configs**: CPU partitioning, kdump, performance settings
- ✅ **Performance Profile**: Isolated/reserved CPUs, real-time kernel
- ✅ **Operators**: PTP, SR-IOV, Local Storage, Cluster Logging
- ✅ **Network**: SR-IOV node state, network diagnostics
- ✅ **System**: Kernel parameters, cgroup configuration, container runtime
- ✅ **Monitoring**: AlertManager, Prometheus, Telemetry settings
