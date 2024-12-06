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

show_info(){
  printf  $(tput setaf 2)"%-54s %-10s"$(tput sgr0)"\n" "$@"
}

show_warn(){
  printf  $(tput setaf 3)"%-54s %-10s"$(tput sgr0)"\n" "$@"
}

usage(){
  echo "Usage: $0 <cluster-name>"
  echo "If <cluster-name> is not present, it will install the newest cluster created by sno-iso"
  echo "Example: $0"
  echo "Example: $0 sno130"
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
  echo "Will install cluster $cluster_name with config: $config_file"
else
  "Config file $config_file not exist, please check."
  exit -1
fi

domain_name=$(yq '.cluster.domain' $config_file)
api_fqdn="api."$cluster_name"."$domain_name

bmc_address=$(yq '.bmc.address' $config_file)
bmc_user="$(yq '.bmc.username' $config_file)"
bmc_password="$(yq '.bmc.password' $config_file)"
password_var=$(echo "$bmc_password" |sed -n 's;^ENV{\(.*\)}$;\1;gp')

export KUBECONFIG=$cluster_workspace/auth/kubeconfig

if [[ -n "${password_var}" ]]; then
  if [[ -z "${!password_var}" ]]; then
    echo "Failed to pick up BMC password from environment variable '${password_var}'"
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
    echo "FATAL: either redfish system or manager is 'null', please check!"
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
    echo "FATAL: redfish virtual media path is empty, cannot start the deployment, please check!"
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
      show_info "$action" "$rest_result"
    else
      show_warn "$action" "$rest_result"
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
    echo "Restart server."
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
  [[ ! -x $(realpath $deploy_cmd) ]] && echo "Failed to deploy ISO, command not executable: $deploy_cmd" && exit
  echo "Deploy ISO: $deploy_cmd $cluster_workspace/agent.x86_64.iso $iso_image"
  $deploy_cmd $cluster_workspace/agent.x86_64.iso $iso_image
  local result=$?
  if [[ $result -ne 0 ]]; then
    echo "Failed: $result"
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
  echo "Approve pending approval InstallPlans if have, will repeat 5 times."
  for i in {1..5}; do
    echo "checking $i"
    oc get ip -A
    while read -s IP; do
      echo "oc patch $IP --type merge --patch '{"spec":{"approved":true}}'"
      oc patch $IP --type merge --patch '{"spec":{"approved":true}}'
    done < <(oc get sub -A -o json |
      jq -r '.items[]|select( (.spec.startingCSV != null) and (.status.installedCSV == null) and (.status.installPlanRef != null) )|.status.installPlanRef|"-n \(.namespace) ip \(.name)"')

    if [[ 0 ==  $(oc get sub -A -o json|jq '[.items[]|select(.status.installedCSV==null)]|length') ]]; then
      echo
      break
    fi

    sleep 30
    echo
  done

  echo "All operator versions:"
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

echo "-------------------------------"
deploy_iso
echo ""
echo "-------------------------------"
redfish_init

echo "Starting SNO deployment..."
echo
server_power_off
sleep 15
virtual_media_eject
virtual_media_insert
#virtual_media_status
server_set_boot_once_from_cd
sleep 10
server_power_on
#server_restart
echo
echo "-------------------------------"
echo "Node is booting from virtual media mounted with $iso_image, check your BMC console to monitor the installation progress."
echo
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

REMOTE_CURL="ssh -q -oStrictHostKeyChecking=no core@$api_fqdn curl -s"
while [[ "$($REMOTE_CURL -o /dev/null -w ''%{http_code}'' $assisted_rest)" != "200" ]]; do
  echo -n "."
  sleep 10;
done

echo
echo "Installing in progress..."
while
  echo "-------------------------------"
  _status=$($REMOTE_CURL $assisted_rest)
  echo "$_status"| \
   jq -c '.[] | with_entries(select(.key | contains("name","updated_at","_count","status","validations_info")))|.validations_info|=(.// empty|fromjson|del(.. | .id?))'
  [[ "\"installing\"" != $(echo "$_status" |jq '.[].status') ]]
do sleep 15; done

echo
prev_percentage=""
echo "-------------------------------"
while
  total_percentage=$($REMOTE_CURL $assisted_rest |jq '.[].progress.total_percentage')
  if [ ! -z $total_percentage ]; then
    if [[ "$total_percentage" == "$prev_percentage" ]]; then
       echo -n "."
    else
      echo
      echo -n "Installation in progress: completed $total_percentage/100"
      prev_percentage=$total_percentage
    fi
  fi
  sleep 20;
  [[ "$($REMOTE_CURL -o /dev/null -w ''%{http_code}'' $assisted_rest)" == "200" ]]
do true; done
echo

echo "-------------------------------"
echo "Node Rebooted..."
echo "Installation still in progress, oc command will be available soon, you can open another terminal to check the installation progress with oc commands..."
echo
echo "Will eject the ISO now..."
virtual_media_eject
echo
echo "Waiting for the cluster to be ready..."
sleep 60
wait_for_stable_cluster 60

approve_pending_install_plans
echo
echo "You are all set..."
