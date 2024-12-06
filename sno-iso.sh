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
  info "- $0 sno130.yaml" " equals: $0 sno130.yaml stable-4.14"
  info "- $0 sno130.yaml 4.14.33"
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

config_file_input=$1; shift
ocp_release=$1; shift

if [ -z "$config_file_input" ]
then
  config_file_input=config.yaml
fi

cluster_name=$(yq '.cluster.name' $config_file_input)
cluster_workspace=$basedir/instances/$cluster_name

if [[ -d "${cluster_workspace}" ]]; then
  echo "${cluster_workspace} already exists, please delete the folder ${cluster_workspace} and re-run the script."
  exit -1
fi

echo "Creating workspace: ${cluster_workspace}."
mkdir -p $cluster_workspace
mkdir -p $cluster_workspace/openshift

if [ -z "$ocp_release" ]
then
  ocp_release='stable-4.14'
fi

ocp_release_version=$(curl -s https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${ocp_release}/release.txt | grep 'Version:' | awk -F ' ' '{print $2}')

#if release not available on mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/, probably ec (early candidate) version, or nightly/ci build.
if [ -z $ocp_release_version ]; then
  ocp_release_version=$ocp_release
fi

export ocp_y_release=$(echo $ocp_release_version |cut -d. -f1-2)
export OCP_Y_VERSION=$ocp_y_release
export OCP_Z_VERSION=$ocp_release_version

config_file="$cluster_workspace/config-resolved.yaml"

if [ $(cat $config_file_input |grep -E 'OCP_Y_RELEASE|OCP_Z_RELEASE' |wc -l) -gt 0 ]; then
  sed "s/OCP_Y_RELEASE/$ocp_y_release/g;s/OCP_Z_RELEASE/$ocp_release_version/g" $config_file_input > $config_file
else
  cp $config_file_input $config_file
fi

echo "Will use $config_file as the configuration in other sno-* scripts."

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
    cp $templates/day1/kdump/06-kdump-master.yaml $cluster_workspace/openshift/
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

    #4.14 or 4.15, cgv1 is the default
    if [ "4.14" = $ocp_y_release ] ||  [ "4.15" = $ocp_y_release ]; then
      if [ "false" = "$(yq '.day1.cgv1' $config_file)" ]; then
        warn "enable cgroup v1:" "false"
      else
        info "enable cgroup v1:" "true"
        cp $templates/day1/cgroupv1/*.yaml $cluster_workspace/openshift/
      fi
    else
      #4.16+
      if [ "true" = "$(yq '.day1.cgv1' $config_file)" ]; then
        warn "default cgv2, enable cgroup v1:" "true"
        cp $templates/day1/cgroupv1/*.yaml $cluster_workspace/openshift/
      else
        info "default cgv2, enable cgroup v1:" "false"
      fi
    fi
  fi

  if [ "true" = "$(yq '.day1.container_storage.enabled' $config_file)" ]; then
    info "Container storage partition:" "enabled"
    jinja2 $templates/day1/container-storage-partition/98-var-lib-containers-partitioned.yaml.j2 $config_file > $cluster_workspace/openshift/98-var-lib-containers-partitioned.yaml
  else
    warn "Container storage partition:" "disabled"
  fi

}

install_operator(){
  op_name=$1
  cp $operators/$op_name/*.yaml $cluster_workspace/openshift/ 2>/dev/null

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

config_operators(){
  echo "Configuring operators..."
  #right now only local storage operator
  if [[ "false" == $(yq ".day1.operators.local-storage.enabled" $config_file) ]]; then
    sleep 1
  else
    # enabled
    if [[ $(yq ".day1.operators.local-storage.provision" $config_file) == "null" ]]; then
      sleep 1
    else
      info "local-storage operator: provision storage"
      export CREATE_LVS_FOR_SNO=$(cat $templates/day1/local-storage/create_lvs_for_lso.sh |base64 -w0)
      export DISK=$(yq '.day1.operators.local-storage.provision.disk_by_path' $config_file)
      export LVS=$(yq '.day1.operators.local-storage.provision.lvs|to_entries|map(.value + "x" + .key)|join(" ")' $config_file)
      jinja2 $templates/day1/local-storage/60-create-lvs-mc.yaml.j2 $config_file > $cluster_workspace/openshift/60-create-lvs-mc.yaml
    fi
  fi
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

copy_extra_manifests(){
  extra_manifests=$(yq '.day1.extra_manifests' $config_file)
  if [ "$extra_manifests" == "null" ]; then
    sleep 1
  else
    echo "Process extra-manifest files"
    all_paths_config=$(yq '.day1.extra_manifests|join(" ")' $config_file)
    all_paths=$(eval echo $all_paths_config)

    for d in $all_paths; do
      if [ -d $d ]; then
        readarray -t csr_files < <(find ${d} -type f \( -name "*.yaml" -o -name "*.yaml.j2" \) |sort)
        for ((i=0; i<${#csr_files[@]}; i++)); do
          file="${csr_files[$i]}"
          case "$file" in
            *.yaml)
              info "$file" "copy to $cluster_workspace/openshift/$file"
              cp "$file" "$cluster_workspace"/openshift/ 2>/dev/null
              ;;
	          *.yaml.j2)
              tname=$(basename $file)
              fname=${tname//.j2/}
              info "$file" "render to $cluster_workspace/openshift/$fname"
              jinja2 $file $config_file > "$cluster_workspace"/openshift/$fname
	            ;;
            *)
              warn $file "skipped: unknown type"
              ;;
          esac
         done
      fi
    done
  fi
}

operator_catalog_sources(){
  if [ "4.12" = $ocp_y_release ] || [ "4.13" = $ocp_y_release ] || [ "4.14" = $ocp_y_release ] || [ "4.15" = $ocp_y_release ]; then
    if [[ $(yq '.container_registry' $config_file) != "null" ]]; then
      jinja2 $templates/day1/operatorhub.yaml.j2 $config_file > $cluster_workspace/openshift/operatorhub.yaml
    fi
  else
    #4.16+, disable marketplace operator
    cp $templates/day1/marketplace/09-openshift-marketplace-ns.yaml $cluster_workspace/openshift/

    #create unmanaged catalog sources
    if [[ "$(yq '.container_registry.catalog_sources.defaults' $config_file)" != "null" ]]; then
      #enable the ones in container_registry.catalog_sources.defaults
      local size=$(yq '.container_registry.catalog_sources.defaults|length' $config_file)
      for ((k=0; k<$size; k++)); do
        local name=$(yq ".container_registry.catalog_sources.defaults[$k]" $config_file)
        jinja2 $templates/day1/catalogsource/$name.yaml.j2 > $cluster_workspace/openshift/$name.yaml
      done
    else
      #by default redhat-operators and certified-operators shall be enabled
      jinja2 $templates/day1/catalogsource/redhat-operators.yaml.j2 > $cluster_workspace/openshift/redhat-operators.yaml
      jinja2 $templates/day1/catalogsource/certified-operators.yaml.j2 > $cluster_workspace/openshift/certified-operators.yaml
    fi

  fi

  #all versions
  if [ "$(yq '.container_registry.catalog_sources.customs' $config_file)" != "null" ]; then
    local size=$(yq '.container_registry.catalog_sources.customs|length' $config_file)
    for ((k=0; k<$size; k++)); do
      yq ".container_registry.catalog_sources.customs[$k]" $config_file |jinja2 $templates/day1/catalogsource/catalogsource.yaml.j2 > $cluster_workspace/openshift/catalogsource-$k.yaml
    done
  fi

  #all versions
  if [ "$(yq '.container_registry.icsp' $config_file)" != "null" ]; then
    local size=$(yq '.container_registry.icsp|length' $config_file)
    for ((k=0; k<$size; k++)); do
      local name=$(yq ".container_registry.icsp[$k]" $config_file)
      if [ -f "$name" ]; then
        info "$name" "copy to $cluster_workspace/openshift/"
        cp $name $cluster_workspace/openshift/
      else
        warn "$name" "not a file or not exist"
      fi
    done
  fi

}

echo
echo "Enabling day1 configuration..."
day1_config
echo

echo "Enabling operators..."
operator_catalog_sources
install_operators
config_operators
echo
setup_ztp_hub
copy_extra_manifests


pull_secret_input=$(yq '.pull_secret' $config_file)
pull_secret_path=$(eval echo $pull_secret_input)
export pull_secret=$(cat $pull_secret_path)

ssh_key_input=$(yq '.ssh_key' $config_file)
ssh_key_path=$(eval echo $ssh_key_input)
export ssh_key=$(cat $ssh_key_path)

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
