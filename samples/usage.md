## Usages

- [full configuration](config-full.yaml)
- [ipv4](config-sno130.yaml)
- [ipv6 with proxy](config-ipv6-proxy.yaml)
- [kvm](config-testkvm.yaml)
- [hub cluster on SNO](config-hub.yaml)

## Day1

You can turn on/off day1 configuration in day1 section, following are the fallback values if day1 is not present.

```yaml
day1:
  workload_partition: true
  kdump: 
    enabled: true
    #set blacklist_ice as true on HPE servers
    blacklist_ice: false
    #secure boot, will have additional kernel argument efi=runtime
    secure_boot: false
  boot_accelerate: true
  #ztp_hub=true will enable rhacm/lvm/gitops/talm on the cluster
  ztp_hub: false
  #4.12 will ignore this setting, 4.13+ will enable crun by default
  crun: true
  #4.14, https://issues.redhat.com/browse/OCPBUGS-17660
  rcu_normal: true
  #4.14, reduce a node boot and fix a race condition issue in sriov operator
  sriov_kernel: true
  #4.14, sync the node time from ntp when node reboot and ptp got involved
  sync_time_once: true
  #enable cgroupv1
  cgv1: true
  operators:
    ptp:
      enabled: true
      #if you want to stay on a particular version ptp-operator.4.12.0-202402081808
      #version: ptp-operator.4.12.0-202402081808
    sriov:
      enabled: true
      #if you want to stay on a particular version sriov-network-operator.v4.12.0-202402081808
      #version: sriov-network-operator.v4.12.0-202402081808
    local-storage:
      enabled: true
      #if you want to stay on a particular version local-storage-operator.v4.12.0-202403082008
      #version: local-storage-operator.v4.12.0-202403082008
    gitops:
      enabled: false
    rhacm:
      enabled: false
    talm:
      enabled: false
    mce:
      enabled: false
    lvm:
      enabled: false
    fec:
      enabled: false
      #if you want to stay on a particular version sriov-fec.v2.7.2
      #version: sriov-fec.v2.7.2
    cluster-logging:
      enabled: false
      #if you want to stay on a particular version
      #version: cluster-logging.v5.8.3
    adp:
      enabled: false
      #set the channel
      #channel: stable-1.3
      #set the version
      #version: 1.3.1
```

## Day2

You can turn on/off day2 configuration in day2 section.

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
    kdump: false
    sysfs:
      #cap the intel_pstate peak frequency at 2.5Ghz
      cpufreq_max_freq: 2500000
  ptp:
    #ptpconfig type: choose any of them: disabled|ordinary|boundary
    #chronyd service will be disabled if ordinary or boundary being selected
    ptpconfig: disabled
    ordinary_clock:
      #name: crdu-ptp-ordinary-clock
      interface: ens1f0
    boundary_clock:
      - slave: ens1f0
        masters:
          - ens1f1
          - ens1f2
          - ens1f3
        #name (default): crdu-boundary-clock-ptp-config
        name: crdu-boundary-clock-ptp-config-nic1
        #profile (default): bc-profile
        profile: bc-profile-nic1
        #phc2sys_enable (default): true
        phc2sys_enable: true
      # configure dual NIC bondary clock (optional)
      # must
      #  - use different name, profile
      #  - set phc2sys_enable to false
      - name: crdu-boundary-clock-ptp-config-nic2
        profile: bc-profile-nic2
        slave: ens2f0
        masters:
          - ens2f1
          - ens2f2
          - ens2f3
        phc2sys_enable: false
    #enable the ptp event
    enable_ptp_event: false
    #enable log_reduce, when setting as true it will reduce(filter all) the ptp logs
    log_reduce: false
    
  #enable the cluster monitoring tuning
  cluster_monitor_tuning: true
  #enable the operator hub tuning: disable unused catalog sources
  operator_hub_tuning: true
  #disable the network diagnostics
  disable_network_diagnostics: true
  #4.14 disable the olm pprof(collect-profile cronjob)
  disable_olm_pprof: true  
  #disable the operator auto-upgrade
  disable_operator_auto_upgrade: true

  #https://github.com/openshift-kni/cnf-features-deploy/blob/master/ztp/source-crs/SriovOperatorConfig-SetSelector.yaml
  sriov:
    enable_injector: false
    enable_webhook: false
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