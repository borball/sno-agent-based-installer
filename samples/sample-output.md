## sno-iso

```
[root@hub-helper sno-vdu]# ./sno-iso.sh config-sno131.yaml 4.13.0
You are going to download OpenShift installer 4.13.0
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  348M  100  348M    0     0  74.7M      0  0:00:04  0:00:04 --:--:-- 79.1M

Enabling day1 configuration...
Workload partitioning:                 enabled   
SNO boot accelerate:                   enabled   
kdump service:                         enabled   
kdump, blacklist_ice(for HPE):         enabled   
Local Storage Operator:                enabled   
PTP Operator:                          enabled   
SR-IOV Network Operator:               enabled   
AMQ Interconnect Operator:             disabled  
Red Hat ACM:                           disabled  
GitOps Operator:                       enabled   
TALM Operator:                         disabled  


Generating boot image...

INFO The rendezvous host IP (node0 IP) is 192.168.14.27 
INFO Extracting base ISO from release payload     
INFO Verifying cached file                        
INFO Using cached Base ISO /root/.cache/agent/image_cache/coreos-x86_64.iso 
INFO Consuming Extra Manifests from target directory 
INFO Consuming Install Config from target directory 
INFO Consuming Agent Config from target directory 

------------------------------------------------
kubeconfig: sno131/auth/kubeconfig.
kubeadmin password: sno131/auth/kubeadmin-password.
------------------------------------------------

Next step: Go to your BMC console and boot the node from ISO: sno131/agent.x86_64.iso.
You can also run ./sno-install.sh to boot the node from the image automatically if you have a HTTP server serves the image.
Enjoy!

```

## sno-install

```
[root@hub-helper sno-vdu]# ./sno-install.sh config-sno131.yaml 
-------------------------------
Starting SNO deployment...

Power off server.
{"error":{"code":"iLO.0.10.ExtendedInfo","message":"See @Message.ExtendedInfo for more information.","@Message.ExtendedInfo":[{"MessageId":"Base.1.4.Success"}]}}200 https://192.168.14.131/redfish/v1/Systems/1/Actions/ComputerSystem.Reset
-------------------------------

Eject Virtual Media.
{"error":{"code":"iLO.0.10.ExtendedInfo","message":"See @Message.ExtendedInfo for more information.","@Message.ExtendedInfo":[{"MessageId":"Base.1.4.Success"}]}}200 https://192.168.14.131/redfish/v1/Managers/1/VirtualMedia/2/Actions/VirtualMedia.EjectMedia
-------------------------------

Insert Virtual Media: http://192.168.58.15/iso/agent-131.iso
{"error":{"code":"iLO.0.10.ExtendedInfo","message":"See @Message.ExtendedInfo for more information.","@Message.ExtendedInfo":[{"MessageId":"Base.1.4.Success"}]}}200 https://192.168.14.131/redfish/v1/Managers/1/VirtualMedia/2/Actions/VirtualMedia.InsertMedia
-------------------------------

Virtual Media Status: 
{
  "@odata.context": "/redfish/v1/$metadata#VirtualMedia.VirtualMedia",
  "@odata.etag": "W/\"70E51051\"",
  "@odata.id": "/redfish/v1/Managers/1/VirtualMedia/2",
  "@odata.type": "#VirtualMedia.v1_3_0.VirtualMedia",
  "Id": "2",
  "Actions": {
    "#VirtualMedia.EjectMedia": {
      "target": "/redfish/v1/Managers/1/VirtualMedia/2/Actions/VirtualMedia.EjectMedia"
    },
    "#VirtualMedia.InsertMedia": {
      "target": "/redfish/v1/Managers/1/VirtualMedia/2/Actions/VirtualMedia.InsertMedia"
    }
  },
  "ConnectedVia": "URI",
  "Description": "Virtual Removable Media",
  "Image": "http://192.168.58.15/iso/agent-131.iso",
  "ImageName": "agent-131.iso",
  "Inserted": true,
  "MediaTypes": [
    "CD",
    "DVD"
  ],
  "Name": "VirtualMedia",
  "Oem": {
    "Hpe": {
      "@odata.context": "/redfish/v1/$metadata#HpeiLOVirtualMedia.HpeiLOVirtualMedia",
      "@odata.type": "#HpeiLOVirtualMedia.v2_2_0.HpeiLOVirtualMedia",
      "Actions": {
        "#HpeiLOVirtualMedia.EjectVirtualMedia": {
          "target": "/redfish/v1/Managers/1/VirtualMedia/2/Actions/Oem/Hpe/HpeiLOVirtualMedia.EjectVirtualMedia"
        },
        "#HpeiLOVirtualMedia.InsertVirtualMedia": {
          "target": "/redfish/v1/Managers/1/VirtualMedia/2/Actions/Oem/Hpe/HpeiLOVirtualMedia.InsertVirtualMedia"
        }
      },
      "BootOnNextServerReset": false
    }
  },
  "TransferProtocolType": "HTTP",
  "WriteProtected": true
}
-------------------------------

Boot node from Virtual Media Once
{"error":{"code":"iLO.0.10.ExtendedInfo","message":"See @Message.ExtendedInfo for more information.","@Message.ExtendedInfo":[{"MessageId":"Base.1.4.Success"}]}}200 https://192.168.14.131/redfish/v1/Systems/1
-------------------------------

Power on server.
{"error":{"code":"iLO.0.10.ExtendedInfo","message":"See @Message.ExtendedInfo for more information.","@Message.ExtendedInfo":[{"MessageId":"Base.1.4.Success"}]}}200 https://192.168.14.131/redfish/v1/Systems/1/Actions/ComputerSystem.Reset

-------------------------------
Node is booting from virtual media mounted with http://192.168.58.15/iso/agent-131.iso, check your BMC console to monitor the installation progress.


Node booting..


```

## sno-day2

```
[root@hub-helper sno-vdu]# ./sno-day2.sh 
Usage: ./sno-day2.sh [config.yaml]
Example: ./sno-day2.sh config-sno130.yaml
[root@hub-helper sno-vdu]# ./sno-day2.sh config-sno131.yaml 
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.13.0    True        False         13h     Cluster version is 4.13.0

NAME                          STATUS   ROLES                         AGE   VERSION
sno131.outbound.vz.bos2.lab   Ready    control-plane,master,worker   13h   v1.26.3+b404935


------------------------------------------------
Applying day2 operations....

performance profile:                                         enabled   
performanceprofile.performance.openshift.io/sno-perfprofile created

tuned performance patch:                                     enabled   
tuned.tuned.openshift.io/performance-patch created

tuned kdump settings:                                        enabled   
tuned.tuned.openshift.io/performance-patch-kdump-setting created

cluster monitor tuning:                                      enabled   
configmap/cluster-monitoring-config created

operator hub tuning:                                         enabled   
operatorhub.config.openshift.io/cluster patched

openshift console:                                           disabled  
console.operator.openshift.io/cluster patched

network diagnostics:                                         disabled  
network.operator.openshift.io/cluster patched

ptp amq router:                                              enabled   
interconnect.interconnectedcloud.github.io/amq-router created

operator amq7-interconnect-subscription auto upgrade:        disabled  
subscription.operators.coreos.com/amq7-interconnect-subscription patched
operator local-storage-operator auto upgrade:                disabled  
subscription.operators.coreos.com/local-storage-operator patched
operator openshift-gitops-operator auto upgrade:             disabled  
subscription.operators.coreos.com/openshift-gitops-operator patched
operator ptp-operator-subscription auto upgrade:             disabled  
subscription.operators.coreos.com/ptp-operator-subscription patched
operator sriov-network-operator-subscription auto upgrade:   disabled  
subscription.operators.coreos.com/sriov-network-operator-subscription patched

Done.
```