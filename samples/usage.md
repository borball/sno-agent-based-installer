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
  #whether enable cgroup v1; 4.14-4.15: will enable cgv1 by default, 4.16+ will enable cgv2 by default
  cgv1: true
  container_storage:
    enabled: false
    device: /dev/nvme0n1
    startMiB: 250000
    sizeMiB: 0
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
      #preparation work for local storage
      provision:
        #Get the ID with command: udevadm info -q property --property=ID_PATH /dev/nvme1n1
        disk_by_path: pci-0000:c3:00.0-nvme-1
        lvs:
          1g: 10
          2g: 10
          4g: 5
          5g: 5
          10g: 2
          15g: 1
          30g: 1
    gitops:
      enabled: false
    rhacm:
      enabled: false
    talm:
      enabled: false
    mce:
      enabled: false
    mcgh:
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
    lca:
      enabled: false
      #set the channel
      #channel: stable
      #set the version
      #version: v4.16.0-89
    kubevirt-hyperconverged:
      enabled: false
      #channel: stable
      #set the version
      #version: v4.16.3
    nfd:
      #source: prega
      enabled: false
      #channel: stable
      #set the version
      #version: 
    gpu:
      enabled: false
      #source: certified-operators
      #channel: v24.9
      #version: gpu-operator-certified.v24.9.2     
  extra_manifests:
    - ${HOME}/1
    - ${HOME}/2
    - $OCP_Y_VERSION
```

## Day2

You can turn on/off day2 configuration in day2 section.

```yaml
day2:
  # pause the MCP for a certain period and unpause it in order to reduce the number of node reboot.
  delay_mcp_update: 60
  performance_profile:
    enabled: true
    #in case you want to specify the performance profile name
    name: sno-perfprofile
    #optional, default value: true
    real_time: false
    #optional, present if want to set user_level_networking as true
    net:
      user_level_networking: true
    #optional for hardware tuning, OCP 4.16
    hardwareTuning:
      isolatedCpuFreq: 2500000
      reservedCpuFreq: 2800000
    #optional
    hugepage:
      default: 2M
      pages:
        - size: 2M
          count: 32768
          #node: 1
          
  tuned_profile:
    enabled: true
    #for wrong bios settings, if passive mode is used, set intel_pstate=active
    cmdline_pstate: intel_pstate=active
    #in case you want to generate kdump for some special scenarios (used in lab)
    kdump: false
    sysfs:
      #cap the intel_pstate peak frequency at 2.5Ghz, used in 4.14. 4.16 can set day2.performance_profile.hardwareTuning
      cpufreq_max_freq: 2500000
  ptp:
    #ptpconfig type: choose any of them: disabled|ordinary|boundary
    #chronyd service will be disabled if ordinary or boundary being selected
    ptpconfig: disabled
    clock_threshold_tuning:
      hold_over_timeout: 5
      max_offset: 500
      min_offset: -500
    ordinary_clock:
      #name: crdu-ptp-ordinary-clock
      interface: ens1f0
    boundary_clock:
      # only supported for 4.16+, when not enabled, the profiles[0] is used for system clock, 4.15 or earlier versions must set it as false
      ha_enabled: false
      #name (default): crdu-boundary-clock-ptp-config
      #name: crdu-boundary-clock-ptp-config
      profiles:
        - name: bc-profile-nic1
          slave: ens1f0
          masters:
            - ens1f1
            - ens1f2
            - ens1f3
          ptp4lConf:
            boundary_clock_jbod: 0
        - name: bc-profile-nic2
          slave: ens2f0
          masters:
            - ens2f1
            - ens2f2
            - ens2f3
          ptp4lConf:
            boundary_clock_jbod: 0

    #enable the ptp event, if true, will set summary_interval as -4, otherwise it will stay at 0
    enable_ptp_event: true
    #event_api_version: "1.0" or "2.0"; to avoid issues, 4.12-4.15, should not set event_api_version
    #4.16-4.17, if event_api_version not present, "1.0" will be the default
    #4.18, if event_api_version not present, "2.0" will be the default
    #4.19+, "1.0" will be deleted
    #event_api_version: "1.0"
    #enable log_reduce, when setting as true it will reduce(filter all) the ptp logs
    log_reduce: true
    
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

  lvm:
    device_classes:
      - name: "sno"
        thin_pool_name: "sno-sdb-pool"
        selector:
          paths:
            - "/dev/sdb"
  #LocalVolume settings for local storage operator, 
  #if not present, and if day1.operators.local-storage.provision.lvs is present, will use default name 'local-disks'
  # and storageClassName 'general'
  local_storage:
    local_volume:
      name: local-disks
      storageClassName: general

  extra_manifests:
    - ${HOME}/1
    - ${HOME}/2
    - $OCP_Y_VERSION
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