#!/bin/bash
# Helper script to boot the node via redfish API from the ISO image
# usage: ./sno-install.sh
# usage: ./sno-install.sh <cluster-name>
#
# The script will install the latest cluster created by sno-iso.sh if <cluster-name> is not present
# If cluster-name presents it will install the cluster with config file: instance/<cluster-name>/config-resolved.yaml
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
  info "Usage: $0 <cluster-name>"
  info "If <cluster-name> is not present, it will install the newest cluster created by sno-iso"
  info "Example: $0"
  info "Example: $0 sno130"
}

if [[ ( $@ == "--help") ||  $@ == "-h" ]]
then
  usage
  exit
fi

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cluster_name=$1; shift

if [ -z "$cluster_name" ]; then
  cluster_name=$(ls -t $basedir/instances |head -1)
fi

cluster_workspace=$basedir/instances/$cluster_name

config_file=$cluster_workspace/config-resolved.yaml
if [ -f "$config_file" ]; then
  info "Configuration file" "$config_file"
  info "Target cluster" "$cluster_name"
else
  error "Config file not found" "$config_file"
  exit -1
fi

domain_name=$(yq '.cluster.domain' $config_file)
api_fqdn="api."$cluster_name"."$domain_name
api_token=$(jq -r '.["*gencrypto.AuthConfig"].UserAuthToken // empty' $cluster_workspace/.openshift_install_state.json)
if [[ -z "${api_token}" ]]; then
  api_token=$(jq -r '.["*gencrypto.AuthConfig"].AgentAuthToken // empty' $cluster_workspace/.openshift_install_state.json)
fi

bmc_address=$(yq '.bmc.address' $config_file)
bmc_user="$(yq '.bmc.username' $config_file)"
bmc_password="$(yq '.bmc.password' $config_file)"
password_var=$(echo "$bmc_password" |sed -n 's;^ENV{\(.*\)}$;\1;gp')

export KUBECONFIG=$cluster_workspace/auth/kubeconfig

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

rest_response=$(mktemp)

CURL="curl -s"
if [[ "true"=="${bmc_noproxy}" ]]; then
  CURL+=" --noproxy ${bmc_address}"
fi

iso_image=$(yq '.iso.address' $config_file)
deploy_cmd=$(eval echo $(yq '.iso.deploy // ""' $config_file))
ocp_arch=$(uname -m)
iso_protocol=$(yq -r '.iso.protocol|select( . != null )' $config_file)
kvm_uuid=$(yq '.bmc.kvm_uuid // "" ' $config_file)

set -euoE pipefail

redfish_init(){
  if [ ! -z $kvm_uuid ] && [ ! $kvm_uuid == "null" ]; then
    system=/redfish/v1/Systems/$kvm_uuid
    manager=/redfish/v1/Managers/$kvm_uuid
  else
    system=$($CURL -sku ${username_password}  https://$bmc_address/redfish/v1/Systems | jq '.Members[0]."@odata.id"' )
    manager=$($CURL -sku ${username_password}  https://$bmc_address/redfish/v1/Managers | jq '.Members[0]."@odata.id"' )
  fi

  if [ $manager == "null" ] || [ $system == "null" ]; then
    error "Redfish initialization failed" "System or manager is 'null'"
    exit -1
  fi

  system=$(sed -e 's/^"//' -e 's/"$//' <<<$system)
  manager=$(sed -e 's/^"//' -e 's/"$//' <<<$manager)
  system_path=https://$bmc_address$system
  manager_path=https://$bmc_address$manager
  virtual_media_root=$manager_path/VirtualMedia
  virtual_media_path=""

  virtual_medias=$($CURL -sku ${username_password} $virtual_media_root | jq '.Members[]."@odata.id"' )
  for vm in $virtual_medias; do
    vm=$(sed -e 's/^"//' -e 's/"$//' <<<$vm)
    if [ $($CURL -sku ${username_password} https://$bmc_address$vm | jq '.MediaTypes[]' |grep -ciE 'CD|DVD') -gt 0 ]; then
      virtual_media_path=$vm
      break
    fi
  done

  if [ $virtual_media_path == "null" ] || [ -z $virtual_media_path ]; then
    error "Virtual media path not found" "Cannot start deployment"
    exit -1
  else
    virtual_media_path=https://$bmc_address$virtual_media_path
  fi
}

server_secureboot_delete_keys() {
    $CURL --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetKeysType":"DeleteAllKeys"}' \
    -X POST  $system_path/SecureBoot/Actions/SecureBoot.ResetKeys
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

server_get_bios_config(){
    # Retrieve BIOS config over Redfish
    $CURL -sku ${username_password}  $system_path/Bios |jq
}

server_restart() {
    # Restart
    info "Restarting server" "..."
    $CURL --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetType": "ForceRestart"}' \
    -X POST $system_path/Actions/ComputerSystem.Reset
}

server_power_off() {
    # Power off
    local action="Power off Server"
    rest_result=$($CURL --globoff -L -w "%{http_code}" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -o "$rest_response" -d '{"ResetType": "ForceOff"}' -X POST $system_path/Actions/ComputerSystem.Reset)
    check_rest_result "$action" "$rest_result" "$rest_response"
}

server_power_on() {
    # Power on
    local action="Power on Server"
    rest_result=$($CURL --globoff  -L -w "%{http_code}" -ku ${username_password} \
      -H "Content-Type: application/json" -H "Accept: application/json" -d '{"ResetType": "On"}' \
      -o "$rest_response" -X POST $system_path/Actions/ComputerSystem.Reset)
    check_rest_result "$action" "$rest_result" "$rest_response"
}

virtual_media_eject() {
    # Eject Media
    local action="Eject Virtual Media"
    rest_result=$($CURL --globoff -L -w "%{http_code}"  -ku ${username_password} \
      -H "Content-Type: application/json" -H "Accept: application/json" -d '{}' \
      -o "$rest_response" -X POST $virtual_media_path/Actions/VirtualMedia.EjectMedia)
    check_rest_result "$action" "$rest_result" "$rest_response"
}

virtual_media_status(){
    # Media Status
    echo "Virtual Media Status: "
    $CURL -s --globoff -H "Content-Type: application/json" -H "Accept: application/json" \
    -k -X GET --user ${username_password} \
    $virtual_media_path| jq
}

deploy_iso(){
  [[ -z "$deploy_cmd" ]] && return
  [[ ! -x $(realpath $deploy_cmd) ]] && error "Deploy command not executable" "$deploy_cmd" && exit
  iso_file=$(find "$cluster_workspace" -name 'agent.*.iso')
  info "Deploying ISO" "$deploy_cmd $iso_file $iso_image"
  $deploy_cmd $iso_file $iso_image
  local result=$?
  if [[ $result -ne 0 ]]; then
    error "ISO deployment failed" "Exit code: $result"
    exit
  fi
}

virtual_media_insert(){
    # Insert Media from http server and iso file
    local action="Insert Virtual Media"
    local protocol="${iso_protocol}"
    if [[ -z "$protocol" ]]; then
      if [[ $iso_image == https* ]]; then
        protocol="HTTPS"
      else
        protocol="HTTP"
      fi
    fi
    if [[ "${protocol}" == "skip" ]]; then
      rest_result=$($CURL --globoff -L -w "%{http_code}" -ku ${username_password} \
      -H "Content-Type: application/json" -H "Accept: application/json" \
      -o "$rest_response" \
      -d "{\"Image\": \"${iso_image}\"}" \
      -X POST $virtual_media_path/Actions/VirtualMedia.InsertMedia)
    else
      rest_result=$($CURL --globoff -L -w "%{http_code}" -ku ${username_password} \
      -H "Content-Type: application/json" -H "Accept: application/json" \
      -o "$rest_response" \
      -d "{\"Image\": \"${iso_image}\", \"TransferProtocolType\": \"${protocol}\"}" \
      -X POST $virtual_media_path/Actions/VirtualMedia.InsertMedia)
    fi
    check_rest_result "$action" "$rest_result" "$rest_response"
}

server_set_boot_once_from_cd() {
    # Set boot
    local action="Boot node from Virtual Media Once"
    rest_result=$($CURL --globoff  -L -w "%{http_code}"  -ku ${username_password}  \
      -H "Content-Type: application/json" -H "Accept: application/json" \
      -d '{"Boot":{ "BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Cd" }}' \
      -o "$rest_response" -X PATCH $system_path)
    check_rest_result "$action" "$rest_result" "$rest_response"
}

approve_pending_install_plans(){
  info "Checking for pending InstallPlans" "up to 5 attempts"
  for i in {1..5}; do
    info "Checking attempt" "$i/5"
    oc get installplan -A
    while read -s IP; do
      info "Approving InstallPlan" "$IP"
      oc patch $IP --type merge --patch '{"spec":{"approved":true}}'
    done < <(oc get sub -A -o json |
      jq -r '.items[]|select( (.spec.startingCSV != null) and (.status.installedCSV == null) and (.status.installPlanRef != null) )|.status.installPlanRef|"-n \(.namespace) installplan \(.name)"')

    if [[ 0 ==  $(oc get sub -A -o json|jq '[.items[]|select(.status.installedCSV==null)]|length') ]]; then
      info "All subscriptions installed" "✓"
      break
    fi

    warn "Waiting for subscriptions" "30 seconds..."
    sleep 30
    echo
  done

  info "Operator versions installed" "listing all"
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

header "SNO Agent-Based Installation - Deployment"

step "Deploying ISO image"
deploy_iso

separator
step "Initializing Redfish connection"
redfish_init

step "Starting SNO deployment"
server_power_off
sleep 15
virtual_media_eject
virtual_media_insert
#virtual_media_status
server_set_boot_once_from_cd
sleep 10
server_power_on
#server_restart

separator
info "Node is booting from virtual media" "$iso_image"
info "Monitor installation progress" "via BMC console"
echo
echo -n "Node booting."

#ipv4_enabled=$(yq '.host.ipv4.enabled // "" ' $config_file)
#if [ "true" = "$ipv4_enabled" ]; then
#  node_ip=$(yq '.host.ipv4.ip' $config_file)
#  assisted_rest=http://$node_ip:8090/api/assisted-install/v2/clusters
#else
#  node_ip=$(yq '.host.ipv6.ip' $config_file)
#  assisted_rest=http://[$node_ip]:8090/api/assisted-install/v2/clusters
#fi

assisted_rest=http://$api_fqdn:8090/api/assisted-install/v2/clusters

SSH_CMD="ssh -q -oStrictHostKeyChecking=no"
ssh_priv_key_input=$(yq -r '.ssh_priv_key //""' $config_file)
if [[ ! -z "${ssh_priv_key_input}" ]]; then
  ssh_key_path=$(eval echo $ssh_priv_key_input)
  SSH_CMD+=" -i ${ssh_key_path}"
fi

REMOTE_CURL="$SSH_CMD core@$api_fqdn curl -s"
if [[ ! -z "${api_token}" ]]; then
  REMOTE_CURL+=" -H 'Authorization: ${api_token}'"
fi

# workaround for https://access.redhat.com/solutions/7120118
exec 3>&2
exec 2> /dev/null

while [[ "$($REMOTE_CURL -o /dev/null -w ''%{http_code}'' $assisted_rest)" != "200" ]]; do
  echo -n "."
  sleep 10;
done

echo
step "Monitoring installation progress"
while
  separator
  _status=$($REMOTE_CURL $assisted_rest)
  echo "$_status"| \
   jq -c '.[] | with_entries(select(.key | contains("name","updated_at","_count","status","validations_info")))|.validations_info|=(.// empty|fromjson|del(.. | .id?))'
  [[ "\"installing\"" != $(echo "$_status" |jq '.[].status') ]]
do sleep 15; done

echo
prev_percentage=""
separator
step "Installation progress tracking"
while
  total_percentage=$($REMOTE_CURL $assisted_rest |jq '.[].progress.total_percentage')
  if [ ! -z $total_percentage ]; then
    if [[ "$total_percentage" == "$prev_percentage" ]]; then
       echo -n "."
    else
      echo
      info "Installation progress" "$total_percentage% completed"
      prev_percentage=$total_percentage
    fi
  fi
  sleep 20;
  [[ "$($REMOTE_CURL -o /dev/null -w ''%{http_code}'' $assisted_rest)" == "200" ]]
do true; done

# restore stderr
exec 2>&3

echo

separator
step "Post-installation cleanup and setup"
info "Node has rebooted" "Installation continuing"
info "OpenShift commands will be available soon" "Monitor with oc commands"
echo

step "Ejecting virtual media"
virtual_media_eject

step "Waiting for cluster stabilization"
sleep 60
wait_for_stable_cluster 60

step "Approving pending install plans"
approve_pending_install_plans

header "Installation Complete - Summary"
info "✅ SNO installation completed" "successfully"
info "📁 Kubeconfig location" "$cluster_workspace/auth/kubeconfig"
info "🔑 Admin password file" "$cluster_workspace/auth/kubeadmin-password"
info "⚙️  Configuration file" "$config_file"
info "🎯 Target cluster" "$cluster_name"
info "🌐 API endpoint" "https://$api_fqdn:6443"

separator
printf "${BOLD}${GREEN}🎉 SNO installation completed successfully!${RESET}\n"
printf "${CYAN}Next Steps:${RESET}\n"
printf "  └─ Access the cluster using the kubeconfig file\n"
printf "  └─ Run day2 operations: ${YELLOW}./sno-day2.sh $cluster_name${RESET}\n"
printf "  └─ Monitor cluster operators and workloads\n"
