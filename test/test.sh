#!/bin/bash

usage(){
  echo "Usage: $0 node [version] [memory] [cpu] [disks]"
  echo "Examples:"
  echo " test.sh sno130"
  echo " test.sh sno148 4.14.3"
  echo " test.sh mce 4.14.3 20480 20 120,50,50"
}

if [ $# -lt 1 ]
then
  usage
  exit
fi

if [[ ( $@ == "--help") ||  $@ == "-h" ]]
then
  usage
  exit
fi

node=$1
version=${2:-stable-4.14}
memory=${3:-20480}
cpu=${4:-16}
disks=${5:-120}

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
root_path="$( cd "$(dirname "$0")/.." >/dev/null 2>&1 ; pwd -P )"
iso="$root_path"/sno-iso.sh
sno_workspace="$root_path"/instances/"$node"
install="$root_path"/sno-install.sh
config="$basedir"/configs/config-"$node".yaml
day2="$root_path"/sno-day2.sh

delete_kvm(){
  ssh 192.168.58.14 kcli stop vm $node
  ssh 192.168.58.14 kcli delete vm $node -y
}

create_kvm(){
  local create="kcli create vm -P uuid=$kvm_uuid -P start=False -P memory=$memory -P numcpus=$cpu -P disks=[$disks] -P nets=[\"{\\\"name\\\":\\\"br-vlan58\\\",\\\"nic\\\":\\\"eth0\\\",\\\"mac\\\":\\\"$2\\\"}\"] $node"
  ssh 192.168.58.14 $create
}

restart_sushy(){
  systemctl restart sushy-tools.service
}

install_ocp(){
  echo "Install OCP on node $node"
  rm -rf $sno_workspace
  $iso $config $version
  cp $sno_workspace/agent.x86_64.iso /var/www/html/iso/$node.iso
  cp $sno_workspace/auth/kubeconfig /root/workload-enablement/kubeconfigs/kubeconfig-$node.yaml
  $install
}

if [ -f  "$config" ]; then
  kvm_uuid=$(yq '.bmc.kvm_uuid // "" ' $config)
  if [ -n "$kvm_uuid" ]; then
    delete_kvm $node
    create_kvm $kvm_uuid $(yq '.host.mac' $config)
    restart_sushy
  fi

  install_ocp
  $day2
fi

