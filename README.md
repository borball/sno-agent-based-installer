# sno-agent-based-installer
Script to deploy SNO with Agent Based Installer

## Configuration

Prepare config.yaml to fit your lab situation, example:

IPv4 with vlan:

```yaml
cluster:
  domain: outbound.vz.bos2.lab
  name: sno148

host:
  interface: ens1f0
  stack: ipv4
  hostname: sno148.outbound.vz.bos2.lab
  ip: 192.168.58.48
  dns: 192.168.58.15
  gateway: 192.168.58.1
  mac: b4:96:91:b4:9d:f0
  prefix: 25
  machine_network_cidr: 192.168.58.0/25
  vlan:
    enabled: true
    name: ens1f0.58
    id: 58
  disk: /dev/nvme0n1

cpu:
  isolated: 2-31,34-63
  reserved: 0-1,32-33

proxy:
  enabled: false
  http:
  https:
  noproxy:

pull_secret: ./pull-secret.json
ssh_key: /home/bzhai/.ssh/id_rsa.pub

```

IPv6 without vlan:

```yaml
cluster:
  domain: outbound.vz.bos2.lab
  name: sno148

host:
  interface: ens1f0
  stack: ipv6
  hostname: sno148.outbound.vz.bos2.lab
  ip: 2600:52:7:58::58
  dns: 2600:52:7:58::15
  gateway: 2600:52:7:58::1
  mac: b4:96:91:b4:9d:f0
  prefix: 64
  machine_network_cidr: 2600:52:7:58::/64
  vlan:
    enabled: false
    name: ens1f0.58
    id: 58
  disk: /dev/nvme0n1

cpu:
  isolated: 2-31,34-63
  reserved: 0-1,32-33

proxy:
  enabled: false
  http:
  https:
  noproxy:

pull_secret: ./pull-secret.json
ssh_key: /home/bzhai/.ssh/id_rsa.pub

```
## Generate ISO

```shell
#./sno-iso.sh
You are going to download OpenShift installer 4.12.6
WARNING Capabilities: %!!(MISSING)s(*types.Capabilities=<nil>) is ignored 
INFO The rendezvous host IP (node0 IP) is 192.168.58.48 
INFO Extracting base ISO from release payload     
INFO Base ISO obtained from release and cached at /home/bzhai/.cache/agent/image_cache/coreos-x86_64.iso 
INFO Consuming Extra Manifests from target directory 
INFO Consuming Install Config from target directory 
INFO Consuming Agent Config from target directory 

------------------------------------------------
Next step: Go to your BMC console and boot the node from ISO: sno148/agent.x86_64.iso.

kubeconfig: sno148/auth/kubeconfig.
kubeadmin password: sno148/auth/kubeadmin-password.

------------------------------------------------

```

Or specify the config file and OCP version:

```shell
#./sno-iso.sh config-ipv6.yaml 4.12.4
```

Specify the config file only:

```shell
#./sno-iso.sh config-ipv6.yaml
```

## Boot node from ISO

Boot the node from the generated ISO, OCP will be installed automatically.

## Day2 operations

Some CRs are not supported in installation phase including PerformanceProfile, those can/shall be done as day 2 operations once SNO is deployed.

```shell
#./sno-day2.sh
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.12.4    True        False         17m     Cluster version is 4.12.4

NAME                          STATUS   ROLES                         AGE   VERSION
sno148.outbound.vz.bos2.lab   Ready    control-plane,master,worker   40m   v1.25.4+a34b9e9

NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
authentication                             4.12.4    True        False         False      22m     
baremetal                                  4.12.4    True        False         False      28m     
cloud-controller-manager                   4.12.4    True        False         False      28m     
cloud-credential                           4.12.4    True        False         False      35m     
cluster-autoscaler                         4.12.4    True        False         False      28m     
config-operator                            4.12.4    True        False         False      36m     
console                                    4.12.4    True        False         False      24m     
control-plane-machine-set                  4.12.4    True        False         False      28m     
csi-snapshot-controller                    4.12.4    True        False         False      36m     
dns                                        4.12.4    True        False         False      6m29s   
etcd                                       4.12.4    True        False         False      32m     
image-registry                             4.12.4    True        False         False      27m     
ingress                                    4.12.4    True        False         False      35m     
insights                                   4.12.4    True        False         False      29m     
kube-apiserver                             4.12.4    True        False         False      27m     
kube-controller-manager                    4.12.4    True        False         False      29m     
kube-scheduler                             4.12.4    True        False         False      30m     
kube-storage-version-migrator              4.12.4    True        False         False      36m     
machine-api                                4.12.4    True        False         False      28m     
machine-approver                           4.12.4    True        False         False      28m     
machine-config                             4.12.4    True        False         False      35m     
marketplace                                4.12.4    True        False         False      35m     
monitoring                                 4.12.4    True        False         False      23m     
network                                    4.12.4    True        False         False      37m     
node-tuning                                4.12.4    True        False         False      49s     
openshift-apiserver                        4.12.4    True        False         False      6m23s   
openshift-controller-manager               4.12.4    True        False         False      27m     
openshift-samples                          4.12.4    True        False         False      28m     
operator-lifecycle-manager                 4.12.4    True        False         False      36m     
operator-lifecycle-manager-catalog         4.12.4    True        False         False      36m     
operator-lifecycle-manager-packageserver   4.12.4    True        False         False      30m     
service-ca                                 4.12.4    True        False         False      36m     
storage                                    4.12.4    True        False         False      36m     

NAME                                                      AGE
local-storage-operator.openshift-local-storage            36m
ptp-operator.openshift-ptp                                36m
sriov-network-operator.openshift-sriov-network-operator   36m

NAMESPACE                              NAME                                          DISPLAY                   VERSION               REPLACES   PHASE
openshift-local-storage                local-storage-operator.v4.12.0-202302280915   Local Storage             4.12.0-202302280915              Succeeded
openshift-operator-lifecycle-manager   packageserver                                 Package Server            0.19.0                           Succeeded
openshift-ptp                          ptp-operator.4.12.0-202302280915              PTP Operator              4.12.0-202302280915              Succeeded
openshift-sriov-network-operator       sriov-network-operator.v4.12.0-202302280915   SR-IOV Network Operator   4.12.0-202302280915              Succeeded


Applying day2 operations....
performanceprofile.performance.openshift.io/sno-performance-profile created
tuned.tuned.openshift.io/performance-patch created
configmap/cluster-monitoring-config created
operatorhub.config.openshift.io/cluster patched
console.operator.openshift.io/cluster patched
network.operator.openshift.io/cluster patched

Done.
```

## Validation

Check if all required tunings and operators are in placed: 

```shell
#./sno-ready.sh
NAME                          STATUS   ROLES                         AGE   VERSION
sno148.outbound.vz.bos2.lab   Ready    control-plane,master,worker   51m   v1.25.4+a34b9e9

Checking node:
 [+]Node is ready.

Checking all pods:
 [+]No failing pods.

Checking required machine config:
 [+]MachineConfig container-mount-namespace-and-kubelet-conf-master exits.
 [+]MachineConfig 02-master-workload-partitioning exits.
 [+]MachineConfig 04-accelerated-container-startup-master exits.
 [+]MachineConfig 05-kdump-config-master exits.
 [+]MachineConfig 06-kdump-enable-master exits.
 [+]MachineConfig 99-crio-disable-wipe-master exits.
 [-]MachineConfig disable-chronyd is not existing.

Checking machine config pool:
 [+]mcp master is updated and not degraded.

Checking required performance profile:
 [+]PerformanceProfile sno-performance-profile exits.
 [+]topologyPolicy is single-numa-node
 [+]realTimeKernel is enabled

Checking required tuned:
 [+]Tuned performance-patch exits.

Checking SRIOV operator status:
 [+]sriovnetworknodestate sync status is 'Succeeded'.

Checking PTP operator status:
 [+]Ptp linuxptp-daemon is ready.
No resources found in openshift-ptp namespace.
 [-]PtpConfig not exist.

Checking openshift monitoring.
 [+]Grafana is not enabled.
 [+]AlertManager is not enabled.
 [+]PrometheusK8s retention is not 24h.

Checking openshift console.
 [+]Openshift console is disabled.

Checking network diagnostics.
 [+]Network diagnostics is disabled.

Checking Operator hub.
 [+]Catalog community-operators is disabled.
 [+]Catalog redhat-marketplace is disabled.

Checking /proc/cmdline:
 [+]systemd.cpu_affinity presents: systemd.cpu_affinity=0,1,32,33
 [+]isolcpus presents: isolcpus=managed_irq,2-31,34-63
 [+]Isolated cpu in cmdline: 2-31,34-63 matches with the ones in performance profile: 2-31,34-63
 [+]Reserved cpu in cmdline: 0,1,32,33 matches with the ones in performance profile: 0-1,32-33

Checking RHCOS kernel:
 [+]Node is realtime kernel.

Checking kdump.service:
 [+]kdump is active.
 [+]kdump is enabled.

Checking chronyd.service:
 [-]chronyd is active.
 [-]chronyd is enabled.

Checking crop-wipe.service:
 [+]crio-wipe is inactive.
 [+]crio-wipe is not enabled.

Completed the checking.

```

## Why not Ansible?
Not every user has ansible environment just in order to deploy a SNO.