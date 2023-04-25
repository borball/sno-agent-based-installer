## Usages

- [full configuration](config-full.yaml)
- [ipv4](config-sno130.yaml)
- [ipv6 with proxy](config-sno148.yaml)
- [kvm](config-testkvm.yaml)
- [hub cluster on SNO](config-hub.yaml)

## Day1

You can turn on/off day1 configurtation in day1 section, following are the fallback values if not poresented.

```yaml
day1:
  workload_partition: true
  kdump: true
  ptp: true
  sriov: true
  storage: true
  accelerate: true
  gitops: true
  rhacm: false
  talm: false
  amq: false

```

## Day2

You can turn on/off day2 configurtation in day2 section, following are the fallback values if not poresented.

```yaml
day2:
  performance_profile:
    name: sno-perfprofile
    enabled: true
  tuned: true
  kdump_tuned: false
  ptp_amq: true
  cluster_monitor: true
  operator_hub: true
  console: true
  network_diagnostics: true
```

## Advanced

