## 2024-06-28
- add LCA(Lifecycle Agent) support
- fix container storage partitioning template path
- 4.14-4.15 set cgv1: true by default, 4.16+ set cgv1: false by default, will use cgv2.

## 2024-06-19
- added support to lock the operators in a certain version
- 4.16 support
- ptp fast event: summary_interval and logReduce
- sriovOperatorConfig in day2, for case#03795200
- support to specify userLevelNetworking in config.yaml
- dual nic boundary clock support
- add oadp operator support in day1
- add container storage partitioning support in day1
- cap the CPU frequency
- 
## 2024-03-27
- nightly build installation support
- do remote ssh check rather than curling directly
- config change, moved operators into metadata folders
- moved workspace into instances/<cluster>
- config to disable redhat-marketplace and community-operators
- disconnected env support
- auto-approve installplan which used "installPlanApproval: Manual", this can be used to lock the operator in a particular version

## 2023-12-19

- Multiple DNS servers (please update your config.yaml)
  Changed from:
  ```yaml
  host:
    ipv4:
      dns: 192.168.58.15
    ipv6: 
      dns: 2600:52:7:58::15
  ```
  to:
  ```yaml
  host:
    ipv4:
      dns:
        - 192.168.58.15
    ipv6:
      dns:
        - 2600:52:7:58::15
  ```

- OpenShift 4.14 support
  - ZTP 4.14 profiles
  ```yaml
  day1:
    #4.14, https://issues.redhat.com/browse/OCPBUGS-17660
    rcu_normal: true
    #4.14, reduce a node boot and fix a race condition issue in sriov operator
    sriov_kernel: true
    #4.14, sync the node time from ntp when node reboot and ptp got involved
    sync_time_once: true
    #ztp_hub=true will enable rhacm/lvm/gitops/talm on the cluster
  
  day2:
    #4.14 disable the olm pprof(collect-profile cronjob)
    disable_olm_pprof: true
  ```

- sno-ready, added more check points:
  - cluster operator status
  - new machineconfig in 4.14 exists or not
  - cluster capabilities check
  - operator hub check
  - pending install plan
  - olm collect-profile cron job (4.14)
  - container runtime

- Intel Fec operator
  ```yaml
  day1:
    operators:
      #default: false
      fec: true
  ```
  
- cluster-logging operator
  ```yaml
  day1:
    operators:
      #default: false
      cluster_logging: true
  ```

- Fixed PtpConfig issues
  - Removed duplicated interface names
  - Removed '-u 2' from phc2sysOpts

- Ptp event notification in day2
  - removed AMQ integration
  - day2
    ```yaml
    day2:
      ptp:
        #enable the ptp event
        enable_ptp_event: false
    ```

- Cluster capabilities support
  - By default, 4.12 will disable all optional cluster operators below
    - CSISnapshot
    - Console
    - Insights
    - Storage
    - openshift-samples
  - 4.14 will disable all optional cluster operators below
    - Build
    - CSISnapshot
    - Console
    - DeploymentConfig
    - ImageRegistry
    - Insights
    - MachineAPI
    - Storage
    - openshift-samples
  
  More info: https://docs.openshift.com/container-platform/4.14/post_installation_configuration/enabling-cluster-capabilities.html 

## 2023-08-22

- OpenShift 4.13/4.14(EC) support

- More operator options in day1

    ```yaml
    day1:
      operators:
        ptp: true
        sriov: true
        storage: true
        gitops: false
        rhacm: false
        talm: false
        mce: false
        lvm: false
    ```

- enable crun (needs 4.13+)

    ```yaml
    day1:
      crun: true
    ```
  
- NTP support

    ```yaml
    cluster:
      ntps:
      - 0.rhel.pool.ntp.org
      - 1.rhel.pool.ntp.org
    
    ```

- Network config refactoring(support dual stack now)
  From:

    ```yaml
      ip: 192.168.58.48
      dns: 192.168.58.15
      gateway: 192.168.58.1
      mac: b4:96:91:b4:9d:f0
      prefix: 25
      vlan:
        enabled: false
        name: ens1f0.58
        id: 58
    ```

  To:

    ```yaml
      interface: ens1f0
      mac: b4:96:91:b4:9d:f0
      ipv4:
        enabled: true
        dhcp: false
        ip: 192.168.58.48
        dns: 192.168.58.15
        gateway: 192.168.58.1
        prefix: 25
        machine_network_cidr: 192.168.58.0/25
        #optional, default 10.128.0.0/14
        #cluster_network_cidr: 10.128.0.0/14
        #optional, default 23
        #cluster_network_host_prefix: 23
      ipv6:
        enabled: false
        dhcp: false
        ip: 2600:52:7:58::48
        dns: 2600:52:7:58::15
        gateway: 2600:52:7:58::1
        prefix: 64
        machine_network_cidr: 2600:52:7:58::/64
        #optional, default fd01::/48
        #cluster_network_cidr: fd01::/48
        #optional, default 64
        #cluster_network_host_prefix: 64
      vlan:
        enabled: false
        name: ens1f0.58
        id: 58
    ```

- ZTP hub (This will install necessary operators required by ZTP hub )

    ```yaml
    day1:
      #ztp_hub=true will enable rhacm/lvm/gitops/talm on the cluster
      ztp_hub: true
    ```
  
- Use config.yaml as argument for all sno*.sh scripts
