#!/bin/bash
# Helper script to boot the node via redfish API from the ISO image
# usage: ./sno-install.sh config.yaml
#

if ! type "yq" > /dev/null; then
  echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

if ! type "jinja2" > /dev/null; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install --user jinja2-cli
  pip3 install --user jinja2-cli[yaml]
fi

set -euoE pipefail

usage(){
  echo "Usage : $0 config-file"
  echo "Example : $0 config-sno130.yaml"
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

config_file=$1; shift
domain_name=$(yq '.cluster.domain' $config_file)
cluster_name=$(yq '.cluster.name' $config_file)
api_fqdn="api."$cluster_name"."$domain_name

bmc_address=$(yq '.bmc.address' $config_file)
username_password="$(yq '.bmc.username' $config_file):$(yq '.bmc.password' $config_file)"
iso_image=$(yq '.iso.address' $config_file)
kvm_uuid=$(yq '.bmc.kvm_uuid // "" ' $config_file)

if [ ! -z $kvm_uuid ]; then
  system=/redfish/v1/Systems/$kvm_uuid
  manager=/redfish/v1/Managers/$kvm_uuid
else
  system=$(curl -sku ${username_password}  https://$bmc_address/redfish/v1/Systems | jq '.Members[0]."@odata.id"' )
  manager=$(curl -sku ${username_password}  https://$bmc_address/redfish/v1/Managers | jq '.Members[0]."@odata.id"' )
fi

system=$(sed -e 's/^"//' -e 's/"$//' <<<$system)
manager=$(sed -e 's/^"//' -e 's/"$//' <<<$manager)

system_path=https://$bmc_address$system
manager_path=https://$bmc_address$manager
virtual_media_root=$manager_path/VirtualMedia
virtual_media_path=""

virtual_medias=$(curl -sku ${username_password} $virtual_media_root | jq '.Members[]."@odata.id"' )
for vm in $virtual_medias; do
  vm=$(sed -e 's/^"//' -e 's/"$//' <<<$vm)
  if [ $(curl -sku ${username_password} https://$bmc_address$vm | jq '.MediaTypes[]' |grep -ciE 'CD|DVD') -gt 0 ]; then
    virtual_media_path=$vm
  fi
done
virtual_media_path=https://$bmc_address$virtual_media_path

server_secureboot_delete_keys() {
    curl --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetKeysType":"DeleteAllKeys"}' \
    -X POST  $system_path/SecureBoot/Actions/SecureBoot.ResetKeys 
}

server_get_bios_config(){
    # Retrieve BIOS config over Redfish
    curl -sku ${username_password}  $system_path/Bios |jq
}

server_restart() {
    # Restart
    echo "Restart server."
    curl --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetType": "ForceRestart"}' \
    -X POST $system_path/Actions/ComputerSystem.Reset
}

server_power_off() {
    # Power off
    echo "Power off server."
    curl --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetType": "ForceOff"}' -X POST $system_path/Actions/ComputerSystem.Reset
}

server_power_on() {
    # Power on
    echo "Power on server."
    curl --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetType": "On"}' -X POST $system_path/Actions/ComputerSystem.Reset
}

virtual_media_eject() {
    # Eject Media
    echo "Eject Virtual Media."
    curl --globoff -L -w "%{http_code} %{url_effective}\\n"  -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{}'  -X POST $virtual_media_path/Actions/VirtualMedia.EjectMedia
}

virtual_media_status(){
    # Media Status
    echo "Virtual Media Status: "
    curl -s --globoff -H "Content-Type: application/json" -H "Accept: application/json" \
    -k -X GET --user ${username_password} \
    $virtual_media_path| jq
}

virtual_media_insert(){
    # Insert Media from http server and iso file
    echo "Insert Virtual Media: $iso_image"
    curl --globoff -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d "{\"Image\": \"${iso_image}\"}" \
    -X POST $virtual_media_path/Actions/VirtualMedia.InsertMedia
}

server_set_boot_once_from_cd() {
    # Set boot
    echo "Boot node from Virtual Media Once"
    curl --globoff  -L -w "%{http_code} %{url_effective}\\n"  -ku ${username_password}  \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"Boot":{ "BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Cd" }}' \
    -X PATCH $system_path
}

echo "-------------------------------"

echo "Starting SNO deployment..."
echo
server_power_off

sleep 15

echo "-------------------------------"
echo
virtual_media_eject
echo "-------------------------------"
echo
virtual_media_insert
echo "-------------------------------"
echo
virtual_media_status
echo "-------------------------------"
echo
server_set_boot_once_from_cd
echo "-------------------------------"

sleep 10
echo
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

while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' $assisted_rest)" != "200" ]]; do
  echo -n "."
  sleep 2;
done

echo
echo "Installing in progress..."

curl --silent $assisted_rest |jq

while [[ "\"installing\"" != $(curl --silent $assisted_rest |jq '.[].status') ]]; do
  echo "-------------------------------"
  curl --silent $assisted_rest |jq
  sleep 5
done

echo
echo "-------------------------------"
while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' $assisted_rest)" == "200" ]]; do
  total_percentage=$(curl --silent $assisted_rest |jq '.[].progress.total_percentage')
  if [ ! -z $total_percentage ]; then
    echo "Installation in progress: completed $total_percentage/100"
  fi
  sleep 15;
done

echo "-------------------------------"
echo "Node Rebooted..."
echo "Installation still in progress, oc command will be available soon, please check the installation progress with oc commands."

virtual_media_eject
echo "Enjoy!"