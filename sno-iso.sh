#!/bin/bash
#
# Helper script to generate bootable ISO with OpenShift agent based installer
# usage: ./sno-iso.sh -h
#

if ! type "yq" > /dev/null; then
  echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
  exit 1
fi

if ! type "jinja2" > /dev/null; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install --user jinja2-cli
  pip3 install --user jinja2-cli[yaml]
fi

if ! type "oc" > /dev/null; then
  echo "Cannot find oc in the path, please install oc on the node first. ref: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/"
  exit 1
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
  local msg1="$1"
  local msg2="$2"
  # Calculate display length accounting for multi-byte characters
  local len=${#msg1}
  local padding=$((80 - len))
  if [ $padding -lt 0 ]; then padding=1; fi
  printf "${GREEN}✓${RESET} %s%*s${GREEN}%s${RESET}\n" "$msg1" "$padding" "" "$msg2"
}
  
warn(){
  local msg1="$1"
  local msg2="$2"
  local len=${#msg1}
  local padding=$((80 - len))
  if [ $padding -lt 0 ]; then padding=1; fi
  printf "${YELLOW}⚠${RESET} %s%*s${YELLOW}%s${RESET}\n" "$msg1" "$padding" "" "$msg2"
}

error(){
  local msg1="$1"
  local msg2="$2"
  local len=${#msg1}
  local padding=$((80 - len))
  if [ $padding -lt 0 ]; then padding=1; fi
  printf "${RED}✗${RESET} %s%*s${RED}%s${RESET}\n" "$msg1" "$padding" "" "$msg2"
}

step(){
  printf "\n${BOLD}${BLUE}▶${RESET} ${BOLD}%s${RESET}\n" "$1"
}

debug(){
  if [[ "${DEBUG:-false}" == "true" ]]; then
    printf "${MAGENTA}[DEBUG]${RESET} %s\n" "$1"
  fi
}

header(){
  echo
  printf "${BOLD}${CYAN}%s${RESET}\n" "$1"
  printf "${CYAN}%s${RESET}\n" "$(printf '%.0s=' {1..60})"
}

separator(){
  printf "${CYAN}%s${RESET}\n" "$(printf '%.0s-' {1..60})"
}

short_path(){
  echo "$*" | sed -e "s;${basedir};\${basedir};g" -e "s;${HOME};\${HOME};g"
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
info "Base directory (basedir)" "${basedir}"
info "Workspace directory" "${cluster_workspace}"
info "Configuration file" "$config_file_input"
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
  if [ -z "$ocp_arch" ] || [ "$ocp_arch" == "null" ]; then
    ocp_arch=$client_arch
  fi

  if [ "$ocp_arch" == "arm" ]; then
    ocp_arch="arm64"
  elif [ "$ocp_arch" == "amd" ] || [ "$ocp_arch" == "intel" ]; then
    ocp_arch="amd64"
  fi

  if [ "$ocp_arch" == "arm64" ]; then
     release_arch="aarch64"
  elif [ "$ocp_arch" == "amd64" ]; then
    release_arch="x86_64"
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
cluster_profile_file_temp=$cluster_workspace/cluster-profile-resolved.yaml.tmp

if [ $(cat $config_file_input |grep -E 'OCP_Y_RELEASE|OCP_Z_RELEASE|KUBECONFIG' |wc -l) -gt 0 ]; then
  sed "s/OCP_Y_RELEASE/$ocp_y_release/g;s/OCP_Z_RELEASE/$ocp_release_version/g;s/KUBECONFIG/${cluster_workspace}\/auth\/kubeconfig/g" $config_file_input| envsubst > $config_file_temp
else
  cat $config_file_input| envsubst > $config_file_temp
fi

if [ $(cat $cluster_profile_file |grep -E 'OCP_Y_RELEASE|OCP_Z_RELEASE|KUBECONFIG' |wc -l) -gt 0 ]; then
  sed "s/OCP_Y_RELEASE/$ocp_y_release/g;s/OCP_Z_RELEASE/$ocp_release_version/g;s/KUBECONFIG/${cluster_workspace}\/auth\/kubeconfig/g" $cluster_profile_file | envsubst> $cluster_profile_file_temp
else
  cat $cluster_profile_file | envsubst > $cluster_profile_file_temp
fi

yq '. *=load("'$config_file_temp'")' $cluster_profile_file_temp > $config_file
info "Configuration resolved" "$config_file"
info "" "Will be used by other sno-* scripts"

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
	info "- Local mirror" "$(short_path ${local_mirror})"
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

        local_ca_file=$(yq '.additional_trust_bundle' $config_file)
        if [[ "${local_ca_file}" != "null" ]]; then
          info "- Trust Bundle" "$(short_path ${local_ca_file})"
          OC_OPTION+=" --certificate-authority=${local_ca_file}"
        fi
      fi
      
      if [[ -f "$basedir/local_release_info.txt" ]]; then
        info  "- Local release info" "$(short_path $basedir/local_release_info.txt)"
        release_image=$(grep "^$ocp_release=" $basedir/local_release_info.txt|cut -f 2 -d =)
        info "- Local release image" "$release_image"
      fi

      if [[ -z "$release_image" ]]; then
        if [[ $ocp_release == *"nightly"* ]] || [[ $ocp_release == *"ci"* ]]; then
          #echo "Using nightly release image or ci release image: registry.ci.openshift.org/ocp/release:$ocp_release_version"
          release_image_base="registry.ci.openshift.org/ocp/release"
          release_image_tag="$ocp_release_version"
        else
          release_image_base="quay.io/openshift-release-dev/ocp-release"
          # ec release image is only available for x86_64
          if [[ $ocp_release == *"ec"* ]]; then
            #echo "Using ec release image: quay.io/openshift-release-dev/ocp-release:$ocp_release_version-x86_64"
            release_image_tag="$ocp_release_version-x86_64"
          else
            #echo "Using stable release image: quay.io/openshift-release-dev/ocp-release:$ocp_release_version-${release_arch}"
            release_image_tag="$ocp_release_version-${release_arch}"
          fi
        fi
        mirror_source=$(yq '.container_registry.image_source' $config_file)
        if [[ "null" != "$mirror_source" ]]; then
          mirror_image_base=$(yq ".imageContentSources|filter(.source == \"${release_image_base}\")|.[].mirrors[0]" $mirror_source)
          if [[ ! -z "${mirror_image_base}" ]]; then
            release_image_base=$mirror_image_base
          fi
        fi
        release_image="$release_image_base:$release_image_tag"
        info "Release Image" "$release_image"
      fi

      info "- Extracting from release image" "$release_image"
      info "- Platform" "${client_arch}"
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
  cluster_tunings_version=$(yq '.cluster_tunings.version' $config_file)
  if [[ -z "$cluster_tunings_version" || "$cluster_tunings_version" == "null" ]] || [[ "$cluster_tunings_version" == "none" ]]; then
    warn "Cluster tunings" "disabled"
  else
    if [[ -d "$templates/day1/cluster-tunings/$cluster_tunings_version" ]]; then
      step "Enabling cluster tunings $cluster_tunings_version"
      
      # Count total available files
      tuning_files=$(ls $templates/day1/cluster-tunings/$cluster_tunings_version/*.yaml 2>/dev/null | wc -l)
      info "Cluster tuning files found" "$tuning_files"
      
      # Copy all files first
      cp $templates/day1/cluster-tunings/$cluster_tunings_version/*.yaml $cluster_workspace/openshift/

      # Process exclusions and show excluded files
      exclude_patterns=$(yq '.cluster_tunings.excludes[]' $config_file 2>/dev/null)
      excluded_count=0
      if [[ -n "$exclude_patterns" && "$exclude_patterns" != "null" ]]; then
        for pattern in $exclude_patterns; do
          exclude_files=$(ls $templates/day1/cluster-tunings/$cluster_tunings_version/*.yaml | grep -E "$pattern")
          for file in $exclude_files; do
            excluded_filename=$(basename "$file")
            rm -f $cluster_workspace/openshift/$excluded_filename
            warn "  ├─ $excluded_filename" "excluded"
            ((excluded_count++))
          done
        done
      fi

      # Show enabled files with proper tree formatting
      enabled_count=0
      for file in $cluster_workspace/openshift/*.yaml; do
        if [[ -f "$file" ]]; then
          enabled_filename=$(basename "$file")
          ((enabled_count++))
          local prefix="  ├─"
          # Use └─ for the last enabled file
          if [[ $enabled_count -eq $((tuning_files - excluded_count)) ]]; then
            prefix="  └─"
          fi
          info "${prefix} $enabled_filename" "enabled"
        fi
      done
      
      # Summary information
      if [[ $excluded_count -gt 0 ]]; then
        warn "Total excluded tuning files" "$excluded_count"
      fi

      info "Total cluster tuning files" "$enabled_count"
      
    else
      warn "Cluster tunings" "version $cluster_tunings_version not found"
      return 1
    fi
  fi

}

container_storage(){
  step "Configuring container storage"
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
    (yq ".operators.$key" $config_file; yq '.catalog_sources // ""' $config_file) | jinja2 $f > $cluster_workspace/openshift/$fname
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
      # if day1 files under templates/day1/$key exists, then apply them
      if [[ -d "$templates/day1/$key" ]]; then 
        # if $templates/day1/$key has any yaml or yaml.j2 file, then apply them
        if [[ -d "$templates/day1/$key" && -n "$(ls -A $templates/day1/$key/*.yaml $templates/day1/$key/*.yaml.j2 2>/dev/null)" ]]; then
          manifest_folders="$templates/day1/$key"
        else
          manifest_folders=""
        fi
      
        # if .operators.$key contains day1, then use it to override manifest_folders
        if [[ $(yq ".operators.$key.day1" $config_file) != "null" ]]; then
          profile_names=$(yq ".operators.$key.day1[].profile" $config_file)
          for profile_name in $profile_names; do
            manifest_folders="$manifest_folders $templates/day1/$key/$profile_name"
          done
        else
          if [[ -d "$templates/day1/$key/default" ]]; then
            manifest_folders="$manifest_folders $templates/day1/$key/default"
          fi
        fi

        if [[ -z "$manifest_folders" ]]; then
          continue
        fi

        info "$key operator: enabling day1"

        info "  └─ manifest_folders" "$(short_path $manifest_folders) to be applied"
        for manifest_folder in $manifest_folders; do
          info "    └─ applying" "$(short_path $manifest_folder)"
          if [[ -d "$manifest_folder" ]]; then
            # execute *.sh files in the manifest_folder
            for f in "$manifest_folder"/*.sh; do
              if [[ -f "$f" ]]; then
                info "    └─ executing $(short_path $f)"
                "$f" "$config_file"
              fi
            done
            # copy *.yaml files in the manifest_folder to $cluster_workspace/openshift/
            for f in "$manifest_folder"/*.yaml; do
              if [[ -f "$f" ]]; then
                info "    └─ applying" "$(short_path $f)"
                cp "$f" "$cluster_workspace/openshift/"
              fi
            done
            # apply *.yaml.j2 files in the manifest_folder
            for f in "$manifest_folder"/*.yaml.j2; do
              if [[ -f "$f" ]]; then
                info "    └─ applying" "$(short_path $f)"
                # if data file exists, then render it
                data_file=$(yq ".operators.$key.data" $config_file)
                if [[ "$data_file" != "null" ]]; then
                  yq ".operators.$key.data" $config_file |jinja2 "$f" > "$cluster_workspace/openshift/$(basename "$f" .j2)"
                else
                  jinja2 "$f" "$config_file" > "$cluster_workspace/openshift/$(basename "$f" .j2)"
                fi
              fi
            done
          else
            warn "    └─ $manifest_folder" "not found"
            continue
          fi
        done
      fi
    fi
  done

  separator
  echo
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
  step "Processing extra manifest files"
  extra_manifests=$(yq '.extra_manifests.day1' $config_file)
  if [ "$extra_manifests" == "null" ]; then
    warn "Extra manifests" "not configured"
  else
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
    jinja2 $templates/day1/catalogsource/operatorhub.yaml.j2 $config_file > $cluster_workspace/openshift/operatorhub.yaml
  fi

  if [ "true" = "$(yq '.catalog_sources.create_default_catalog_sources' $config_file)" ]; then
    if [[ "$(yq '.catalog_sources.defaults' $config_file)" != "null" ]]; then
      info "Creating default catalog sources" "enabled"
      local size=$(yq '.catalog_sources.defaults|length' $config_file)
      for ((k=1; k<=$size; k++)); do
        local name=$(yq ".catalog_sources.defaults[$((k-1))]" $config_file)
        local lead="  ├─"
        if [[ $k -ge $size ]]; then
           lead="  └─"
        fi
        info "${lead} $name catalog" "created"
        jinja2 $templates/day1/catalogsource/$name.yaml.j2 > $cluster_workspace/openshift/$name.yaml
      done
    fi
  fi

  if [ "$(yq '.catalog_sources.customs' $config_file)" != "null" ]; then
    local size=$(yq '.catalog_sources.customs|length' $config_file)
    info "Custom catalog sources" "$size configured"
    for ((k=1; k<=$size; k++)); do
      local custom_name=$(yq ".catalog_sources.customs[$((k-1))].name // \"custom-$k\"" $config_file)
      local provide=$(yq ".catalog_sources.customs[$((k-1))].provide // \"$custom_name\"" $config_file)
      local lead="  ├─"
      if [[ $k -ge $size ]]; then
         lead="  └─"
      fi
      info "${lead} $custom_name($provide)" "created"
      yq ".catalog_sources.customs[$((k-1))]" $config_file |jinja2 $templates/day1/catalogsource/catalogsource.yaml.j2 > $cluster_workspace/openshift/catalogsource-$k.yaml
    done
  fi

}

mirror_source(){
  if [ "$(yq '.container_registry.image_source' $config_file)" != "null" ]; then 
    step "Configuring mirror source"
    cat $(yq '.container_registry.image_source' $config_file) >> $cluster_workspace/install-config.yaml
  fi

  if [ "$(yq '.container_registry.icsp' $config_file)" != "null" ]; then
    step "Configuring ICSP"
    local size=$(yq '.container_registry.icsp|length' $config_file)
    for ((k=1; k<=$size; k++)); do
      local name=$(yq ".container_registry.icsp[$((k-1))]" $config_file)
      local lead="  ├─"
      if [[ $k -ge $size ]]; then
         lead="  └─"
      fi
      if [ "${name:0:1}" = "/" ]; then
        if [ -f "$name"  ]; then
          info "${lead} $(short_path $name)" "copy to $(short_path $cluster_workspace/openshift/)"
          cp $name $cluster_workspace/openshift/
        fi
      elif [ -f "$basedir/$name" ]; then
        info "${lead} $(short_path $name)" "copy to $(short_path $cluster_workspace/openshift/)"
        cp $basedir/$name $cluster_workspace/openshift/
      else
        warn "${lead} $name" "not a file or not exist"
      fi
    done
  fi
}

render_install_configs(){
  step "Rendering install-config.yaml and agent-config.yaml"
  pull_secret_input=$(yq '.pull_secret' $config_file)
  pull_secret_path=$(eval echo $pull_secret_input)
  if [[ -z "$pull_secret_path" ]] || [[ ! -f "$pull_secret_path" ]]; then
    error "Pull secret not found" "$(short_path $pull_secret_path)"
    exit 1
  fi

  export pull_secret=$(cat $pull_secret_path)

  ssh_key_input=$(yq '.ssh_key' $config_file)
  ssh_key_path=$(eval echo $ssh_key_input)
  if [[ -z "$ssh_key_path" ]] || [[ ! -f "$ssh_key_path" ]]; then
    error "SSH key not found" "$(short_path $ssh_key_path)"
    exit 1
  fi
  export ssh_key=$(cat $ssh_key_path)

  bundle_file=$(yq '.additional_trust_bundle' $config_file)
  if [[ "null" != "$bundle_file" ]]; then
    if [[ -z "$bundle_file" ]] || [[ ! -f "$bundle_file" ]]; then
      error "Additional trust bundle not found" "$(short_path $bundle_file)"
      exit 1
    fi
    export additional_trust_bundle=$(cat $bundle_file)
  fi

  jinja2 $templates/agent-config.yaml.j2 $config_file > $cluster_workspace/agent-config.yaml
  jinja2 $templates/install-config.yaml.j2 $config_file > $cluster_workspace/install-config.yaml
}

backup_install_configs(){
  step "Back-up installer configuratino files"
  cp $cluster_workspace/agent-config.yaml $cluster_workspace/agent-config-backup.yaml
  info "File install-config.yaml" "saved as $(short_path $cluster_workspace/agent-config-backup.yaml)"
  cp $cluster_workspace/install-config.yaml $cluster_workspace/install-config-backup.yaml
  info "File agent-config.yaml" "saved as $(short_path $cluster_workspace/install-config-backup.yaml)"
}

render_install_configs
cluster_tunings
container_storage
operator_catalog_sources
mirror_source
install_operators
config_operators
extra_manifests
backup_install_configs


step "Generating bootable ISO image"
info "Using OpenShift installer" "$(short_path $($basedir/openshift-install version | head -1))"
info "Target architecture" "$ocp_arch"
info "Log level" "${ABI_LOG_LEVEL:-info}"
echo
$basedir/openshift-install --dir $cluster_workspace agent --log-level=${ABI_LOG_LEVEL:-"info"} create image

header "Complete - Summary"

info "Bootable ISO generated" "$(ls $cluster_workspace/agent.*.iso)"
info "Kubeconfig location" "$cluster_workspace/auth/kubeconfig"
info "Admin password file" "$cluster_workspace/auth/kubeadmin-password"
info "Configuration file" "$config_file"
info "OpenShift version" "$ocp_release_version"
info "Target architecture" "$ocp_arch"

separator
printf "${BOLD}${GREEN}Next Steps:${RESET}\n"
printf "${CYAN}Option 1 (Manual):${RESET}\n"
printf "  └─ Boot node from ISO via BMC console:\n"
printf "     ${YELLOW}$(ls $cluster_workspace/agent.*.iso)${RESET}\n\n"
printf "${CYAN}Option 2 (Automated):${RESET}\n"
printf "  └─ Run automated installation (requires HTTP server):\n"
printf "     ${YELLOW}./sno-install.sh $cluster_name${RESET}\n\n"
printf "${BOLD}${GREEN}🎉 ISO generation completed successfully!${RESET}\n"
