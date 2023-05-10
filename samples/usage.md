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
  kdump: 
    enabled: true
    #set blacklist_ice as true on HPE servers
    blacklist_ice: false
  boot_accelerate: true
  operators:
    ptp: true
    sriov: true
    storage: true
    gitops: true
    rhacm: false
    talm: false
    amq: false

```

## Day2

You can turn on/off day2 configurtation in day2 section.

```yaml
day2:
  performance_profile:
    enabled: true
    #in case you want to specify the performance profile name
    name: sno-perfprofile
  tuned_profile: 
    enabled: true
    #for wrong bios settings, if passive mode is used, set intel_pstate=active
    cmdline_pstate: intel_pstate=active
    #in case you want to generate kdump for some special scenarios (used in lab)
    kdump: true
  #enable the amq interconnector for ptp  
  ptp_amq_router: true
  #enable the cluster monitoring tuning
  cluster_monitor_tuning: true
  #enable the opertor hub tuning: disable unused catalogsources
  operator_hub_tuning: true
  #disable the ocp console operator
  disable_ocp_console: true
  #disable the network diagnostics
  disable_network_diagnostics: true
```

## Other usages

An example to use this repo to create a SNO running on KVM, and install the ZTP required opertators so to act as a ZTP hub. 

```shell

## Create VM
ssh 192.168.58.14 kcli stop vm hub
ssh 192.168.58.14 kcli delete vm hub -y
ssh 192.168.58.14 'kcli create vm -P uuid=11111111-1111-1111-1234-000000000000 -P start=False -P memory=20480 -P numcpus=16 -P disks=[150] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:85\"}"] hub'
ssh 192.168.58.14 kcli list vm

systemctl restart sushy-tools.service

## Generate ISO, config-hub.yaml turn on all ZTP required operators but turn off others

rm -f ~/.cache/agent/image_cache/coreos-x86_64.iso
rm -rf hub
./sno-iso.sh samples/ztp-hub-on-sno/config-hub.yaml
cp hub/agent.x86_64.iso /var/www/html/iso/hub.iso


## Install OCP
./sno-install.sh samples/ztp-hub-on-sno/config-hub.yaml


oc get node --kubeconfig hub/auth/kubeconfig
oc get clusterversion --kubeconfig hub/auth/kubeconfig

echo "Installation in progress, please check it in 30m."


## Run extra manifests

oc --kubeconfig hub/auth/kubeconfig apply -k ./extra-manifests

```