#!/bin/bash

version=${1:-stable-4.18}

cluster=acm0

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
root_path="$( cd "$(dirname "$0")/.." >/dev/null 2>&1 ; pwd -P )"
iso_cmd="$root_path"/sno-iso.sh
sno_workspace="$root_path"/instances/"$cluster"
install_cmd="$root_path"/sno-install.sh
config="$basedir"/configs/config-"$cluster".yaml
day2_cmd="$root_path"/sno-day2.sh


create_vm(){
  echo "Create VM"
  oc apply -k $basedir/virtual-machines/$cluster
}

delete_vm(){
  echo "Delete VM"
  oc delete vm -n $cluster --all
  oc delete dv -n $cluster --all
  oc delete pvc -n $cluster --all
}

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

to_vhub(){
    echo "To vhub"
    export KUBECONFIG=/etc/kubes/kubeconfig-vhub.yaml
}

vm_ready_to_power_on() {
  echo "Waiting for the VM being ready to power on..."
  while [[ $(oc get dv -n $cluster | wc -l) -ne 4 ]]; do
    echo "Waiting for the VM's DataVolume to be created..."
    sleep 1
  done

  timeout=120
  while [[ $timeout -gt 0 ]]; do
    success=true
    for dv in $(oc get dv -n $cluster -o name); do
      phase=$(oc get -n $cluster $dv -o yaml | yq '.status.phase')
      if [[ "$phase" != "Succeeded" ]]; then
        echo "$dv phase $phase is not Succeeded yet; Waiting for the $dv DataVolume to be and succeed..."
        sleep 5
        timeout=$((timeout - 1))
        success=false
      fi
    done
    if $success; then
      break
    fi
  done

  done=true
  for dv in $(oc get dv -n $cluster -o name); do
    phase=$(oc get -n $cluster $dv -o yaml | yq '.status.phase')
    if [[ "$phase" != "Succeeded" ]]; then
      echo "$dv phase $phase is not Succeeded yet; Waiting for the $dv DataVolume to be and succeed..."
      sleep 5
      timeout=$((timeout - 1))
      done=false
    fi
  done
  if $done; then
    echo "The VM is ready to power on."
  else
    echo "The VM is not ready to power on, please check the DataVolumes' phase."
    exit 1
  fi
  echo
}

power_on_vm() {
  echo "Powering on the VM to start the installation."
  virtctl start $cluster -n $cluster
  echo
}

iso
to_vhub

delete_vm
create_vm

vm_ready_to_power_on
power_on_vm

install
day2


