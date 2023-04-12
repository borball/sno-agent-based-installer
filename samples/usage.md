## IPV4

```
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
ssh_key: /root/.ssh/id_rsa.pub

```

## IPV6 with proxy

```
cluster:
  domain: outbound.vz.bos2.lab
  name: sno148

host:
  interface: ens1f0
  stack: ipv6
  hostname: sno148.outbound.vz.bos2.lab
  ip: 2600:52:7:58::48
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
  enabled: true
  http: http://[2600:52:7:58::15]:3128
  https: http://[2600:52:7:58::15]:3128
  noproxy: 2600:52:7:58::/64,localhost,127.0.0.1

pull_secret: ./pull-secret.json
ssh_key: /root/.ssh/id_rsa.pub
```

## IPv4, with certain operators as ZTP hub

```
cluster:
  domain: outbound.vz.bos2.lab
  name: hub

host:
  interface: ens1f0
  stack: ipv4
  hostname: hub.outbound.vz.bos2.lab
  ip: 192.168.58.80
  dns: 192.168.58.15
  gateway: 192.168.58.1
  mac: de:ad:be:ff:10:01
  prefix: 25
  machine_network_cidr: 192.168.58.0/25
  vlan:
    enabled: false
    name: ens1f0.58
    id: 58
  disk: /dev/vda

day1:
  workload_partition: false  #default true
  kdump: false  #default true
  ptp: false  #default true
  sriov: false #default true
  storage: true #default true
  accelerate: true #default true
  gitops: true #default false
  rhacm: true #default false
  talm: true #default false
  
proxy:
  enabled: false
  http:
  https:
  noproxy:

pull_secret: ./pull-secret.json
ssh_key: /root/.ssh/id_rsa.pub

```
