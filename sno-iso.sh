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
  printf  $(tput setaf 2)"%-56s %-10s"$(tput sgr0)"\n" "$@"
}

warn(){
  printf  $(tput setaf 3)"%-56s %-10s"$(tput sgr0)"\n" "$@"
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
operators=$basedir/operators

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

#if release not available on mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/, probably ec (early candidate) version, or nightly/ci build.
if [ -z $ocp_release_version ]; then
  ocp_release_version=$ocp_release
fi

export ocp_y_release=$(echo $ocp_release_version |cut -d. -f1-2)

echo "You are going to download OpenShift installer $ocp_release: ${ocp_release_version}"

if [ ! -f $basedir/openshift-install-linux.$ocp_release_version.tar.gz ]; then
  status_code=$(curl -s -o /dev/null -w "%{http_code}" https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$ocp_release_version/)
  if [ $status_code = "200" ]; then
    curl -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${ocp_release_version}/openshift-install-linux.tar.gz -o $basedir/openshift-install-linux.$ocp_release_version.tar.gz
    if [[ $? -eq 0 ]]; then
      tar zxf $basedir/openshift-install-linux.$ocp_release_version.tar.gz -C $basedir openshift-install
    else
      rm -f $basedir/openshift-install-linux.$ocp_release_version.tar.gz
      exit -1
    fi
  else
    #fetch from image
    if [[ $ocp_release == *"nightly"* ]] || [[ $ocp_release == *"ci"* ]]; then
      oc adm release extract --command=openshift-install registry.ci.openshift.org/ocp/release:$ocp_release_version --registry-config=$(yq '.pull_secret' $config_file) --to="$basedir"
    else
      oc adm release extract --command=openshift-install quay.io/openshift-release-dev/ocp-release:$ocp_release_version-x86_64 --registry-config=$(yq '.pull_secret' $config_file) --to="$basedir"
    fi
  fi
else
  tar zxf $basedir/openshift-install-linux.$ocp_release_version.tar.gz -C $basedir openshift-install
fi

cluster_name=$(yq '.cluster.name' $config_file)
cluster_workspace=$basedir/instances/$cluster_name

if [[ -d "${cluster_workspace}" ]]; then
  echo "${cluster_workspace} already exists, please delete the folder ${cluster_workspace} and re-run the script."
  exit -1
fi

mkdir -p $cluster_workspace
mkdir -p $cluster_workspace/openshift

day1_config(){
  if [ "false" = "$(yq '.day1.workload_partition' $config_file)" ]; then
    warn "Workload partitioning:" "disabled"
  else
    if [ "4.12" = "$ocp_y_release" ] || [ "4.13" = "$ocp_y_release" ]; then
      info "Workload partitioning:" "enabled"
      export crio_wp=$(jinja2 $templates/day1/workload-partition/crio.conf $config_file |base64 -w0)
      export k8s_wp=$(jinja2 $templates/day1/workload-partition/kubelet.conf $config_file |base64 -w0)
      jinja2 $templates/day1/workload-partition/02-master-workload-partitioning.yaml.j2 $config_file > $cluster_workspace/openshift/02-master-workload-partitioning.yaml
    else
      info "Workload partitioning:" "enabled(through install-config)"
    fi
  fi

  if [ "false" = "$(yq '.day1.boot_accelerate' $config_file)" ]; then
    warn "SNO boot accelerate:" "disabled"
  else
    info "SNO boot accelerate:" "enabled"
    cp $templates/day1/accelerate/*.yaml $cluster_workspace/openshift/

    if [ "4.12" = "$ocp_y_release" ] || [ "4.13" = "$ocp_y_release" ]; then
      cp $templates/day1/accelerate/$ocp_y_release/*.yaml $cluster_workspace/openshift/
    else
      cp $templates/day1/accelerate/4.14-above/*.yaml $cluster_workspace/openshift/
    fi
  fi

  if [ "false" = "$(yq '.day1.kdump.enabled' $config_file)" ]; then
    warn "kdump service:" "disabled"
  else
    if [ "true" = "$(yq '.day1.kdump.secure_boot' $config_file)" ]; then
      info "kdump service(secure boot):" "enabled"
      cp $templates/day1/kdump/06-kdump-master-secureboot.yaml $cluster_workspace/openshift/
    else
      info "kdump service:" "enabled"
      cp $templates/day1/kdump/06-kdump-master.yaml $cluster_workspace/openshift/
    fi
  fi

  if [ "true" = "$(yq '.day1.kdump.blacklist_ice' $config_file)" ]; then
    info "kdump, blacklist_ice(for HPE):" "enabled"
    cp $templates/day1/kdump/05-kdump-config-master.yaml $cluster_workspace/openshift/
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
      cp $templates/day1/crun/*.yaml $cluster_workspace/openshift/
    fi
  fi

  # 4.14+ specific
  if [ "4.12" = $ocp_y_release ] ||  [ "4.13" = $ocp_y_release ]; then
    #do nothing
    sleep 1
  else
    if [ "false" = "$(yq '.day1.sriov_kernel' $config_file)" ]; then
      warn "SR-IOV kernel(intel_iommu):" "disabled"
    else
      info "SR-IOV kernel(intel_iommu):" "enabled"
      cp $templates/day1/sriov-kernel/*.yaml $cluster_workspace/openshift/
    fi

    if [ "false" = "$(yq '.day1.rcu_normal' $config_file)" ]; then
      warn "Set rcu_normal=1 after node reboot:" "disabled"
    else
      info "Set rcu_normal=1 after node reboot:" "enabled"
      cp $templates/day1/rcu-normal/*.yaml $cluster_workspace/openshift/
    fi

    if [ "false" = "$(yq '.day1.sync_time_once' $config_file)" ]; then
      warn "Sync time once after node reboot:" "disabled"
    else
      info "Sync time once after node reboot:" "enabled"
      cp $templates/day1/sync-time-once/*.yaml $cluster_workspace/openshift/
    fi

    if [ "false" = "$(yq '.day1.cgv1' $config_file)" ]; then
      warn "enable cgroup v1:" "false"
    else
      info "enable cgroup v1:" "true"
      cp $templates/day1/cgroupv1/*.yaml $cluster_workspace/openshift/
    fi
  fi

  if [ "true" = "$(yq '.day1.container_storage.enabled' $config_file)" ]; then
    info "Container storage partition:" "enabled"
    jinja2 $templates/day1/container_storage/98-var-lib-containers-partitioned.yaml.j2 $config_file > $cluster_workspace/openshift/98-var-lib-containers-partitioned.yaml
  else
    warn "Container storage partition:" "disabled"
  fi
}

install_operator(){
  op_name=$1
  cp $operators/$op_name/*.yaml $cluster_workspace/openshift/

  #render j2 files
  j2files=$(ls $operators/$op_name/*.j2 2>/dev/null)
  for f in $j2files; do
    tname=$(basename $f)
    fname=${tname//.j2/}
    yq ".day1.operators.$key" $config_file| jinja2 $f > $cluster_workspace/openshift/$fname
  done  
}

install_operators(){
  readarray -t keys < <(yq ".operators|keys" $operators/operators.yaml|yq '.[]')
  for ((k=0; k<${#keys[@]}; k++)); do
    key="${keys[$k]}"
    desc=$(yq ".operators.$key.desc" $operators/operators.yaml)
    enabled_by_default=$(yq ".operators.$key.enabled" $operators/operators.yaml)

    #enabled by default
    if [[ "true" == "$enabled_by_default" ]]; then
      #disable by intention
      if [[ "false" == $(yq ".day1.operators.$key.enabled" $config_file) ]]; then
        warn "$desc" "disabled"
      else
        info "$desc" "enabled"
        install_operator $key
      fi
    #disabled by default
    else
      #enable by intention
      if [[ "true" == $(yq ".day1.operators.$key.enabled" $config_file) ]]; then
        info "$desc" "enabled"
        install_operator $key
      else
        warn "$desc" "disabled"
      fi
    fi
  done
  echo
}

setup_ztp_hub(){
  #will be ztp hub
  if [ "true" = "$(yq '.day1.ztp_hub' $config_file)" ]; then
    info "ZTP Hub(LVM, RHACM, GitOps, TALM):" "enabled"
    cp $operators/lvm/*.yaml $cluster_workspace/openshift/
    cp $operators/rhacm/*.yaml $cluster_workspace/openshift/
    jinja2 $operators/lvm/StorageLVMSubscription.yaml.j2 > $cluster_workspace/openshift/StorageLVMSubscription.yaml
    jinja2 $operators/rhacm/AdvancedClusterManagementSubscription.yaml.j2 > $cluster_workspace/openshift/AdvancedClusterManagementSubscription.yaml
    jinja2 $operators/talm/TopologyAwareLifeCycleManagerSubscription.yaml.j2 > $cluster_workspace/openshift/TopologyAwareLifeCycleManagerSubscription.yaml
    jinja2 $operators/gitops/GitopsSubscription.yaml.j2 > $cluster_workspace/openshift/GitopsSubscription.yaml

    echo
  fi
}

apply_extra_manifests(){
  extra_manifests=$(yq '.extra_manifests' $config_file)
  if [ -n "$extra_manifests" ]; then
    if [ -d "$extra_manifests" ]; then
      echo "Copy customized CRs from extra-manifests folder if present"
      ls -l "$extra_manifests"
      cp "$extra_manifests"/*.yaml "$cluster_workspace"/openshift/ 2>/dev/null
      echo
    fi
  fi
}

operator_catalog_sources(){
  if [[ $(yq '.container_registry' $config_file) != "null" ]]; then
    if [ "true" = "$(yq '.container_registry.prega' $config_file)" ]; then
      info "PreGA catalog sources" "enabled"
      cp $templates/day1/prega/*.yaml $cluster_workspace/openshift/
    fi

    jinja2 $templates/day1/operatorhub.yaml.j2 $config_file > $cluster_workspace/openshift/operatorhub.yaml
  fi
}

echo
echo "Enabling day1 configuration..."
day1_config
echo

echo "Enabling operators..."
operator_catalog_sources
install_operators
echo

setup_ztp_hub
apply_extra_manifests


pull_secret=$(yq '.pull_secret' $config_file)
export pull_secret=$(cat $pull_secret)
ssh_key=$(yq '.ssh_key' $config_file)
export ssh_key=$(cat $ssh_key)

bundle_file=$(yq '.additional_trust_bundle' $config_file)
if [[ "null" != "$bundle_file" ]]; then
  export additional_trust_bundle=$(cat $bundle_file)
fi

jinja2 $templates/agent-config.yaml.j2 $config_file > $cluster_workspace/agent-config.yaml
jinja2 $templates/install-config.yaml.j2 $config_file > $cluster_workspace/install-config.yaml

mirror_source=$(yq '.container_registry.image_source' $config_file)
if [[ "null" != "$mirror_source" ]]; then
  cat $mirror_source >> $cluster_workspace/install-config.yaml
fi

cp $cluster_workspace/agent-config.yaml $cluster_workspace/agent-config-backup.yaml
cp $cluster_workspace/install-config.yaml $cluster_workspace/install-config-backup.yaml

echo
echo "Generating boot image..."
echo
$basedir/openshift-install --dir $cluster_workspace agent --log-level=info create image

echo ""
echo "------------------------------------------------"
echo "kubeconfig: $cluster_workspace/auth/kubeconfig."
echo "kubeadmin password: $cluster_workspace/auth/kubeadmin-password."
echo "------------------------------------------------"

echo
echo "Next step: Go to your BMC console and boot the node from ISO: $cluster_workspace/agent.x86_64.iso."
echo "You can also run ./sno-install.sh to boot the node from the image automatically if you have a HTTP server serves the image."
echo "Enjoy!"
