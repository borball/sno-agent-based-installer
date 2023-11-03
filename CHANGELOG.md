## 2023-11-03

- OpenShift 4.14 support
  - ZTP 4.14 profiles

- Intel Fec operator
  ```yaml
  day1:
    operators:
      fec: true
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
    - baremetal
    - openshift-samples
  - 4.13+ will disable all optional cluster operators below
    - Build
    - CSISnapshot
    - Console
    - DeploymentConfig
    - ImageRegistry
    - Insights
    - MachineAPI
    - Storage
    - baremetal
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
