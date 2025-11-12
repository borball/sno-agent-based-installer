#!/bin/bash

version=${1:-4.20.0-rc.2}

cluster=sno130

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
root_path="$( cd "$(dirname "$0")/../.." >/dev/null 2>&1 ; pwd -P )"
iso_cmd="$root_path"/sno-iso.sh
sno_workspace="$root_path"/instances/"$cluster"
install_cmd="$root_path"/sno-install.sh
config="$basedir"/tests/sno130/config-"$cluster"-420.yaml
day2_cmd="$root_path"/sno-day2.sh

iso(){
    echo "Generate ISO"
    rm -rf $sno_workspace
    $iso_cmd $config $version
    scp $sno_workspace/agent.x86_64.iso 192.168.58.15:/var/www/html/iso/$cluster.iso
    cp $sno_workspace/auth/kubeconfig /etc/kubes/kubeconfig-$cluster.yaml
}

install(){
  echo "Install OCP cluster $cluster"
  $install_cmd
}

day2(){
  echo "Day2"
  $day2_cmd
}

iso
install
day2

