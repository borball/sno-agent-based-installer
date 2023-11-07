#!/bin/bash
# 
# Helper script to generate bootable ISO with OpenShift agent based installer
# usage: ./sno-iso.sh -h
# 


if ! type "yq" > /dev/null; then
  echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

if ! type "jinja2" > /dev/null; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install --user jinja2-cli
  pip3 install --user jinja2-cli[yaml]
fi

info(){
  printf  $(tput setaf 2)"%-38s %-10s"$(tput sgr0)"\n" "$@"
}

warn(){
  printf  $(tput setaf 3)"%-38s %-10s"$(tput sgr0)"\n" "$@"
}


usage(){
	info "Usage: $0 [config file] [ocp version]"
  info "config file and ocp version are optional, examples:"
  info "- $0 sno130.yaml" " equals: $0 sno130.yaml stable-4.12"
  info "- $0 sno130.yaml 4.12.10"
  echo 
  info "Prepare a configuration file by following the example in config.yaml.sample"
  echo "-----------------------------------"
  echo "# content of config.yaml.sample"
  cat config.yaml.sample
  echo
  echo "-----------------------------------"
  echo
  info "Example to run it: $0 config-sno130.yaml"
  echo
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

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
templates=$basedir/templates

config_file=$1; shift
ocp_release=$1; shift

if [ -z "$config_file" ]
then
  config_file=config.yaml
fi

if [ -z "$ocp_release" ]
then
  ocp_release='stable-4.12'
fi

ocp_release_version=$(curl -s https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${ocp_release}/release.txt | grep 'Version:' | awk -F ' ' '{print $2}')

#if release not available on mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/, probably ec (early candidate) version.
if [ -z $ocp_release_version ]; then
  ocp_release_version=$ocp_release
fi

export ocp_y_release=$(echo $ocp_release_version |cut -d. -f1-2)

echo "You are going to download OpenShift installer $ocp_release: ${ocp_release_version}"

if [ -f $basedir/openshift-install-linux.tar.gz ]; then
  rm -f $basedir/openshift-install-linux.tar.gz
fi

status_code=$(curl -s -o /dev/null -w "%{http_code}" https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$ocp_release_version/)
if [ $status_code = "200" ]; then
  curl -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${ocp_release_version}/openshift-install-linux.tar.gz -o $basedir/openshift-install-linux.tar.gz
  tar xfz $basedir/openshift-install-linux.tar.gz openshift-install
else
  #fetch from image
  oc adm release extract --command=openshift-install quay.io/openshift-release-dev/ocp-release:$ocp_release_version-x86_64 --registry-config=$(yq '.pull_secret' $config_file)
fi

cluster_name=$(yq '.cluster.name' $config_file)
cluster_workspace=$cluster_name

mkdir -p $cluster_workspace
mkdir -p $cluster_workspace/openshift

echo
echo "Enabling day1 configuration..."
if [ "false" = "$(yq '.day1.workload_partition' $config_file)" ]; then
  warn "Workload partitioning:" "disabled"
else
  info "Workload partitioning:" "enabled"
  export crio_wp=$(jinja2 $templates/openshift/day1/workload-partition/crio.conf $config_file |base64 -w0)
  export k8s_wp=$(jinja2 $templates/openshift/day1/workload-partition/kubelet.conf $config_file |base64 -w0)
  jinja2 $templates/openshift/day1/workload-partition/02-master-workload-partitioning.yaml.j2 $config_file > $cluster_workspace/openshift/02-master-workload-partitioning.yaml
fi

if [ "false" = "$(yq '.day1.boot_accelerate' $config_file)" ]; then
  warn "SNO boot accelerate:" "disabled"
else
  info "SNO boot accelerate:" "enabled"
  cp $templates/openshift/day1/accelerate/*.yaml $cluster_workspace/openshift/
  cp $templates/openshift/day1/accelerate/$ocp_y_release/*.yaml $cluster_workspace/openshift/
fi

if [ "false" = "$(yq '.day1.kdump.enabled' $config_file)" ]; then
  warn "kdump service:" "disabled"
else
  if [ "true" = "$(yq '.day1.kdump.secure_boot' $config_file)" ]; then
    info "kdump service(secure boot):" "enabled"
    cp $templates/openshift/day1/kdump/06-kdump-master-secureboot.yaml $cluster_workspace/openshift/
  else
    info "kdump service:" "enabled"
    cp $templates/openshift/day1/kdump/06-kdump-master.yaml $cluster_workspace/openshift/
  fi
fi

if [ "true" = "$(yq '.day1.kdump.blacklist_ice' $config_file)" ]; then
  info "kdump, blacklist_ice(for HPE):" "enabled"
  cp $templates/openshift/day1/kdump/05-kdump-config-master.yaml $cluster_workspace/openshift/
else
  warn "kdump, blacklist_ice(for HPE):" "disabled"
fi

if [ "4.12" = $ocp_y_release ]; then
  warn "Container runtime crun(4.13+):" "disabled"
else
  #4.13+ by default enabled.
  if [ "false" = "$(yq '.day1.crun' $config_file)" ]; then
    warn "Container runtime crun(4.13+):" "disabled"
  else
    info "Container runtime crun(4.13+):" "enabled"
    cp $templates/openshift/day1/crun/*.yaml $cluster_workspace/openshift/
  fi
fi

if [ "false" = "$(yq '.day1.operators.storage' $config_file)" ]; then
  warn "Local Storage Operator:" "disabled"
else
  info "Local Storage Operator:" "enabled"
  cp $templates/openshift/day1/local-storage/*.yaml $cluster_workspace/openshift/
fi

if [ "false" = "$(yq '.day1.operators.ptp' $config_file)" ]; then
  warn "PTP Operator:" "disabled"
else
  info "PTP Operator:" "enabled"
  cp $templates/openshift/day1/ptp/*.yaml $cluster_workspace/openshift/
fi

if [ "false" = "$(yq '.day1.operators.sriov' $config_file)" ]; then
  warn "SR-IOV Network Operator:" "disabled"
else
  info "SR-IOV Network Operator:" "enabled"
  cp $templates/openshift/day1/sriov/*.yaml $cluster_workspace/openshift/
fi

if [ "true" = "$(yq '.day1.operators.rhacm' $config_file)" ]; then
  info "Red Hat ACM:" "enabled"
  cp $templates/openshift/day1/rhacm/*.yaml $cluster_workspace/openshift/
else
  warn "Red Hat ACM:" "disabled"
fi

if [ "true" = "$(yq '.day1.operators.gitops' $config_file)" ]; then
  info "GitOps Operator:" "enabled"
  cp $templates/openshift/day1/gitops/*.yaml $cluster_workspace/openshift/
else
  warn "GitOps Operator:" "disabled"
fi

if [ "true" = "$(yq '.day1.operators.talm' $config_file)" ]; then
  info "TALM Operator:" "enabled"
  cp $templates/openshift/day1/talm/*.yaml $cluster_workspace/openshift/
else
  warn "TALM Operator:" "disabled"
fi

if [ "true" = "$(yq '.day1.operators.mce' $config_file)" ]; then
  info "MCE Operator:" "enabled"
  cp $templates/openshift/day1/mce/*.yaml $cluster_workspace/openshift/
else
  warn "MCE Operator:" "disabled"
fi

if [ "true" = "$(yq '.day1.operators.lvm' $config_file)" ]; then
  info "LVM Storage Operator:" "enabled"
  cp $templates/openshift/day1/lvm/*.yaml $cluster_workspace/openshift/
else
  warn "LVM Storage Operator:" "disabled"
fi

if [ "true" = "$(yq '.day1.operators.fec' $config_file)" ]; then
  info "Intel SRIOV-FEC Operator:" "enabled"
  cp $templates/openshift/day1/fec/*.yaml $cluster_workspace/openshift/
else
  warn "Intel SRIOV-FEC Operator:" "disabled"
fi

#will be ztp hub
if [ "true" = "$(yq '.day1.ztp_hub' $config_file)" ]; then
  info "ZTP Hub(LVM, RHACM, GitOps, TALM):" "enabled"
  cp $templates/openshift/day1/lvm/*.yaml $cluster_workspace/openshift/
  cp $templates/openshift/day1/gitops/*.yaml $cluster_workspace/openshift/
  cp $templates/openshift/day1/rhacm/*.yaml $cluster_workspace/openshift/
  cp $templates/openshift/day1/talm/*.yaml $cluster_workspace/openshift/
fi

echo

if [ -d $basedir/extra-manifests ]; then
  echo "Copy customized CRs from extra-manifests folder if present"
  echo "$(ls -l $basedir/extra-manifests/)"
  cp $basedir/extra-manifests/*.yaml $cluster_workspace/openshift/ 2>/dev/null
fi

pull_secret=$(yq '.pull_secret' $config_file)
export pull_secret=$(cat $pull_secret)
ssh_key=$(yq '.ssh_key' $config_file)
export ssh_key=$(cat $ssh_key)

jinja2 $templates/agent-config.yaml.j2 $config_file > $cluster_workspace/agent-config.yaml
jinja2 $templates/install-config.yaml.j2 $config_file > $cluster_workspace/install-config.yaml

echo
echo "Generating boot image..."
echo
$basedir/openshift-install --dir $cluster_workspace agent create image

echo ""
echo "------------------------------------------------"
echo "kubeconfig: $cluster_workspace/auth/kubeconfig."
echo "kubeadmin password: $cluster_workspace/auth/kubeadmin-password."
echo "------------------------------------------------"

echo
echo "Next step: Go to your BMC console and boot the node from ISO: $cluster_workspace/agent.x86_64.iso."
echo "You can also run ./sno-install.sh to boot the node from the image automatically if you have a HTTP server serves the image."
echo "Enjoy!"
