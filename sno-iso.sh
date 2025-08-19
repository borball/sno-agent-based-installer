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
  ocp_release='stable-4.18'
fi

fetch_archs(){
  client_arch=$(uname -m)
  if [ "$client_arch" == "aarch64" ]; then
    client_arch="arm64"
  fi
  if [ "$client_arch" == "x86_64" ]; then
    client_arch="amd64"
  fi

  ocp_arch=$(yq '.cluster.platform' $config_file_input)
  if [ "$ocp_arch" == "arm" ]; then
    ocp_arch="arm64"
  fi
  if [ "$ocp_arch" == "amd" ] || [ "$ocp_arch" == "intel" ]; then
    ocp_arch="amd64"
  fi

  if [ -z "$ocp_arch" ] || [ "$ocp_arch" == "null" ]; then
    ocp_arch=$client_arch
  fi
}

fetch_archs

case ${ocp_release} in
  fast-* | lastest-* | stable-* | candidate-*)
    ocp_release_version=$(curl --connect-timeout 10 -s https://mirror.openshift.com/pub/openshift-v4/${ocp_arch}/clients/ocp/${ocp_release}/release.txt | grep 'Version:' | awk -F ' ' '{print $2}')
    ;;
esac

#if release not available on mirror.openshift.com/pub/openshift-v4/${ocp_arch}/clients/ocp/, probably ec (early candidate) version, or nightly/ci build.
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

is_gzipped(){
  if [ $(file $1 -- |grep -E 'gzip|bzip2|xz' |wc -l) -gt 0 ]; then
    echo "1"
  else
    echo "0"
  fi
}

echo "Will use $config_file as the configuration in other sno-* scripts."

download_openshift_installer(){

  # check to see if we can re-use the current binary
  if [[ -x $basedir/openshift-install ]]; then
    if [[ -z $($basedir/openshift-install version |grep -E "^.* $ocp_release_version$") ]]; then
       echo "Ignore existing openshift-install: version does not matching" 
    elif [[ -z $($basedir/openshift-install version |grep -E "^release architecture ${ocp_arch}$") ]]; then
       echo "Ignore existing openshift-install: release architecture does not matching"
    else
      echo "Reusing existing openshift-install binary"
      $basedir/openshift-install version
      return
    fi
  fi

  openshift_install_tar_file=openshift-install-client-${client_arch}-target-${ocp_arch}.$ocp_release_version.tar.gz
  openshift_mirror_path=https://mirror.openshift.com/pub/openshift-v4/${ocp_arch}/clients/ocp/${ocp_release_version}

  if [ ! -f $basedir/$openshift_install_tar_file ]; then
    echo "You are going to download OpenShift installer $ocp_release: ${ocp_release_version} on ${client_arch} platform, target cluster platform is ${ocp_arch}"

    status_code=$(curl --connect-timeout 10 -s -o /dev/null -w "%{http_code}" $openshift_mirror_path/)
    if [ $status_code = "200" ]; then
      #try to download the file with the client arch first
      curl -L ${openshift_mirror_path}/openshift-install-linux-${client_arch}.tar.gz -o $basedir/$openshift_install_tar_file
      
      if [[ $(is_gzipped $basedir/$openshift_install_tar_file) -eq 1 ]]; then
        echo "Downloaded openshift-install tar file from ${openshift_mirror_path}/openshift-install-linux-${client_arch}.tar.gz "
      else
        rm -f $basedir/$openshift_install_tar_file
        #if not found, try to download the default linux file
        curl -L ${openshift_mirror_path}/openshift-install-linux.tar.gz -o $basedir/$openshift_install_tar_file
        if [[ $(is_gzipped $basedir/$openshift_install_tar_file) -eq 1 ]]; then
          echo "Downloaded openshift-install tar file from ${openshift_mirror_path}/openshift-install-linux.tar.gz "
        else
          rm -f $basedir/$openshift_install_tar_file
          echo "Error: download failed: could not download openshift-install-linux-${client_arch}.tar.gz or openshift-install-linux.tar.gz from ${openshift_mirror_path}"
          exit -1
        fi
      fi

      tar zxf $basedir/$openshift_install_tar_file -C $basedir openshift-install
    else
      #fetch from image
      OC_OPTION="--registry-config=$(yq '.pull_secret' $config_file)"
      local_mirror=$(yq '.container_registry.image_source' $config_file)
      if [[ "${local_mirror}" != "null" ]]; then
        idms_file=${cluster_workspace}/idms-release-0.yaml
        echo "Using local mirror ${local_mirror}"
        cat << EOF > ${idms_file}
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: idms-release-0
spec:
  imageDigestMirrors:
EOF
        
        yq '.imageContentSources' ${local_mirror} |pr -T -o 4 >> ${idms_file}
        OC_OPTION+=" --idms-file=${idms_file}"
      fi
      
      local_ca_file=$(yq '.additional_trust_bundle' $config_file)
      if [[ "${local_ca_file}" != "null" ]]; then
        echo "Using CA ${local_ca_file}"
        OC_OPTION+=" --certificate-authority=${local_ca_file}"
      fi

      if [[ -f "$basedir/local_release_info.txt" ]]; then
        echo "Using local release info: $basedir/local_release_info.txt"
        release_image=$(grep "^$ocp_release=" $basedir/local_release_info.txt|cut -f 2 -d =)
        echo "Using local release image: $release_image"
      fi

      if [[ -z "$release_image" ]]; then
        if [[ $ocp_release == *"nightly"* ]] || [[ $ocp_release == *"ci"* ]]; then
          echo "Using nightly release image or ci release image: registry.ci.openshift.org/ocp/release:$ocp_release_version"
          release_image="registry.ci.openshift.org/ocp/release:$ocp_release_version"
        else
          # ec release image is only available for x86_64
          if [[ $ocp_release == *"ec"* ]]; then
            echo "Using ec release image: quay.io/openshift-release-dev/ocp-release:$ocp_release_version-x86_64"
            release_image="quay.io/openshift-release-dev/ocp-release:$ocp_release_version-x86_64"
          else
            echo "Using stable release image: quay.io/openshift-release-dev/ocp-release:$ocp_release_version-${client_arch}"
            release_image="quay.io/openshift-release-dev/ocp-release:$ocp_release_version-${client_arch}"
          fi
        fi
      fi

      echo "Extracting openshift-install from release image: $release_image on ${client_arch} platform"
      oc adm release extract --command-os=linux/${client_arch} --command=openshift-install $release_image --to="$basedir" ${OC_OPTION} || {
        echo "Error: adm release extract failed: oc adm release extract --command-os=linux/${client_arch} --command=openshift-install $release_image --to="$basedir" ${OC_OPTION} "
        exit 1
      }
    fi
  else

    echo "You are going to reuse the local OpenShift installer $ocp_release: ${ocp_release_version} on ${client_arch} platform, target cluster platform is ${ocp_arch}"
    tar zxf $basedir/$openshift_install_tar_file -C $basedir openshift-install
  fi

  if [[ ! -x $basedir/openshift-install ]]; then
    echo "Failed to obtain openshift-install, for disconnected install, populate local_release_info.txt with missing"
    echo "<release>=<image>"
    exit -1
  fi
  
}

download_openshift_installer

platform_arch=$(yq '.cluster.platform // "intel"' $config_file)

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
    warn "Container runtime crun(4.12):" "disabled"
  else
    if [ "4.13" = $ocp_y_release ] || [ "4.14" = $ocp_y_release ] || [ "4.15" = $ocp_y_release ] || [ "4.16" = $ocp_y_release ] || [ "4.17" = $ocp_y_release ]; then
      #4.13+ by default enabled.
      if [ "false" = "$(yq '.day1.crun' $config_file)" ]; then
        warn "Container runtime crun(4.13-4.17):" "disabled"
      else
        info "Container runtime crun(4.13-4.17):" "enabled"
        cp $templates/day1/crun/*.yaml $cluster_workspace/openshift/
      fi
    else
      info "Container runtime crun(4.18+):" "default"
    fi
  fi

  # 4.14+ specific
  if [ "4.12" = $ocp_y_release ] ||  [ "4.13" = $ocp_y_release ]; then
    #do nothing
    sleep 1
  else
    if [ "false" = "$(yq '.day1.sriov_kernel' $config_file)" ]; then
      warn "SR-IOV kernel(${platform_arch} iommu):" "disabled"
    else
      info "SR-IOV kernel(${platform_arch} iommu):" "enabled"
      copy_platform_config $templates/day1/sriov-kernel/ $cluster_workspace/openshift/
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
  #local storage operator
  if [[ "false" == $(yq ".day1.operators.local-storage.enabled" $config_file) ]]; then
    sleep 1
  else
    # enabled
    if [[ $(yq ".day1.operators.local-storage.provision" $config_file) == "null" ]]; then
      sleep 1
    else
      # maintain backward compatibility by checking for "provision.lvs"
      if [[ $(yq '.day1.operators.local-storage.provision.lvs // "null"' $config_file) == "null" ]]; then
         # using new configuration
         prov_type=$(yq '.day1.operators.local-storage.provision.type // "partition"' $config_file)
         partitions_key="partitions"
      else
         # maintain backward compatibility with old format
	 warn "local-storage operator" "using deprecated provision.lvs property"
         prov_type="lvs"
         partitions_key="lvs"
      fi
      info "local-storage operator: provision ${prov_type}"
      if [[ "${prov_type}" == "partition" ]]; then
        jinja2 $templates/day1/local-storage/60-prepare-lso-partition-mc.yaml.j2 $config_file > $cluster_workspace/openshift/60-prepare-lso-partition-mc.yaml
      else
        export CREATE_LVS_FOR_SNO=$(cat $templates/day1/local-storage/create_lvs_for_lso.sh |base64 -w0)
        export DISK=$(yq '.day1.operators.local-storage.provision.disk_by_path' $config_file)
        export LVS=$(yq ".day1.operators.local-storage.provision.${partitions_key}|to_entries|map(.value + \"x\" + .key)|join(\" \")" $config_file)
        jinja2 $templates/day1/local-storage/60-create-lvs-mc.yaml.j2 $config_file > $cluster_workspace/openshift/60-create-lvs-mc.yaml
      fi
    fi
  fi
  #lvms
  if [[ "false" == $(yq ".day1.operators.lvm.enabled" $config_file) ]]; then
    sleep 1
  else
    # enabled
    if [[ $(yq ".day1.operators.lvm.provision" $config_file) == "null" ]]; then
      sleep 1
    else
      info "lvm operator: provision storage"
      jinja2 $templates/day1/lvm/98-prepare-lvm-disk-mc.yaml.j2 $config_file > $cluster_workspace/openshift/98-prepare-lvm-disk-mc.yaml
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

# copy platform related configuration from source destination
#   will copy file fits following patterns
#     <file_name>.yaml
#     <file_name>.<arch>.yaml
copy_platform_config(){
  local _src=$1
  local _dest=$2

  while read -r _file; do
    local _filename=$(basename $_file)
    if [[ $(echo "$_filename"|cut -f 2 -d .) == "${platform_arch}" ]] || [[ -z $(echo "$_filename"|cut -f 3 -d .) ]]; then
      info "- $_filename" "added"
      cp $_file ${_dest}
    fi
  done < <(find ${_src} -type f -name '*.yaml')
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
$basedir/openshift-install --dir $cluster_workspace agent --log-level=${ABI_LOG_LEVEL:-"info"} create image

echo ""
echo "------------------------------------------------"
echo "kubeconfig: $cluster_workspace/auth/kubeconfig."
echo "kubeadmin password: $cluster_workspace/auth/kubeadmin-password."
echo "------------------------------------------------"

echo
echo "Next step: Go to your BMC console and boot the node from ISO: $cluster_workspace/agent.${ocp_arch}.iso."
echo "You can also run ./sno-install.sh to boot the node from the image automatically if you have a HTTP server serves the image."
echo "Enjoy!"
