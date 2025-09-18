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

# Color codes for better output
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# Enhanced output functions
info(){
  printf "${GREEN}✓${RESET} %-64s ${GREEN}%-10s${RESET}\n" "$@"
}
  
warn(){
  printf "${YELLOW}⚠${RESET} %-64s ${YELLOW}%-10s${RESET}\n" "$@"
}

error(){
  printf "${RED}✗${RESET} %-64s ${RED}%-10s${RESET}\n" "$@"
}

step(){
  printf "\n${BOLD}${BLUE}▶${RESET} ${BOLD}%s${RESET}\n" "$1"
}

header(){
  echo
  printf "${BOLD}${CYAN}%s${RESET}\n" "$1"
  printf "${CYAN}%s${RESET}\n" "$(printf '%.0s=' {1..60})"
}

separator(){
  printf "${CYAN}%s${RESET}\n" "$(printf '%.0s-' {1..60})"
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
cluster_profile=$(yq '.cluster.profile' $config_file_input)
if [ -z "$cluster_profile" ]
then
  cluster_profile="none"
fi



cluster_workspace=$basedir/instances/$cluster_name

if [[ -d "${cluster_workspace}" ]]; then
  error "Workspace already exists" "${cluster_workspace}"
  printf "${RED}Please delete the existing workspace and re-run the script:${RESET}\n"
  printf "${YELLOW}rm -rf ${cluster_workspace}${RESET}\n"
  exit 1
fi

header "SNO Agent-Based Installer - ISO Generation"
step "Setting up workspace"
info "Workspace directory" "${cluster_workspace}"
info "Configuration file" "$config_file"
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

cluster_profile_file=$templates/cluster-profile-$cluster_profile.yaml
if [ ! -f "$cluster_profile_file" ]; then
  cluster_profile_file=$templates/cluster-profile-$cluster_profile-$OCP_Y_VERSION.yaml
  if [ ! -f "$cluster_profile_file" ]; then
    error "Cluster profile file not found" "$cluster_profile"
    printf "${RED}Available profiles:${RESET}\n"
    ls -1 $templates/cluster-profile-*.yaml 2>/dev/null | sed 's/.*cluster-profile-//;s/\.yaml$//' | sed 's/^/  - /'
    exit 1
  fi
fi

config_file="$cluster_workspace/config-resolved.yaml"
config_file_temp=$cluster_workspace/config-resolved.yaml.tmp

if [ $(cat $config_file_input |grep -E 'OCP_Y_RELEASE|OCP_Z_RELEASE' |wc -l) -gt 0 ]; then
  sed "s/OCP_Y_RELEASE/$ocp_y_release/g;s/OCP_Z_RELEASE/$ocp_release_version/g" $config_file_input > $config_file_temp
else
  cp $config_file_input $config_file_temp
fi

yq '. *=load("'$config_file_temp'")' $cluster_profile_file > $config_file
info "Configuration resolved" "$config_file"
info "Will be used by other sno-* scripts" "✓"

is_gzipped(){
  if [ $(file $1 -- |grep -E 'gzip|bzip2|xz' |wc -l) -gt 0 ]; then
    echo "1"
  else
    echo "0"
  fi
}

download_openshift_installer(){
  step "Obtaining OpenShift installer binary"
  # check to see if we can re-use the current binary
  if [[ -x $basedir/openshift-install ]]; then
    if [[ -z $($basedir/openshift-install version |grep -E "^.* $ocp_release_version$") ]]; then
       echo "Ignore existing openshift-install: version does not matching" 
    elif [[ -z $($basedir/openshift-install version |grep -E "^release architecture ${ocp_arch}$") ]]; then
       echo "Ignore existing openshift-install: release architecture does not matching"
    else
    info "Reusing existing openshift-install binary" "✓"
    echo "${GREEN}$($basedir/openshift-install version)${RESET}"
    return
    fi
  fi

  openshift_install_tar_file=openshift-install-client-${client_arch}-target-${ocp_arch}.$ocp_release_version.tar.gz
  openshift_mirror_path=https://mirror.openshift.com/pub/openshift-v4/${ocp_arch}/clients/ocp/${ocp_release_version}

  if [ ! -f $basedir/$openshift_install_tar_file ]; then
    info "Downloading OpenShift installer" "$ocp_release_version"
    info "Client architecture" "$client_arch"
    info "Target architecture" "$ocp_arch"

    status_code=$(curl --connect-timeout 10 -s -o /dev/null -w "%{http_code}" $openshift_mirror_path/)
    if [ $status_code = "200" ]; then
      #try to download the file with the client arch first
      curl -L ${openshift_mirror_path}/openshift-install-linux-${client_arch}.tar.gz -o $basedir/$openshift_install_tar_file
      
      if [[ $(is_gzipped $basedir/$openshift_install_tar_file) -eq 1 ]]; then
        info "Downloaded installer" "openshift-install-linux-${client_arch}.tar.gz"
      else
        rm -f $basedir/$openshift_install_tar_file
        #if not found, try to download the default linux file
        curl -L ${openshift_mirror_path}/openshift-install-linux.tar.gz -o $basedir/$openshift_install_tar_file
        if [[ $(is_gzipped $basedir/$openshift_install_tar_file) -eq 1 ]]; then
          info "Downloaded installer" "openshift-install-linux.tar.gz"
        else
          rm -f $basedir/$openshift_install_tar_file
          error "Download failed" "Could not download installer from ${openshift_mirror_path}"
          exit 1
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

      info "Extracting from release image" "$release_image"
      info "Platform" "${client_arch}"
      oc adm release extract --command-os=linux/${client_arch} --command=openshift-install $release_image --to="$basedir" ${OC_OPTION} || {
        error "Release extraction failed" "Check oc command and connectivity"
        printf "${RED}Failed command:${RESET}\n"
        printf "${YELLOW}oc adm release extract --command-os=linux/${client_arch} --command=openshift-install $release_image --to="$basedir" ${OC_OPTION}${RESET}\n"
        exit 1
      }
    fi
  else
    info "Reusing local installer" "$ocp_release_version"
    info "Client platform" "$client_arch"
    info "Target platform" "$ocp_arch"
    tar zxf $basedir/$openshift_install_tar_file -C $basedir openshift-install
  fi

  if [[ ! -x $basedir/openshift-install ]]; then
    error "Failed to obtain openshift-install binary" "Check connectivity"
    printf "${RED}For disconnected installations:${RESET}\n"
    printf "${YELLOW}Create local_release_info.txt with format: <release>=<image>${RESET}\n"
    exit 1
  fi
  
}

download_openshift_installer

platform_arch=$(yq '.cluster.platform // "intel"' $config_file)

cluster_tunings(){
  cluster_tunings=$(yq '.cluster_tunings' $config_file)
  if [ -z "$cluster_tunings" ]; then
    warn "Cluster tunings" "disabled"
  else
    step "Enabling cluster tunings for OpenShift $ocp_y_release"
    tuning_files=$(ls $templates/day1/cluster-tunings/$cluster_tunings/*.yaml 2>/dev/null | wc -l)
    info "Cluster tuning files found" "$tuning_files files"
    for file in $templates/day1/cluster-tunings/$cluster_tunings/*.yaml; do
      filename=$(basename "$file")
      info "  └─ $filename" "enabled"
    done
    cp $templates/day1/cluster-tunings/$cluster_tunings/*.yaml $cluster_workspace/openshift/
  fi
}

container_storage(){
  if [ "true" = "$(yq '.container_storage.enabled' $config_file)" ]; then
    info "Container storage:" "enabled"
    jinja2 $templates/day1/container-storage-partition/98-var-lib-containers-partitioned.yaml.j2 $config_file > $cluster_workspace/openshift/98-var-lib-containers-partitioned.yaml
  else
    warn "Container storage:" "disabled"
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
    yq ".operators.$key" $config_file| jinja2 $f > $cluster_workspace/openshift/$fname
  done
}

install_operators(){
  step "Configuring OpenShift Operators"
  readarray -t keys < <(yq ".operators|keys" $config_file|yq '.[]')
  
  enabled_count=0
  disabled_count=0
  
  for ((k=0; k<${#keys[@]}; k++)); do
    key="${keys[$k]}"
    desc=$(yq ".operators.$key.desc" $operators/operators.yaml)

    if [[ "true" == $(yq ".operators.$key.enabled" $config_file) ]]; then
      info "$desc" "enabled"
      install_operator $key
      ((enabled_count++))
    else
      warn "$desc" "disabled"
      ((disabled_count++))
    fi
  done
  
  separator
  info "Operators enabled" "$enabled_count"
  info "Operators disabled" "$disabled_count"
  echo
}

config_operators(){
  step "Configuring operator-specific settings"

  readarray -t keys < <(yq ".operators|keys" $config_file|yq '.[]')
  
  for ((k=0; k<${#keys[@]}; k++)); do
    key="${keys[$k]}"
    if [[ $(yq ".operators.$key.enabled" $config_file) == "true" ]]; then
      if [[ $(yq ".operators.$key.provision" $config_file) == "null" ]]; then
        # No provision configuration
        continue
      else
        info "$key operator: enabling provision"
        
        # Handle before scripts
        before_scripts=$(yq ".operators.$key.provision.before[]?" $config_file 2>/dev/null)
        if [[ -z "$before_scripts" ]]; then
          info "  └─ no before scripts"
        else
          info "  └─ executing before scripts"
          while IFS= read -r script; do
            if [[ -n "$script" && "$script" != "null" ]]; then
              script_path="$templates/day1/$key/$script"
              if [[ -f "$script_path" ]]; then
                info "    └─ running $script"
                "$script_path" "$config_file"
              else
                warn "    └─ script not found: $script"
              fi
            fi
          done <<< "$before_scripts"
        fi

        # Handle manifest files
        manifest_files=$(yq ".operators.$key.provision.manifests[]?" $config_file 2>/dev/null)
        if [[ -z "$manifest_files" ]]; then
          info "  └─ using all files from templates/day1/$key/"
          if [[ -d "$templates/day1/$key" ]]; then
            for f in "$templates/day1/$key"/*.yaml "$templates/day1/$key"/*.yaml.j2; do
              if [[ -f "$f" ]]; then
                filename=$(basename "$f")
                if [[ "$f" == *.j2 ]]; then
                  info "    └─ rendering $filename"
                  data_file=$(yq ".operators.$key.provision.data" $config_file)
                  if [[ "$data_file" != "null" ]]; then
                    jinja2 "$f" "$data_file" > "$cluster_workspace/openshift/$(basename "$f" .j2)"
                  else
                    jinja2 "$f" "$config_file" > "$cluster_workspace/openshift/$(basename "$f" .j2)"
                  fi
                else
                  info "    └─ copying $filename"
                  cp "$f" "$cluster_workspace/openshift/"
                fi
              fi
            done
          fi
        else
          info "  └─ using specified manifest files"
          while IFS= read -r manifest; do
            if [[ -n "$manifest" && "$manifest" != "null" ]]; then
              manifest_path="$templates/day1/$key/$manifest"
              if [[ -f "$manifest_path" ]]; then
                filename=$(basename "$manifest")
                if [[ "$manifest" == *.j2 ]]; then
                  info "    └─ rendering $filename"
                  data_file=$(yq ".operators.$key.provision.data" $config_file)
                  if [[ "$data_file" != "null" ]]; then
                    yq ".operators.$key.provision.data" $config_file |jinja2 "$manifest_path"  > "$cluster_workspace/openshift/$(basename "$manifest" .j2)"
                  else
                    jinja2 "$manifest_path" "$config_file" > "$cluster_workspace/openshift/$(basename "$manifest" .j2)"
                  fi
                else
                  info "    └─ copying $filename"
                  cp "$manifest_path" "$cluster_workspace/openshift/"
                fi
              else
                warn "    └─ manifest not found: $manifest"
              fi
            fi
          done <<< "$manifest_files"
        fi
      fi
    fi
  done
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

extra_manifests(){
  extra_manifests=$(yq '.extra_manifests.day1' $config_file)
  if [ "$extra_manifests" == "null" ]; then
    warn "Extra manifests" "not configured"
  else
    step "Processing extra manifest files"
    all_paths_config=$(yq '.extra_manifests.day1|join(" ")' $config_file)
    all_paths=$(eval echo $all_paths_config)

    for d in $all_paths; do
      if [ -d $d ]; then
        readarray -t csr_files < <(find ${d} -type f \( -name "*.yaml" -o -name "*.yaml.j2" \) |sort)
        for ((i=0; i<${#csr_files[@]}; i++)); do
          file="${csr_files[$i]}"
          case "$file" in
            *.yaml)
              filename=$(basename "$file")
              info "  ├─ $filename" "copied"
              cp "$file" "$cluster_workspace"/openshift/ 2>/dev/null
              ;;
	          *.yaml.j2)
              tname=$(basename $file)
              fname=${tname//.j2/}
              info "  ├─ $fname" "rendered"
              jinja2 $file $config_file > "$cluster_workspace"/openshift/$fname
	            ;;
            *)
              warn "  ├─ $(basename $file)" "skipped (unknown type)"
              ;;
          esac
         done
      fi
    done
  fi
}

operator_catalog_sources(){
  step "Configuring operator catalog sources"
  
  if [ "true" = "$(yq '.catalog_sources.create_marketplace_ns' $config_file)" ]; then
    info "Creating marketplace namespace" "enabled"
    cp $templates/day1/catalogsource/09-openshift-marketplace-ns.yaml $cluster_workspace/openshift/
  fi
  
  if [ "true" = "$(yq '.catalog_sources.update_operator_hub' $config_file)" ]; then
    info "Updating OperatorHub configuration" "enabled"
    cp $templates/day1/catalogsource/operatorhub.yaml.j2 $cluster_workspace/openshift/operatorhub.yaml
  fi

  if [ "true" = "$(yq '.catalog_sources.create_default_catalog_sources' $config_file)" ]; then
    if [[ "$(yq '.catalog_sources.defaults' $config_file)" != "null" ]]; then
      info "Creating default catalog sources" "enabled"
      local size=$(yq '.catalog_sources.defaults|length' $config_file)
      for ((k=0; k<$size; k++)); do
        local name=$(yq ".catalog_sources.defaults[$k]" $config_file)
        info "  ├─ $name catalog" "created"
        jinja2 $templates/day1/catalogsource/$name.yaml.j2 > $cluster_workspace/openshift/$name.yaml
      done
    fi
  fi

  if [ "$(yq '.catalog_sources.customs' $config_file)" != "null" ]; then
    local size=$(yq '.catalog_sources.customs|length' $config_file)
    info "Custom catalog sources" "$size configured"
    for ((k=0; k<$size; k++)); do
      local custom_name=$(yq ".catalog_sources.customs[$k].name // \"custom-$k\"" $config_file)
      info "  ├─ $custom_name" "created"
      yq ".catalog_sources.customs[$k]" $config_file |jinja2 $templates/day1/catalogsource/catalogsource.yaml.j2 > $cluster_workspace/openshift/catalogsource-$k.yaml
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

mirror_source(){
  if [ "$(yq '.container_registry.image_source' $config_file)" != "null" ]; then 
    cat $(yq '.container_registry.image_source' $config_file) >> $cluster_workspace/install-config.yaml
  fi

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
cluster_tunings

container_storage

operator_catalog_sources

install_operators
config_operators

extra_manifests

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

mirror_source

cp $cluster_workspace/agent-config.yaml $cluster_workspace/agent-config-backup.yaml
cp $cluster_workspace/install-config.yaml $cluster_workspace/install-config-backup.yaml

step "Generating bootable ISO image"
info "Using OpenShift installer" "$($basedir/openshift-install version | head -1)"
info "Target architecture" "$ocp_arch"
info "Log level" "${ABI_LOG_LEVEL:-info}"
echo
$basedir/openshift-install --dir $cluster_workspace agent --log-level=${ABI_LOG_LEVEL:-"info"} create image

header "Installation Complete - Summary"
info "✅ Bootable ISO generated" "$cluster_workspace/agent.${ocp_arch}.iso"
info "📁 Kubeconfig location" "$cluster_workspace/auth/kubeconfig"
info "🔑 Admin password file" "$cluster_workspace/auth/kubeadmin-password"
info "⚙️  Configuration file" "$config_file"
info "🏗️  OpenShift version" "$ocp_release_version"
info "💻 Target architecture" "$ocp_arch"

separator
printf "${BOLD}${GREEN}Next Steps:${RESET}\n"
printf "${CYAN}Option 1 (Manual):${RESET}\n"
printf "  └─ Boot node from ISO via BMC console:\n"
printf "     ${YELLOW}$cluster_workspace/agent.${ocp_arch}.iso${RESET}\n\n"
printf "${CYAN}Option 2 (Automated):${RESET}\n"
printf "  └─ Run automated installation (requires HTTP server):\n"
printf "     ${YELLOW}./sno-install.sh $config_file${RESET}\n\n"
printf "${BOLD}${GREEN}🎉 ISO generation completed successfully!${RESET}\n"
