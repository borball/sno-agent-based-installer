#!/bin/bash
# Helper script to boot the node via redfish API from the ISO image
# usage: ./sno-install.sh
# usage: ./sno-install.sh <cluster-name>
#
# The script will install the latest cluster created by sno-iso.sh if <cluster-name> is not present
# If cluster-name presents it will install the cluster with config file: instance/<cluster-name>/config-resolved.yaml

check_dependencies(){
  if ! type "yq" > /dev/null; then
    echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
  fi

  if ! type "jinja2" > /dev/null; then
    echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
    pip3 install --user jinja2-cli
    pip3 install --user jinja2-cli[yaml]
  fi
}

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
  printf "\n${BOLD}${BLUE}▶%s${RESET}\n" "$1"
}

header(){
  echo
  printf "${BOLD}${CYAN}%s${RESET}\n" "$1"
  printf "${CYAN}%s${RESET}\n" "$(printf '%.0s=' {1..60})"
}

separator(){
  printf "${CYAN}%s${RESET}\n" "$(printf '%.0s-' {1..60})"
}

check_dependencies

usage(){
  echo "Usage: $0 <cluster-name>"
  echo "If <cluster-name> is not present, it will install the newest cluster created by sno-iso.sh"
  echo "Example: $0"
  echo "Example: $0 sno130"
}

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cluster_name=$1; shift

if [ -z "$cluster_name" ]; then
  cluster_name=$(ls -t $basedir/instances |head -1)
fi

cluster_workspace=$basedir/instances/$cluster_name

header "SNO Install Operations - General Information"

config_file=$cluster_workspace/config-resolved.yaml
if [ -f "$config_file" ]; then
  info "Configuration file" "$config_file"
  info "Target cluster" "$cluster_name"
else
  error "Config file not found" "$config_file"
  exit -1
fi

iso_info(){
  iso_image=$(yq '.iso.address' $config_file)
}

deploy_iso(){
  deploy_cmd=$(eval echo $(yq '.iso.deploy // ""' $config_file))

  [[ -z "$deploy_cmd" ]] && return
  [[ ! -x $(realpath $deploy_cmd) ]] && error "Deploy command not executable" "$deploy_cmd" && exit
  iso_file=$(find "$cluster_workspace" -name 'agent.*.iso')
  info "Deploying ISO" "$deploy_cmd $iso_file $iso_image"
  $deploy_cmd $iso_file $iso_image
  local result=$?
  if [[ $result -ne 0 ]]; then
    error "ISO deployment failed" "Exit code: $result"
    exit -1
  fi
}

redfish_init(){
  step "Initializing Redfish"
  rest_response=$(mktemp)

  bmc_address=$(yq '.bmc.address' $config_file)
  bmc_user="$(yq '.bmc.username' $config_file)"
  bmc_password="$(yq '.bmc.password' $config_file)"
  password_var=$(echo "$bmc_password" |sed -n 's;^ENV{\(.*\)}$;\1;gp')

  if [[ -n "${password_var}" ]]; then
    if [[ -z "${!password_var}" ]]; then
      error "BMC password not found" "Environment variable '${password_var}' is empty"
      exit -1
    fi
    username_password="${bmc_user}:${!password_var}"
  else
    username_password="${bmc_user}:${bmc_password}"
  fi
  bmc_noproxy=$(yq ".bmc.bypass_proxy" $config_file)

  redfish_curl_cmd="curl -s"
  if [[ "true"=="${bmc_noproxy}" ]]; then
    redfish_curl_cmd+=" --noproxy ${bmc_address}"
  fi
  redfish_curl_cmd+=" -ku ${username_password}"
  redfish_curl_cmd+=" -H 'Content-Type: application/json'"
  redfish_curl_cmd+=" -H 'Accept: application/json'"

  # Function to get HTTP status code from redfish endpoint
  get_redfish_status() {
    local url="$1"
    local temp_file=$(mktemp)
    local status_code
    
    if [[ "true"=="${bmc_noproxy}" ]]; then
      status_code=$(curl -s --noproxy "${bmc_address}" -ku "${username_password}" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        -w '%{http_code}' -o "$temp_file" "$url" 2>&1 | tail -c 3)
    else
      status_code=$(curl -s -ku "${username_password}" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        -w '%{http_code}' -o "$temp_file" "$url" 2>&1 | tail -c 3)
    fi
    
    # Fallback if status_code is empty or not a number
    if [[ ! "$status_code" =~ ^[0-9]{3}$ ]]; then
      status_code="000"
    fi
    
    rm -f "$temp_file"
    echo "$status_code"
  }

  if [ ! -z $kvm_uuid ] && [ ! $kvm_uuid == "null" ]; then
    system=https://$bmc_address/redfish/v1/Systems/$kvm_uuid
    status_code=$(get_redfish_status "$system")
    if [ "$status_code" -ne 200 ]; then
      error "Redfish initialization failed" "System is not available"
      exit -1
    fi

    manager=https://$bmc_address/redfish/v1/Managers/$kvm_uuid
    status_code=$(get_redfish_status "$manager")
    if [ "$status_code" -ne 200 ]; then
      warn "Redfish initialization failed" "Manager is not available, will try to use system instead"
      manager=$system
    fi
  else
    status_code=$(get_redfish_status "https://$bmc_address/redfish/v1/Systems")
    if [ "$status_code" -ne 200 ]; then
      error "Redfish initialization failed" "System is not available"
      exit -1
    else
      system=https://$bmc_address$($redfish_curl_cmd  https://$bmc_address/redfish/v1/Systems | jq -r '.Members[0]."@odata.id"' )
    fi

    status_code=$(get_redfish_status "https://$bmc_address/redfish/v1/Managers")
    if [ "$status_code" -ne 200 ]; then
      warn "Redfish initialization failed" "Manager is not available, will try to use system instead"
      manager=$system
    else
      manager=https://$bmc_address$($redfish_curl_cmd  https://$bmc_address/redfish/v1/Managers | jq -r '.Members[0]."@odata.id"' )
    fi
  fi

  set +e
  virtual_media_root=$manager/VirtualMedia
  virtual_media_path=""
  virtual_medias=$($redfish_curl_cmd $virtual_media_root | jq '.Members[]."@odata.id"'  2>/dev/null)
  if [[ -z "$virtual_medias" ]]; then
    virtual_media_root=$system/VirtualMedia
    virtual_medias=$($redfish_curl_cmd $virtual_media_root | jq -r '.Members[]."@odata.id"' 2>/dev/null)
    if [[ -z "$virtual_medias" ]]; then
      echo "Failed to get virtual media"
      exit -1
    fi
  fi
  set -e

  for vm in $virtual_medias; do
    if [ $($redfish_curl_cmd https://$bmc_address$vm | jq -r '.MediaTypes[]' |grep -ciE 'CD|DVD|cdrom') -gt 0 ]; then
      virtual_media=$vm
      break
    fi
  done

  if [ $virtual_media == "null" ] || [ -z $virtual_media ]; then
    error "Virtual media path not found" "Cannot start deployment"
    exit -1
  else
    virtual_media=https://$bmc_address$virtual_media
  fi

  info "System" "$system"
  info "Manager" "$manager"
  info "Virtual media" "$virtual_media"

}

check_rest_result() {
  local action=$1
  local rest_result=$2
  local rest_response=$3

  if [[ -n "$rest_result" ]] && [[ $rest_result -lt 300 ]]; then
    info "$action" "$rest_result"
  else
    warn "$action" "$rest_result"
    echo $(cat $rest_response)
  fi
  rm -f $rest_response
}

virtual_media_insert(){
  # Insert Media from http server and iso file
  local action="Insert Virtual Media"
  local temp_file=$(mktemp)
   
  local protocol="${iso_protocol}"
  if [[ -z "$protocol" ]]; then
    if [[ $iso_image == https* ]]; then
      protocol="HTTPS"
    else
      protocol="HTTP"
    fi
  fi
  
  if [[ "${protocol}" == "skip" ]]; then
    if [[ "true"=="${bmc_noproxy}" ]]; then
      rest_result=$(curl -s --noproxy "${bmc_address}" -ku "${username_password}" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        --globoff -L -w "%{http_code}" \
        -d "{\"Image\": \"${iso_image}\"}" \
        -o "$temp_file" -X POST "$virtual_media/Actions/VirtualMedia.InsertMedia" 2>&1 | tail -c 3)
    else
      rest_result=$(curl -s -ku "${username_password}" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        --globoff -L -w "%{http_code}" \
        -d "{\"Image\": \"${iso_image}\"}" \
        -o "$temp_file" -X POST "$virtual_media/Actions/VirtualMedia.InsertMedia" 2>&1 | tail -c 3)
    fi
  else
    if [[ "true"=="${bmc_noproxy}" ]]; then
      rest_result=$(curl -s --noproxy "${bmc_address}" -ku "${username_password}" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        --globoff -L -w "%{http_code}" \
        -d "{\"Image\": \"${iso_image}\", \"TransferProtocolType\": \"${protocol}\"}" \
        -o "$temp_file" -X POST "$virtual_media/Actions/VirtualMedia.InsertMedia" 2>&1 | tail -c 3)
    else
      rest_result=$(curl -s -ku "${username_password}" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        --globoff -L -w "%{http_code}" \
        -d "{\"Image\": \"${iso_image}\", \"TransferProtocolType\": \"${protocol}\"}" \
        -o "$temp_file" -X POST "$virtual_media/Actions/VirtualMedia.InsertMedia" 2>&1 | tail -c 3)
    fi
  fi
  
  # Copy temp response to rest_response for check_rest_result
  cp "$temp_file" "$rest_response"
  rm -f "$temp_file"
  
  # Fallback if rest_result is not a valid HTTP code
  if [[ ! "$rest_result" =~ ^[0-9]{3}$ ]]; then
    rest_result="000"
  fi
  
  check_rest_result "$action" "$rest_result" "$rest_response"
}

server_power_off() {
  # Power off
  local action="Power off Server"
  local temp_file=$(mktemp)
  
  if [[ "true"=="${bmc_noproxy}" ]]; then
    rest_result=$(curl -s --noproxy "${bmc_address}" -ku "${username_password}" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --globoff -L -w "%{http_code}" \
      -d '{"ResetType": "ForceOff"}' \
      -o "$temp_file" -X POST "$system/Actions/ComputerSystem.Reset" 2>&1 | tail -c 3)
  else
    rest_result=$(curl -s -ku "${username_password}" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --globoff -L -w "%{http_code}" \
      -d '{"ResetType": "ForceOff"}' \
      -o "$temp_file" -X POST "$system/Actions/ComputerSystem.Reset" 2>&1 | tail -c 3)
  fi
  
  # Copy temp response to rest_response for check_rest_result
  cp "$temp_file" "$rest_response"
  rm -f "$temp_file"
  
  # Fallback if rest_result is not a valid HTTP code
  if [[ ! "$rest_result" =~ ^[0-9]{3}$ ]]; then
    rest_result="000"
  fi
  
  check_rest_result "$action" "$rest_result" "$rest_response"
}

server_power_on() {
  # Power on
  local action="Power on Server"
  local temp_file=$(mktemp)
  
  if [[ "true"=="${bmc_noproxy}" ]]; then
    rest_result=$(curl -s --noproxy "${bmc_address}" -ku "${username_password}" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --globoff -L -w "%{http_code}" \
      -d '{"ResetType": "On"}' \
      -o "$temp_file" -X POST "$system/Actions/ComputerSystem.Reset" 2>&1 | tail -c 3)
  else
    rest_result=$(curl -s -ku "${username_password}" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --globoff -L -w "%{http_code}" \
      -d '{"ResetType": "On"}' \
      -o "$temp_file" -X POST "$system/Actions/ComputerSystem.Reset" 2>&1 | tail -c 3)
  fi
  
  # Copy temp response to rest_response for check_rest_result
  cp "$temp_file" "$rest_response"
  rm -f "$temp_file"
  
  # Fallback if rest_result is not a valid HTTP code
  if [[ ! "$rest_result" =~ ^[0-9]{3}$ ]]; then
    rest_result="000"
  fi
  
  check_rest_result "$action" "$rest_result" "$rest_response"
}

virtual_media_eject() {
  # Eject Media
  local action="Eject Virtual Media"
  local temp_file=$(mktemp)
  
  if [[ "true"=="${bmc_noproxy}" ]]; then
    rest_result=$(curl -s --noproxy "${bmc_address}" -ku "${username_password}" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --globoff -L -w "%{http_code}" -d '{}' \
      -o "$temp_file" -X POST "$virtual_media/Actions/VirtualMedia.EjectMedia" 2>&1 | tail -c 3)
  else
    rest_result=$(curl -s -ku "${username_password}" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --globoff -L -w "%{http_code}" -d '{}' \
      -o "$temp_file" -X POST "$virtual_media/Actions/VirtualMedia.EjectMedia" 2>&1 | tail -c 3)
  fi
  
  # Copy temp response to rest_response for check_rest_result
  cp "$temp_file" "$rest_response"
  rm -f "$temp_file"
  
  # Fallback if rest_result is not a valid HTTP code
  if [[ ! "$rest_result" =~ ^[0-9]{3}$ ]]; then
    rest_result="000"
  fi
  
  check_rest_result "$action" "$rest_result" "$rest_response"
}

virtual_media_status(){
  # Media Status
  info "Virtual media status" "checking..."
  $redfish_curl_cmd --globoff $virtual_media| jq
}

server_set_boot_once_from_cd() {
  # Set boot
  local action="Boot node from Virtual Media Once"
  local temp_file=$(mktemp)
  
  if [[ "true"=="${bmc_noproxy}" ]]; then
    rest_result=$(curl -s --noproxy "${bmc_address}" -ku "${username_password}" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --globoff -L -w "%{http_code}" \
      -d '{"Boot":{ "BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Cd" }}' \
      -o "$temp_file" -X PATCH "$system" 2>&1 | tail -c 3)
  else
    rest_result=$(curl -s -ku "${username_password}" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --globoff -L -w "%{http_code}" \
      -d '{"Boot":{ "BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Cd" }}' \
      -o "$temp_file" -X PATCH "$system" 2>&1 | tail -c 3)
  fi
  
  # Copy temp response to rest_response for check_rest_result
  cp "$temp_file" "$rest_response"
  rm -f "$temp_file"
  
  # Fallback if rest_result is not a valid HTTP code
  if [[ ! "$rest_result" =~ ^[0-9]{3}$ ]]; then
    rest_result="000"
  fi
  
  check_rest_result "$action" "$rest_result" "$rest_response"
}

monitor_installation_status(){
  step "Monitoring installation status"
  
  export KUBECONFIG=$cluster_workspace/auth/kubeconfig

  if [ -f $cluster_workspace/.openshift_install_state.json ]; then
    info "Installation state file" "exists"
  else
    error "Installation state file" "does not exist"
    exit -1
  fi

  domain_name=$(yq '.cluster.domain' $config_file)
  api_fqdn="api."$cluster_name"."$domain_name
  api_token=$(jq -r '.["*gencrypto.AuthConfig"].UserAuthToken // empty' $cluster_workspace/.openshift_install_state.json)
  if [[ -z "${api_token}" ]]; then
    api_token=$(jq -r '.["*gencrypto.AuthConfig"].AgentAuthToken // empty' $cluster_workspace/.openshift_install_state.json)
  fi

  assisted_rest=http://$api_fqdn:8090/api/assisted-install/v2/clusters
  
  # Check if SSH private key is configured and exists
  ssh_priv_key_input=$(yq -r '.ssh_priv_key //""' $config_file)
  if [[ ! -z "${ssh_priv_key_input}" ]]; then
    ssh_key_path=$(eval echo $ssh_priv_key_input)
    if [[ -f "${ssh_key_path}" ]]; then
      # Use curl over SSH when SSH key exists and is valid
      info "Connection method" "SSH tunnel via core@$api_fqdn using key: $ssh_key_path"
      SSH_CMD="ssh -q -oStrictHostKeyChecking=no -i ${ssh_key_path}"
      REMOTE_CURL="$SSH_CMD core@$api_fqdn curl -s"
      if [[ ! -z "${api_token}" ]]; then
        REMOTE_CURL+=" -H 'Authorization: ${api_token}'"
      fi
      
      # Function to make authenticated API calls over SSH
      monitor_curl() {
        $REMOTE_CURL "$@"
      }
    else
      # SSH key configured but file doesn't exist, use direct curl
      warn "SSH key configured but not found" "$ssh_key_path - falling back to direct connection"
      info "Connection method" "Direct HTTP to $api_fqdn:8090"
      monitor_curl() {
        curl -s -H "Authorization: ${api_token}" "$@"
      }
    fi
  else
    # No SSH key configured, use direct curl
    info "Connection method" "Direct HTTP to $api_fqdn:8090 (no SSH key configured)"
    monitor_curl() {
      curl -s -H "Authorization: ${api_token}" "$@"
    }
  fi

  # workaround for https://access.redhat.com/solutions/7120118
  exec 3>&2
  exec 2> /dev/null

  info "Waiting for API endpoint" "$assisted_rest"
  echo -n "Checking API availability"
  while [[ "$(monitor_curl "$assisted_rest" -o /dev/null -w '%{http_code}')" != "200" ]]; do
    echo -n "."
    sleep 10;
  done

  echo
  info "API endpoint available" "starting installation monitoring"
  info "Monitoring cluster status" "waiting for installation to begin"
  while
    echo "-------------------------------"
    _status=$(monitor_curl "$assisted_rest")
    current_status=$(echo "$_status" |jq -r '.[].status // "unknown"')
    info "Cluster status" "$current_status"
    echo "$_status"| \
    jq -c '.[] | with_entries(select(.key | contains("name","updated_at","_count","status","validations_info")))|.validations_info|=(.// empty|fromjson|del(.. | .id?))'
    [[ "\"installing\"" != $(echo "$_status" |jq '.[].status') ]]
  do sleep 15; done

  echo
  info "🚀 Installation started" "monitoring progress"
  local prev_percentage=""
  local dot_count=0
  echo "-------------------------------"
  while
    total_percentage=$(monitor_curl "$assisted_rest" |jq '.[].progress.total_percentage')
    if [ ! -z $total_percentage ]; then
      if [ "$total_percentage" != "$prev_percentage" ]; then
        if [[ $dot_count -gt 0 ]]; then
	  echo ""
	fi
        info "📈 Installation progress" "$total_percentage%"
        prev_percentage="$total_percentage"
        dot_count=0
      else
        echo -n "."
	((dot_count++))
      fi
    else
      echo -n "."
      ((dot_count++))
    fi
    sleep 20;
    api_status=$(monitor_curl "$assisted_rest" -o /dev/null -w '%{http_code}')
    if [[ "$api_status" != "200" ]]; then
      warn "API connection lost" "HTTP $api_status - installation may be completing"
    fi
    [[ "$api_status" == "200" ]]
  do true; done

  # restore stderr
  exec 2>&3

  echo
  virtual_media_eject
  info "API monitoring complete" "installation finished or node rebooted"
  header "Installation Complete - Summary"
  info "Installation completed" "successfully"
  info "Installation progress" "$total_percentage%"
}

approve_pending_install_plans(){
  step "Checking for pending InstallPlans"
  for i in {1..5}; do
    info "  └─ Checking attempt" "$i/5"
    oc get installplan -A
    while read -s IP; do
      info "    └─ Approving InstallPlan" "$IP"
      oc patch $IP --type merge --patch '{"spec":{"approved":true}}'
    done < <(oc get sub -A -o json |
      jq -r '.items[]|select( (.spec.startingCSV != null) and (.status.installedCSV == null) and (.status.installPlanRef != null) )|.status.installPlanRef|"-n \(.namespace) installplan \(.name)"')

    if [[ 0 ==  $(oc get sub -A -o json|jq '[.items[]|select(.status.installedCSV==null)]|length') ]]; then
      info "  └─ All subscriptions installed" "✓"
      break
    fi

    warn "  └─ Waiting for subscriptions" "30 seconds..."
    sleep 30
    echo
  done

  separator
  info "📋 Operator versions installed" "summary"
  oc get csv -A -o custom-columns="0AME:.metadata.name,DISPLAY:.spec.displayName,VERSION:.spec.version" |sort -f|uniq|sed 's/0AME/NAME/'
}

wait_for_stable_cluster(){
  local interval=${1:-60}
  local next_run=0
  local skipped=""
  set +e
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local current=$(date +%s --date="now")
    if [[ $current -gt $next_run ]]; then
      if [[ ! -z "$skipped" ]]; then
	echo
	skipped=""
      fi
      echo $line
      let next_run=$current+$interval
     else
       echo -n .
       skipped="$line"
     fi
  done < <(oc adm wait-for-stable-cluster --minimum-stable-period=1m  2>&1)
  set -e
  if [[ ! -z "$skipped" ]]; then
    echo
    echo $skipped
  fi
}

redfish_install(){
  header "SNO Agent-Based Installer - Redfish Installation"
  
  redfish_init
  server_power_off
  sleep 15
  virtual_media_eject
  virtual_media_insert
  server_set_boot_once_from_cd
  sleep 15
  server_power_on
  monitor_installation_status
}

post_install(){
  step "Post installation"
  
  # Set KUBECONFIG for any post-installation operations
  if [ -f "$cluster_workspace/auth/kubeconfig" ]; then
    export KUBECONFIG=$cluster_workspace/auth/kubeconfig
    info "KUBECONFIG set" "$cluster_workspace/auth/kubeconfig"
  else
    warn "Kubeconfig not found" "Post-install operations may be limited"
  fi
}

iso_info
deploy_iso

skip_redfish=$(yq '.iso.skip_redfish' $config_file)

if [ "$skip_redfish" == "true" ]; then
  warn "Skipping Redfish" "ISO image mounted via other methods"
  monitor_installation_status
else
  info "Using Redfish" "ISO image will be mounted via Redfish"
  redfish_install
fi

export KUBECONFIG=$cluster_workspace/auth/kubeconfig

wait_for_stable_cluster
approve_pending_install_plans

post_install


