#!/bin/bash

usage(){
	echo "Usage: $0 node [memory] [cpu] [disks]"
  echo "Examples:"
  echo " test.sh sno130"
  echo " test.sh mce 20480 20 120,50,50"
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
memory=${2:-20480}
cpu=${3:-16}
disks=${4:-120}

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
root_path="$( cd "$(dirname "$basedir")" >/dev/null 2>&1 ; pwd -P )"
iso="$root_path"/sno-iso.sh
install="$root_path"/sno-install.sh
config="$basedir"/configs/config-"$node".yaml

delete_kvm(){
  echo ssh 192.168.58.14 kcli stop vm $node
  echo ssh 192.168.58.14 kcli delete vm $node -y
}

create_kvm(){
  local create="kcli create vm -P uuid=$kvm_uuid -P start=False -P memory=$memory -P numcpus=$cpu -P disks=[$disks] -P nets=[\"{\\\"name\\\":\\\"br-vlan58\\\",\\\"nic\\\":\\\"eth0\\\",\\\"mac\\\":\\\"$2\\\"}\"] $node"
  echo ssh 192.168.58.14 $create
}

restart_sushy(){
  echo systemctl restart sushy-tools.service
}

install_ocp(){
  echo "Install OCP on node $node"
  $iso $config
}

if [ -f  "$config" ]; then
  kvm_uuid=$(yq '.bmc.kvm_uuid // "" ' $config)
  if [ -n "$kvm_uuid" ]; then
    delete_kvm $node
    create_kvm $kvm_uuid $(yq '.host.mac' $config)
    restart_sushy
  fi

  install_ocp

fi

